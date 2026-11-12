// -*- c++ -*-
// device_midi_win.inc: the MIDI devices of the Windows build for device_midi.cc (included in place of the ALSA functions, as the macOS build includes device_midi_coremidi.inc), so the byte parser above
// (running status, sysex chunks, events to Lua) stays the shared one. the system part is platform/windows/midi: midi_winmm.c (WinMM) behind midi_port.cc.
//
// device paths are "winmm:<name>" (all ports of one device; the port index picks one) and "osc:127.0.0.1:<port>" (the OSC input). input: the WinMM callback hands clock and song position to the clock at once and puts all
// bytes in a ring; dev_midi_start reads the ring on the device thread exactly like snd_rawmidi_read on Linux.

#include "platform/windows/midi/midi_monitor.h"
#include "platform/windows/midi/midi_port.h"
#include "platform/windows/midi/midi_win.h"
#include "platform/windows/midi/midi_winmm.h"
#include "platform/windows/midi/osc_in.h"

extern "C" void vmidi_win_port_opened(const char *key, const char *name, void *port);
extern "C" void vmidi_win_port_closed(void *port);

static void win_clock_msg(uint8_t m) { clock_midi_handle_message_at(m, clock_get_system_time()); }
static void win_clock_spp(uint16_t b) { clock_midi_handle_song_position(b); }
static const vmidi_hooks WIN_HOOKS = {win_clock_msg, win_clock_spp};

unsigned int dev_midi_port_count(const char *path) {
    vmidi_found f;
    if (path == NULL || !vmidi_monitor_find(path, &f)) {
        return 0;
    }
    return (unsigned int)f.nports;
}

int dev_midi_node_present(const char *path) {
    return path != NULL && vmidi_monitor_present(path);
}

int dev_midi_init(void *self, unsigned int port_index, bool multiport_device) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;
    vmidi_found f;

    midi->win_port = NULL;
    midi->win_osc = false;
    midi->port_index = port_index;
    midi->gone = 0;
    if (!vmidi_monitor_find(base->path, &f) || port_index >= (unsigned)f.nports) {
        return -1;
    }
    midi->clock_enabled = true;
    midi->clock_timed = true; // the clock gets its messages from the callback, with the time of arrival
    char shown[160];
    snprintf(shown, sizeof shown, multiport_device ? "%s %u" : "%s", f.name, port_index + 1);
    if (multiport_device) {
        char *with_port = strdup(shown);
        if (with_port == NULL) {
            return -1;
        }
        base->name = with_port;
    }
    char note[200] = "";
    vmidi_port *p;
    if (f.extra) {
        p = vmidi_port_new_push(&WIN_HOOKS, (const volatile uint8_t *)&midi->clock_enabled);
        if (p == NULL || vmidi_osc_start(p, vmidi_win_osc_port(), note, sizeof note) != 0) {
            vmidi_note_set(base->path, f.name, note[0] ? note : "the OSC input did not start");
            if (p != NULL) {
                vmidi_port_close(p);
                vmidi_port_unref(p);
            }
            return -1;
        }
        midi->win_osc = true;
    } else {
        p = vmidi_port_open(&vmidi_winmm_backend, f.in_idx[port_index], f.out_idx[port_index], &WIN_HOOKS, (const volatile uint8_t *)&midi->clock_enabled, note, sizeof note);
        if (p == NULL) {
            vmidi_note_set(base->path, shown, note[0] ? note : "did not open");
            return -1;
        }
    }
    if (note[0]) {
        vmidi_note_set(base->path, shown, note); // opened with a part missing (an input held by another program): said on the DEVICES page
    } else {
        vmidi_note_clear(base->path);
    }
    midi->win_port = p;
    vmidi_win_port_opened(base->path, f.name, p);
    if (!vmidi_port_has_output(p)) {
        fprintf(stderr, "midi: %s opened (only input)\n", shown);
    } else if (!vmidi_port_has_input(p)) {
        fprintf(stderr, "midi: %s opened (only output)\n", shown);
    } else {
        fprintf(stderr, "midi: %s opened (input and output)\n", shown);
    }
    base->start = vmidi_port_has_input(p) ? &dev_midi_start : NULL;
    base->deinit = &dev_midi_deinit;
    return 0;
}

int dev_midi_virtual_init(void *self) {
    (void)self;
    return -1; // the "virtual" device of the Linux build is a JACK port; here other programs' ports are ordinary devices (loopMIDI and others)
}

void dev_midi_deinit(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    if (midi->win_osc) {
        vmidi_osc_stop();
    }
    if (midi->win_port != NULL) {
        vmidi_win_port_closed(midi->win_port);
        vmidi_port_close((vmidi_port *)midi->win_port);
        vmidi_port_unref((vmidi_port *)midi->win_port);
        midi->win_port = NULL;
    }
}

void *dev_midi_start(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;
    midi_input_state_t state;
    long n;

    memset(&state, 0, sizeof state);
    if (midi->win_port == NULL) {
        fprintf(stderr, "starting a reader thread for a non-input MIDI device; shouldn't get here!\n");
        return NULL;
    }
    while ((n = vmidi_port_read((vmidi_port *)midi->win_port, state.buffer, DEV_MIDI_INPUT_BUFFER_SIZE)) > 0) {
        if (dev_midi_consume_buffer(&state, n, midi) != n) {
            fprintf(stderr, "midi inconsistency for device: %s\n", base->name);
        }
    }
    return NULL;
}

ssize_t dev_midi_send(void *self, uint8_t *data, size_t n) {
    struct dev_midi *midi = (struct dev_midi *)self;
    if (midi->win_port == NULL) {
        return -1;
    }
    return (ssize_t)vmidi_port_send((vmidi_port *)midi->win_port, data, n);
}
