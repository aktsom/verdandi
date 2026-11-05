/*
 * aseq_dump_test.c: an aseqdump-style receiver for norns' ALSA sequencer output (client "Verdandi", port "Verdandi out", matron/src/platform/linux/aseq_out.cc). used by linux/tests/run_all.sh on a machine
 * with a kernel sequencer (/dev/snd/seq: not in the CI containers, where the test is skipped).
 *
 *   cc -std=gnu11 aseq_dump_test.c -o aseq_dump_test -lasound
 *   aseq_dump_test <client name> <seconds to listen> <subscribe: 1 or 0>
 *
 * waits up to 30 s for the client "Verdandi" with its port; with subscribe=1 it subscribes to it (like a DAW that opens the MIDI input), with 0 it only listens (nothing is connected). prints "EV <ms since the first
 * event> <hex bytes>" per event, the bytes as a MIDI cable would carry them (so the result is compared with what the script sent, as for the JACK output), then "aseq_dump_test: done <n> events".
 */
#include <alsa/asoundlib.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static int find_port(snd_seq_t *seq, int *client_out, int *port_out) {
    snd_seq_client_info_t *ci;
    snd_seq_port_info_t *pi;
    snd_seq_client_info_alloca(&ci);
    snd_seq_port_info_alloca(&pi);
    snd_seq_client_info_set_client(ci, -1);
    while (snd_seq_query_next_client(seq, ci) >= 0) {
        if (strcmp(snd_seq_client_info_get_name(ci), "Verdandi") != 0) continue;
        int c = snd_seq_client_info_get_client(ci);
        snd_seq_port_info_set_client(pi, c);
        snd_seq_port_info_set_port(pi, -1);
        while (snd_seq_query_next_port(seq, pi) >= 0) {
            if (strcmp(snd_seq_port_info_get_name(pi), "Verdandi out") == 0) {
                *client_out = c;
                *port_out = snd_seq_port_info_get_port(pi);
                return 1;
            }
        }
    }
    return 0;
}

static void print_event(double ms, const snd_seq_event_t *e) {
    unsigned char b[3];
    int n = 0;
    switch (e->type) {
    case SND_SEQ_EVENT_NOTEON: b[0] = 0x90 | e->data.note.channel; b[1] = e->data.note.note; b[2] = e->data.note.velocity; n = 3; break;
    case SND_SEQ_EVENT_NOTEOFF: b[0] = 0x80 | e->data.note.channel; b[1] = e->data.note.note; b[2] = e->data.note.velocity; n = 3; break;
    case SND_SEQ_EVENT_KEYPRESS: b[0] = 0xa0 | e->data.note.channel; b[1] = e->data.note.note; b[2] = e->data.note.velocity; n = 3; break;
    case SND_SEQ_EVENT_CONTROLLER: b[0] = 0xb0 | e->data.control.channel; b[1] = e->data.control.param; b[2] = e->data.control.value; n = 3; break;
    case SND_SEQ_EVENT_PGMCHANGE: b[0] = 0xc0 | e->data.control.channel; b[1] = e->data.control.value; n = 2; break;
    case SND_SEQ_EVENT_CHANPRESS: b[0] = 0xd0 | e->data.control.channel; b[1] = e->data.control.value; n = 2; break;
    case SND_SEQ_EVENT_PITCHBEND: { int v = e->data.control.value + 8192; b[0] = 0xe0 | e->data.control.channel; b[1] = v & 127; b[2] = v >> 7; n = 3; break; }
    case SND_SEQ_EVENT_SONGPOS: b[0] = 0xf2; b[1] = e->data.control.value & 127; b[2] = (e->data.control.value >> 7) & 127; n = 3; break;
    case SND_SEQ_EVENT_SONGSEL: b[0] = 0xf3; b[1] = e->data.control.value; n = 2; break;
    case SND_SEQ_EVENT_QFRAME: b[0] = 0xf1; b[1] = e->data.control.value; n = 2; break;
    case SND_SEQ_EVENT_TUNE_REQUEST: b[0] = 0xf6; n = 1; break;
    case SND_SEQ_EVENT_CLOCK: b[0] = 0xf8; n = 1; break;
    case SND_SEQ_EVENT_START: b[0] = 0xfa; n = 1; break;
    case SND_SEQ_EVENT_CONTINUE: b[0] = 0xfb; n = 1; break;
    case SND_SEQ_EVENT_STOP: b[0] = 0xfc; n = 1; break;
    case SND_SEQ_EVENT_SENSING: b[0] = 0xfe; n = 1; break;
    case SND_SEQ_EVENT_RESET: b[0] = 0xff; n = 1; break;
    case SND_SEQ_EVENT_SYSEX: {
        printf("EV %.2f", ms);
        for (unsigned i = 0; i < e->data.ext.len; i++) printf(" %02x", ((unsigned char *)e->data.ext.ptr)[i]);
        printf("\n");
        return;
    }
    default: return; // port subscription and other system events are not MIDI
    }
    printf("EV %.2f", ms);
    for (int i = 0; i < n; i++) printf(" %02x", b[i]);
    printf("\n");
}

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "aseq_cap";
    int seconds = argc > 2 ? atoi(argv[2]) : 14;
    int subscribe = argc > 3 ? atoi(argv[3]) : 1;
    snd_seq_t *seq;
    if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_INPUT, SND_SEQ_NONBLOCK) < 0) {
        printf("aseq_dump_test: no ALSA sequencer\n");
        return 2;
    }
    snd_seq_set_client_name(seq, name);
    int my = snd_seq_create_simple_port(seq, "in", SND_SEQ_PORT_CAP_WRITE | SND_SEQ_PORT_CAP_SUBS_WRITE, SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
    int client = -1, port = -1;
    for (int i = 0; i < 300 && !find_port(seq, &client, &port); i++) usleep(100000);
    if (client < 0) {
        printf("aseq_dump_test: no client Verdandi with the port Verdandi out\n");
        return 1;
    }
    if (subscribe && snd_seq_connect_from(seq, my, client, port) < 0) {
        printf("aseq_dump_test: could not subscribe\n");
        return 1;
    }
    printf("aseq_dump_test: %s\n", subscribe ? "subscribed" : "listening, not subscribed");
    fflush(stdout);
    int npfd = snd_seq_poll_descriptors_count(seq, POLLIN);
    struct pollfd *pfd = alloca(npfd * sizeof *pfd);
    snd_seq_poll_descriptors(seq, pfd, npfd, POLLIN);
    double end = now_ms() + seconds * 1000.0, first = -1;
    int count = 0;
    while (now_ms() < end) {
        poll(pfd, npfd, 100);
        snd_seq_event_t *ev;
        while (snd_seq_event_input(seq, &ev) >= 0 && ev != NULL) {
            double t = now_ms();
            if (ev->type == SND_SEQ_EVENT_PORT_SUBSCRIBED || ev->type == SND_SEQ_EVENT_PORT_UNSUBSCRIBED || ev->type == SND_SEQ_EVENT_CLIENT_START ||
                ev->type == SND_SEQ_EVENT_CLIENT_EXIT || ev->type == SND_SEQ_EVENT_PORT_START || ev->type == SND_SEQ_EVENT_PORT_EXIT) continue;
            if (first < 0) first = t;
            print_event(t - first, ev);
            count++;
        }
    }
    printf("aseq_dump_test: done %d events\n", count);
    snd_seq_close(seq);
    return 0;
}
