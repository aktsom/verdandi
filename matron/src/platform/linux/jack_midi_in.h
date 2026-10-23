/*
 * jack_midi_in.h
 *
 * MIDI into norns through JACK: a JACK client "Verdandi" with one MIDI input port, "midi_in". Any program that
 * can send JACK MIDI (and, through PipeWire's JACK or a2jmidid, ALSA and other MIDI) can send clock, start,
 * continue, song position and notes to norns. norns sees it as a normal MIDI device, "Verdandi JACK in": scripts
 * can read it, and it is a clock source for `clock_midi` (parameter "midi clock in": all, or its port).
 *
 * the process callback only copies events into a lock-free queue; a reader thread writes the bytes into a pipe
 * that the device reads with the same parser as every other MIDI device (device_midi.cc, `from_pipe`).
 * nothing is connected automatically: the port shows up in jack_lsp, qpwgraph, Helvum, Reaper.
 * NORNS_JACK_MIDI=0 turns it off.
 */

#pragma once

#include <stdbool.h>

#define JACK_MIDI_PATH "jackmidi:"

#ifdef __cplusplus
extern "C" {
#endif

// make the client, the port, the thread and the pipe, and add the norns MIDI device. 0 = up, -1 = not (no
// JACK server, switched off): norns then has no JACK MIDI input and says so in the log
extern int jack_midi_in_start(void);

// device_midi.cc: the read end of the pipe for the device it is making (ownership goes with it), -1 if none
extern int jack_midi_in_take_pipe(void);

// device_midi.cc: the address of the device's "clock receive" flag (lua's switch). while it is true, the clock
// messages of this input go to `clock_midi` from here with their exact JACK time
extern void jack_midi_in_set_clock_flag(const bool *flag);

// the JACK port name, for tests and messages
extern const char *jack_midi_in_port_name(void);

#ifdef __cplusplus
}
#endif
