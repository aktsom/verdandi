/*
 * pin_state_test.c: the rules of the PIN button (matron/src/platform/common/pin_state.h, docs/port/phase-m16.md): the state starts OFF, one toggle changes every window that exists,
 * a window that opens later gets the state at once, a window that is closed and opened again too, a second toggle turns it off for all. and the Windows list of MIDI actions
 * (matron/src/platform/linux/window_actions.c compiled with NORNS_WINDOWS): the slot of "keys" is "pin", the other 13 names and the order are as they were, the Linux list is untouched.
 */
#include <stdio.h>
#include <string.h>

#include "pin_state.h"
#include "window_actions.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL " __VA_ARGS__);                                                                               \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

typedef struct {
    int top;
    int sets; // how often the state was written
} fake_window_t;

static void set_fake(void *w, int on, void *ctx) {
    (void)ctx;
    ((fake_window_t *)w)->top = on;
    ((fake_window_t *)w)->sets++;
}

int main(void) {
    pin_state_t pin;
    pin_init(&pin);
    CHECK(pin_get(&pin) == 0, "a new state is off");
    fake_window_t main_w = {0, 0}, arc_w = {0, 0}, screen_w = {0, 0};
    void *list[4] = {&main_w, NULL, &arc_w, &screen_w};

    // one press: every window that exists
    pin_toggle(&pin);
    pin_apply(&pin, list, 4, set_fake, NULL);
    CHECK(pin_get(&pin) == 1 && main_w.top == 1 && arc_w.top == 1 && screen_w.top == 1, "one toggle turns it on for the main, arc and screen windows");

    // a window opened later (the grid slot was empty) and one closed and opened again
    fake_window_t late = {0, 0};
    late.top = pin_for_new_window(&pin);
    CHECK(late.top == 1, "a window that opens while it is on gets it at once");
    arc_w.top = 0; // the arc window was closed ...
    arc_w.top = pin_for_new_window(&pin); // ... and opened again
    CHECK(arc_w.top == 1, "a window closed and opened again gets it too");

    // the second press turns it off for all
    pin_toggle(&pin);
    list[1] = &late;
    pin_apply(&pin, list, 4, set_fake, NULL);
    CHECK(pin_get(&pin) == 0 && main_w.top == 0 && arc_w.top == 0 && screen_w.top == 0 && late.top == 0, "the second toggle turns it off for every window");
    CHECK(pin_for_new_window(&pin) == 0, "and a window that opens now is not on top");

    // never carried over: a fresh state (the next start) is off whatever it was
    pin_toggle(&pin);
    pin_state_t next;
    pin_init(&next);
    CHECK(pin_get(&pin) == 1 && pin_get(&next) == 0, "the next start begins off");

    // the actions
    // Windows and, since M25, Linux: the slot of the virtual keyboard is PIN
    CHECK(window_action_count() == 14, "14 actions on Windows and on Linux");
    CHECK(window_action_find("pin") == 7, "pin is where keys was (index 7), got %d", window_action_find("pin"));
    CHECK(window_action_find("keys") == -1, "there is no keys action");
    const wa_entry_t *e = window_action_get(window_action_find("pin"));
    CHECK(e != NULL && e->kind == WA_CONTROL, "pin is a control action (the button's)");
    CHECK(window_action_find("arc") == 6 && window_action_find("maiden") == 8, "the neighbours did not move");

    // M28: a press while the window is not in view brings it up and turns PIN on; in view it toggles
    {
        pin_state_t q;
        view_state_t in = {0, 0, 0}, in_unknown = {0, 0, -1}, mini = {1, 0, -1}, hidden = {0, 1, -1}, covered = {0, 0, 1}, mini_covered = {1, 0, 1};
        CHECK(view_in_view(&in) && view_in_view(&in_unknown), "in view: not minimized, not hidden, not covered (or covered not told)");
        CHECK(!view_in_view(&mini) && !view_in_view(&hidden) && !view_in_view(&covered) && !view_in_view(&mini_covered), "not in view: minimized, hidden, fully covered");
        pin_init(&q);
        CHECK(pin_press(&q, &in) == PIN_PRESS_TOGGLE && pin_get(&q) == 1, "in view, off: a press toggles it on");
        CHECK(pin_press(&q, &in) == PIN_PRESS_TOGGLE && pin_get(&q) == 0, "in view, on: a press toggles it off");
        pin_init(&q);
        CHECK(pin_press(&q, &mini) == PIN_PRESS_BRING_UP && pin_get(&q) == 1, "minimized, off: brought up and PIN on");
        CHECK(pin_press(&q, &hidden) == PIN_PRESS_BRING_UP && pin_get(&q) == 1, "hidden, already on: brought up and PIN stays ON (never toggles off)");
        CHECK(pin_press(&q, &covered) == PIN_PRESS_BRING_UP && pin_get(&q) == 1, "covered, already on: brought up, PIN stays on");
        CHECK(pin_press(&q, &in_unknown) == PIN_PRESS_TOGGLE && pin_get(&q) == 0, "back in view: the next press toggles as usual");
        pin_init(&q);
        CHECK(pin_press(&q, &covered) == PIN_PRESS_BRING_UP && pin_get(&q) == 1, "covered, off: brought up and PIN on");
        int none[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0}, one[9] = {0, 0, 0, 0, 0, 0, 0, 0, 1}, all[9] = {1, 1, 1, 1, 1, 1, 1, 1, 1};
        CHECK(view_covered_from_samples(none, 9) == 1, "no sampled point shows our window: covered");
        CHECK(view_covered_from_samples(one, 9) == 0 && view_covered_from_samples(all, 9) == 0, "one or all points show it: not covered (partly covered is in view)");
        CHECK(view_covered_from_samples(none, 0) == -1, "no points: not told");
    }

    if (fails) {
        printf("pin_state_test: %d FAILED\n", fails);
        return 1;
    }
    printf("pin_state_test: ok\n");
    return 0;
}
