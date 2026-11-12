// midi_monitor.h: which MIDI devices are there, now and again: one scan of the backend's ports (midi_core.h groups them into devices), the difference to the list, and the thread that does it when the system says
// something changed and every 2 seconds besides. the list itself (norns' device list) is behind the sink, so that the tests can look at what would be added and removed. docs/port/phase-m4.md.
#pragma once

#include <stddef.h>
#include "midi_port.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vmidi_sink {
    void (*add)(const char *key, const char *name);
    void (*remove)(const char *key);
    int (*ports_listed)(const char *key); /* how many ports of the device are in the list now */
} vmidi_sink;

typedef struct vmidi_found {
    char name[96];
    int nports;
    int in_idx[32];
    int out_idx[32];
    int extra; /* not a MIDI driver's device (the OSC input): no indices */
} vmidi_found;

void vmidi_monitor_init(const vmidi_backend *be, const vmidi_sink *sink, const char *ignore_setting);
/* an input that is not a driver's (path key, name): listed like the others, as long as it is set */
void vmidi_monitor_set_extra(const char *key, const char *name);
/* one scan; returns the number of devices added and removed. also tries again devices that are not (fully) in the list yet, every 3 seconds */
int vmidi_monitor_scan(void);
int vmidi_monitor_find(const char *key, vmidi_found *out);
int vmidi_monitor_present(const char *key);
void vmidi_monitor_poke(void);
int vmidi_monitor_start(void);
void vmidi_monitor_stop(void);

/* what the DEVICES page says (plain words): one line per device that has a problem, "name: text", separated by "\n". returns the number of lines */
void vmidi_note_set(const char *key, const char *name, const char *text);
void vmidi_note_clear(const char *key);
int vmidi_notes_text(char *buf, size_t n);
/* the numbers: devices of drivers, of those the ones that look like a virtual cable */
void vmidi_monitor_counts(int *devices, int *virtual_cables);
/* the names of the virtual cables, "\n" separated */
int vmidi_monitor_virtual_names(char *buf, size_t n);

#ifdef __cplusplus
}
#endif
