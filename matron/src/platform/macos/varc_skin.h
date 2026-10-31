/*
 * varc_skin.h
 *
 * the virtual arc window drawn as the device: a silver plate, four big aluminium knobs,
 * each in a ring of 64 leds (led 0 at the top, clockwise). pure cairo, like vgrid_skin.h
 * (macos/tests/device_skin_test.c renders it).
 */

#pragma once

#include <cairo.h>
#include <stdint.h>

#include "vgrid_proto.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int rings;
    double s;      // device pixels per unit
    double ox, oy; // origin in device pixels
} varc_geom_t;

#ifdef NORNS_LINUX_DESKTOP
// MIDI MAP learn: the ring to light (0-3), -1 none: drawn as a bright ring round the knob (docs/port/arc-plan.md)
extern void varc_skin_set_lit(int ring);
#endif

// window size in units (one unit per point at 1:1)
extern void varc_skin_units(int rings, int *w, int *h);
extern void varc_skin_geom(int w, int h, int rings, varc_geom_t *g);

// the ring under device pixel x/y (0-based), -1 if none
extern int varc_skin_hit(const varc_geom_t *g, double x, double y);
// centre of ring n in device pixels, for turning a knob by dragging round it
extern void varc_skin_center(const varc_geom_t *g, int n, double *x, double *y);

// angle[n]: how far knob n has turned, in turns (only moves the knurl); pressed: bit n =
// push button n held
extern void varc_skin_draw(cairo_t *cr, const varc_geom_t *g, int w, int h,
                           const uint8_t ring[VARC_RINGS][VARC_LEDS], int intensity, const double angle[VARC_RINGS],
                           int pressed);

#ifdef __cplusplus
}
#endif
