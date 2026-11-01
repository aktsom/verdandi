#pragma once
/*
 * screen_toast: the message pill at the bottom of the detached screen window (screen_window.cc), sized to its text and wrapped into up to TOAST_MAX_LINES lines so that the text never leaves the pill, at any
 * window size (docs/port/KNOWN-ISSUES.md 33). cairo only, no SDL: linux/tests/toast_width_test.c measures it with the real font at several sizes.
 */
#include <cairo.h>

#include "toast_fit.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    toast_lines_t lines;
    double k;          // the scale of the window (1 at 992 wide)
    double x, y, w, h; // the pill, device pixels
    double dot;        // room for the recording dot
    double line_h;     // distance between the lines
    double font;       // the font size
} screen_toast_t;

extern void screen_toast_layout(int w, int h, const char *text, int recording, screen_toast_t *out);
extern void screen_toast_draw(cairo_t *cr, int w, int h, const char *text, int recording);

#ifdef __cplusplus
}
#endif
