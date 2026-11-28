/* fake_midi <client name> [port name ...]: a JACK client with MIDI output ports (one, called "out", when none is named) (a DAW or a Midi-Bridge port).
 * for linux/tests/midi_autoconnect_test.sh. runs until killed. */
#include <jack/jack.h>
#include <jack/midiport.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static jack_port_t *port;
static jack_port_t *more[8];
static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    jack_midi_clear_buffer(jack_port_get_buffer(port, n));
    for (int i = 0; i < 8; i++) {
        if (more[i]) jack_midi_clear_buffer(jack_port_get_buffer(more[i], n));
    }
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
    for (int i = 3; i < argc && i < 11; i++) { // more ports of the same client (Midi-Bridge has one per ALSA client)
        more[i - 3] = jack_port_register(c, argv[i], JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    }
    jack_set_process_callback(c, process, NULL);
    jack_activate(c);
    /* M44: FAKE_MIDI_LINK_TO=<input port>: this client links its first port to that port itself, as soon as the port exists (the way a
     * sound system that restores a link, or a jack_connect that said "no" and linked all the same, behaves for Verdandi's auto-connect) */
    const char *to = getenv("FAKE_MIDI_LINK_TO");
    if (to != NULL && to[0] != 0) {
        for (int i = 0; i < 600; i++) {
            if (jack_connect(c, jack_port_name(port), to) == 0) {
                break;
            }
            usleep(50000);
        }
    }
    for (;;) {
        sleep(1);
    }
}
