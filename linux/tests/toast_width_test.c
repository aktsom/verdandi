/*
 * toast_width_test.c: no toast leaves its border (docs/port/KNOWN-ISSUES.md 33). every message the program shows on the box (copied, saved, restored not saved, MIDI actions on/off, screenshot and GIF,
 * muted, learn, errors, the serialosc note, a very long one) is measured with the real fonts and drawn: the lines are no wider than the pill's inside, there are at most three, the pill stays in the room it has
 * and clear of the controls, and what is drawn stays inside it:
 *   - the aluminium style: the layout, and the picture with and without the toast differs only inside the pill (at the smallest window, the default and a large one)
 *   - PIXEL, RETRO, 8-BIT, 16-BIT with norns.ttf and with the built-in font: the layout, and no pixel of the (unique) font colour in the toast's room outside the pill
 *   - the screen window's pill at the smallest allowed size, a small one, the default, a large one and a very large one
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos -I matron/src/platform/linux $(pkg-config --cflags cairo freetype2) linux/tests/toast_width_test.c \
 *      matron/src/platform/macos/device_skin.c matron/src/platform/linux/box_style.c matron/src/platform/linux/box_palette.c matron/src/platform/linux/toast_fit.c matron/src/platform/linux/screen_toast.c \
 *      -o /tmp/twt $(pkg-config --libs cairo freetype2) -lm
 */
#include <cairo.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "box_palette.h"
#include "box_style.h"
#include "device_skin.h"
#include "screen_toast.h"
#include "toast_fit.h"

static int failures = 0;
#define CHECK(cond, ...)                                                                                               \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            if (failures < 40) {                                                                                       \
                printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                            \
                printf(__VA_ARGS__);                                                                                   \
                printf("\n");                                                                                          \
            }                                                                                                          \
        }                                                                                                              \
    } while (0)

static const char *TEXTS[] = {
    "copied #3B6EA8", "saved #3B6EA8", "restored, not saved", "unchanged", "MIDI actions on", "MIDI actions off", "screenshot saved to Pictures", "screenshot saved to dust",
    "GIF saved to Desktop", "REC  GIF  \xc2\xb7  shift-cmd-G stops", "Output muted (Ctrl+M)", "app input does not start (see norns.log)", "the screen window could not be opened",
    "3 files linked, 2 copied, 1 left out (1 not audio or a script)", "nothing to import: not audio or a script", "ARC WINDOW IS CLOSED: F8", "LEARN MIX: PRESS A BUTTON", "ACTION SCREENSHOT FAILED",
    "MIDI MAP: NOTE 36 IS ON MANUAL AND MUTE +2 MORE", "ACTIONS NEED THE WINDOW", "FULLSCREEN: DETACH THE SCREEN FIRST (F9)", "MIDI actions on",
    "ERROR key: lua/core/menu/midimap.lua:1234: attempt to index a nil value (field 'ctl')",
    "GRID: serialosc has this grid. Stop: sudo systemctl stop serialosc.service",
    "GRID: serialosc has this grid\nStop it: sudo systemctl stop serialosc.service\n(later: sudo systemctl start serialosc.service)",
    "PLUGINS: wrong-architecture plug-in, see log", "AUDIO: not connected, see SYSTEM > AUDIO",
    "SOME VERY LONG MESSAGE THAT KEEPS GOING AND GOING WITHOUT ANY END IN SIGHT FOR A LONG TIME, SO LONG THAT IT CANNOT FIT IN THREE LINES OF ANY WINDOW AT ALL, NOT EVEN THE BIGGEST ONE YOU CAN OPEN ON THE BIGGEST SCREEN",
    "a_very_long_word_without_any_space_in_it_that_would_not_fit_in_one_line_of_the_pill_at_all_even_if_it_tried",
    "", "x",
};
#define NTEXTS ((int)(sizeof TEXTS / sizeof TEXTS[0]))

// the room the box's toast has, with room for the shadow
static const double ZONE[4] = {300, 136, 868, 214};

