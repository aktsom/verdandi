/*
 * vgrid_skin.h: the virtual grid window drawn as a grid (pure cairo, like device_skin.h)
 */

#pragma once

#include <cairo.h>
#include <stdint.h>

#include "vgrid_proto.h"

#ifdef __cplusplus
extern "C" {
#endif

// layout units
#define VGRID_SKIN_PITCH 44
#define VGRID_SKIN_KEY 36
#define VGRID_SKIN_PAD 26
#define VGRID_SKIN_W (VGRID_COLS * VGRID_SKIN_PITCH - (VGRID_SKIN_PITCH - VGRID_SKIN_KEY) + 2 * VGRID_SKIN_PAD)
#define VGRID_SKIN_H (VGRID_ROWS * VGRID_SKIN_PITCH - (VGRID_SKIN_PITCH - VGRID_SKIN_KEY) + 2 * VGRID_SKIN_PAD)

// held[y][x] flags
#define VGRID_HELD_MOUSE 1
#define VGRID_HELD_LATCH 2

typedef struct {
    double s;      // device pixels per unit
    double ox, oy; // origin in device pixels
} vgrid_geom_t;

extern void vgrid_skin_geom(int w, int h, vgrid_geom_t *g);

// the key under device pixel x/y (anywhere in its cell); 0 if none
extern int vgrid_skin_hit(const vgrid_geom_t *g, double x, double y, int *col, int *row);

extern void vgrid_skin_draw(cairo_t *cr, const vgrid_geom_t *g, int w, int h,
                            const uint8_t level[VGRID_ROWS][VGRID_COLS], int intensity,
                            const uint8_t held[VGRID_ROWS][VGRID_COLS]);

#ifdef __cplusplus
}
#endif
