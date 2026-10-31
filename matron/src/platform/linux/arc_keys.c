/*
 * arc_keys.c: see arc_keys.h
 */

#include "arc_keys.h"

#include <SDL2/SDL_scancode.h>

static const struct {
    int scancode, ring, dir;
} KEYS[8] = {{SDL_SCANCODE_5, 1, -1}, {SDL_SCANCODE_6, 1, 1}, {SDL_SCANCODE_T, 2, -1}, {SDL_SCANCODE_Y, 2, 1},
             {SDL_SCANCODE_G, 3, -1}, {SDL_SCANCODE_H, 3, 1}, {SDL_SCANCODE_B, 4, -1}, {SDL_SCANCODE_N, 4, 1}};

int arc_key_lookup(int scancode, int *ring, int *dir) {
    for (int i = 0; i < 8; i++) {
        if (KEYS[i].scancode == scancode) {
            *ring = KEYS[i].ring;
            *dir = KEYS[i].dir;
            return 1;
        }
    }
    return 0;
}

int arc_key_ticks(int down, int repeat, int shift, int repeats, int ramp) {
    if (!down) {
        return 0;
    }
    int n = shift ? 4 : 16;
    if (repeat && ramp) {
        if (repeats >= 25) {
            n *= 4;
        } else if (repeats >= 10) {
            n *= 2;
        }
    }
    return n;
}
