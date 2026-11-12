// midi_port.h: one MIDI port pair (an input and an output of one device) of the Windows build, independent of the system API: the system part is a vmidi_backend (WinMM in midi_winmm.c, a fake in the tests),
// so that everything else can be tested on Linux (linux/tests/midi_port_test.cpp). docs/port/phase-m4.md.
//   input:  the backend calls rx() on ITS thread. the realtime bytes (clock, start, continue, stop) and the song position pointer are handed to the clock at once, on that thread, with no queue between (that is
//           what keeps the timing); all bytes, those too, go to a ring that the device thread of norns reads (dev_midi_start), as the Linux build reads the rawmidi port.
//   output: send() writes to the backend.
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*vmidi_rx_fn)(void *user, const uint8_t *data, size_t n);

typedef struct vmidi_backend {
    const char *name;
    /* the port names in the order of the system's indices (input != 0: inputs). returns the number */
    int (*list)(int input, char names[][64], int max);
    /* *busy = 1: another program has the port. err: one short sentence */
    void *(*open_in)(int index, vmidi_rx_fn rx, void *user, char *err, size_t errn, int *busy);
    void (*close_in)(void *h);
    void *(*open_out)(int index, char *err, size_t errn, int *busy);
    int (*send)(void *h, const uint8_t *data, size_t n); /* bytes written, -1 = failed */
    void (*close_out)(void *h);
    double (*now_us)(void); /* monotonic microseconds */
} vmidi_backend;

typedef struct vmidi_hooks {
    void (*clock_msg)(uint8_t message); /* 0xf8, 0xfa, 0xfb, 0xfc, on the backend's thread, at once */
    void (*clock_spp)(uint16_t midi_beats);
} vmidi_hooks;

typedef struct vmidi_stats {
    unsigned long long ticks;   /* clock ticks seen */
    double mean_us, max_us, min_us, jitter_us; /* the interval between ticks: mean and the standard deviation over the last window */
    unsigned long long dropped; /* bytes lost because norns' reader was too slow */
    unsigned long long bytes;
} vmidi_stats;

typedef struct vmidi_port vmidi_port;

/* in_index / out_index: -1 = none. *clock_enabled is read for every realtime byte (NULL = always). returns NULL if neither opened; `note` then (or when only one side opened) says in plain words what is wrong */
vmidi_port *vmidi_port_open(const vmidi_backend *be, int in_index, int out_index, const vmidi_hooks *hooks, const volatile uint8_t *clock_enabled, char *note, size_t noten);
/* an input that has no driver behind it: bytes come through vmidi_port_push() (the OSC input). it has no output */
vmidi_port *vmidi_port_new_push(const vmidi_hooks *hooks, const volatile uint8_t *clock_enabled);
int vmidi_port_has_input(const vmidi_port *p);
int vmidi_port_has_output(const vmidi_port *p);
/* blocks until bytes are there; 0 = the port was closed */
long vmidi_port_read(vmidi_port *p, uint8_t *buf, size_t max);
long vmidi_port_send(vmidi_port *p, const uint8_t *data, size_t n);
/* bytes that come from elsewhere than a MIDI driver (the OSC input): the same path as rx */
void vmidi_port_push(vmidi_port *p, const uint8_t *data, size_t n);
/* closes the backend side and wakes the reader. the port is freed when the last reference is gone: the owner holds one, a reader thread takes another with vmidi_port_ref() before it starts and gives it back
 * with vmidi_port_unref() when vmidi_port_read returned 0. vmidi_port_close() does not drop the owner's reference: call vmidi_port_unref() after it */
void vmidi_port_close(vmidi_port *p);
void vmidi_port_ref(vmidi_port *p);
void vmidi_port_unref(vmidi_port *p);
/* a probe sees every input chunk first (with the time of its arrival in the backend's microseconds); returning 1 swallows it (the route test's own messages must not reach scripts). NULL removes it */
typedef int (*vmidi_probe_fn)(void *user, const uint8_t *data, size_t n, double t_us);
void vmidi_port_set_probe(vmidi_port *p, vmidi_probe_fn fn, void *user);
double vmidi_port_now_us(vmidi_port *p);
/* microseconds since the last clock tick came in on this port, -1 if none ever came */
double vmidi_port_tick_age_us(vmidi_port *p);
/* the clock statistics of the window since the last call (resets the window) */
void vmidi_port_stats(vmidi_port *p, vmidi_stats *out);

#ifdef __cplusplus
}
#endif
