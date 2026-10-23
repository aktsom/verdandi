/* fake_card <client name> [nomidi|app]: a JACK client that looks like a sound card under PipeWire:
 * capture_FL/FR (output, physical, terminal), playback_FL/FR (input, physical, terminal), monitor_FL/FR
 * (output, not physical) and a physical MIDI port beside them. "app": an application stream instead:
 * output_FL/FR (output, not physical) only. for linux/tests/audio_ports_test.sh. runs until killed. */
#include <jack/jack.h>
#include <jack/midiport.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static jack_port_t *out[2], *in[2];
static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    for (int i = 0; i < 2; i++) {
        memset(jack_port_get_buffer(out[i], n), 0, n * sizeof(float));
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return 2;
    }
    jack_client_t *c = jack_client_open(argv[1], JackNoStartServer, NULL);
    if (!c) {
        fprintf(stderr, "fake_card: no jack\n");
        return 1;
    }
    if (argc > 2 && strcmp(argv[2], "app") == 0) {
        out[0] = jack_port_register(c, "output_FL", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
        out[1] = jack_port_register(c, "output_FR", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
        jack_set_process_callback(c, process, NULL);
        jack_activate(c);
        for (;;) {
            sleep(1);
        }
    }
    const unsigned long f = JackPortIsPhysical | JackPortIsTerminal;
    out[0] = jack_port_register(c, "capture_FL", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput | f, 0);
    out[1] = jack_port_register(c, "capture_FR", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput | f, 0);
    in[0] = jack_port_register(c, "playback_FL", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput | f, 0);
    in[1] = jack_port_register(c, "playback_FR", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput | f, 0);
    jack_port_register(c, "monitor_FL", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    jack_port_register(c, "monitor_FR", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    if (!(argc > 2 && strcmp(argv[2], "nomidi") == 0)) {
        /* registered first in the list of a real system: a physical MIDI port must not be taken for audio */
        jack_port_register(c, "midi_capture", JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput | f, 0);
        jack_port_register(c, "midi_playback", JACK_DEFAULT_MIDI_TYPE, JackPortIsInput | f, 0);
    }
    jack_set_process_callback(c, process, NULL);
    jack_activate(c);
    for (;;) {
        sleep(1);
    }
}
