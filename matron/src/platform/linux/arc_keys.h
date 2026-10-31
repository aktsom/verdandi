/*
 * arc_keys.h: the arc keys of the virtual arc window on the Linux desktop (docs/port/arc-plan.md 3.3, tier 1): 5 6 = ring 1 left/right, T Y = ring 2, G H = ring 3, B N = ring 4. pure C (SDL scancode numbers only),
 * tested in linux/tests/arc_keys_c_test.c. Linux desktop only. one press is 16 ticks (one LED of the 64 on a ring), Shift 4, a repeat the same; the optional ramp doubles after 10 repeats and again after 25; a key up is nothing.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// 1 and the ring (1-4) and the direction (-1 left, +1 right) if the scancode is one of the eight, else 0
extern int arc_key_lookup(int scancode, int *ring, int *dir);

// the ticks of a key event: down 0 = a key up (0 ticks); repeat = an autorepeat event; shift; the repeats so far; the ramp setting
extern int arc_key_ticks(int down, int repeat, int shift, int repeats, int ramp);

// a text entry is open (lua/lib/textentry.lua tells the window): the arc window takes no key. the caller checks it before arc_key_lookup (a name or a number typed in the arc window, after a learn by clicking a ring)
extern void arc_keys_set_blocked(int blocked);
extern int arc_keys_blocked(void);

#ifdef __cplusplus
}
#endif
