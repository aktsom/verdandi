/*
 * auv3_bridge.c
 *
 * the norns side of the AUv3: a jack client that receives the DAW's audio from the AU over
 * UDP (127.0.0.1, see bridge_protocol.h), resamples between the DAW clock and the jack clock
 * (jack's adapter), and answers each block with norns' output. while an AU is rendering,
 * crone's inputs come from the DAW instead of the audio interface and crone's main output
 * goes to the DAW instead of the speakers; when it stops (bye or 1 s of silence) the original
 * connections come back. MIDI from the DAW appears as the CoreMIDI source "norns AUv3".
 *
 * started by macos/norns.sh; idle until an AU connects.
 */

#include <CoreMIDI/CoreMIDI.h>
#include <arpa/inet.h>
#include <errno.h>
#include <jack/jack.h>
#include <jack/net.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "bridge_protocol.h"

#define IDLE_TIMEOUT_MS 1000
#define MAX_LINKS 16
#define PORT_NAME 320 // jack_port_name_size() on jack2 is 256 + client name

static jack_client_t *client;
static jack_port_t *to_crone[NB_CHANNELS];   // our outputs -> crone:input_N
static jack_port_t *from_crone[NB_CHANNELS]; // crone:output_N -> our inputs
static _Atomic(jack_adapter_t *) adapter = NULL;

static MIDIClientRef midi_client;
static MIDIEndpointRef midi_source;

// connections we replaced while active: src -> dst pairs
static char saved[MAX_LINKS][2][PORT_NAME];
static int n_saved = 0;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static int process(jack_nframes_t nframes, void *arg) {
    (void)arg;
    float *to[NB_CHANNELS], *from[NB_CHANNELS];
    for (int c = 0; c < NB_CHANNELS; c++) {
        to[c] = (float *)jack_port_get_buffer(to_crone[c], nframes);
        from[c] = (float *)jack_port_get_buffer(from_crone[c], nframes);
    }
    jack_adapter_t *a = atomic_load(&adapter);
    if (a == NULL) {
        for (int c = 0; c < NB_CHANNELS; c++) {
            memset(to[c], 0, nframes * sizeof(float));
        }
        return 0;
    }
    // into the jack graph (to crone), out of it (from crone)
    jack_adapter_pull_and_push(a, to, from, nframes);
    return 0;
}

static void on_shutdown(void *arg) {
    (void)arg;
    exit(0);
}

static void save_and_disconnect(const char *src, const char *dst) {
    if (n_saved < MAX_LINKS && jack_disconnect(client, src, dst) == 0) {
        snprintf(saved[n_saved][0], PORT_NAME, "%s", src);
        snprintf(saved[n_saved][1], PORT_NAME, "%s", dst);
        n_saved++;
    }
}

// crone's main inputs and outputs: take them over from the audio interface
static void rewire_to_au(void) {
    char name[64];
    n_saved = 0;
    for (int c = 0; c < NB_CHANNELS; c++) {
        snprintf(name, sizeof(name), "crone:input_%d", c + 1);
        jack_port_t *in = jack_port_by_name(client, name);
        if (in != NULL) {
            const char **src = jack_port_get_all_connections(client, in);
            for (int i = 0; src != NULL && src[i] != NULL; i++) {
                save_and_disconnect(src[i], name);
            }
            jack_free(src);
            jack_connect(client, jack_port_name(to_crone[c]), name);
        }
        snprintf(name, sizeof(name), "crone:output_%d", c + 1);
        jack_port_t *out = jack_port_by_name(client, name);
        if (out != NULL) {
            const char **dst = jack_port_get_all_connections(client, out);
            for (int i = 0; dst != NULL && dst[i] != NULL; i++) {
                if (strncmp(dst[i], "system:", 7) == 0) {
                    save_and_disconnect(name, dst[i]);
                }
            }
            jack_free(dst);
            jack_connect(client, name, jack_port_name(from_crone[c]));
        }
    }
}

static void rewire_back(void) {
    for (int c = 0; c < NB_CHANNELS; c++) {
        char name[64];
        snprintf(name, sizeof(name), "crone:input_%d", c + 1);
        jack_disconnect(client, jack_port_name(to_crone[c]), name);
        snprintf(name, sizeof(name), "crone:output_%d", c + 1);
        jack_disconnect(client, name, jack_port_name(from_crone[c]));
    }
    for (int i = 0; i < n_saved; i++) {
        jack_connect(client, saved[i][0], saved[i][1]);
    }
    n_saved = 0;
}

static void activate(uint32_t sample_rate) {
    jack_adapter_t *a = jack_create_adapter(NB_CHANNELS, NB_CHANNELS, NB_BLOCK, sample_rate,
                                            jack_get_buffer_size(client), jack_get_sample_rate(client));
    if (a == NULL) {
        fprintf(stderr, "auv3_bridge: cannot create adapter (%u Hz)\n", sample_rate);
        return;
    }
    atomic_store(&adapter, a);
    rewire_to_au();
    fprintf(stderr, "auv3_bridge: AU connected (%u Hz), norns audio goes through the DAW\n", sample_rate);
}

