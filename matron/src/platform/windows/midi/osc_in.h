// osc_in.h: the OSC input (UDP, 127.0.0.1 only) as a MIDI device. see osc_midi.h for the messages.
#pragma once
#include "midi_port.h"
#ifdef __cplusplus
extern "C" {
#endif
/* binds 127.0.0.1:port and starts the receiving thread; every message that is a control value is pushed into the port as MIDI bytes. 0 = ok, else err says why in one sentence */
int vmidi_osc_start(vmidi_port *p, int port, char *err, size_t errn);
void vmidi_osc_stop(void);
/* counts: packets that made MIDI, packets that did not */
void vmidi_osc_counts(unsigned long long *used, unsigned long long *ignored);
#ifdef __cplusplus
}
#endif
