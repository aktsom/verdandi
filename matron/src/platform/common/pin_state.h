/*
 * pin_state.h: the "always on top" state of the Verdandi windows (the PIN button, Windows), as plain functions so that the rules can be tested (linux/tests/pin_state_test.c):
 * it starts OFF at every start and is never saved; one toggle changes it for every window; a window that opens later (the arc, the screen window) or is closed and opened again
 * gets the state at once. docs/port/phase-m16.md
 */

#pragma once

typedef struct {
    int on;
} pin_state_t;

typedef void (*pin_set_fn)(void *window, int on, void *ctx);

static inline void pin_init(pin_state_t *p) {
    p->on = 0;
}

static inline int pin_get(const pin_state_t *p) {
    return p->on;
}

// the button, F7, the menu and the MIDI action all come here. returns the new state
static inline int pin_toggle(pin_state_t *p) {
    p->on = !p->on;
    return p->on;
}

// what a window that opens now must be set to
static inline int pin_for_new_window(const pin_state_t *p) {
    return p->on;
}

// every window that exists (NULL entries are windows that are closed)
static inline void pin_apply(const pin_state_t *p, void *const *windows, int n, pin_set_fn set, void *ctx) {
    for (int i = 0; i < n; i++) {
        if (windows[i] != 0) {
            set(windows[i], p->on, ctx);
        }
    }
}
