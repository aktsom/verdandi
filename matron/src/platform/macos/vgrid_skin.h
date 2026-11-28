/*
 * vgrid_skin.h: the virtual grid window drawn like a monome grid (pure cairo, like
 * device_skin.h): the bead-blasted aluminium plate with light grey square keys in their
 * cut-outs, lit keys glowing yellow. under the plate (not on the grid) a switch for the size:
 * 64 (8x8), 128 (16x8), 256 (16x16).
 */

#pragma once

#include <cairo.h>
#include <stdint.h>

#include "vgrid_proto.h"

#ifdef __cplusplus
extern "C" {
#endif

// held[y][x] flags
#define VGRID_HELD_MOUSE 1
#define VGRID_HELD_LATCH 2

// the Linux desktop's extras (docs/port/phase-m41.md): the ROTATE button next to the size buttons and the white outline of a key that is pending for shift multi-press. not in the macOS
// build (this file is shared with it) and not in the Windows build (the virtual grid is off there)
#if defined(NORNS_LINUX_DESKTOP) && !defined(NORNS_WINDOWS)
#define VGRID_ROTATE 1
#define VGRID_HELD_PENDING 4
#define VGRID_HELD_STAGED 8 // M43: staged with Ctrl (a dashed blue outline; nothing is sent until Ctrl is let go)
#define VGRID_HELD_FIRE 16  // M43: a fired chord is down for its hold time (drawn pressed)
#endif

// the size switch: 1 = 64, 2 = 128, 3 = 256
extern const int vgrid_sizes[4][2]; // [size] = {cols, rows}

typedef struct {
    int cols, rows;
    double s;      // device pixels per unit
    double ox, oy; // window origin of the layout, device pixels
    int scols, srows; // the plate as drawn: cols x rows, or rows x cols when the device is turned 90 or 270 degrees
    int rot;          // 0-3: the device is drawn turned rot x 90 degrees clockwise (always 0 on the Mac)
} vgrid_geom_t;

// the whole window in layout units (= points at 1:1) for a grid of that size
extern void vgrid_skin_units(int cols, int rows, int *w, int *h);

extern void vgrid_skin_geom(int w, int h, int cols, int rows, vgrid_geom_t *g);

// the key under device pixel x/y (anywhere in its cell); 0 if none
extern int vgrid_skin_hit(const vgrid_geom_t *g, double x, double y, int *col, int *row);

// the size button under x/y: 1-3, 0 if none. (the Linux desktop: 4 is the ROTATE button)
extern int vgrid_skin_hit_size(const vgrid_geom_t *g, double x, double y);

#ifdef VGRID_ROTATE
// the same for a device turned rot x 90 degrees clockwise: the window units, the geometry; vgrid_skin_hit then gives the DEVICE key under the pointer
extern void vgrid_skin_units_rot(int cols, int rows, int rot, int *w, int *h);
extern void vgrid_skin_geom_rot(int w, int h, int cols, int rows, int rot, vgrid_geom_t *g);
#endif

extern void vgrid_skin_draw(cairo_t *cr, const vgrid_geom_t *g, int w, int h,
                            const uint8_t level[VGRID_MAX][VGRID_MAX], int intensity,
                            const uint8_t held[VGRID_MAX][VGRID_MAX], int size);

#ifdef __cplusplus
}
#endif
