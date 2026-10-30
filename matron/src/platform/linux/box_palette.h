/*
 * box_palette.h
 *
 * the colours of the box on the Linux desktop (docs/port/box-style-plan.md): five colours (box, keys, encoders, buttons, font) given as hex codes, and what is
 * computed from them. pure C, no cairo, no SDL: tested on its own (linux/tests/box_palette_test.c).
 *   - the pixel style's shades: dark, darker, light (one formula)
 *   - the aluminium style's tint: a gradient stop of the original drawing, remapped onto the user's colour so that the lightness structure (the highlight, the shadow)
 *     stays the same and only the colour changes. an untouched part (its colour is the default) is not remapped at all: the original drawing runs as it always did
 *   - the built-in looks (DARK, LIGHT, COLOUR, MAC)
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    unsigned char r, g, b;
} box_rgb_t;

// the five colours of a look
enum { BOX_PART_BOX = 0, BOX_PART_KEYS, BOX_PART_ENCODERS, BOX_PART_BUTTONS, BOX_PART_FONT, BOX_PARTS };

// the colours of the aluminium drawing as it always was (and of the Mac look): a part whose colour is its default is drawn by the original code
extern const unsigned box_default_rgb[BOX_PARTS];

// "RRGGBB" or "RGB" (no #): 1 and the colour, 0 if it is not a hex colour
extern int box_parse_hex(const char *text, box_rgb_t *out);

// the pixel style's shades: dark = 0.60 v, darker = 0.36 v, light = v + 0.30 (255 - v)
extern box_rgb_t box_dark(box_rgb_t c);
extern box_rgb_t box_darker(box_rgb_t c);
extern box_rgb_t box_light(box_rgb_t c);

// the retro looks' ramp of seven shades of one colour (docs/port/retro-look-plan.md section 3): s0 x0.22 (deepest: outlines, the hard shadow), s1 = box_darker, s2 = box_dark, s3 x0.80, s4 = the
// colour itself, s5 = box_light, s6 = +60 percent of the way to white (highlights). s1, s2, s4, s5 are exactly the four shades of the PIXEL look
#define BOX_RAMP 7
extern void box_ramp(box_rgb_t c, box_rgb_t out[BOX_RAMP]);

// the ordered dither: 1 when block (x, y) takes the second colour of a blend whose share of it is t (0 to 1); a pure function of x, y and t. mode BAYER: a 4 x 4 Bayer matrix; CHECKER: every second block
// (t above a quarter) and everywhere at t above three quarters
enum { BOX_DITHER_NONE = 0, BOX_DITHER_BAYER = 1, BOX_DITHER_CHECKER = 2 };
extern int box_dither_pick(int x, int y, double t, int mode);

// the aluminium tint: stop is a colour of the original drawing (0xRRGGBB), part says which default it belongs to, colour is the user's. lighter than the part's default: the same share of
// the way to white; darker: the same share of the colour
extern box_rgb_t box_tint_stop(unsigned stop, int part, box_rgb_t colour);

// contrast ratio (1 to 21) of two colours, as the WCAG formula
extern double box_contrast(box_rgb_t a, box_rgb_t b);

// built-in looks
typedef struct {
    const char *name;
    int style; // 1 = pixel
    unsigned rgb[BOX_PARTS];
} box_look_t;
extern const box_look_t box_builtin_looks[];
extern const int box_builtin_look_count;

#ifdef __cplusplus
}
#endif
