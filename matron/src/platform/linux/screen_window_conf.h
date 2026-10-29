/*
 * screen_window_conf.h: the state file of the detached screen window, <norns home>/screen-window.conf (docs/port/detach-plan.md section 4).
 * plain key=value lines like audio.conf and ui.conf, written by the C side only (never by lua, so it cannot race with ui.conf):
 *   detached=1       the screen is in its own window (default 0)
 *   x=1480  y=120    the place of the windowed rectangle, in points (none: the window finds its own)
 *   w=1024  h=512    its size, 128..16384 (none: 5 x with its margin, 695 x 367, or smaller on a small display)
 *   fullscreen=0     (default 0)
 *   border=1         the desktop's title bar and frame (default 1; Shift+F11 turns it off)
 * a damaged value falls back to its own default with a log line that names it; the rest of the file is used. a missing file is the defaults.
 * pure C, no SDL: linux/tests/screen_window_conf_test.c. Linux desktop only.
 */

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int detached;
    int fullscreen;
    int border;
    int has_pos; // x and y are valid
    int x, y;
    int w, h; // 0: the default
} sw_conf_t;

typedef void (*sw_log_fn)(const char *line);

extern void sw_conf_defaults(sw_conf_t *c);
// the text of a file into c (starting from the defaults); log may be NULL
extern void sw_conf_parse(const char *text, sw_conf_t *c, sw_log_fn log);
// the file's text; the length, or -1 if the buffer is too small
extern int sw_conf_format(const sw_conf_t *c, char *buf, size_t n);
// 0 always: a missing or unreadable file is the defaults
extern int sw_conf_load(const char *path, sw_conf_t *c, sw_log_fn log);
// through a temporary file and a rename, so that a crash never leaves half a file. 0, or -1 if it could not be written
extern int sw_conf_save(const char *path, const sw_conf_t *c);

#ifdef __cplusplus
}
#endif
