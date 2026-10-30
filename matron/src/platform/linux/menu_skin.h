/*
 * menu_skin.h
 *
 * the in-window menu of the norns window on Linux (there is no global menu bar): a popup list drawn
 * over the device, opened with F10 or the right button, used with the mouse or the keyboard.
 * pure cairo, no SDL, so it can be rendered to png and hit-tested without a window
 * (linux/tests/menu_skin_test.c).
 */

#pragma once

#include <cairo.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MENU_MAX 40 // 28 items were possible before the box styles (docs/port/box-style-plan.md added 5)

typedef struct {
    int id;          // what the shell does with it (SHELL_MENU_*), 0 for a separator
    char label[48];  // "Import files..."
    char hint[16];   // the shortcut shown at the right: "F6", "Ctrl+Q"
    int checked;     // a check mark in front of the label
    int disabled;    // drawn dim, cannot be chosen
    int separator;   // a line, not an item
} menu_item_t;

typedef struct {
    int open;
    int n;
    menu_item_t item[MENU_MAX];
    int hover; // item index under the pointer or chosen with the keys, -1 none
    double anchor_x, anchor_y;
    // layout (menu_skin_layout): the box in window pixels
    double x, y, w, h, row, sep, pad, scale;
} menu_t;

// the menu opens at the pointer (anchor in window pixels); scale: 1.0 at 96 dpi, window size w x h
// keeps it inside the window
extern void menu_skin_open(menu_t *m, double anchor_x, double anchor_y, double scale, int win_w, int win_h);
extern void menu_skin_close(menu_t *m);

// item under a point, -1 for none (separators and disabled items count as none)
extern int menu_skin_hit(const menu_t *m, double px, double py);
// is the point inside the box (the pad around the items counts)
extern int menu_skin_inside(const menu_t *m, double px, double py);

// keyboard: +1 down / -1 up to the next item that can be chosen (wraps)
extern void menu_skin_move(menu_t *m, int dir);

// draw it over what is there (after the device)
extern void menu_skin_draw(cairo_t *cr, const menu_t *m);

#ifdef __cplusplus
}
#endif
