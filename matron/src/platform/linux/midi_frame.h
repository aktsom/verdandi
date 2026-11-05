/*
 * midi_frame.h: the cut of the bytes a script sends into whole MIDI messages, for the JACK MIDI output (jack_midi_in.cc). a JACK MIDI event is one
 * complete message, and a script may hand over one message, several, running status, or a system exclusive message. pure C, no JACK, tested by
 * linux/tests/midi_frame_test.c.
 *   - channel messages (80..EF): status and 1 or 2 data bytes (C0 and D0: one); a data byte without a status byte uses the running status
 *   - real-time bytes (F8..FF) are messages of their own, also in the middle of another message (which goes on)
 *   - F0 .. F7 system exclusive: one message, cut into events of at most MIDI_FRAME_MAX bytes if it is longer; without its F7 it is sent as it is; a status byte ends it
 *   - F1, F3: two bytes, F2: three, F4 F5 F6: one, a stray F7: nothing
 *   - a message that is cut off (not enough data bytes at the end) and data bytes with no status are dropped
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#define MIDI_FRAME_MAX 512

typedef void (*midi_frame_emit_t)(const uint8_t *msg, size_t len, void *ctx);

static inline void midi_frame_split(const uint8_t *data, size_t n, midi_frame_emit_t emit, void *ctx) {
    uint8_t buf[MIDI_FRAME_MAX];
    size_t have = 0;  // bytes of the message being built
    size_t want = 0;  // its length (0: open sysex)
    uint8_t status = 0, running = 0;
    int in_sysex = 0;
    for (size_t i = 0; i < n; i++) {
        uint8_t b = data[i];
        if (b >= 0xf8) {
            emit(&b, 1, ctx);
            continue;
        }
        if (b & 0x80) {
            if (in_sysex) {
                // F7 closes it; any other status byte ends it too
                if (b == 0xf7) {
                    if (have < MIDI_FRAME_MAX) buf[have++] = b;
                    emit(buf, have, ctx);
                    have = 0;
                    in_sysex = 0;
                    status = 0;
                    continue;
                }
                emit(buf, have, ctx);
                have = 0;
                in_sysex = 0;
            }
            have = 0;
            status = b;
            if (b == 0xf0) {
                in_sysex = 1;
                buf[have++] = b;
                running = 0;
                continue;
            }
            if (b == 0xf7) { status = 0; continue; }
            if (b >= 0xf4) { // F4 F5 F6 (F7 above): a message of one byte
                if (b == 0xf6) emit(&b, 1, ctx);
                status = 0;
                running = 0;
                continue;
            }
            if (b >= 0xf1) { // F1 F3: two bytes, F2: three
                want = (b == 0xf2) ? 3 : 2;
                running = 0;
            } else {
                want = ((b & 0xf0) == 0xc0 || (b & 0xf0) == 0xd0) ? 2 : 3;
                running = b;
            }
            buf[have++] = b;
            continue;
        }
        // a data byte
        if (in_sysex) {
            if (have == MIDI_FRAME_MAX) { // a very long sysex: the first events are full, the rest follows
                emit(buf, have, ctx);
                have = 0;
            }
            buf[have++] = b;
            continue;
        }
        if (status == 0 && running == 0) continue; // no status: dropped
        if (have == 0) {                           // running status: the status byte again
            status = running;
            want = ((status & 0xf0) == 0xc0 || (status & 0xf0) == 0xd0) ? 2 : 3;
            buf[have++] = status;
        }
        buf[have++] = b;
        if (have == want) {
            emit(buf, have, ctx);
            have = 0;
            if (running == 0) status = 0;
        }
    }
    if (in_sysex && have > 0) emit(buf, have, ctx); // an open sysex is sent as it is; a cut-off channel message is dropped
}