static double real_width(const char *s) {
    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_A8, 8, 8);
    cairo_t *cr = cairo_create(surf);
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 14);
    cairo_text_extents_t te;
    cairo_text_extents(cr, s, &te);
    double w = te.x_advance;
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    return w;
}

static double gap(const double a[4], const double b[4]) {
    double dx = fmax(fmax(a[0] - b[2], b[0] - a[2]), 0), dy = fmax(fmax(a[1] - b[3], b[1] - a[3]), 0);
    return hypot(dx, dy);
}

static void controls_clear(const double pill[4], const char *what) {
    box_style_set_variant(0);
    for (int id = SKIN_K1; id <= SKIN_MUTE; id++) {
        double r[4];
        if (!box_style_control_rect(id, &r[0], &r[1], &r[2], &r[3])) continue;
        CHECK(gap(pill, r) >= 3, "%s: the pill (%g,%g)-(%g,%g) touches control %d", what, pill[0], pill[1], pill[2], pill[3], id);
    }
}

static void test_aluminium(void) {
    skin_set_look(SKIN_STYLE_ALUMINIUM, NULL, NULL, NULL, NULL, NULL);
    for (int rec = 0; rec < 2; rec++) {
        for (int i = 0; i < NTEXTS; i++) {
            skin_toast_t t;
            skin_toast_layout(TEXTS[i], rec, 1, &t);
            char what[160];
            snprintf(what, sizeof what, "aluminium '%.30s'%s", TEXTS[i], rec ? " recording" : "");
            CHECK(t.lines.n >= 1 && t.lines.n <= TOAST_MAX_LINES, "%s: %d lines", what, t.lines.n);
            double inner = t.w - 36 - t.dot;
            for (int k = 0; k < t.lines.n; k++) {
                double w = real_width(t.lines.line[k]);
                CHECK(w <= inner + 0.01, "%s: line %d is %.1f wide, the inside of the pill %.1f", what, k, w, inner);
            }
            double pill[4] = {t.x, t.y, t.x + t.w, t.y + t.h};
            CHECK(pill[0] >= ZONE[0] && pill[2] <= ZONE[2] && pill[1] >= ZONE[1] && pill[3] <= ZONE[3], "%s: the pill (%g,%g)-(%g,%g) is outside its room", what, pill[0], pill[1], pill[2], pill[3]);
            controls_clear(pill, what);
        }
    }
    // the picture: with and without the toast, at the smallest window, the default and a large one: only the pill's place differs
    int sizes[][2] = {{496, 331}, {992, 662}, {1500, 1000}, {2000, 1330}};
    for (unsigned si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
        int w = sizes[si][0], h = sizes[si][1];
        skin_geom_t g;
        skin_geom(w, h, &g);
        for (int i = 0; i < NTEXTS; i++) {
            if (TEXTS[i][0] == 0) continue;
            skin_state_t st;
            memset(&st, 0, sizeof st);
            st.input = SKIN_INPUT_MIC;
            unsigned char *pic[2];
            for (int with = 0; with < 2; with++) {
                cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
                cairo_t *cr = cairo_create(s);
                st.toast = with ? TEXTS[i] : NULL;
                skin_draw_static(cr, &g);
                skin_draw_controls(cr, &g, &st);
                cairo_surface_flush(s);
                size_t n = (size_t)cairo_image_surface_get_stride(s) * h;
                pic[with] = (unsigned char *)malloc(n);
                memcpy(pic[with], cairo_image_surface_get_data(s), n);
                if (with == 0) cairo_surface_flush(s);
                int stride = cairo_image_surface_get_stride(s);
                (void)stride;
                cairo_destroy(cr);
                cairo_surface_destroy(s);
            }
            skin_toast_t t;
            skin_toast_layout(TEXTS[i], 0, g.s, &t);
            // the pill in device pixels, with 4 units for the shadow
            double x0 = g.ox + (t.x - 4) * g.s, y0 = g.oy + (t.y - 4) * g.s, x1 = g.ox + (t.x + t.w + 4) * g.s, y1 = g.oy + (t.y + t.h + 6) * g.s;
            int stride = w * 4, outside = 0, inside = 0;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    if (memcmp(pic[0] + y * stride + x * 4, pic[1] + y * stride + x * 4, 4) != 0) {
                        if (x >= x0 - 1 && x <= x1 + 1 && y >= y0 - 1 && y <= y1 + 1) inside++; else outside++;
                    }
                }
            }
            CHECK(outside == 0, "aluminium at %dx%d '%.30s': %d pixels differ outside the pill", w, h, TEXTS[i], outside);
            CHECK(inside > 0, "aluminium at %dx%d '%.30s': the toast drew nothing", w, h, TEXTS[i]);
            free(pic[0]);
            free(pic[1]);
        }
    }
}

