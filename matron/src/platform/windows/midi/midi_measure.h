// midi_measure.h: how long does a message take on a route? (docs/port/phase-m4.md, "Measuring the routes"). a message goes out of the program on one route and comes back on another end of the same route; the time is
// taken from the same clock. for MIDI: a port pair joined by a cable (a loopMIDI port, a Windows MIDI Services loopback endpoint); for OSC: UDP on the loopback of this machine, through the same parser.
// this is the cost of the route itself; the program that sits at the other end (Ableton, VCV Rack ...) adds its own buffer on top, which this cannot see.
#pragma once
#include <stddef.h>
#include "midi_port.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vmidi_route_result {
    int sent, got;
    double min_ms, mean_ms, p50_ms, p99_ms, max_ms, jitter_ms; /* round trip (out and back); jitter = standard deviation */
} vmidi_route_result;

/* the port must have an input and an output joined by a cable. blocking: count messages, one at a time, about interval_ms apart (a little irregular on purpose). returns 0, or -1 with `err` */
int vmidi_measure_port(vmidi_port *p, int count, int interval_ms, vmidi_route_result *out, char *err, size_t errn);
int vmidi_measure_udp(int count, int interval_ms, vmidi_route_result *out, char *err, size_t errn);
/* "loopMIDI Port: 0.8 ms round trip (mean), 1.9 worst, jitter 0.2, 200 of 200" */
void vmidi_route_format(const vmidi_route_result *r, const char *label, char *buf, size_t n);

#ifdef __cplusplus
}
#endif
