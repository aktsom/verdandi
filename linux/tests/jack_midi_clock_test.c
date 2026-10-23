/*
 * jack_midi_clock_test.c: a JACK MIDI client that plays a "DAW" at 120 BPM into norns' JACK MIDI input
 * (client "Verdandi", port "midi_in"), with frame-accurate timing. used by linux/tests/run_all.sh.
 *
 *   cc -std=gnu11 jack_midi_clock_test.c -o jack_midi_clock_test $(pkg-config --cflags --libs jack)
 *   jack_midi_clock_test [seconds to wait for the port, default 30]
 *
 * the clock (24 ticks per beat) runs the whole time; on top of it, in seconds after the connection:
 *   0.0 start 0xfa     1.0 note on 60 vel 100     1.2 note off 60
 *   3.0 song position 64 (16 beats)               4.0 stop 0xfc
 *   5.0 continue 0xfb  7.0 start 0xfa (again)     9.5 end
 */

#include <jack/jack.h>
#include <jack/midiport.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static jack_client_t *client;
static jack_port_t *out;
static jack_nframes_t sr;
static _Atomic int running = 0;          // 1 once connected: the timeline starts
static _Atomic long long t0_frame = 0;   // frame counter at the first cycle of the timeline
static long long frame_counter = 0;      // frames since activation (process thread only)
static long long next_tick = 0;          // timeline frame of the next clock tick
static int next_msg = 0;

typedef struct {
    double t;
    unsigned char len;
    unsigned char data[3];
} msg_t;

static const msg_t script[] = {
    {0.0, 1, {0xfa}},
    {1.0, 3, {0x90, 60, 100}},
    {1.2, 3, {0x80, 60, 0}},
    {3.0, 3, {0xf2, 64, 0}}, // lsb 64, msb 0
    {4.0, 1, {0xfc}},
    {5.0, 1, {0xfb}},
    {7.0, 1, {0xfa}},
};
#define NMSG ((int)(sizeof script / sizeof script[0]))
#define END_T 9.5

static atomic_int finished = 0;

static int process(jack_nframes_t nframes, void *arg) {
    (void)arg;
    void *buf = jack_port_get_buffer(out, nframes);
    jack_midi_clear_buffer(buf);
    if (!atomic_load(&running)) {
        frame_counter += nframes;
        return 0;
    }
    if (atomic_load(&t0_frame) == 0) {
        atomic_store(&t0_frame, frame_counter + 1); // +1: 0 means "not set"
    }
    long long base = atomic_load(&t0_frame) - 1;
    double tick_period = sr * 0.5 / 24.0; // 120 BPM
    for (jack_nframes_t i = 0; i < nframes; i++) {
        long long tl = frame_counter + i - base; // timeline frame
        // everything due at this frame: script messages first, then the clock tick
        while (next_msg < NMSG && tl >= (long long)(script[next_msg].t * sr)) {
            jack_midi_event_write(buf, i, script[next_msg].data, script[next_msg].len);
            next_msg++;
        }
        if ((double)tl >= (double)next_tick * tick_period) {
            unsigned char tick = 0xf8;
            jack_midi_event_write(buf, i, &tick, 1);
            next_tick++;
        }
        if (tl >= (long long)(END_T * sr)) {
            atomic_store(&finished, 1);
        }
    }
    frame_counter += nframes;
    return 0;
}

int main(int argc, char **argv) {
    int wait_s = argc > 1 ? atoi(argv[1]) : 30;
    client = jack_client_open("midi_test", JackNoStartServer, NULL);
    if (client == NULL) {
        fprintf(stderr, "jack_midi_clock_test: no JACK server\n");
        return 2;
    }
    sr = jack_get_sample_rate(client);
    out = jack_port_register(client, "out", JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(client, process, NULL);
    jack_activate(client);
    int ok = 0;
    for (int i = 0; i < wait_s * 10 && !ok; i++) {
        ok = jack_connect(client, "midi_test:out", "Verdandi:midi_in") == 0;
        if (!ok) {
            usleep(100000);
        }
    }
    if (!ok) {
        fprintf(stderr, "jack_midi_clock_test: no port Verdandi:midi_in\n");
        jack_client_close(client);
        return 1;
    }
    printf("jack_midi_clock_test: connected\n");
    fflush(stdout);
    atomic_store(&running, 1);
    while (!atomic_load(&finished)) {
        usleep(50000);
    }
    usleep(300000);
    printf("jack_midi_clock_test: done\n");
    jack_client_close(client);
    return 0;
}
