/*
 * window_keys.c
 */

#include <string.h>

#include "window_keys.h"

// USB HID keyboard usages
enum {
    U_A = 0x04,
    U_Q = 0x14,
    U_S = 0x16,
    U_W = 0x1a,
    U_X = 0x1b,
    U_Z = 0x1d,
    U_1 = 0x1e,
    U_2 = 0x1f,
    U_3 = 0x20,
    U_ENTER = 0x28,
    U_ESC = 0x29,
    U_SPACE = 0x2c,
    U_RIGHT = 0x4f,
    U_LEFT = 0x50,
    U_DOWN = 0x51,
    U_UP = 0x52,
    U_KP_ENTER = 0x58,
};

static int control_key(int usage) {
    switch (usage) {
    case U_1: return 1;
    case U_2: return 2;
    case U_3: return 3;
    // confirm
    case U_ENTER: return 3;
    case U_KP_ENTER: return 3;
    case U_SPACE: return 3;
    default: return 0;
    }
}

// encoder n and direction for usage; 0 if not an encoder key
static int control_enc(int usage, int *dir) {
    switch (usage) {
    case U_Q: *dir = -1; return 1;
    case U_W: *dir = 1; return 1;
    case U_A: *dir = -1; return 2;
    case U_S: *dir = 1; return 2;
    case U_UP: *dir = -1; return 2;
    case U_DOWN: *dir = 1; return 2;
    case U_Z: *dir = -1; return 3;
    case U_X: *dir = 1; return 3;
    case U_LEFT: *dir = -1; return 3;
    case U_RIGHT: *dir = 1; return 3;
    default: return 0;
    }
}

void window_keys_init(window_keys_t *wk) {
    memset(wk, 0, sizeof(*wk));
}

int window_keys_process(window_keys_t *wk, int usage, int down, int repeat, int option, int shift,
                        window_key_event_t *out) {
    if (usage <= 0 || usage >= WINDOW_KEYS_MAX_USAGE) {
        return 0;
    }

    // releases go wherever the press went
    if (!down) {
        if (wk->held_key[usage]) {
            out->kind = WK_KEY;
            out->n = wk->held_key[usage];
            out->value = 0;
            wk->held_key[usage] = 0;
            return 1;
        }
        if (wk->forwarded[usage]) {
            wk->forwarded[usage] = 0;
            out->kind = WK_HID;
            out->n = usage;
            out->value = 0;
            return 1;
        }
        return 0; // release of a consumed encoder / mode key
    }

    // a keyboard key that is already down keeps repeating as a keyboard key, even if
    // Option was pressed in the meantime
    if (repeat && wk->forwarded[usage]) {
        out->kind = WK_HID;
        out->n = usage;
        out->value = 2;
        return 1;
    }

    if (usage == U_ESC && option) {
        if (repeat) {
            return 0;
        }
        wk->norns_mode = !wk->norns_mode;
        out->kind = WK_MODE;
        out->n = 0;
        out->value = wk->norns_mode;
        return 1;
    }

    if (option || wk->norns_mode) {
        int n = control_key(usage);
        if (n) {
            // a held key keeps repeating; only the first press counts
            if (repeat || wk->held_key[usage]) {
                return 0;
            }
            wk->held_key[usage] = (uint8_t)n;
            out->kind = WK_KEY;
            out->n = n;
            out->value = 1;
            return 1;
        }
        int dir = 0;
        n = control_enc(usage, &dir);
        if (n) {
            out->kind = WK_ENC;
            out->n = n;
            out->value = dir * (shift ? WINDOW_KEYS_SHIFT_STEPS : 1);
            return 1;
        }
    }

    // a repeat of a key that did not go down as a keyboard key is dropped
    if (repeat) {
        return 0;
    }
    wk->forwarded[usage] = 1;
    out->kind = WK_HID;
    out->n = usage;
    out->value = 1;
    return 1;
}
