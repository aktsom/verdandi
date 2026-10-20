/*
 * vkeys_skin.h
 *
 * the virtual keyboard window: two octaves of piano keys (C to C, 25 keys) under a strip
 * with octave, velocity and latch. norns sees it as a midi device ("norns keys", see
 * sdl_bridge.cc). pure cairo, like vgrid_skin.h (macos/tests/vkeys_test.c).
 *
 * the computer keyboard plays it while its window has focus, laid out like a piano by key
 * position (any layout): A W S E D F T G Y H U J K O L P ; ' from C up, Z / X octave down /
 * up, C / V velocity down / up.
 */

#pragma once

#include <cairo.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VKEYS_N 25
#define VKEYS_OCT_MIN 0
#define VKEYS_OCT_MAX 8

// held[] bits
#define VKEYS_HELD_MOUSE 1
#define VKEYS_HELD_LATCH 2
#define VKEYS_HELD_TYPED 4

// strip controls
enum { VK_NONE = 0, VK_OCT_DOWN, VK_OCT_UP, VK_VEL_DOWN, VK_VEL_UP, VK_LATCH, VK_KEY };

typedef struct {
    int octave;   // of the lowest C: note 12 * (octave + 1), so octave 4 starts at middle C (60)
    int velocity; // for the computer keyboard; the mouse takes it from where the key is hit
    int latch;    // clicks hold notes until clicked again
    uint8_t held[VKEYS_N];
    int hover;       // control under the mouse
    int button_down; // strip control held by the mouse
    const char *typed_label[VKEYS_N]; // the computer key for each piano key, NULL for none
} vkeys_state_t;

typedef struct {
    double s;
    double ox, oy;
} vkeys_geom_t;

extern void vkeys_skin_units(int *w, int *h);
extern void vkeys_skin_geom(int w, int h, vkeys_geom_t *g);

// what is under device pixel x/y: VK_NONE, a strip control, or VK_KEY with *key (0-24)
// and *velocity (1-127: soft at the top of the key, loud at the front)
extern int vkeys_skin_hit(const vkeys_geom_t *g, double x, double y, int *key, int *velocity);

extern void vkeys_skin_draw(cairo_t *cr, const vkeys_geom_t *g, int w, int h, const vkeys_state_t *st);

// the midi note of key i at this octave
extern int vkeys_note(const vkeys_state_t *st, int key);

// computer keyboard, by USB HID usage (= SDL scancode): the key it plays (0-17, above the
// lowest C) or -1; *control = VK_OCT_DOWN / UP, VK_VEL_DOWN / UP for Z X C V, else VK_NONE
extern int vkeys_typed(int usage, int *control);
// the usage for key i, -1 if none plays it
extern int vkeys_typed_usage(int key);

#ifdef __cplusplus
}
#endif
