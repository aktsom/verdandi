/*
 * device_skin_test.c: hit testing and png renders for platform/macos/device_skin.c
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos $(pkg-config --cflags --libs cairo) \
 *    macos/tests/device_skin_test.c matron/src/platform/macos/device_skin.c \
 *    matron/src/platform/macos/vgrid_skin.c -o /tmp/dst && /tmp/dst [out_dir]
 *
 * with out_dir it also writes skin_<w>x<h>.png renders to look at.
 */

#include <math.h>
#include <stdio.h>

#include "device_skin.h"
#include "vgrid_skin.h"

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
    // the button row: pages, grid, maiden, manual, left to right
    static const double bx[7] = {77, 181, 285, 389, 561, 665, 769};
    for (int i = 0; i < 7; i++) {
        int hb = skin_hit(&g, px(&g, bx[i] + 48), py(&g, 90));
        CHECK(hb == SKIN_PAGE1 + i, "%dx%d: button %d hits %d", w, h, i, hb);
    }
    CHECK(skin_hit(&g, px(&g, 523), py(&g, 90)) == SKIN_NONE, "%dx%d: gap between button groups", w, h);
    CHECK(skin_hit(&g, px(&g, 125), py(&g, 160)) == SKIN_NONE, "%dx%d: below the buttons", w, h);
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

static void test_vgrid(const char *dir, int size) {
    int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1], uw, uh, c, r;
    vgrid_skin_units(cols, rows, &uw, &uh);
    int w = uw * 2, h = uh * 2;
    vgrid_geom_t g;
    vgrid_skin_geom(w, h, cols, rows, &g);
    // key centres (pitch 44, key 31, 18 + 26.5 to the first key) hit their key
    for (int y = 0; y < rows; y++) {
        for (int x = 0; x < cols; x++) {
            double px = g.ox + (44.5 + x * 44 + 15.5) * g.s, py = g.oy + (44.5 + y * 44 + 15.5) * g.s;
            CHECK(vgrid_skin_hit(&g, px, py, &c, &r) && c == x && r == y, "%dx%d: key %d,%d hits %d,%d", cols, rows,
                  x, y, c, r);
        }
    }
    CHECK(!vgrid_skin_hit(&g, 2, 2, &c, &r), "%dx%d: corner hits a key", cols, rows);
    CHECK(!vgrid_skin_hit(&g, w - 2, h / 2.0, &c, &r), "%dx%d: right edge hits a key", cols, rows);
    // the size switch sits under the plate, in the middle, and no key is under it
    int found[4] = {0};
    for (double x = 0; x < w; x += 2) {
        int s = vgrid_skin_hit_size(&g, x, g.oy + (uh - 50 + 4 + 13 + 5) * g.s);
        found[s] = 1;
    }
    CHECK(found[1] && found[2] && found[3], "%dx%d: size switch has 64 128 256", cols, rows);
    CHECK(vgrid_skin_hit_size(&g, w / 2.0, g.oy + 60 * g.s) == 0, "%dx%d: switch on the keys", cols, rows);
    if (dir == NULL) {
        return;
    }
    uint8_t level[VGRID_MAX][VGRID_MAX] = {{0}}, held[VGRID_MAX][VGRID_MAX] = {{0}};
    for (int x = 0; x < cols; x++) {
        level[x % rows][x] = 15;
        level[rows - 1][x] = (uint8_t)(x * 15 / (cols - 1));
    }
    level[3][5] = 4;
    held[2][6] = VGRID_HELD_MOUSE;
    held[5][7] = VGRID_HELD_LATCH;
    cairo_surface_t *out = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    cairo_t *cr = cairo_create(out);
    vgrid_skin_draw(cr, &g, w, h, level, 15, held, size);
    char path[512];
    snprintf(path, sizeof path, "%s/vgrid_%d.png", dir, cols * rows);
    CHECK(cairo_surface_write_to_png(out, path) == CAIRO_STATUS_SUCCESS, "write %s", path);
    cairo_destroy(cr);
    cairo_surface_destroy(out);
}

int main(int argc, char **argv) {
    for (int size = 1; size <= 3; size++) {
        test_vgrid(argc > 1 ? argv[1] : NULL, size);
    }
    int sizes[][2] = {{1984, 1324}, {992, 662}, {496, 331}, {2400, 900}, {700, 1200}};
    for (unsigned i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
        test_geom(sizes[i][0], sizes[i][1]);
    }
    if (argc > 1) {
        skin_state_t idle = {{0, 0, 0}, {0, 0, 0}, SKIN_NONE, 0, 0, SKIN_NONE};
        skin_state_t used = {{0, 1, 0}, {0, 3, -5}, SKIN_E1, 4, 1, SKIN_MAIDEN};
        render(argv[1], 1984, 1324, &idle, "");
        render(argv[1], 1984, 1324, &used, "_used");
        render(argv[1], 992, 662, &idle, "");
    }
    printf("%s: %d failures\n", failures ? "FAILED" : "ok", failures);
    return failures != 0;
}
