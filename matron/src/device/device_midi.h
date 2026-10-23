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
#endif
#endif
};

extern unsigned int dev_midi_port_count(const char *path);

extern int dev_midi_init(void *self, unsigned int port_index, bool multiport_device);
extern int dev_midi_virtual_init(void *self);

extern void dev_midi_deinit(void *self);
extern void *dev_midi_start(void *self);
extern ssize_t dev_midi_send(void *self, uint8_t *data, size_t n);

#ifdef __cplusplus
}
#endif
