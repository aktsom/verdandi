/*
 * keys_midi.h
 *
 * the MIDI source of the virtual keyboard window ("norns keys"), two ways out:
 *   A. an internal device for norns: the window writes the MIDI bytes into a pipe, a norns MIDI
 *      device ("norns keys", path KEYS_MIDI_PATH) reads it with the same parser as any MIDI device
 *      (device_midi.cc). always there.
 *   B. an ALSA sequencer port, client "Verdandi", port "norns keys", so other programs (a DAW, a
 *      synth) can subscribe to the keys. only when the sequencer is there (/dev/snd/seq); when it is
 *      not, A still works and one line says so.
 */

#pragma once

#include <stdint.h>

#define KEYS_MIDI_PATH "vkeys:"

#ifdef __cplusplus
extern "C" {
#endif

// 0 = open (the norns device is added), -1 = could not
extern int keys_midi_open(void);
// the norns device and the sequencer port go away
extern void keys_midi_close(void);
extern int keys_midi_is_open(void);
// one 3-byte message (note on/off), to norns and to the sequencer port
extern void keys_midi_send(uint8_t status, uint8_t d1, uint8_t d2);

// device_midi.cc: the read end of the pipe for the device it is making (ownership goes with it), -1 if
// the window has none open
extern int keys_midi_take_pipe(void);

// whether B is up (the ALSA sequencer port exists); for tests and messages
extern int keys_midi_seq_up(void);

#ifdef __cplusplus
}
#endif
