/*
 * device_skin_test.c: hit testing and png renders for platform/macos/device_skin.c
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos $(pkg-config --cflags --libs cairo) \
 *    macos/tests/device_skin_test.c matron/src/platform/macos/device_skin.c -o /tmp/dst && /tmp/dst [out_dir]
 *
 * with out_dir it also writes skin_<w>x<h>.png renders to look at.
 */

#include <math.h>
#include <stdio.h>

#include "device_skin.h"

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

// layout units -> device pixels
static double px(const skin_geom_t *g, double u) {
    return g->ox + u * g->s;
}
static double py(const skin_geom_t *g, double u) {
    return g->oy + u * g->s;
}

static void test_geom(int w, int h) {
    skin_geom_t g;
    skin_geom(w, h, &g);
    // the box fits, centred
    CHECK(g.ox >= 0 && g.oy >= 0, "%dx%d: box origin %.1f,%.1f", w, h, g.ox, g.oy);
    CHECK(g.ox + SKIN_W * g.s <= w + 0.01 && g.oy + SKIN_H * g.s <= h + 0.01, "%dx%d: box overflows", w, h);
    // the oled is an integer scale inside the bezel (77,356 417x220)
    CHECK(g.oled_px >= 1, "%dx%d: oled px %d", w, h, g.oled_px);
    CHECK(g.oled_x >= px(&g, 77) && g.oled_x + 128 * g.oled_px <= px(&g, 77 + 417) + 0.5, "%dx%d: oled x outside bezel",
          w, h);
    CHECK(g.oled_y >= py(&g, 356) && g.oled_y + 64 * g.oled_px <= py(&g, 356 + 220) + 0.5, "%dx%d: oled y outside bezel",
          w, h);
    // the oled keeps a margin to the bezel edge (the text is not pressed against the frame)
    CHECK(g.oled_x - px(&g, 77) >= 8 * g.s, "%dx%d: no left margin", w, h);

    // controls at their centres
    static const double k[3][2] = {{109, 252}, {594, 542}, {749, 542}};
    static const double e[3][2] = {{216, 252}, {672, 420}, {827, 420}};
    for (int i = 0; i < 3; i++) {
        int hk = skin_hit(&g, px(&g, k[i][0]), py(&g, k[i][1]));
        CHECK(hk == SKIN_K1 + i, "%dx%d: K%d centre hits %d", w, h, i + 1, hk);
        int he = skin_hit(&g, px(&g, e[i][0]), py(&g, e[i][1]));
        CHECK(he == SKIN_E1 + i, "%dx%d: E%d centre hits %d", w, h, i + 1, he);
        // edge of the knob still turns it
        he = skin_hit(&g, px(&g, e[i][0] + 36), py(&g, e[i][1]));
        CHECK(he == SKIN_E1 + i, "%dx%d: E%d rim hits %d", w, h, i + 1, he);
        CHECK(skin_nearest_enc(&g, px(&g, e[i][0] + 3), py(&g, e[i][1] - 50)) == i + 1, "%dx%d: nearest E%d", w, h,
              i + 1);
    }
    // the screen, the empty top and the outside are no control
    CHECK(skin_hit(&g, px(&g, 280), py(&g, 460)) == SKIN_NONE, "%dx%d: screen hits a control", w, h);
    CHECK(skin_hit(&g, px(&g, 500), py(&g, 100)) == SKIN_NONE, "%dx%d: top hits a control", w, h);
    CHECK(skin_hit(&g, 1, 1) == SKIN_NONE, "%dx%d: corner hits a control", w, h);
    // K2 and E2 do not overlap: between them is nothing
    CHECK(skin_hit(&g, px(&g, 633), py(&g, 481)) == SKIN_NONE, "%dx%d: K2/E2 overlap", w, h);
}

// a fake menu frame, like the HOME page
static cairo_surface_t *fake_oled(void) {
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    cairo_t *cr = cairo_create(s);
    cairo_set_source_rgb(cr, 0, 0, 0);
    cairo_paint(cr);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_NONE);
    const char *lines[] = {"HOME", "", "SELECT >", "SYSTEM >", "SLEEP >"};
    for (int i = 0; i < 5; i++) {
        double l = i == 2 ? 1 : 0.3;
        cairo_set_source_rgb(cr, l, l, l);
        cairo_move_to(cr, 0, 10 * (i + 1));
        cairo_set_font_size(cr, 8);
        cairo_show_text(cr, lines[i]);
    }
    cairo_destroy(cr);
    return s;
}

static void render(const char *dir, int w, int h, const skin_state_t *st, const char *tag) {
    skin_geom_t g;
    skin_geom(w, h, &g);
    cairo_surface_t *out = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    cairo_t *cr = cairo_create(out);
    cairo_surface_t *oled = fake_oled();
    skin_draw_static(cr, &g);
    skin_draw_controls(cr, &g, st);
    skin_draw_oled(cr, &g, oled);
    char path[512];
    snprintf(path, sizeof path, "%s/skin_%dx%d%s.png", dir, w, h, tag);
    CHECK(cairo_surface_write_to_png(out, path) == CAIRO_STATUS_SUCCESS, "write %s", path);
    cairo_surface_destroy(oled);
    cairo_destroy(cr);
    cairo_surface_destroy(out);
}

int main(int argc, char **argv) {
    int sizes[][2] = {{1984, 1324}, {992, 662}, {496, 331}, {2400, 900}, {700, 1200}};
    for (unsigned i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
        test_geom(sizes[i][0], sizes[i][1]);
    }
    if (argc > 1) {
        skin_state_t idle = {{0, 0, 0}, {0, 0, 0}, SKIN_NONE};
        skin_state_t used = {{0, 1, 0}, {0, 3, -5}, SKIN_E1};
        render(argv[1], 1984, 1324, &idle, "");
        render(argv[1], 1984, 1324, &used, "_used");
        render(argv[1], 992, 662, &idle, "");
    }
    printf("%s: %d failures\n", failures ? "FAILED" : "ok", failures);
    return failures != 0;
}
