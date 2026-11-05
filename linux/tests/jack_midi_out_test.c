/*
 * jack_midi_out_test.c: a JACK MIDI client that listens to norns' JACK MIDI output (client "Verdandi", port "midi_out") and prints every message with its time.
 * used by linux/tests/run_all.sh (the virtual MIDI device sends through JACK MIDI).
 *
 *   cc -std=gnu11 jack_midi_out_test.c -o jack_midi_out_test $(pkg-config --cflags --libs jack)
 *   jack_midi_out_test <client name> <seconds to listen> <connect: 1 or 0> [sink port name of the client, default "in"]
 *
 * waits up to 30 s for Verdandi:midi_out; with connect=1 it links it to its own input port (with 0 it only listens to nothing: a client that is there but not
 * connected, to see that norns does not care). prints "EV <ms since the first event> <hex bytes>" per message, then "jack_midi_out_test: done <n> events".
 * recording happens in the process callback into a fixed array (no printing, no allocation there).
 */
#include <jack/jack.h>
#include <jack/midiport.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAXEV 20000
typedef struct { unsigned int frame; unsigned short len; unsigned char data[24]; } ev_t;
static ev_t evs[MAXEV];
static atomic_int nev = 0;
static jack_client_t *client;
static jack_port_t *in_port;

static int process(jack_nframes_t nframes, void *arg) {
    (void)arg;
    void *buf = jack_port_get_buffer(in_port, nframes);
    jack_nframes_t n = jack_midi_get_event_count(buf);
    jack_nframes_t start = jack_last_frame_time(client);
    for (jack_nframes_t i = 0; i < n; i++) {
        jack_midi_event_t e;
        if (jack_midi_event_get(&e, buf, i) != 0) continue;
        int k = atomic_load(&nev);
        if (k >= MAXEV) continue;
        evs[k].frame = start + e.time;
        evs[k].len = (unsigned short)e.size;
        memcpy(evs[k].data, e.buffer, e.size < sizeof evs[k].data ? e.size : sizeof evs[k].data);
        atomic_store(&nev, k + 1);
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "midi_cap";
    int seconds = argc > 2 ? atoi(argv[2]) : 14;
    int connect = argc > 3 ? atoi(argv[3]) : 1;
    const char *sink = argc > 4 ? argv[4] : "in";
    client = jack_client_open(name, JackNoStartServer, NULL);
    if (client == NULL) { fprintf(stderr, "jack_midi_out_test: no JACK server\n"); return 2; }
    jack_nframes_t sr = jack_get_sample_rate(client);
    in_port = jack_port_register(client, sink, JACK_DEFAULT_MIDI_TYPE, JackPortIsInput, 0);
    jack_set_process_callback(client, process, NULL);
    jack_activate(client);
    char mine[128];
    snprintf(mine, sizeof mine, "%s:%s", name, sink);
    int ok = 0;
    for (int i = 0; i < 300 && !ok; i++) {
        if (jack_port_by_name(client, "Verdandi:midi_out") != NULL) {
            ok = connect ? jack_connect(client, "Verdandi:midi_out", mine) == 0 : 1;
        }
        if (!ok) usleep(100000);
    }
    if (!ok) { printf("jack_midi_out_test: no port Verdandi:midi_out\n"); jack_client_close(client); return 1; }
    printf("jack_midi_out_test: %s\n", connect ? "connected" : "listening, not connected");
    fflush(stdout);
    sleep((unsigned)seconds);
    int n = atomic_load(&nev);
    for (int i = 0; i < n; i++) {
        double ms = (double)(int)(evs[i].frame - evs[0].frame) * 1000.0 / sr;
        printf("EV %.2f", ms);
        for (int b = 0; b < evs[i].len && b < (int)sizeof evs[i].data; b++) printf(" %02x", evs[i].data[b]);
        if (evs[i].len > sizeof evs[i].data) printf(" .. (%d bytes)", evs[i].len);
        printf("\n");
    }
    printf("jack_midi_out_test: done %d events\n", n);
    jack_client_close(client);
    return 0;
}