static void deactivate(void) {
    jack_adapter_t *a = atomic_exchange(&adapter, NULL);
    if (a == NULL) {
        return;
    }
    rewire_back();
    // let a running process cycle finish with the old adapter
    usleep(100000);
    jack_destroy_adapter(a);
    fprintf(stderr, "auv3_bridge: AU gone, norns audio back on the audio interface\n");
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void midi_forward(const uint8_t *bytes, int n) {
    uint8_t buf[sizeof(MIDIPacketList) + NB_MAX_MIDI];
    MIDIPacketList *list = (MIDIPacketList *)buf;
    MIDIPacket *pkt = MIDIPacketListInit(list);
    pkt = MIDIPacketListAdd(list, sizeof(buf), pkt, 0, n, bytes);
    if (pkt != NULL) {
        MIDIReceived(midi_source, list);
    }
}
#pragma clang diagnostic pop

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    jack_status_t status;
    client = jack_client_open("auv3", JackNoStartServer, &status);
    if (client == NULL) {
        fprintf(stderr, "auv3_bridge: no jack server\n");
        return 1;
    }
    for (int c = 0; c < NB_CHANNELS; c++) {
        char name[16];
        snprintf(name, sizeof(name), "out_%d", c + 1);
        to_crone[c] = jack_port_register(client, name, JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
        snprintf(name, sizeof(name), "in_%d", c + 1);
        from_crone[c] = jack_port_register(client, name, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    }
    jack_set_process_callback(client, process, NULL);
    jack_on_shutdown(client, on_shutdown, NULL);
    if (jack_activate(client) != 0) {
        fprintf(stderr, "auv3_bridge: cannot activate\n");
        return 1;
    }

    if (MIDIClientCreate(CFSTR("norns AUv3 bridge"), NULL, NULL, &midi_client) != noErr ||
        MIDISourceCreate(midi_client, CFSTR("norns AUv3"), &midi_source) != noErr) {
        fprintf(stderr, "auv3_bridge: no CoreMIDI source, DAW MIDI will not reach norns\n");
    }

    int port = getenv("NORNS_AUV3_PORT") ? atoi(getenv("NORNS_AUV3_PORT")) : NB_PORT;
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (sock < 0 || bind(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        fprintf(stderr, "auv3_bridge: cannot bind 127.0.0.1:%d (%s)\n", port, strerror(errno));
        return 1;
    }
    struct timeval tv = {0, 200000};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    fprintf(stderr, "auv3_bridge: waiting for the AU on 127.0.0.1:%d\n", port);

    uint8_t pkt[NB_MAX_PACKET];
    float in[NB_CHANNELS][NB_BLOCK], out[NB_CHANNELS][NB_BLOCK];
    float *inp[NB_CHANNELS], *outp[NB_CHANNELS];
    for (int c = 0; c < NB_CHANNELS; c++) {
        inp[c] = in[c];
        outp[c] = out[c];
    }
    uint32_t rate = 0;
    double last = 0;

    for (;;) {
        struct sockaddr_in from;
        socklen_t flen = sizeof(from);
        ssize_t n = recvfrom(sock, pkt, sizeof(pkt), 0, (struct sockaddr *)&from, &flen);
        if (n < (ssize_t)sizeof(nb_header_t)) {
            if (atomic_load(&adapter) != NULL && now_ms() - last > IDLE_TIMEOUT_MS) {
                deactivate();
                rate = 0;
            }
            continue;
        }
        nb_header_t h;
        memcpy(&h, pkt, sizeof(h));
        if (h.magic != NB_MAGIC) {
            continue;
        }
        last = now_ms();
        if (h.type == NB_MIDI) {
            if (h.frames <= NB_MAX_MIDI && n >= (ssize_t)(sizeof(h) + h.frames)) {
                midi_forward(pkt + sizeof(h), h.frames);
            }
            continue;
        }
        if (h.type == NB_BYE) {
            deactivate();
            rate = 0;
            continue;
        }
        if (h.type != NB_AUDIO || h.frames != NB_BLOCK || n != (ssize_t)(sizeof(h) + NB_AUDIO_BYTES(NB_BLOCK))) {
            continue;
        }
        if (h.sample_rate != rate) {
            deactivate();
            rate = h.sample_rate;
            activate(rate);
        }
        jack_adapter_t *a = atomic_load(&adapter);
        for (int c = 0; c < NB_CHANNELS; c++) {
            memcpy(in[c], pkt + sizeof(h) + c * NB_BLOCK * sizeof(float), NB_BLOCK * sizeof(float));
        }
        if (a == NULL || jack_adapter_push_and_pull(a, inp, outp, NB_BLOCK) != 0) {
            memset(out, 0, sizeof(out));
        }
        for (int c = 0; c < NB_CHANNELS; c++) {
            memcpy(pkt + sizeof(h) + c * NB_BLOCK * sizeof(float), out[c], NB_BLOCK * sizeof(float));
        }
        sendto(sock, pkt, sizeof(h) + NB_AUDIO_BYTES(NB_BLOCK), 0, (struct sockaddr *)&from, flen);
    }
}
