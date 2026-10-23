#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void clock_midi_init();
// realtime messages: 0xf8 tick, 0xfa start, 0xfb continue, 0xfc stop
void clock_midi_handle_message(uint8_t message);
// the same with the time the message happened (JACK MIDI: the frame time of the event, in clock_get_system_time's
// time base), for sources that know it better than "when it was handled"
void clock_midi_handle_message_at(uint8_t message, double time);
// song position pointer (0xf2): 14 bits, in midi beats (one midi beat = 6 clocks = a sixteenth note)
void clock_midi_handle_song_position(uint16_t midi_beats);
double clock_midi_get_beat();
double clock_midi_get_tempo();

#ifdef __cplusplus
}
#endif
