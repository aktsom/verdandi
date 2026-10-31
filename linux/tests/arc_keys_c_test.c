/*
 * arc_keys_c_test.c: the arc keys of the virtual arc window (matron/src/platform/linux/arc_keys.c, docs/port/arc-plan.md 3.3, tier 1): 5 6 = ring 1 left/right, T Y = 2, G H = 3, B N = 4, and no other key;
 * one press 16 ticks, Shift 4, a repeat the same, the optional ramp doubles after 10 repeats and again after 25, a key up is nothing
 */
#include <SDL2/SDL_scancode.h>
#include <stdio.h>

#include "arc_keys.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL " __VA_ARGS__);                                                                               \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

int main(void) {
    struct {
        int sc, ring, dir;
        const char *name;
    } keys[8] = {{SDL_SCANCODE_5, 1, -1, "5"}, {SDL_SCANCODE_6, 1, 1, "6"}, {SDL_SCANCODE_T, 2, -1, "T"}, {SDL_SCANCODE_Y, 2, 1, "Y"},
                 {SDL_SCANCODE_G, 3, -1, "G"}, {SDL_SCANCODE_H, 3, 1, "H"},  {SDL_SCANCODE_B, 4, -1, "B"}, {SDL_SCANCODE_N, 4, 1, "N"}};
    for (int i = 0; i < 8; i++) {
        int ring = 0, dir = 0;
        CHECK(arc_key_lookup(keys[i].sc, &ring, &dir) == 1, "%s is an arc key", keys[i].name);
        CHECK(ring == keys[i].ring && dir == keys[i].dir, "%s is ring %d, direction %d (got %d, %d)", keys[i].name, keys[i].ring, keys[i].dir, ring, dir);
    }
    int taken = 0;
    for (int sc = 0; sc < 512; sc++) {
        int ring, dir;
        int is_arc = 0;
        for (int i = 0; i < 8; i++) {
            is_arc |= keys[i].sc == sc;
        }
        if (arc_key_lookup(sc, &ring, &dir) != is_arc) {
            printf("FAIL scancode %d is %staken\n", sc, is_arc ? "not " : "");
            fails++;
        }
        taken += arc_key_lookup(sc, &ring, &dir);
    }
    CHECK(taken == 8, "exactly eight keys are taken (%d)", taken);
    // F1-F12, the other letters, the other digits, the keys of the norns mapping are not
    int others[] = {SDL_SCANCODE_F1, SDL_SCANCODE_F6, SDL_SCANCODE_F7, SDL_SCANCODE_F8, SDL_SCANCODE_F12, SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4, SDL_SCANCODE_7, SDL_SCANCODE_Q,
                    SDL_SCANCODE_W, SDL_SCANCODE_A, SDL_SCANCODE_S, SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_RETURN, SDL_SCANCODE_SPACE, SDL_SCANCODE_ESCAPE, SDL_SCANCODE_UP, SDL_SCANCODE_LEFT};
    for (unsigned i = 0; i < sizeof others / sizeof others[0]; i++) {
        int ring, dir;
        CHECK(arc_key_lookup(others[i], &ring, &dir) == 0, "scancode %d is not an arc key", others[i]);
    }
    // ticks: down, repeat event, shift, repeats so far, ramp
    CHECK(arc_key_ticks(1, 0, 0, 0, 0) == 16, "a press is 16");
    CHECK(arc_key_ticks(1, 0, 1, 0, 0) == 4, "Shift: 4");
    CHECK(arc_key_ticks(1, 1, 0, 3, 0) == 16, "a repeat is 16");
    CHECK(arc_key_ticks(1, 1, 1, 3, 0) == 4, "a shifted repeat is 4");
    CHECK(arc_key_ticks(0, 0, 0, 0, 0) == 0, "a key up is nothing");
    CHECK(arc_key_ticks(0, 1, 0, 30, 1) == 0, "a key up is nothing, whatever the ramp");
    CHECK(arc_key_ticks(1, 1, 0, 9, 1) == 16, "ramp: 9 repeats = x1");
    CHECK(arc_key_ticks(1, 1, 0, 10, 1) == 32, "ramp: 10 = x2");
    CHECK(arc_key_ticks(1, 1, 0, 24, 1) == 32, "ramp: 24 = x2");
    CHECK(arc_key_ticks(1, 1, 0, 25, 1) == 64, "ramp: 25 = x4");
    CHECK(arc_key_ticks(1, 1, 0, 40, 0) == 16, "no ramp unless asked");
    CHECK(arc_key_ticks(1, 0, 0, 40, 1) == 16, "a press is never ramped");
    // a text entry open: the arc window takes no key (the flag is set from lua by the entry, textentry.lua); lookup itself stays what it is
    CHECK(arc_keys_blocked() == 0, "not blocked at first");
    arc_keys_set_blocked(1);
    CHECK(arc_keys_blocked() == 1, "blocked while an entry is open");
    for (int i = 0; i < 8; i++) {
        int ring, dir;
        CHECK(arc_key_lookup(keys[i].sc, &ring, &dir) == 1, "%s is still an arc key for the lookup (the caller checks the flag)", keys[i].name);
    }
    arc_keys_set_blocked(5);
    CHECK(arc_keys_blocked() == 1, "any non-zero value blocks");
    arc_keys_set_blocked(0);
    CHECK(arc_keys_blocked() == 0, "and 0 gives the keys back");
    if (fails == 0) {
        printf("arc keys (C): eight keys, no others; 16 ticks, Shift 4, ramp only if asked, a key up is nothing\n");
    }
    return fails == 0 ? 0 : 1;
}
