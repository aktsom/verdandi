#pragma once

#ifndef __APPLE__
#include <alsa/asoundlib.h>
#endif
#include <stdbool.h>
#include <sys/types.h>

#include "device_common.h"

#ifdef __cplusplus
extern "C" {
#endif

struct dev_midi {
    struct dev_common dev;
    bool clock_enabled;
#ifdef __APPLE__
    // CoreMIDI object refs (UInt32), see platform/macos/device_midi_coremidi.inc
    uint32_t src;     // MIDIEndpointRef we read from (0 = none)
    uint32_t dst;     // MIDIEndpointRef we send to (0 = none)
    uint32_t in_port; // MIDIPortRef connected to src
    uint32_t vsrc;    // virtual device: our own source, others receive what we send
    uint32_t vdst;    // virtual device: our own destination, others send to us
    int pipe_rd;      // CoreMIDI callback -> pipe -> dev_midi_start reader thread
    int pipe_wr;
#else
    snd_rawmidi_t *handle_in;
    snd_rawmidi_t *handle_out;
#ifdef NORNS_LINUX_DESKTOP
    // the virtual keyboard window's device ("norns keys"): it reads a pipe, not a rawmidi port
    bool from_pipe;
    int pipe_rd;
    // the JACK MIDI input feeds the clock itself, with the time of each message (jack_midi_in.cc)
    bool clock_timed;
    // the JACK MIDI device ("virtual") also sends: its output is the JACK port Verdandi:midi_out (jack_midi_in.cc)
    bool jack_out;
    // a USB / ALSA rawmidi device: which of the ports of its node this is, and whether the read thread found the device gone (-ENODEV: unplugged, powered off). the device list removes a gone device without
    // waiting for a udev event that may never come, and a new device of the same node replaces it (docs/port/KNOWN-ISSUES.md 36)
    unsigned int port_index;
    volatile int gone;
    // M37: when a write that was dropped was last said in the log (a device that takes no data is said once in a while, not at every message)
    double last_drop_say;
#ifdef NORNS_WINDOWS
    // the Windows MIDI layer (platform/windows/midi): the port pair of this device (midi_port.h)
    void *win_port;
    bool win_osc;
#endif
#endif
#endif
};

extern unsigned int dev_midi_port_count(const char *path);
#ifdef NORNS_WINDOWS
// Windows: is the device with this path ("winmm:name", "osc:...") in the last scan?
extern int dev_midi_node_present(const char *path);
#endif

#if defined(NORNS_LINUX_DESKTOP) && !defined(NORNS_WINDOWS)
// why the last dev_midi_init of this thread failed: 1 = the port is busy (another program has it open), 0 = another reason; the sentence goes to `why` (the device list says it once)
extern int dev_midi_open_failure(char *why, size_t n);
#endif
extern int dev_midi_init(void *self, unsigned int port_index, bool multiport_device);
extern int dev_midi_virtual_init(void *self);

extern void dev_midi_deinit(void *self);
extern void *dev_midi_start(void *self);
extern ssize_t dev_midi_send(void *self, uint8_t *data, size_t n);

#ifdef __cplusplus
}
#endif