static void test_pixel_looks(void) {
    static const char *fonts[2] = {"builtin", NULL}; // NULL: norns.ttf as the screen finds it (NORNS_BOX_FONT_PATH or resources/norns.ttf)
    box_rgb_t col[BOX_PARTS];
    unsigned cv[BOX_PARTS] = {0x2c2e33, 0x444853, 0x5d6270, 0x3a3d45, 0xff00ff}; // the font colour is magenta: nothing else is
    for (int i = 0; i < BOX_PARTS; i++) {
        col[i].r = (unsigned char)(cv[i] >> 16);
        col[i].g = (unsigned char)(cv[i] >> 8);
        col[i].b = (unsigned char)cv[i];
    }
    box_style_set_colours(col);
    for (int f = 0; f < 2; f++) {
        box_style_set_font(fonts[f] ? fonts[f] : getenv("NORNS_TEST_TTF"));
        for (int v = 0; v < 4; v++) {
            box_style_set_variant(v);
            int iw, ih;
            box_style_image_size(&iw, &ih);
            int cu = box_style_cell_units();
            for (int rec = 0; rec < 2; rec++) {
                for (int i = 0; i < NTEXTS; i++) {
                    char what[200];
                    snprintf(what, sizeof what, "look %d font %s '%.30s'%s", v, box_style_font_name(), TEXTS[i], rec ? " recording" : "");
                    box_toast_t t;
                    box_style_toast_layout(TEXTS[i], rec, &t);
                    CHECK(t.lines.n >= 1 && t.lines.n <= TOAST_MAX_LINES, "%s: %d lines", what, t.lines.n);
                    CHECK(t.text_w <= t.inner_w + 1e-6, "%s: the widest line %g is wider than the inside %g", what, t.text_w, t.inner_w);
                    CHECK(t.w >= t.text_w, "%s: the pill %g is narrower than its text %g", what, t.w, t.text_w);
                    double pill[4] = {t.x, t.y, t.x + t.w, t.y + t.h};
                    CHECK(pill[0] >= ZONE[0] - 2 && pill[2] <= ZONE[2] && pill[1] >= ZONE[1] && pill[3] <= ZONE[3], "%s: the pill (%g,%g)-(%g,%g) is outside its room", what, pill[0], pill[1], pill[2], pill[3]);
                    controls_clear(pill, what);
                    box_style_set_variant(v); // controls_clear used variant 0
                    if (TEXTS[i][0] == 0) continue;
                    // the picture: font coloured pixels in the toast's room are inside the pill
                    uint32_t *px = (uint32_t *)calloc((size_t)iw * ih, 4);
                    skin_state_t st;
                    memset(&st, 0, sizeof st);
                    st.input = SKIN_INPUT_MIC;
                    st.toast = TEXTS[i];
                    st.recording = rec;
                    box_style_render_controls(px, &st, 1);
                    int zx0 = (int)((16 + ZONE[0] - 24) / cu), zx1 = (int)((16 + ZONE[2] + 24) / cu), zy0 = (int)((16 + ZONE[1] - 8) / cu), zy1 = (int)((16 + ZONE[3] + 8) / cu);
                    int px0 = (int)floor((16 + pill[0]) / cu + 0.5), px1 = (int)floor((16 + pill[2]) / cu + 0.5), py0 = (int)floor((16 + pill[1]) / cu + 0.5), py1 = (int)floor((16 + pill[3]) / cu + 0.5);
                    int outside = 0, inside = 0;
                    for (int y = zy0; y < zy1 && y < ih; y++) {
                        for (int x = zx0; x < zx1 && x < iw; x++) {
                            if ((px[(size_t)y * iw + x] & 0x00ffffff) == 0x00ff00ff) {
                                if (x >= px0 && x < px1 && y >= py0 && y < py1) inside++; else outside++;
                            }
                        }
                    }
                    CHECK(outside == 0, "%s: %d font coloured pixels outside the pill [%d..%d]x[%d..%d]", what, outside, px0, px1, py0, py1);
                    CHECK(inside > 0, "%s: no text pixels inside the pill", what);
                    free(px);
                }
            }
        }
    }
    box_style_set_variant(0);
    box_style_set_font(NULL);
}

