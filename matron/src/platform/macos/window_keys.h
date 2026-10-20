/*
 * window_keys.h
 *
 * computer keyboard -> norns hardware controls, for the macOS window. pure logic, no SDL:
 * key codes are USB HID keyboard usages (what SDL scancodes are).
 *
 * with Option held (or always, in "norns mode") these keys are the hardware:
 *   1 2 3          K1 K2 K3 (press / hold / release)
 *   enter space    K3 (confirm)
 *   Q W  A S  Z X  E1 E2 E3, down / up
 *   up/down        E2      left/right   E3
 *   + Shift        5 steps per press
 *   Option+Esc     toggles norns mode
 * everything else is passed on as the norns usb keyboard. a key always releases the way it
 * was pressed, whatever the modifiers are at release.
 */

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WINDOW_KEYS_MAX_USAGE 256
#define WINDOW_KEYS_SHIFT_STEPS 5

typedef enum {
    WK_KEY,    // norns key n (1..3), value 1 = down, 0 = up
    WK_ENC,    // norns encoder n (1..3), value = delta
    WK_HID,    // usb keyboard usage n, value 1 = down, 0 = up, 2 = autorepeat
    WK_MODE,   // norns mode changed, value = new mode (0/1)
} window_key_action_t;

typedef struct {
    window_key_action_t kind;
    int n;
    int value;
} window_key_event_t;

typedef struct {
    int norns_mode;
    uint8_t held_key[WINDOW_KEYS_MAX_USAGE];  // usage -> norns key held by it (0 = none)
    uint8_t forwarded[WINDOW_KEYS_MAX_USAGE]; // usage went down as a keyboard key
} window_keys_t;

extern void window_keys_init(window_keys_t *wk);

// one keyboard event in, at most one action out; returns 1 if *out was filled
extern int window_keys_process(window_keys_t *wk, int usage, int down, int repeat, int option, int shift,
                               window_key_event_t *out);

#ifdef __cplusplus
}
#endif
