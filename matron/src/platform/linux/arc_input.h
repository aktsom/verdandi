/*
 * arc_input.h: what a mouse does to a ring of the virtual arc window, as plain functions (the window, sdl_bridge.cc, calls them; linux/tests/arc_input_test.c
 * checks the numbers). the same on Linux and Windows.
 *
 *   a real arc has 1024 ticks to a turn. a drag with the left button round a ring is a quarter of that for a full turn of the pointer (a small knob under a mouse
 *   would be far touchier than the hardware under a hand); a wheel notch is 2 ticks (a trackpad scrolls in fractions of a notch); Shift is a quarter of that, the
 *   GUI key (Super, Windows key) four times. the fractions are kept per ring and only whole ticks go to the script.
 */

#pragma once

#include <math.h>

#define ARC_TICKS_PER_TURN 1024.0
#define ARC_DRAG_GEAR 0.25
#define ARC_WHEEL_TICKS 2
// a pointer this close to the centre (in units of the window) makes the angle jump: the drag waits there
#define ARC_DRAG_DEAD_ZONE 8

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
