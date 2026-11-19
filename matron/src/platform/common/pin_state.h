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

// ---- M28: a press of PIN while the window is not in view brings it up and turns PIN on (docs/port/phase-m28.md)
// covered: 1 = other windows hide all of it, 0 = some of it shows, -1 = not told (X11: only minimized and hidden count)
typedef struct {
    int minimized;
    int hidden;
    int covered;
} view_state_t;

// in view = not minimized, not hidden and not fully covered
static inline int view_in_view(const view_state_t *v) {
    return !(v->minimized || v->hidden || v->covered == 1);
}

enum {
    PIN_PRESS_TOGGLE = 0,  // the window is in view: PIN toggles
    PIN_PRESS_BRING_UP = 1 // not in view: restore, raise and PIN on (never off)
};

static inline int pin_press_action(const view_state_t *v) {
    return view_in_view(v) ? PIN_PRESS_TOGGLE : PIN_PRESS_BRING_UP;
}

// the bring-up: PIN is on afterwards, whatever it was. returns the new state (1)
static inline int pin_bring_up(pin_state_t *p) {
    p->on = 1;
    return 1;
}

// one press of PIN (the button, F7, the menu and the MIDI action all end here): not in view = bring up and on; in view = toggle. returns PIN_PRESS_BRING_UP or PIN_PRESS_TOGGLE, the state is updated
static inline int pin_press(pin_state_t *p, const view_state_t *v) {
    if (pin_press_action(v) == PIN_PRESS_BRING_UP) {
        pin_bring_up(p);
        return PIN_PRESS_BRING_UP;
    }
    pin_toggle(p);
    return PIN_PRESS_TOGGLE;
}

// the sampled points of a window: ours[i] = 1 where our window shows, 0 where another window is. covered when there are points and none shows ours; -1 when there are none
static inline int view_covered_from_samples(const int *ours, int n) {
    if (n <= 0) {
        return -1;
    }
    for (int i = 0; i < n; i++) {
        if (ours[i]) {
            return 0;
        }
    }
    return 1;
}
