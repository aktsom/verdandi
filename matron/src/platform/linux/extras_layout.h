/*
 * extras_layout.h: where the virtual grid, arc and keys windows go round the norns window on the Linux desktop. the norns window STAYS WHERE IT IS and as large as the user made it: opening one of
 * these windows used to move it and resize it (the macOS layout, which centres everything at one scale; arrange_windows in sdl_bridge.cc). pure C, no SDL: tested without a window
 * (linux/tests/extras_layout_test.c). Linux desktop only.
 *
 * the device windows go below, right of, left of or above the norns window, in one row or one column, at one scale (at most 1: their natural size), on the side that leaves them largest **if that is at least 0.6 of their natural size**; otherwise (a big norns window on a small screen) they are put in one row at the bottom of the screen, over the norns window, at the largest scale
 * the screen allows: a tiny window is no use, an overlapping one can be dragged away. every window has a title bar of height t above its content rectangle.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int x, y, w, h; // a window's content rectangle in screen pixels (the title bar is above y)
} xl_rect_t;

// usable: the free area of the display; main: the norns window (content rectangle, never changed); t: the height of a title bar; n (1 to 3) windows of natural sizes uw[i] x uh[i].
// fills out[i] and returns the scale (> 0, <= 1) applied to all of them
extern double extras_layout(const xl_rect_t *usable, const xl_rect_t *main, int t, int n, const int *uw, const int *uh, xl_rect_t *out);

#ifdef __cplusplus
}
#endif
