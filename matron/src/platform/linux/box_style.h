/*
 * box_style.h
 *
 * the pixel style of the norns window on Linux (docs/port/box-style-plan.md): the box, keys, encoders and the button row drawn as hard-edged blocks on a grid of 2 layout units, matt, in a
 * palette of five colours and the shades the formula in box_palette.c gives. one block is one pixel of a 496 x 331 image (the 480 x 315 box and 8 blocks of margin: the whole window at 100
 * percent); the image is drawn by plain pixel writes (no anti-aliasing anywhere) and then placed in the window by whole multiples where the window size allows, else slightly soft, as the
 * screen is. the screen, its bezel and margin are the aluminium style's, unchanged. pure C: cairo is only used to place the image, so the shapes can be tested without a window
 * (linux/tests/box_style_test.c).
 */

#pragma once

#include <stdint.h>

#include <cairo.h>

#include "box_palette.h"
#include "../macos/device_skin.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BS_BLOCK 2  // layout units per block
#define BS_MARGIN 8 // blocks of margin round the box in the image (the window's 16 units)
#define BS_W (SKIN_W / BS_BLOCK + 2 * BS_MARGIN)
#define BS_H (SKIN_H / BS_BLOCK + 2 * BS_MARGIN)

// the pixel looks (docs/port/retro-look-plan.md): PIXEL is the look above and never changes. RETRO and 8-BIT draw on a 4 unit block (the box is 632 units tall), 16-BIT on a 3 unit block; all three
// draw into an image of 2 unit cells (16-BIT: 1 unit cells) so that the labels can stay in 2 unit pixels. the layers, the caches, the placing and the hit tests follow the look
enum { BOX_LOOK_PIXEL = 0, BOX_LOOK_RETRO, BOX_LOOK_8BIT, BOX_LOOK_16BIT, BOX_LOOKS };
extern void box_style_set_variant(int variant);
extern int box_style_variant(void);
// the block image of the look in use: its size in cells, the layout units of a cell and of a block, the box's size in layout units
extern void box_style_image_size(int *w, int *h);
extern int box_style_cell_units(void);
extern int box_style_block_units(void);
extern void box_style_box_units(int *w, int *h);
// for tests: bit 1 no speckle, 2 no grille, 4 no dithered band on the box face (what the render leaves out is the only difference)
extern void box_style_set_debug(unsigned mask);

// the five colours (box, keys, encoders, buttons, font)
extern void box_style_set_colours(const box_rgb_t colours[BOX_PARTS]);

// the layout: the rectangle (layout units) of a control, SKIN_K1.. SKIN_MUTE; 0 if there is none
extern int box_style_control_rect(int control, double *x0, double *y0, double *x1, double *y1);

// the control under device pixel x/y (SKIN_NONE if none). hidden row: the buttons are not there, except the MUTE chip while muted
extern int box_style_hit(const skin_geom_t *g, double x, double y, int buttons_shown, int muted);
extern int box_style_nearest_enc(const skin_geom_t *g, double x, double y);

// what the palette gives for the current colours: the colour of the window's surround
extern box_rgb_t box_style_surround(void);

// the layers, as block images (ARGB32, BS_W x BS_H): static = surround, shadow, box, bezel; controls = buttons, toast, keys, encoders on transparent
extern void box_style_render_static(uint32_t *px);
extern void box_style_render_controls(uint32_t *px, const skin_state_t *st, int buttons_shown);

// the same on a cairo canvas, placed by the scale of the window
extern void box_style_draw_static(cairo_t *cr, const skin_geom_t *g);
extern void box_style_draw_controls(cairo_t *cr, const skin_geom_t *g, const skin_state_t *st, int buttons_shown);

// while the window is being resized: placing the block images is cheap (no enlarging, no filter); false again when the size settles, then the next frame is the quality one
extern void box_style_set_fast(int fast);

// the pixel font: width in blocks of a text (the font of the screen, norns.ttf at 8 px, or the built-in 3 x 5 font), which font is in use ("norns.ttf" or "builtin")
extern int box_style_text_width(const char *text);
extern const char *box_style_font_name(void);
// for tests: NULL = look for norns.ttf as the screen does ($HOME/norns/resources/norns.ttf, or NORNS_BOX_FONT_PATH), "builtin" = the built-in font
extern void box_style_set_font(const char *path_or_builtin);

#ifdef __cplusplus
}
#endif
