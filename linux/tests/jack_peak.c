/*
 * jack_peak.c: the largest sample that arrives on some JACK output ports within a time (a headless "is there sound" check).
 *
 * cc -std=gnu11 linux/tests/jack_peak.c -o /tmp/jack_peak -ljack -lm
 * usage: jack_peak SECONDS PORT [PORT...]      prints "PEAK <value> <port count connected>"  (value 0 when silent or nothing connected)
 */
#include <jack/jack.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MAXP 8
static jack_port_t *in[MAXP];
static int nin = 0;
static volatile float peak = 0;

static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    for (int p = 0; p < nin; p++) {
        const float *b = jack_port_get_buffer(in[p], n);
        for (jack_nframes_t i = 0; i < n; i++) {
            float a = fabsf(b[i]);
            if (a > peak) {
                peak = a;
            }
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: jack_peak SECONDS PORT...\n");
        return 2;
    }
    double secs = atof(argv[1]);
    jack_status_t st;
    jack_client_t *c = jack_client_open("peak_check", JackNoStartServer, &st);
    if (c == NULL) {
        printf("PEAK 0 0 (no jack server)\n");
        return 1;
    }
    jack_set_process_callback(c, process, NULL);
    int connected = 0;
    for (int i = 2; i < argc && nin < MAXP; i++) {
        char name[16];
        snprintf(name, sizeof name, "in%d", nin);
        in[nin] = jack_port_register(c, name, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
        if (in[nin] == NULL) {
            continue;
        }
        nin++;
    }
    jack_activate(c);
    for (int i = 0; i < nin; i++) {
        char mine[64];
        snprintf(mine, sizeof mine, "peak_check:in%d", i);
        if (jack_connect(c, argv[2 + i], mine) == 0) {
            connected++;
        }
    }
    usleep((useconds_t)(secs * 1e6));
    printf("PEAK %.5f %d\n", peak, connected);
    jack_client_close(c);
    return 0;
}
