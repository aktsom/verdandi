/*
 * gif_writer.h
 *
 * a small animated gif writer for recordings of the screen: 16 grey levels (the oled's
 * 4 bits), every frame whole, scaled up by an integer factor with crisp pixels, looping.
 * pure C (macos/tests/gif_test.c).
 */

#pragma once

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    FILE *f;
    int w, h, scale;
} gif_writer_t;

// w x h source pixels, written scale times larger. false if the file could not be written
extern int gif_begin(gif_writer_t *g, FILE *f, int w, int h, int scale);
// one frame: w * h levels 0-15, row by row, shown for delay_cs hundredths of a second
extern int gif_frame(gif_writer_t *g, const uint8_t *levels, int delay_cs);
extern int gif_end(gif_writer_t *g);

#ifdef __cplusplus
}
#endif
