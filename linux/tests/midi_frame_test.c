/*
 * midi_frame_test.c: matron/src/platform/linux/midi_frame.h, the cut of a script's bytes into whole MIDI messages for the JACK MIDI output
 * (a JACK MIDI event is one complete message). cc -std=gnu11 -I matron/src/platform/linux linux/tests/midi_frame_test.c
 */
#include <stdio.h>
#include <string.h>

#include "midi_frame.h"

static int fails = 0;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)

typedef struct { int n; size_t len[64]; uint8_t msg[64][MIDI_FRAME_MAX]; } got_t;
static void emit(const uint8_t *m, size_t len, void *ctx) {
    got_t *g = ctx;
    if (g->n < 64) { g->len[g->n] = len; memcpy(g->msg[g->n], m, len); g->n++; }
}
static got_t run(const uint8_t *d, size_t n) { got_t g; memset(&g, 0, sizeof g); midi_frame_split(d, n, emit, &g); return g; }
static int is(got_t *g, int i, const uint8_t *want, size_t wl) { return i < g->n && g->len[i] == wl && memcmp(g->msg[i], want, wl) == 0; }

int main(void) {
    { uint8_t d[] = {0x90, 60, 100}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "a note on is one message"); }
    { uint8_t d[] = {0x80, 60, 0}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "a note off"); }
    { uint8_t d[] = {0xb2, 7, 64}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "a cc on channel 3"); }
    { uint8_t d[] = {0xc0, 5}; got_t g = run(d, 2); CHECK(g.n == 1 && is(&g, 0, d, 2), "a program change is two bytes"); }
    { uint8_t d[] = {0xd1, 9}; got_t g = run(d, 2); CHECK(g.n == 1 && is(&g, 0, d, 2), "a channel pressure is two bytes"); }
    { uint8_t d[] = {0xe0, 0, 64}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "a pitch bend is three bytes"); }
    { uint8_t d[] = {0xa0, 60, 30}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "a key pressure is three bytes"); }
    { uint8_t d[] = {0xf8}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "clock"); }
    { uint8_t d[] = {0xfa}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "start"); }
    { uint8_t d[] = {0xfb}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "continue"); }
    { uint8_t d[] = {0xfc}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "stop"); }
    { uint8_t d[] = {0xfe}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "active sensing"); }
    { uint8_t d[] = {0xf2, 0x10, 0x01}; got_t g = run(d, 3); CHECK(g.n == 1 && is(&g, 0, d, 3), "song position is three bytes"); }
    { uint8_t d[] = {0xf3, 4}; got_t g = run(d, 2); CHECK(g.n == 1 && is(&g, 0, d, 2), "song select is two bytes"); }
    { uint8_t d[] = {0xf1, 0x22}; got_t g = run(d, 2); CHECK(g.n == 1 && is(&g, 0, d, 2), "time code quarter frame is two bytes"); }
    { uint8_t d[] = {0xf6}; got_t g = run(d, 1); CHECK(g.n == 1 && is(&g, 0, d, 1), "tune request"); }
    { uint8_t d[] = {0xf0, 0x7e, 0x7f, 0x06, 0x01, 0xf7}; got_t g = run(d, 6); CHECK(g.n == 1 && is(&g, 0, d, 6), "a system exclusive message is one message, F7 included"); }
    { uint8_t d[] = {0x90, 60, 100, 0x80, 60, 0}; got_t g = run(d, 6); uint8_t a[] = {0x90, 60, 100}, b[] = {0x80, 60, 0};
      CHECK(g.n == 2 && is(&g, 0, a, 3) && is(&g, 1, b, 3), "two messages in one call stay two, in order"); }
    { uint8_t d[] = {0x90, 60, 100, 62, 90}; got_t g = run(d, 5); uint8_t a[] = {0x90, 60, 100}, b[] = {0x90, 62, 90};
      CHECK(g.n == 2 && is(&g, 0, a, 3) && is(&g, 1, b, 3), "running status: the second note carries its status"); }
    { uint8_t d[] = {0x90, 60, 0xf8, 100}; got_t g = run(d, 4); uint8_t c[] = {0xf8}, a[] = {0x90, 60, 100};
      CHECK(g.n == 2 && is(&g, 0, c, 1) && is(&g, 1, a, 3), "a real-time byte inside a message is its own message, the message goes on"); }
    { uint8_t d[] = {0x90, 60}; got_t g = run(d, 2); CHECK(g.n == 0, "a cut-off channel message is dropped"); }
    { uint8_t d[] = {60, 100}; got_t g = run(d, 2); CHECK(g.n == 0, "data bytes with no status are dropped"); }
    { got_t g = run((const uint8_t *)"", 0); CHECK(g.n == 0, "nothing is nothing"); }
    { uint8_t d[] = {0xf0, 1, 2, 3}; got_t g = run(d, 4); CHECK(g.n == 1 && is(&g, 0, d, 4), "a sysex without its F7 is sent as it is"); }
    { uint8_t d[] = {0xf7}; got_t g = run(d, 1); CHECK(g.n == 0 || (g.n == 1 && g.len[0] == 1), "a stray F7 does no harm"); }
    { uint8_t d[] = {0xf0, 1, 0x90, 60, 100}; got_t g = run(d, 5); uint8_t a[] = {0x90, 60, 100}; CHECK(g.n == 2 && g.len[0] == 2 && is(&g, 1, a, 3), "a status byte ends an open sysex"); }
    { uint8_t d[MIDI_FRAME_MAX * 2 + 10]; d[0] = 0xf0; for (size_t i = 1; i < sizeof d - 1; i++) d[i] = 1; d[sizeof d - 1] = 0xf7;
      got_t g = run(d, sizeof d); size_t total = 0; int ok = g.n >= 3; for (int i = 0; i < g.n; i++) { total += g.len[i]; if (g.len[i] > MIDI_FRAME_MAX) ok = 0; }
      CHECK(ok && total == sizeof d, "a very long sysex is cut into events of at most MIDI_FRAME_MAX bytes, none lost"); }
    if (fails) { printf("midi_frame_test: %d failed\n", fails); return 1; }
    printf("midi_frame_test: all passed\n");
    return 0;
}
