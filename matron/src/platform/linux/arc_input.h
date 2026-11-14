/*
 * arc_input.h: what a mouse does to a ring of the virtual arc window, as plain functions (the window, sdl_bridge.cc, calls them; linux/tests/arc_input_test.c
 * checks the numbers). the same on Linux and Windows.
 *
 *   a real arc has 1024 ticks to a turn. a drag with the left button round a ring is a quarter of that for a full turn of the pointer (a small knob under a mouse
 *   would be far touchier than the hardware under a hand); a wheel notch is 2 ticks (a trackpad scrolls in fractions of a notch); Shift is a quarter of that, the
 *   GUI key (Super, Windows key) four times. the fractions are kept per ring and only whole ticks go to the script.
 *
 *   the second way to drag (setting ARC DRAG in MIDI MAP; Windows 0.10.5, docs/port/phase-m14.md): up and down. holding the left button and moving the pointer UP turns the ring clockwise, DOWN
 *   counter-clockwise; the distance decides how far. ARC_UD_TICKS_PER_UNIT ticks for each unit of the window (the window is 830 x 260 units at 1:1 and the picture scales with it, so the feel does not
 *   depend on its size): 1024 ticks, one lap of a real arc, in 1024 / 12 = 85.3 units, 33 percent of the window's height of 260. Shift is a quarter of that, Ctrl (Windows) or Super four times, as for the wheel.
 */

#pragma once

#include <math.h>

#define ARC_TICKS_PER_TURN 1024.0
#define ARC_DRAG_GEAR 0.25
#define ARC_WHEEL_TICKS 2
// a pointer this close to the centre (in units of the window) makes the angle jump: the drag waits there
#define ARC_DRAG_DEAD_ZONE 8

// the two ways a left-button drag turns a ring (setting ARC DRAG): round the ring, or up and down
#define ARC_DRAG_CIRCLE 0
#define ARC_DRAG_UPDOWN 1
// up and down: ticks for each unit of window height the pointer moves (1 unit = 1 point at 1:1 size). a lap (1024 ticks) is 85.3 units, a third of the height of the arc window (260 units)
#define ARC_UD_TICKS_PER_UNIT 12.0

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// the change of angle from last to now, in radians, the short way round (-pi to pi)
static inline double arc_input_angle_step(double now, double last) {
    double da = now - last;
    while (da > M_PI) {
        da -= 2 * M_PI;
    }
    while (da < -M_PI) {
        da += 2 * M_PI;
    }
    return da;
}

// ticks (fractional) for a turn of the pointer round a ring by da radians, clockwise positive; factor: 1, Shift 0.25, Super 4
static inline double arc_input_drag_ticks(double da, double factor) {
    return da / (2 * M_PI) * ARC_TICKS_PER_TURN * ARC_DRAG_GEAR * factor;
}

// up and down drag: the pointer went from *last_y to y (pixels of the window, y grows downward); `unit` is the pixels of one unit of the window. returns the ticks (fractional), up (y smaller) = clockwise = positive.
// *last_y is set to y, also when y is outside the window (a captured drag goes on there). factor: 1, Shift 0.25, Ctrl or Super 4
static inline double arc_input_ud_ticks(double *last_y, double y, double unit, double factor) {
    double dy = (*last_y - y) / (unit > 0 ? unit : 1);
    *last_y = y;
    return dy * ARC_UD_TICKS_PER_UNIT * factor;
}

// ticks (fractional) for a wheel turn of dy notches (up positive); flipped: the system says the direction is reversed
static inline double arc_input_wheel_ticks(double dy, int flipped, double factor) {
    return (flipped ? -dy : dy) * ARC_WHEEL_TICKS * factor;
}

// add ticks to a ring's accumulator; returns the whole ticks to send (0 if less than one has built up), the fraction stays in *acc
static inline int arc_input_take(double *acc, double ticks) {
    *acc += ticks;
    int t = (int)*acc;
    if (t != 0) {
        *acc -= t;
    }
    return t;
}
