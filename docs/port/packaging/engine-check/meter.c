// meter <seconds>: peak of crone:output_1/2 over the time, one line "PEAK <value>"
#include <jack/jack.h>
#include <stdio.h>
#include <math.h>
#include <unistd.h>
static jack_port_t *p[2];
static volatile float peak;
static int process(jack_nframes_t n, void *a) {
    for (int c = 0; c < 2; c++) {
        float *b = jack_port_get_buffer(p[c], n);
        for (jack_nframes_t i = 0; i < n; i++) if (fabsf(b[i]) > peak) peak = fabsf(b[i]);
    }
    return 0;
}
int main(int argc, char **argv) {
    jack_client_t *c = jack_client_open("meter", JackNoStartServer, 0);
    if (!c) { puts("PEAK nojack"); return 1; }
    p[0] = jack_port_register(c, "in1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    p[1] = jack_port_register(c, "in2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    jack_set_process_callback(c, process, 0);
    jack_activate(c);
    jack_connect(c, "crone:output_1", "meter:in1");
    jack_connect(c, "crone:output_2", "meter:in2");
    sleep(argc > 1 ? atoi(argv[1]) : 2);
    printf("PEAK %f\n", peak);
    return 0;
}
