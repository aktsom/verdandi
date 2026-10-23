/*
 * input_route.h: the card's capture ports on or off crone's input (MIC / OFF), and whether the optional sink
 * monitor input is switched on (NORNS_SYS_MONITOR=1, from audio.conf sys_monitor=1). the rest is app_audio.h.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

extern void input_route_mic(int live);
extern int input_route_monitor_enabled(void);

// the JACK client "Verdandi ctl" shared by the input routing and the MIDI auto-connect (NULL: no JACK server)
#include <jack/jack.h>
#include <stddef.h>
extern jack_client_t *input_route_client(void);

// the optional MIDI auto-connect (midi_autoconnect.cc): prefix list "a;b" of JACK MIDI output port names to link to
// Verdandi:midi_in and keep linked. returns 1 if it is on. status: 1 if on, count of linked ports and their names.
// poke: a port was registered (any thread, a JACK callback too)
extern int midi_autoconnect_start(const char *prefix_list);
extern void midi_autoconnect_poke(void);
extern int midi_autoconnect_status(int *count, char *names, size_t n);

#ifdef __cplusplus
}
#endif
