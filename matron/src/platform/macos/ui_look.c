/*
 * ui_look.c: see ui_look.h
 */

#include <math.h>
#include <stdint.h>

#include "ui_look.h"

double ui_look_factor(double brightness) {
    if (brightness < 0.1) {
        brightness = 0.1;
    }
    if (brightness > 1) {
        brightness = 1;
    }
    return pow(brightness, 0.6);
}

int ui_look_normalise(int *r, int *g, int *b) {
    int m = *r > *g ? (*r > *b ? *r : *b) : (*g > *b ? *g : *b);
    if (m <= 0) {
        return 0;
    }
    *r = (int)(*r * 255.0 / m + 0.5);
    *g = (int)(*g * 255.0 / m + 0.5);
    *b = (int)(*b * 255.0 / m + 0.5);
    return 1;
}

void ui_look_table(uint8_t lut[3][256], double brightness, int r, int g, int b, double gamma) {
    int t[3] = {r, g, b};
    if (!ui_look_normalise(&t[0], &t[1], &t[2])) {
        t[0] = t[1] = t[2] = 255;
    }
    if (gamma < 0.4) {
        gamma = 0.4;
    }
    if (gamma > 1.0) {
        gamma = 1.0;
    }
    double f = ui_look_factor(brightness);
    for (int grey = 0; grey < 256; grey++) {
        double corrected = 255.0 * pow(grey / 255.0, gamma);
        for (int c = 0; c < 3; c++) {
            double v = corrected * t[c] / 255.0 * f;
            lut[c][grey] = (uint8_t)(v > 255 ? 255 : (int)(v + 0.5));
        }
    }
}

void ui_look_palette(uint8_t pal[16][3], double brightness, int r, int g, int b, double gamma) {
    uint8_t lut[3][256];
    ui_look_table(lut, brightness, r, g, b, gamma);
    for (int i = 0; i < 16; i++) {
        for (int c = 0; c < 3; c++) {
            pal[i][c] = lut[c][i * 17];
        }
    }
}

int ui_look_is_identity(double brightness, int r, int g, int b, double gamma) {
    if (!ui_look_normalise(&r, &g, &b)) {
        return 0;
    }
    return brightness >= 1.0 && gamma == 1.0 && r == 255 && g == 255 && b == 255;
}
