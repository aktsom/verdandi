/*
 * the screen's look (docs/port/ui-settings-plan.md section 2): grey correction, tint and brightness in three 256-entry tables, and the palette of a gif.
 * usage: ui_look_test REFERENCE_DUMP   (the dump of docs/port/ui-previews/ui_tint.py dump: the Python reference of the mapping, every grey for every
 * gamma 0.4..1.0, brightness 0.1..1 and five tints: the two implementations must agree to the last value)
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gif_writer.h"
#include "ui_look.h"

static int failures;
#define CHECK(cond, ...)                                                                                                                             \
    do {                                                                                                                                             \
        if (!(cond)) {                                                                                                                               \
            failures++;                                                                                                                              \
            printf("FAIL: " __VA_ARGS__);                                                                                                            \
            printf("\n");                                                                                                                            \
        }                                                                                                                                            \
    } while (0)

static void tint_of(const char *hex, int *r, int *g, int *b) {
    unsigned v = (unsigned)strtoul(hex, NULL, 16);
    *r = (v >> 16) & 0xff;
    *g = (v >> 8) & 0xff;
    *b = v & 0xff;
}

static void test_reference(const char *path) {
    FILE *f = fopen(path, "r");
    CHECK(f != NULL, "cannot open the reference dump %s", path);
    if (f == NULL) {
        return;
    }
    char hex[16];
    double gamma, bright;
    int grey, er, eg, eb, n = 0, bad = 0;
    while (fscanf(f, "%lf %lf %15s %d %d %d %d", &gamma, &bright, hex, &grey, &er, &eg, &eb) == 7) {
        static double last_g = -1, last_b = -1;
        static char last_t[16] = "";
        static uint8_t lut[3][256];
        if (gamma != last_g || bright != last_b || strcmp(hex, last_t) != 0) {
            int r, g, b;
            tint_of(hex, &r, &g, &b);
            ui_look_table(lut, bright, r, g, b, gamma);
            last_g = gamma;
            last_b = bright;
            strcpy(last_t, hex);
        }
        n++;
        if (lut[0][grey] != er || lut[1][grey] != eg || lut[2][grey] != eb) {
            if (bad++ < 5) {
                printf("  gamma %.1f brightness %.1f tint %s grey %d: got %02x%02x%02x, reference %02x%02x%02x\n", gamma, bright, hex, grey, lut[0][grey],
                       lut[1][grey], lut[2][grey], er, eg, eb);
            }
        }
    }
    fclose(f);
    CHECK(n == 89600, "the reference has %d lines, want 89600", n);
    CHECK(bad == 0, "%d of %d values differ from the reference", bad, n);
}

static void test_invariants(void) {
    static const int tints[][3] = {{255, 255, 255}, {255, 208, 0}, {255, 128, 184}, {32, 192, 160}, {32, 32, 32}, {1, 0, 0}, {0, 0, 255}, {0, 1, 0}};
    int bad_black = 0, bad_white = 0, bad_mono = 0;
    for (unsigned t = 0; t < sizeof tints / sizeof tints[0]; t++) {
        for (int gi = 4; gi <= 10; gi++) {
            for (int bi = 1; bi <= 10; bi++) {
                uint8_t lut[3][256];
                ui_look_table(lut, bi / 10.0, tints[t][0], tints[t][1], tints[t][2], gi / 10.0);
                // black stays black, whatever tint, gamma and brightness
                if (lut[0][0] || lut[1][0] || lut[2][0]) bad_black++;
                // full white is the (normalised) tint times the brightness curve, and does not depend on the grey correction
                int nr = tints[t][0], ng = tints[t][1], nb = tints[t][2];
                ui_look_normalise(&nr, &ng, &nb);
                double f = pow(bi / 10.0, 0.6);
                if (lut[0][255] != (int)(nr * f + 0.5) || lut[1][255] != (int)(ng * f + 0.5) || lut[2][255] != (int)(nb * f + 0.5)) bad_white++;
                // monotonic in the grey, per channel
                for (int c = 0; c < 3; c++)
                    for (int g = 1; g < 256; g++)
                        if (lut[c][g] < lut[c][g - 1]) bad_mono++;
            }
        }
    }
    CHECK(bad_black == 0, "black is not black in %d tables", bad_black);
    CHECK(bad_white == 0, "full white is not the tint times the brightness in %d tables", bad_white);
    CHECK(bad_mono == 0, "%d steps go down", bad_mono);
}

static void test_normalise(void) {
    int r = 32, g = 32, b = 32;
    CHECK(ui_look_normalise(&r, &g, &b) && r == 255 && g == 255 && b == 255, "202020 is not raised to white: %d %d %d", r, g, b);
    r = 1; g = 0; b = 0;
    CHECK(ui_look_normalise(&r, &g, &b) && r == 255 && g == 0 && b == 0, "010000 is not raised to red");
    r = 32; g = 192; b = 160;
    CHECK(ui_look_normalise(&r, &g, &b) && r == 43 && g == 255 && b == 213, "20C0A0 normalises to %d %d %d, want 43 255 213", r, g, b);
    r = g = b = 0;
    CHECK(!ui_look_normalise(&r, &g, &b), "black must not be a tint");
}

static void test_identity_and_levels(void) {
    uint8_t lut[3][256];
    ui_look_table(lut, 1.0, 255, 255, 255, 1.0);
    int id = 1;
    for (int g = 0; g < 256; g++)
        for (int c = 0; c < 3; c++)
            if (lut[c][g] != g) id = 0;
    CHECK(id, "white, brightness 1, greys 1.0 is not the identity");
    CHECK(ui_look_is_identity(1.0, 255, 255, 255, 1.0), "identity not recognised");
    CHECK(!ui_look_is_identity(1.0, 255, 255, 255, 0.5), "greys 0.5 is not the identity");
    CHECK(!ui_look_is_identity(0.9, 255, 255, 255, 1.0), "brightness 0.9 is not the identity");
    CHECK(!ui_look_is_identity(1.0, 255, 208, 0, 1.0), "yellow is not the identity");
    CHECK(ui_look_is_identity(1.0, 128, 128, 128, 1.0), "a grey custom colour normalises to white: the identity");
    // the plan's numbers: level 3 (grey 51) and level 1 (grey 17) and level 4 (grey 68) at the three GREYS values, white, brightness 1
    static const struct { double gamma; int l1, l3, l4; } want[] = {{1.0, 17, 51, 68}, {0.7, 38, 83, 101}, {0.5, 66, 114, 132}};
    for (unsigned i = 0; i < 3; i++) {
        ui_look_table(lut, 1.0, 255, 255, 255, want[i].gamma);
        CHECK(lut[1][17] == want[i].l1 && lut[1][51] == want[i].l3 && lut[1][68] == want[i].l4, "greys %.1f: levels 1, 3, 4 are %d %d %d, want %d %d %d", want[i].gamma,
              lut[1][17], lut[1][51], lut[1][68], want[i].l1, want[i].l3, want[i].l4);
    }
    // the brightness curve: 0.1 .. 0.4 are not all near black
    CHECK(fabs(ui_look_factor(0.1) - 0.251) < 0.001 && fabs(ui_look_factor(0.4) - 0.577) < 0.001 && ui_look_factor(1.0) == 1.0, "brightness curve");
    // the palette of a gif: the 16 levels
    uint8_t pal[16][3];
    ui_look_palette(pal, 0.4, 255, 208, 0, 0.5);
    CHECK(pal[0][0] == 0 && pal[0][1] == 0 && pal[0][2] == 0, "palette entry 0 is not black");
    ui_look_table(lut, 0.4, 255, 208, 0, 0.5);
    int same = 1;
    for (int i = 0; i < 16; i++)
        for (int c = 0; c < 3; c++)
            if (pal[i][c] != lut[c][i * 17]) same = 0;
    CHECK(same, "the palette is not the table at the 16 levels");
}

static void test_gif_palette(void) {
    uint8_t pal[16][3];
    ui_look_palette(pal, 0.4, 255, 208, 0, 0.5);
    for (int variant = 0; variant < 2; variant++) {
        FILE *f = tmpfile();
        gif_writer_t g;
        int ok = variant == 0 ? gif_begin_palette(&g, f, 4, 2, 1, &pal[0][0]) : gif_begin(&g, f, 4, 2, 1);
        CHECK(ok, "gif_begin%s failed", variant ? "" : "_palette");
        fflush(f);
        rewind(f);
        uint8_t head[13 + 48];
        CHECK(fread(head, 1, sizeof head, f) == sizeof head, "short gif header");
        CHECK(memcmp(head, "GIF89a", 6) == 0, "not a gif");
        int match = 1;
        for (int i = 0; i < 16; i++)
            for (int c = 0; c < 3; c++) {
                int want = variant == 0 ? pal[i][c] : i * 17;
                if (head[13 + i * 3 + c] != want) match = 0;
            }
        CHECK(match, "%s: the colour table of the gif is not %s", variant ? "gif_begin" : "gif_begin_palette", variant ? "the old grey palette i * 17" : "the mapped palette");
        fclose(f);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("usage: ui_look_test REFERENCE_DUMP\n");
        return 2;
    }
    test_reference(argv[1]);
    test_invariants();
    test_normalise();
    test_identity_and_levels();
    test_gif_palette();
    if (failures) {
        printf("ui_look_test: %d failed\n", failures);
        return 1;
    }
    printf("ui_look_test: all passed\n");
    return 0;
}
