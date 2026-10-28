/*
 * ui_look.h
 *
 * the look of the screen (Linux desktop, docs/port/ui-settings-plan.md section 2): the grey correction (GREYS), the tint and the brightness
 * (SYSTEM > UI) as three 256-entry tables, red, green and blue, from the screen backend's grey to the colour that the window, the screenshot and
 * the gif show. pure C (linux/tests/ui_look_test.c).
 */

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// the brightness curve: b ^ 0.6 (0.1 -> 0.25, 0.4 -> 0.58, 1 -> 1), so that 0.1 to 0.4 are not all near black
extern double ui_look_factor(double brightness);

// the tint raised to full value: its largest channel becomes 255 (hue and saturation kept). 0 if the colour is black (not a tint)
extern int ui_look_normalise(int *r, int *g, int *b);

// lut[c][grey] for c = red, green, blue and every grey 0-255:
// round(255 * (grey / 255) ^ gamma * normalised tint / 255 * factor(brightness)): one rounding, black stays black, white is the tint
extern void ui_look_table(uint8_t lut[3][256], double brightness, int r, int g, int b, double gamma);

// the colours of the 16 levels (grey 17 n) for a gif's colour table
extern void ui_look_palette(uint8_t pal[16][3], double brightness, int r, int g, int b, double gamma);

// white, brightness 1 and gamma 1.0 (a grey tint counts as white): the table is the identity and the screen image can be used as it is
extern int ui_look_is_identity(double brightness, int r, int g, int b, double gamma);

#ifdef __cplusplus
}
#endif
