/*
 * screen_window_geom.h: where the screen's picture goes in the detached screen window (docs/port/detach-plan.md 3.2), and the sizes of that window.
 * pure C, no SDL, no cairo: the numbers are tested without a window (linux/tests/screen_window_geom_test.c). Linux desktop only.
 *
 * the picture is always 2:1, inside the window, centred, with a black margin round it in the proportions of the box's bezel (the Mac's): 22/512 of the
 * picture's width at each side, 56/768 of its height above and below. the picture plus the margin has to fit the window, with black bars outside if the window is
 * not that shape. a whole multiple of 128 x 64 when the window is the size of that multiple's picture plus margin (sw_frame_size) or up to 0.02 of a scale step above
 * it (drawn with nearest neighbour: crisp), else the widest even width that fits (the main window's two-step rule: nearest to a whole multiple, then scaled).
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int x, y, w, h; // the picture in the window's pixels
    int scale;      // 1, 2, 3 ...: a whole multiple (nearest neighbour); 0: in between (filtered)
} sw_picture_t;

typedef struct {
    int x, y, w, h;
} sw_rect_t;

// the picture for a window of win_w x win_h pixels (all zero for a window with no room)
extern void sw_picture_fit(int win_w, int win_h, sw_picture_t *p);
extern int sw_picture_contains(const sw_picture_t *p, int x, int y);

// the window size at which the picture at this whole scale, with its margin, fits exactly (4 x: 556 x 294, the bezel of the box)
extern void sw_frame_size(int scale, int *w, int *h);

// the size of a new screen window on a display with this usable area: 5 x with its margin (695 x 367) if it fits with the title bar, else the largest whole multiple down to 2 x
extern void sw_default_window(int usable_w, int usable_h, int title_h, int *w, int *h);

// at least 64 x 64 pixels of the rectangle are on one of the displays
extern int sw_rect_visible(const sw_rect_t *r, const sw_rect_t *displays, int n);

#ifdef __cplusplus
}
#endif
