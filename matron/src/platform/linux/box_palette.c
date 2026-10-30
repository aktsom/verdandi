/*
 * box_palette.c: see box_palette.h
 */

#include <ctype.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

#include "box_palette.h"

// the colours of the aluminium drawing: the middle of the box's gradient (dfe1e4 to c4c7cb), of the key caps (5b5e63 to 26272a), of the knobs (fbfbfc to c0c3c8), of the button faces (3d3f43 to
// 232427), and the label grey. these are also the Mac look
const unsigned box_default_rgb[BOX_PARTS] = {0xD1D4D8, 0x404246, 0xDCDDE0, 0x303135, 0xC3C6CB};

const box_look_t box_builtin_looks[] = {
    {"DARK", 1, {0x2C2E33, 0x444853, 0x5D6270, 0x3A3D45, 0xE4E6EA}},
    {"LIGHT", 1, {0xD8D5CE, 0xF4F2ED, 0xB9B5AB, 0xEBE8E1, 0x34343A}},
    {"COLOUR", 1, {0x2B6F73, 0xF2B63D, 0xE9DFC8, 0x1D4A4D, 0xF7F0DE}},
    {"MAC", 1, {0xD1D4D8, 0x404246, 0xDCDDE0, 0x303135, 0xC3C6CB}},
};
const int box_builtin_look_count = (int)(sizeof box_builtin_looks / sizeof box_builtin_looks[0]);

static int hexval(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    c = (char)tolower((unsigned char)c);
    return c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

int box_parse_hex(const char *text, box_rgb_t *out) {
    if (text == NULL) {
        return 0;
    }
    size_t n = strlen(text);
    if (n != 3 && n != 6) {
        return 0;
    }
    int v[6];
    for (size_t i = 0; i < n; i++) {
        v[i] = hexval(text[i]);
        if (v[i] < 0) {
            return 0;
        }
    }
    if (n == 3) {
        out->r = (unsigned char)(v[0] * 17);
        out->g = (unsigned char)(v[1] * 17);
        out->b = (unsigned char)(v[2] * 17);
    } else {
        out->r = (unsigned char)(v[0] * 16 + v[1]);
        out->g = (unsigned char)(v[2] * 16 + v[3]);
        out->b = (unsigned char)(v[4] * 16 + v[5]);
    }
    return 1;
}

static unsigned char clamp8(double v) {
    return (unsigned char)(v < 0 ? 0 : v > 255 ? 255 : floor(v + 0.5));
}

box_rgb_t box_dark(box_rgb_t c) {
    box_rgb_t o = {clamp8(c.r * 0.60), clamp8(c.g * 0.60), clamp8(c.b * 0.60)};
    return o;
}

box_rgb_t box_darker(box_rgb_t c) {
    box_rgb_t o = {clamp8(c.r * 0.36), clamp8(c.g * 0.36), clamp8(c.b * 0.36)};
    return o;
}

box_rgb_t box_light(box_rgb_t c) {
    box_rgb_t o = {clamp8(c.r + (255 - c.r) * 0.30), clamp8(c.g + (255 - c.g) * 0.30), clamp8(c.b + (255 - c.b) * 0.30)};
    return o;
}

void box_ramp(box_rgb_t c, box_rgb_t out[BOX_RAMP]) {
    box_rgb_t s0 = {clamp8(c.r * 0.22), clamp8(c.g * 0.22), clamp8(c.b * 0.22)};
    box_rgb_t s3 = {clamp8(c.r * 0.80), clamp8(c.g * 0.80), clamp8(c.b * 0.80)};
    box_rgb_t s6 = {clamp8(c.r + (255 - c.r) * 0.60), clamp8(c.g + (255 - c.g) * 0.60), clamp8(c.b + (255 - c.b) * 0.60)};
    out[0] = s0;
    out[1] = box_darker(c);
    out[2] = box_dark(c);
    out[3] = s3;
    out[4] = c;
    out[5] = box_light(c);
    out[6] = s6;
}

int box_dither_pick(int x, int y, double t, int mode) {
    static const int bayer[4][4] = {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}};
    if (t <= 0) {
        return 0;
    }
    if (t >= 1) {
        return 1;
    }
    if (mode == BOX_DITHER_CHECKER) {
        if (t > 0.75) {
            return 1;
        }
        return (((x + y) % 2 + 2) % 2 == 0) && t > 0.25;
    }
    int bx = ((x % 4) + 4) % 4, by = ((y % 4) + 4) % 4;
    return (bayer[by][bx] + 0.5) / 16.0 < t;
}

static double luma(double r, double g, double b) {
    return 0.299 * r + 0.587 * g + 0.114 * b;
}

box_rgb_t box_tint_stop(unsigned stop, int part, box_rgb_t colour) {
    unsigned base = box_default_rgb[part < 0 || part >= BOX_PARTS ? 0 : part];
    double ys = luma((stop >> 16) & 0xff, (stop >> 8) & 0xff, stop & 0xff);
    double yb = luma((base >> 16) & 0xff, (base >> 8) & 0xff, base & 0xff);
    box_rgb_t o;
    if (ys <= yb) {
        double f = yb > 0 ? ys / yb : 0;
        o.r = clamp8(colour.r * f);
        o.g = clamp8(colour.g * f);
        o.b = clamp8(colour.b * f);
    } else {
        double a = yb < 255 ? (ys - yb) / (255 - yb) : 0;
        o.r = clamp8(colour.r + (255 - colour.r) * a);
        o.g = clamp8(colour.g + (255 - colour.g) * a);
        o.b = clamp8(colour.b + (255 - colour.b) * a);
    }
    return o;
}

static double chan(double v) {
    v /= 255.0;
    return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

double box_contrast(box_rgb_t a, box_rgb_t b) {
    double la = 0.2126 * chan(a.r) + 0.7152 * chan(a.g) + 0.0722 * chan(a.b);
    double lb = 0.2126 * chan(b.r) + 0.7152 * chan(b.g) + 0.0722 * chan(b.b);
    double hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
}
