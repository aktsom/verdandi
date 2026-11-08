// linux/tests/namamp_boot_test.sh: a JACK client "nam_tone" that plays a sine (freq, amp) on one output port until it is killed
#include <jack/jack.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static jack_port_t *out; static double ph = 0, freq = 110, amp = 0.1; static double sr = 48000;
static int process(jack_nframes_t n, void *a) { (void)a; float *b = jack_port_get_buffer(out, n); for (jack_nframes_t i = 0; i < n; i++) { b[i] = (float)(amp * sin(ph)); ph += 2 * M_PI * freq / sr; if (ph > 2 * M_PI) ph -= 2 * M_PI; } return 0; }
int main(int argc, char **argv) {
    if (argc > 1) freq = atof(argv[1]);
    if (argc > 2) amp = atof(argv[2]);
    jack_client_t *c = jack_client_open("nam_tone", JackNoStartServer, NULL);
    if (!c) { fprintf(stderr, "no jack\n"); return 1; }
    sr = jack_get_sample_rate(c);
    out = jack_port_register(c, "out", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(c, process, NULL);
    jack_activate(c);
    for (int i = 4; i < argc; i++) { char buf[64]; (void)buf; }
    for (;;) sleep(1);
}
