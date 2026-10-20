/*
 * vgrid_skin.h: the virtual grid window drawn like a monome grid (pure cairo, like
 * device_skin.h): the bead-blasted aluminium plate with light grey square keys in their
 * cut-outs, lit keys warm white. under the plate (not on the grid) a switch for the size:
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

// the size switch: 1 = 64, 2 = 128, 3 = 256
extern const int vgrid_sizes[4][2]; // [size] = {cols, rows}

typedef struct {
    int cols, rows;
    double s;      // device pixels per unit
    double ox, oy; // window origin of the layout, device pixels
} vgrid_geom_t;

// the whole window in layout units (= points at 1:1) for a grid of that size
extern void vgrid_skin_units(int cols, int rows, int *w, int *h);

extern void vgrid_skin_geom(int w, int h, int cols, int rows, vgrid_geom_t *g);

// the key under device pixel x/y (anywhere in its cell); 0 if none
extern int vgrid_skin_hit(const vgrid_geom_t *g, double x, double y, int *col, int *row);

// the size button under x/y: 1-3, 0 if none
extern int vgrid_skin_hit_size(const vgrid_geom_t *g, double x, double y);

extern void vgrid_skin_draw(cairo_t *cr, const vgrid_geom_t *g, int w, int h,
                            const uint8_t level[VGRID_MAX][VGRID_MAX], int intensity,
                            const uint8_t held[VGRID_MAX][VGRID_MAX], int size);

#ifdef __cplusplus
}
#endif
