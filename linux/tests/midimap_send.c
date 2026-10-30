/*
 * midimap_send.c: a JACK MIDI client that plays some controller into norns' JACK MIDI input (client "Verdandi", port "midi_in"), one three-byte message every 20 ms. used by the MIDI MAP scenario of
 * linux/tests/run_all.sh (docs/port/midi-map-plan.md): the messages take the real way, JACK MIDI -> the pipe -> device_midi -> Lua.
 *
 *   cc -std=gnu11 midimap_send.c -o midimap_send $(pkg-config --cflags --libs jack)
 *   midimap_send B0:47:01 B0:47:7F ...      (status:data1:data2 in hex)
 */

#include <errno.h>
#include <jack/jack.h>
#include <jack/midiport.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static jack_port_t *out;
static unsigned char msgs[256][3];
static int nmsg;
static _Atomic int next_msg = 0;
static _Atomic int go = 0;
static jack_nframes_t gap;
static jack_nframes_t acc;

static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    void *buf = jack_port_get_buffer(out, n);
    jack_midi_clear_buffer(buf);
    if (!atomic_load(&go)) {
        return 0;
    }
    acc += n;
    int i = atomic_load(&next_msg);
    if (acc >= gap && i < nmsg) {
        acc = 0;
        jack_midi_event_write(buf, 0, msgs[i], 3);
        atomic_store(&next_msg, i + 1);
    }
    return 0;
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc && nmsg < 256; i++) {
        unsigned a, b, c;
        if (sscanf(argv[i], "%x:%x:%x", &a, &b, &c) == 3) {
            msgs[nmsg][0] = (unsigned char)a;
            msgs[nmsg][1] = (unsigned char)b;
            msgs[nmsg][2] = (unsigned char)c;
            nmsg++;
        }
    }
    jack_client_t *client = jack_client_open("mmsend", JackNoStartServer, NULL);
    if (!client) {
        fprintf(stderr, "midimap_send: no JACK server\n");
        return 1;
    }
    out = jack_port_register(client, "out", JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    gap = jack_get_sample_rate(client) / 50;
    jack_set_process_callback(client, process, NULL);
    jack_activate(client);
    int connected = 0;
    for (int i = 0; i < 200 && !connected; i++) {
        int r = jack_connect(client, "mmsend:out", "Verdandi:midi_in");
        connected = (r == 0 || r == EEXIST);
        if (!connected) {
            usleep(100000);
        }
    }
    if (!connected) {
        fprintf(stderr, "midimap_send: no Verdandi:midi_in\n");
        return 1;
    }
    atomic_store(&go, 1);
    for (int i = 0; i < 400 && atomic_load(&next_msg) < nmsg; i++) {
        usleep(10000);
    }
    usleep(300000);
    jack_client_close(client);
    return 0;
}
