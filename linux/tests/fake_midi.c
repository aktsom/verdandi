/* fake_midi <client name> [port name]: a JACK client with one MIDI output port (a DAW or a Midi-Bridge port).
 * for linux/tests/midi_autoconnect_test.sh. runs until killed. */
#include <jack/jack.h>
#include <jack/midiport.h>
#include <stdio.h>
#include <unistd.h>

static jack_port_t *port;
static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    jack_midi_clear_buffer(jack_port_get_buffer(port, n));
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return 2;
    }
    jack_client_t *c = jack_client_open(argv[1], JackNoStartServer, NULL);
    if (!c) {
        return 1;
    }
    port = jack_port_register(c, argc > 2 ? argv[2] : "out", JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(c, process, NULL);
    jack_activate(c);
    for (;;) {
        sleep(1);
    }
}
