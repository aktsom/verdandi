/*
 * box_palette_test.c: matron/src/platform/linux/box_palette.c (docs/port/box-style-plan.md 2.4, test 3 and 4): the hex parser, the shade formula, the aluminium tint, the contrast ratio, the
 * built-in looks.
 *   cc -std=gnu11 -Wall -Wextra -I matron/src/platform/linux linux/tests/box_palette_test.c matron/src/platform/linux/box_palette.c -o /tmp/bpt -lm && /tmp/bpt
 */
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "box_palette.h"

static int failures = 0;
#define CHECK(cond, ...)                                                                                               \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                                \
            printf(__VA_ARGS__);                                                                                       \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

static unsigned pack(box_rgb_t c) { return (unsigned)c.r << 16 | (unsigned)c.g << 8 | c.b; }

int main(void) {
    box_rgb_t c;
    // hex: 3 and 6 digits, either case; nothing else
    CHECK(box_parse_hex("2c2e33", &c) && pack(c) == 0x2C2E33, "6 digits");
    CHECK(box_parse_hex("2C2E33", &c) && pack(c) == 0x2C2E33, "upper case");
    CHECK(box_parse_hex("f80", &c) && pack(c) == 0xFF8800, "3 digits are doubled: %06X", pack(c));
    CHECK(box_parse_hex("000", &c) && pack(c) == 0, "black is a colour here");
    const char *bad[] = {"", "12", "1234", "12345", "1234567", "ggg", "12 456", "#123456", "12345g", "-12345", NULL};
    for (int i = 0; bad[i]; i++) {
        CHECK(!box_parse_hex(bad[i], &c), "'%s' must be rejected", bad[i]);
    }
    CHECK(!box_parse_hex(NULL, &c), "NULL");

    // the shade formula (the table of the plan, section 2.4): DARK's box 2C2E33
    box_rgb_t box = {0x2C, 0x2E, 0x33};
    CHECK(pack(box_dark(box)) == 0x1A1C1F, "dark(2C2E33) = %06X", pack(box_dark(box)));
    CHECK(pack(box_light(box)) == 0x6B6D70, "light(2C2E33) = %06X", pack(box_light(box)));
    box_rgb_t darker = box_darker(box);
    CHECK(darker.r == 16 && darker.g == 17 && darker.b == 18, "darker(2C2E33) = %d %d %d", darker.r, darker.g, darker.b);
    box_rgb_t keys = {0xF2, 0xB6, 0x3D};
    CHECK(pack(box_light(keys)) == 0xF6CC77 && pack(box_dark(keys)) == 0x916D25, "COLOUR keys: %06X %06X", pack(box_light(keys)), pack(box_dark(keys)));
    box_rgb_t black = {0, 0, 0}, white = {255, 255, 255};
    CHECK(pack(box_dark(black)) == 0 && pack(box_darker(black)) == 0 && pack(box_light(black)) == 0x4D4D4D, "black: %06X", pack(box_light(black)));
    CHECK(pack(box_light(white)) == 0xFFFFFF && pack(box_dark(white)) == 0x999999, "white: %06X", pack(box_dark(white)));
    // order: darker <= dark <= base <= light, every channel, every colour of the built-in looks
    for (int l = 0; l < box_builtin_look_count; l++) {
        for (int p = 0; p < BOX_PARTS; p++) {
            unsigned v = box_builtin_looks[l].rgb[p];
            box_rgb_t b = {(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff};
            box_rgb_t d = box_dark(b), dd = box_darker(b), li = box_light(b);
            CHECK(dd.r <= d.r && d.r <= b.r && b.r <= li.r && dd.g <= d.g && d.g <= b.g && b.g <= li.g && dd.b <= d.b && d.b <= b.b && b.b <= li.b, "%s part %d: shades out of order", box_builtin_looks[l].name, p);
        }
    }

    // the tint: a part at its default colour maps its own base to itself; lighter stops go towards white, darker ones towards black; the hue of the user's colour is kept
    for (int p = 0; p < BOX_PARTS; p++) {
        unsigned d = box_default_rgb[p];
        box_rgb_t base = {(d >> 16) & 0xff, (d >> 8) & 0xff, d & 0xff};
        box_rgb_t t = box_tint_stop(d, p, base);
        CHECK(abs(t.r - base.r) <= 1 && abs(t.g - base.g) <= 1 && abs(t.b - base.b) <= 1, "part %d: the base stop on the default colour is %06X, not %06X", p, pack(t), d);
    }
    box_rgb_t blue = {0x3B, 0x6E, 0xA8};
    box_rgb_t top = box_tint_stop(0xdfe1e4, BOX_PART_BOX, blue), bottom = box_tint_stop(0xc4c7cb, BOX_PART_BOX, blue);
    CHECK(top.r > blue.r && top.b > blue.b, "the lighter stop of the box is lighter than the colour: %06X", pack(top));
    CHECK(bottom.r < blue.r && bottom.b < blue.b, "the darker stop is darker: %06X", pack(bottom));
    CHECK(bottom.b > bottom.r && top.b > top.r, "the colour stays blue at both ends");
    box_rgb_t nearblack = {0x10, 0x10, 0x14};
    box_rgb_t a = box_tint_stop(0xdfe1e4, BOX_PART_BOX, nearblack), b = box_tint_stop(0xc4c7cb, BOX_PART_BOX, nearblack);
    CHECK(a.r - b.r >= 25, "a near-black box still has a visible gradient (%d to %d)", b.r, a.r);
    box_rgb_t w = box_tint_stop(0xdfe1e4, BOX_PART_BOX, white);
    CHECK(w.r == 255 && w.g == 255 && w.b == 255, "a white box stays white at the top");

    // contrast
    CHECK(fabs(box_contrast(white, black) - 21.0) < 0.01, "white on black 21");
    CHECK(fabs(box_contrast(white, white) - 1.0) < 1e-9, "equal 1");
    box_rgb_t f = {0xE4, 0xE6, 0xEA}, bt = {0x3A, 0x3D, 0x45};
    CHECK(fabs(box_contrast(f, bt) - 8.7) < 0.1, "DARK font on buttons 8.7, got %.2f", box_contrast(f, bt));

    // the built-in looks
    CHECK(box_builtin_look_count == 4, "four built-in looks");
    CHECK(!strcmp(box_builtin_looks[0].name, "DARK") && !strcmp(box_builtin_looks[1].name, "LIGHT") && !strcmp(box_builtin_looks[2].name, "COLOUR") && !strcmp(box_builtin_looks[3].name, "MAC"), "names and order");
    for (int p = 0; p < BOX_PARTS; p++) {
        CHECK(box_builtin_looks[3].rgb[p] == box_default_rgb[p], "the Mac look is the aluminium defaults (part %d)", p);
    }
    for (int l = 0; l < box_builtin_look_count; l++) {
        CHECK(box_builtin_looks[l].style == 1, "%s is a pixel look", box_builtin_looks[l].name);
    }
    // the seven shade ramp of the retro looks (docs/port/retro-look-plan.md section 3): s1, s2, s4, s5 are today's darker, dark, base, light; s0 and s3 and s6 are new
    {
        box_rgb_t bases[8] = {{0x2C, 0x2E, 0x33}, {0xD8, 0xD5, 0xCE}, {0x2B, 0x6F, 0x73}, {0xD1, 0xD4, 0xD8}, {0x80, 0x80, 0x80}, {0xFF, 0x00, 0x00}, {0, 0, 0}, {255, 255, 255}};
        for (int i = 0; i < 8; i++) {
            box_rgb_t r[BOX_RAMP];
            box_ramp(bases[i], r);
            box_rgb_t d = box_dark(bases[i]), dd = box_darker(bases[i]), l = box_light(bases[i]);
            CHECK(pack(r[1]) == pack(dd) && pack(r[2]) == pack(d) && pack(r[4]) == pack(bases[i]) && pack(r[5]) == pack(l), "the four old shades are unchanged in the ramp of %06X", pack(bases[i]));
            double prev = -1;
            for (int k = 0; k < BOX_RAMP; k++) {
                double y = 0.299 * r[k].r + 0.587 * r[k].g + 0.114 * r[k].b;
                CHECK(y >= prev - 1e-9, "ramp of %06X is not monotonic at %d", pack(bases[i]), k);
                prev = y;
            }
            if (i < 5) {
                for (int k = 1; k < BOX_RAMP; k++) {
                    int dr = abs(r[k].r - r[k - 1].r) + abs(r[k].g - r[k - 1].g) + abs(r[k].b - r[k - 1].b);
                    CHECK(dr >= 4, "ramp of %06X: steps %d and %d are only %d apart", pack(bases[i]), k - 1, k, dr);
                }
            }
        }
        box_rgb_t black = {0, 0, 0}, wh = {255, 255, 255}, rb[BOX_RAMP], rw[BOX_RAMP];
        box_ramp(black, rb);
        box_ramp(wh, rw);
        CHECK(pack(rb[0]) == 0 && pack(rb[4]) == 0 && rb[6].r > 100, "a black base: the shadows stay black, the highlight is lifted");
        CHECK(rw[6].r == 255 && rw[0].r < 80, "a white base: the highlight is white, the deepest shade is dark");
    }
    // the ordered dither: a pure function of the block (x, y) and the share t; the same answer every time, a 4 x 4 Bayer matrix for mode 1, a checkerboard for mode 2
    {
        static const int bayer[4][4] = {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}};
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                CHECK(box_dither_pick(x, y, 0.0, BOX_DITHER_BAYER) == 0 && box_dither_pick(x, y, 1.0, BOX_DITHER_BAYER) == 1, "bayer: t 0 never, t 1 always (%d,%d)", x, y);
                for (int q = 1; q < 16; q++) {
                    double t = (q + 0.01) / 16.0;
                    int want = (bayer[y % 4][x % 4] + 0.5) / 16.0 < t;
                    CHECK(box_dither_pick(x, y, t, BOX_DITHER_BAYER) == want, "bayer (%d,%d) t=%g", x, y, t);
                }
                CHECK(box_dither_pick(x, y, 0.5, BOX_DITHER_BAYER) == box_dither_pick(x + 4, y + 4, 0.5, BOX_DITHER_BAYER), "the pattern repeats every 4 blocks");
                CHECK(box_dither_pick(x, y, 0.5, BOX_DITHER_CHECKER) == (((x + y) % 2) == 0), "checker at 0.5: every second block");
                CHECK(box_dither_pick(x, y, 0.0, BOX_DITHER_CHECKER) == 0 && box_dither_pick(x, y, 1.0, BOX_DITHER_CHECKER) == 1, "checker: 0 never, 1 always");
            }
        }
        int ones = 0;
        for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) ones += box_dither_pick(x, y, 0.5, BOX_DITHER_BAYER);
        CHECK(ones == 8, "bayer at half is half of the blocks (%d)", ones);
    }
    if (failures == 0) {
        printf("box_palette_test: all passed\n");
    }
    return failures ? 1 : 0;
}
