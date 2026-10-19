/*
 * window_keys_test.c: scenarios for platform/macos/window_keys.c
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos \
 *    macos/tests/window_keys_test.c matron/src/platform/macos/window_keys.c -o /tmp/wkt && /tmp/wkt
 */

#include <stdio.h>
#include <string.h>

#include "window_keys.h"

enum { U_A = 0x04, U_Q = 0x14, U_W = 0x1a, U_X = 0x1b, U_1 = 0x1e, U_3 = 0x20, U_ESC = 0x29, U_DOWN = 0x51, U_LALT = 0xe2 };

static int failures = 0;

// process one event and compare against the expected action (kind -1 = no action)
static void expect(window_keys_t *wk, const char *what, int usage, int down, int repeat, int option, int shift,
                   int kind, int n, int value) {
    window_key_event_t ev;
    memset(&ev, 0, sizeof(ev));
    int got = window_keys_process(wk, usage, down, repeat, option, shift, &ev);
    int ok = kind < 0 ? !got : (got && (int)ev.kind == kind && ev.n == n && ev.value == value);
    if (!ok) {
        failures++;
        if (got) {
            printf("FAIL %s: got kind=%d n=%d value=%d, want kind=%d n=%d value=%d\n", what, ev.kind, ev.n, ev.value,
                   kind, n, value);
        } else {
            printf("FAIL %s: got nothing, want kind=%d n=%d value=%d\n", what, kind, n, value);
        }
    }
}

int main(void) {
    window_keys_t wk;

    // plain typing reaches the script as the usb keyboard
    window_keys_init(&wk);
    expect(&wk, "q down", U_Q, 1, 0, 0, 0, WK_HID, U_Q, 1);
    expect(&wk, "q repeat", U_Q, 1, 1, 0, 0, WK_HID, U_Q, 2);
    expect(&wk, "q up", U_Q, 0, 0, 0, 0, WK_HID, U_Q, 0);
    expect(&wk, "1 down", U_1, 1, 0, 0, 0, WK_HID, U_1, 1);
    expect(&wk, "1 up", U_1, 0, 0, 0, 0, WK_HID, U_1, 0);

    // option + 1 holds K1 until 1 is released, even if option goes first (K1 + turn)
    window_keys_init(&wk);
    expect(&wk, "opt+1 down", U_1, 1, 0, 1, 0, WK_KEY, 1, 1);
    expect(&wk, "opt+1 repeat", U_1, 1, 1, 1, 0, -1, 0, 0);
    expect(&wk, "opt+w while K1 held", U_W, 1, 0, 1, 0, WK_ENC, 1, 1);
    expect(&wk, "w up consumed", U_W, 0, 0, 1, 0, -1, 0, 0);
    expect(&wk, "1 up after option released", U_1, 0, 0, 0, 0, WK_KEY, 1, 0);

    // encoders: rows, arrows, shift = 5 steps, autorepeat keeps turning
    window_keys_init(&wk);
    expect(&wk, "opt+q", U_Q, 1, 0, 1, 0, WK_ENC, 1, -1);
    expect(&wk, "opt+a", U_A, 1, 0, 1, 0, WK_ENC, 2, -1);
    expect(&wk, "opt+x", U_X, 1, 0, 1, 0, WK_ENC, 3, 1);
    expect(&wk, "opt+down", U_DOWN, 1, 0, 1, 0, WK_ENC, 2, 1);
    expect(&wk, "opt+shift+w", U_W, 1, 0, 1, 1, WK_ENC, 1, 5);
    expect(&wk, "opt+w repeat", U_W, 1, 1, 1, 0, WK_ENC, 1, 1);
    expect(&wk, "w up", U_W, 0, 0, 1, 0, -1, 0, 0);

    // a key that went down as keyboard key stays one: repeat and release, option or not
    window_keys_init(&wk);
    expect(&wk, "q down plain", U_Q, 1, 0, 0, 0, WK_HID, U_Q, 1);
    expect(&wk, "q repeat with option now held", U_Q, 1, 1, 1, 0, WK_HID, U_Q, 2);
    expect(&wk, "q up with option held", U_Q, 0, 0, 1, 0, WK_HID, U_Q, 0);

    // the option key itself is a normal keyboard key
    window_keys_init(&wk);
    expect(&wk, "left alt down", U_LALT, 1, 0, 1, 0, WK_HID, U_LALT, 1);
    expect(&wk, "left alt up", U_LALT, 0, 0, 0, 0, WK_HID, U_LALT, 0);

    // norns mode: option+esc toggles; then plain keys are the hardware, other keys still type
    window_keys_init(&wk);
    expect(&wk, "opt+esc", U_ESC, 1, 0, 1, 0, WK_MODE, 0, 1);
    expect(&wk, "esc up consumed", U_ESC, 0, 0, 1, 0, -1, 0, 0);
    expect(&wk, "3 in norns mode", U_3, 1, 0, 0, 0, WK_KEY, 3, 1);
    expect(&wk, "3 up", U_3, 0, 0, 0, 0, WK_KEY, 3, 0);
    expect(&wk, "q in norns mode", U_Q, 1, 0, 0, 0, WK_ENC, 1, -1);
    expect(&wk, "esc alone still types", U_ESC, 1, 0, 0, 0, WK_HID, U_ESC, 1);
    expect(&wk, "esc up", U_ESC, 0, 0, 0, 0, WK_HID, U_ESC, 0);
    expect(&wk, "opt+esc again", U_ESC, 1, 0, 1, 0, WK_MODE, 0, 0);
    expect(&wk, "q after leaving mode", U_Q, 1, 0, 0, 0, WK_HID, U_Q, 1);

    // garbage in
    expect(&wk, "usage 0", 0, 1, 0, 0, 0, -1, 0, 0);
    expect(&wk, "usage out of range", 300, 1, 0, 0, 0, -1, 0, 0);

    if (failures == 0) {
        printf("window_keys: all scenarios pass\n");
    }
    return failures ? 1 : 0;
}
