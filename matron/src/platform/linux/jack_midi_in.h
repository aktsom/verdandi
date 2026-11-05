/*
 * jack_midi_in.h
 *
 * MIDI into and out of norns through JACK: a JACK client "Verdandi" with a MIDI input port "midi_in" and a MIDI output port "midi_out". Any program that
 * can send JACK MIDI (and, through PipeWire's JACK or a2jmidid, ALSA and other MIDI) can send clock, start,
 * continue, song position and notes to norns, and can take what a script sends to the virtual device. norns sees both as one normal MIDI device,
 * "virtual": scripts read it (midi.connect(n).event) and send to it (m:note_on, m:cc, m:send, clock, start, stop ...), and it is a clock source for
 * `clock_midi` (parameter "midi clock in": all, or its port).
 *
 * input: the process callback only copies events into a lock-free queue; a reader thread writes the bytes into a pipe
 * that the device reads with the same parser as every other MIDI device (device_midi.cc, `from_pipe`).
 * output: what a script sends is cut into whole messages (midi_frame.h) and put into a second lock-free queue with the JACK frame time of the send;
 * the process callback writes them into the port buffer one period later at the same distances (no allocation, no lock, no waiting there).
 * nothing is connected automatically unless audio.conf says so (midi_in_from, midi_out_to): the ports show up in jack_lsp, qpwgraph, Helvum, Reaper.
 * NORNS_JACK_MIDI=0 turns both off.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

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

// the JACK port names, for tests and messages
extern const char *jack_midi_in_port_name(void);
extern const char *jack_midi_out_port_name(void);

// device_midi.cc: bytes a script sent to the virtual device. they are cut into messages and queued for the JACK port. returns the number of bytes taken,
// -1 if there is no port (no JACK MIDI). never waits; a full queue drops the message (said once in the log)
extern long jack_midi_out_send(const uint8_t *data, size_t n);

#ifdef __cplusplus
}
#endif