static void test_screen_window(void) {
    int sizes[][2] = {{256, 128}, {496, 331}, {992, 662}, {1500, 1000}, {2560, 1440}};
    for (unsigned si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
        int w = sizes[si][0], h = sizes[si][1];
        for (int rec = 0; rec < 2; rec++) {
            for (int i = 0; i < NTEXTS; i++) {
                screen_toast_t t;
                screen_toast_layout(w, h, TEXTS[i], rec, &t);
                char what[160];
                snprintf(what, sizeof what, "screen window %dx%d '%.30s'%s", w, h, TEXTS[i], rec ? " recording" : "");
                CHECK(t.lines.n >= 1 && t.lines.n <= TOAST_MAX_LINES, "%s: %d lines", what, t.lines.n);
                cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_A8, 8, 8);
                cairo_t *cr = cairo_create(surf);
                cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
                cairo_set_font_size(cr, t.font);
                double inner = t.w - 36 * t.k - t.dot;
                for (int k = 0; k < t.lines.n; k++) {
                    cairo_text_extents_t te;
                    cairo_text_extents(cr, t.lines.line[k], &te);
                    CHECK(te.x_advance <= inner + 0.01, "%s: line %d is %.1f wide, the inside %.1f", what, k, te.x_advance, inner);
                }
                cairo_destroy(cr);
                cairo_surface_destroy(surf);
                CHECK(t.x >= 0 && t.x + t.w <= w && t.y >= 0 && t.y + t.h <= h, "%s: the pill (%g,%g,%g,%g) is outside the window", what, t.x, t.y, t.w, t.h);
                // the picture: nothing but the pill is touched
                if (TEXTS[i][0] != 0) {
                    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
                    cairo_t *c2 = cairo_create(s);
                    cairo_set_source_rgb(c2, 0.5, 0.5, 0.5);
                    cairo_paint(c2);
                    screen_toast_draw(c2, w, h, TEXTS[i], rec);
                    cairo_surface_flush(s);
                    unsigned char *d = cairo_image_surface_get_data(s);
                    int stride = cairo_image_surface_get_stride(s), outside = 0;
                    for (int y = 0; y < h; y++) {
                        for (int x = 0; x < w; x++) {
                            unsigned char *p = d + y * stride + x * 4;
                            int grey = p[0] == 128 && p[1] == 128 && p[2] == 128;
                            if (!grey && !(x >= t.x - 1 && x <= t.x + t.w + 1 && y >= t.y - 1 && y <= t.y + t.h + 1)) outside++;
                        }
                    }
                    CHECK(outside == 0, "%s: %d pixels drawn outside the pill", what, outside);
                    cairo_destroy(c2);
                    cairo_surface_destroy(s);
                }
            }
        }
    }
}

int main(void) {
    if (getenv("NORNS_TEST_TTF") == NULL) {
        // the screen's font: next to the repository's resources
        setenv("NORNS_TEST_TTF", "resources/norns.ttf", 0);
    }
    test_aluminium();
    test_pixel_looks();
    test_screen_window();
    if (failures == 0) printf("toast width: all passed (%d texts)\n", NTEXTS);
    else printf("toast width: %d failed\n", failures);
    return failures == 0 ? 0 : 1;
}
