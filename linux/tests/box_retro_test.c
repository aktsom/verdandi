/*
 * box_retro_test.c: the retro looks of the pixel style (docs/port/retro-look-plan.md, section 7): PIXEL, RETRO, 8-BIT, 16-BIT. what is tested, with the block image of each look:
 *   sizes and layout (the block, the box, the buttons 72 units wide, the control rectangles on the block grid and within the stated snap of the PIXEL ones), hit areas (every control is hit
 *   in its rectangle, not outside the slop, no two overlap), outlines and shadows do not leave their control or touch another, speckle and grille and the dither band never fall on a control
 *   or the bezel, every picture is the same every time, the looks differ from each other and PIXEL is unchanged by the others having been drawn, all four built-in looks work with every look,
 *   switching looks gives back exactly the first picture (the caches), the placing in a window does not fail at any size.
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos -I matron/src/platform/linux $(pkg-config --cflags cairo freetype2) linux/tests/box_retro_test.c \
 *      matron/src/platform/macos/device_skin.c matron/src/platform/linux/box_style.c matron/src/platform/linux/box_palette.c -o /tmp/brt $(pkg-config --libs cairo freetype2) -lm
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

static const char *names[4] = {"PIXEL", "RETRO", "8-BIT", "16-BIT"};
static const int blk_units[4] = {2, 4, 4, 3};

static box_rgb_t hex(unsigned v) {
    box_rgb_t c = {(unsigned char)(v >> 16), (unsigned char)(v >> 8), (unsigned char)v};
    return c;
}

static void set_look(int l) {
    box_rgb_t c[BOX_PARTS];
    for (int i = 0; i < BOX_PARTS; i++) {
        c[i] = hex(box_builtin_looks[l].rgb[i]);
    }
    box_style_set_colours(c);
}

static uint32_t *render(int variant, int controls, int dbg) {
    box_style_set_variant(variant);
    box_style_set_debug(dbg);
    int w, h;
    box_style_image_size(&w, &h);
    uint32_t *px = (uint32_t *)calloc((size_t)w * h, 4);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    if (controls) {
        box_style_render_controls(px, &st, 1);
    } else {
        box_style_render_static(px);
    }
    box_style_set_debug(0);
    return px;
}

static size_t image_bytes(int variant) {
    box_style_set_variant(variant);
    int w, h;
    box_style_image_size(&w, &h);
    return (size_t)w * h * 4;
}

typedef struct {
    double x0, y0, x1, y1;
} urect_t;

static int all_controls(int *ids) {
    int n = 0;
    for (int id = SKIN_PAGE1; id <= SKIN_MUTE; id++) {
        double a, b, c, d;
        if (box_style_control_rect(id, &a, &b, &c, &d)) {
            ids[n++] = id;
        }
    }
    for (int id = SKIN_K1; id <= SKIN_K1 + 2; id++) ids[n++] = id;
    for (int id = SKIN_E1; id <= SKIN_E1 + 2; id++) ids[n++] = id;
    return n;
}

static void test_sizes_and_layout(void) {
    int ids[64], idsn;
    urect_t px_rect[64];
    box_style_set_variant(0);
    idsn = all_controls(ids);
    CHECK(idsn >= 17, "controls found: %d", idsn);
    for (int i = 0; i < idsn; i++) {
        box_style_control_rect(ids[i], &px_rect[i].x0, &px_rect[i].y0, &px_rect[i].x1, &px_rect[i].y1);
    }
    for (int v = 0; v < 4; v++) {
        box_style_set_variant(v);
        CHECK(box_style_variant() == v, "variant %d is set", v);
        CHECK(box_style_block_units() == blk_units[v], "%s: block %d units", names[v], box_style_block_units());
        int w, h;
        box_style_image_size(&w, &h);
        int cu = box_style_cell_units();
        CHECK(cu == (v == 3 ? 1 : 2), "%s: image cell %d units", names[v], cu);
        CHECK(w * cu == 992 && h * cu == 662, "%s: the image covers the 992 x 662 window (%d x %d cells of %d units)", names[v], w, h, cu);
        int bw, bh;
        box_style_box_units(&bw, &bh);
        CHECK(bw == 960 && bh == (v == 1 || v == 2 ? 632 : 630), "%s: the box is %d x %d units (RETRO and 8-BIT are 2 units taller)", names[v], bw, bh);
        int bl = box_style_block_units();
        for (int i = 0; i < idsn; i++) {
            urect_t r;
            CHECK(box_style_control_rect(ids[i], &r.x0, &r.y0, &r.x1, &r.y1), "%s: control %d has a rectangle", names[v], ids[i]);
            // on the block grid of the box (the box starts at layout 0)
            CHECK(v == 0 || (fmod(r.x0, bl) == 0 && fmod(r.y0, bl) == 0 && fmod(r.x1 - r.x0, bl) == 0 && fmod(r.y1 - r.y0, bl) == 0), "%s: control %d (%g,%g)-(%g,%g) is not on the %d unit grid", names[v], ids[i], r.x0, r.y0, r.x1, r.y1, bl);
            double tol = v == 0 ? 0 : (v == 3 ? 3 : 2);
            // the left and top edge move by the snap (half a block); the right and bottom edge also by the button's 2 units of extra width
            CHECK(fabs(r.x0 - px_rect[i].x0) <= tol && fabs(r.y0 - px_rect[i].y0) <= tol && fabs(r.x1 - px_rect[i].x1) <= tol + 2 && fabs(r.y1 - px_rect[i].y1) <= tol + 2,
                  "%s: control %d moved more than %g units from PIXEL's (%g,%g)-(%g,%g) -> (%g,%g)-(%g,%g)", names[v], ids[i], tol, px_rect[i].x0, px_rect[i].y0, px_rect[i].x1, px_rect[i].y1, r.x0, r.y0, r.x1, r.y1);
            if (ids[i] >= SKIN_PAGE1 && v >= 1) {
                CHECK(r.x1 - r.x0 == 72, "%s: button %d is 72 units wide (%g)", names[v], ids[i], r.x1 - r.x0);
            }
        }
    }
}

static void test_hit(void) {
    skin_geom_t g;
    skin_geom(992, 662, &g);
    for (int v = 0; v < 4; v++) {
        box_style_set_variant(v);
        int ids[64], n = all_controls(ids);
        for (int i = 0; i < n; i++) {
            urect_t r;
            box_style_control_rect(ids[i], &r.x0, &r.y0, &r.x1, &r.y1);
            double cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2;
            CHECK(box_style_hit(&g, g.ox + cx * g.s, g.oy + cy * g.s, 1, 0) == ids[i], "%s: the centre of control %d hits it", names[v], ids[i]);
            CHECK(box_style_hit(&g, g.ox + (r.x0 - 6) * g.s, g.oy + cy * g.s, 1, 0) != ids[i], "%s: 6 units left of control %d is not it", names[v], ids[i]);
            CHECK(box_style_hit(&g, g.ox + cx * g.s, g.oy + (r.y1 + 6) * g.s, 1, 0) != ids[i], "%s: 6 units under control %d is not it", names[v], ids[i]);
        }
        // the screen and the bezel are no control
        CHECK(box_style_hit(&g, g.ox + 300 * g.s, g.oy + 450 * g.s, 1, 0) == SKIN_NONE, "%s: the screen is no control", names[v]);
        // the hidden row: no buttons, except the MUTE chip while muted
        double r[4];
        box_style_control_rect(SKIN_MIC, &r[0], &r[1], &r[2], &r[3]);
        CHECK(box_style_hit(&g, g.ox + (r[0] + r[2]) / 2 * g.s, g.oy + (r[1] + r[3]) / 2 * g.s, 0, 0) == SKIN_NONE, "%s: a hidden button is not hit", names[v]);
        box_style_control_rect(SKIN_MUTE, &r[0], &r[1], &r[2], &r[3]);
        CHECK(box_style_hit(&g, g.ox + (r[0] + r[2]) / 2 * g.s, g.oy + (r[1] + r[3]) / 2 * g.s, 0, 1) == SKIN_MUTE, "%s: the MUTE chip is hit while muted", names[v]);
        // no two controls overlap (rectangles + the 2 unit slop on both)
        for (int a = 0; a < n; a++) {
            for (int b = a + 1; b < n; b++) {
                urect_t p, q;
                box_style_control_rect(ids[a], &p.x0, &p.y0, &p.x1, &p.y1);
                box_style_control_rect(ids[b], &q.x0, &q.y0, &q.x1, &q.y1);
                double sl = v == 3 ? 1 : 2;
                int overlap = p.x0 - sl < q.x1 + sl && q.x0 - sl < p.x1 + sl && p.y0 - sl < q.y1 + sl && q.y0 - sl < p.y1 + sl;
                CHECK(!overlap, "%s: controls %d and %d overlap with their slop", names[v], ids[a], ids[b]);
            }
        }
    }
}

// the opaque pixels of the controls layer: all inside a control's rectangle grown by its shadow (one block right and down) and its 1 block of outline margin, and the grown rectangles are disjoint
static void test_outlines(void) {
    set_look(0);
    for (int v = 1; v < 4; v++) {
        uint32_t *px = render(v, 1, 0);
        int w, h;
        box_style_image_size(&w, &h);
        int cu = box_style_cell_units(), bl = box_style_block_units();
        int ids[64], n = all_controls(ids);
        urect_t grown[64];
        for (int i = 0; i < n; i++) {
            box_style_control_rect(ids[i], &grown[i].x0, &grown[i].y0, &grown[i].x1, &grown[i].y1);
            grown[i].x1 += bl; // the hard shadow: one block right and down
            grown[i].y1 += bl;
        }
        for (int a = 0; a < n; a++) {
            for (int b = a + 1; b < n; b++) {
                int overlap = grown[a].x0 < grown[b].x1 && grown[b].x0 < grown[a].x1 && grown[a].y0 < grown[b].y1 && grown[b].y0 < grown[a].y1;
                CHECK(!overlap, "%s: control %d with its shadow touches control %d", names[v], ids[a], ids[b]);
            }
        }
        long stray = 0, total = 0;
        double ox = 16.0 / cu;
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                if ((px[y * w + x] >> 24) == 0) continue;
                total++;
                double ux = (x - ox) * cu, uy = (y - ox) * cu;
                int in = 0;
                for (int i = 0; i < n && !in; i++) {
                    in = ux >= grown[i].x0 && ux < grown[i].x1 && uy >= grown[i].y0 && uy < grown[i].y1;
                }
                stray += !in;
            }
        }
        CHECK(total > 1000, "%s: the controls layer has pixels (%ld)", names[v], total);
        CHECK(stray == 0, "%s: %ld controls pixels are outside every control and its shadow", names[v], stray);
        free(px);
    }
}

// speckle, grille and the band never fall on a control (and a bit more), the bezel or the screen
static int snap(double u, int bl) { return (int)floor(u / bl + 0.5); }

static void test_decorations(void) {
    set_look(0);
    const int NO_SPECKLE = 1, NO_GRILLE = 2, NO_BAND = 4;
    for (int v = 1; v < 4; v++) {
        uint32_t *base = render(v, 0, 0);
        int w, h;
        box_style_image_size(&w, &h);
        int cu = box_style_cell_units(), bl = box_style_block_units();
        int ids[64], n = all_controls(ids);
        const int masks[3] = {NO_SPECKLE, NO_GRILLE, NO_BAND};
        const char *what[3] = {"speckle", "grille", "band"};
        // which looks have which (the plan, section 3)
        const int has[4][3] = {{0, 0, 0}, {1, 1, 1}, {0, 0, 1}, {1, 0, 1}};
        for (int m = 0; m < 3; m++) {
            uint32_t *off = render(v, 0, masks[m]);
            long diff = 0, bad = 0;
            double ox = 16.0 / cu;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    if (base[y * w + x] == off[y * w + x]) continue;
                    diff++;
                    double ux = (x - ox) * cu, uy = (y - ox) * cu;
                    int keep = 0;
                    if (m < 2) {
                        // speckle and grille: not within one block of a control, not in the bezel's frame, not in the screen
                        for (int i = 0; i < n && !keep; i++) {
                            urect_t r;
                            box_style_control_rect(ids[i], &r.x0, &r.y0, &r.x1, &r.y1);
                            keep = ux >= r.x0 - bl && ux < r.x1 + 2 * bl && uy >= r.y0 - bl && uy < r.y1 + 2 * bl;
                        }
                        keep |= ux >= (snap(36, bl) - 3) * bl && ux < (snap(592, bl) + 3) * bl && uy >= (snap(300.667, bl) - 3) * bl && uy < (snap(594, bl) + 3) * bl;
                    }
                    bad += keep;
                }
            }
            CHECK((diff > 0) == (has[v][m] != 0), "%s: %s %s (%ld pixels differ)", names[v], what[m], has[v][m] ? "is missing" : "is there but should not be", diff);
            CHECK(bad == 0, "%s: %ld %s pixels fall on a control or the bezel", names[v], bad, what[m]);
            free(off);
        }
        free(base);
    }
}

static void test_deterministic_and_distinct(void) {
    set_look(0);
    uint32_t *first[4], *ctl[4];
    for (int v = 0; v < 4; v++) {
        first[v] = render(v, 0, 0);
        ctl[v] = render(v, 1, 0);
        uint32_t *again = render(v, 0, 0), *again2 = render(v, 1, 0);
        size_t bytes = image_bytes(v);
        CHECK(memcmp(first[v], again, bytes) == 0 && memcmp(ctl[v], again2, bytes) == 0, "%s: two renders are the same", names[v]);
        free(again);
        free(again2);
    }
    for (int a = 0; a < 4; a++) {
        for (int b = a + 1; b < 4; b++) {
            if (image_bytes(a) == image_bytes(b)) {
                CHECK(memcmp(first[a], first[b], image_bytes(a)) != 0, "%s and %s draw the same box", names[a], names[b]);
            }
        }
    }
    // PIXEL is the same whatever was drawn in between
    uint32_t *p2 = render(0, 0, 0);
    CHECK(memcmp(first[0], p2, image_bytes(0)) == 0, "PIXEL after the others is unchanged");
    free(p2);
    for (int v = 0; v < 4; v++) {
        free(first[v]);
        free(ctl[v]);
    }
}

static void test_looks(void) {
    for (int l = 0; l < box_builtin_look_count; l++) {
        set_look(l);
        box_rgb_t surround = box_style_surround();
        box_rgb_t box = hex(box_builtin_looks[l].rgb[0]);
        box_rgb_t want = box_darker(box);
        CHECK(surround.r == want.r && surround.g == want.g && surround.b == want.b, "look %s: the surround is the box's darker shade", box_builtin_looks[l].name);
        for (int v = 0; v < 4; v++) {
            uint32_t *s = render(v, 0, 0), *c = render(v, 1, 0);
            int w, h;
            box_style_image_size(&w, &h);
            // the box face is the box colour somewhere (the middle of the empty upper area), the button ink (the font colour) is somewhere on a button
            int cu = box_style_cell_units();
            uint32_t face = 0xff000000u | ((uint32_t)box.r << 16) | ((uint32_t)box.g << 8) | box.b;
            long faces = 0, ink = 0;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    faces += s[y * w + x] == face;
                }
            }
            uint32_t fc = 0xff000000u | ((uint32_t)hex(box_builtin_looks[l].rgb[4]).r << 16) | ((uint32_t)hex(box_builtin_looks[l].rgb[4]).g << 8) | hex(box_builtin_looks[l].rgb[4]).b;
            double r[4];
            box_style_control_rect(SKIN_PAGE1, &r[0], &r[1], &r[2], &r[3]);
            for (int y = (int)(16 / cu + r[1] / cu); y < (int)(16 / cu + r[3] / cu); y++) {
                for (int x = (int)(16 / cu + r[0] / cu); x < (int)(16 / cu + r[2] / cu); x++) {
                    ink += c[y * w + x] == fc;
                }
            }
            CHECK(faces > 2000, "%s with %s: the box face colour is there (%ld)", names[v], box_builtin_looks[l].name, faces);
            CHECK(ink > 10, "%s with %s: the label of the first button is drawn in the font colour (%ld)", names[v], box_builtin_looks[l].name, ink);
            free(s);
            free(c);
        }
    }
}

static unsigned long hash_canvas(cairo_surface_t *c) {
    cairo_surface_flush(c);
    unsigned char *d = cairo_image_surface_get_data(c);
    int stride = cairo_image_surface_get_stride(c), w = cairo_image_surface_get_width(c), h = cairo_image_surface_get_height(c);
    unsigned long hsh = 1469598103934665603ul;
    for (int y = 0; y < h; y++) {
        for (int i = 0; i < w * 4; i++) {
            hsh = (hsh ^ d[(size_t)y * stride + i]) * 1099511628211ul;
        }
    }
    return hsh;
}

// placing in a window: every size works, switching looks gives back the first picture (the caches are dropped and made again), fast mode and the settled picture
static void test_placing(void) {
    set_look(0);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    static const int sizes[][2] = {{992, 662}, {744, 497}, {1240, 828}, {640, 427}, {1600, 1068}, {800, 533}};
    for (unsigned z = 0; z < sizeof sizes / sizeof sizes[0]; z++) {
        unsigned long first[4];
        for (int v = 0; v < 4; v++) {
            box_style_set_variant(v);
            cairo_surface_t *c = cairo_image_surface_create(CAIRO_FORMAT_RGB24, sizes[z][0], sizes[z][1]);
            cairo_t *cr = cairo_create(c);
            skin_geom_t g;
            skin_geom(sizes[z][0], sizes[z][1], &g);
            box_style_draw_static(cr, &g);
            box_style_draw_controls(cr, &g, &st, 1);
            first[v] = hash_canvas(c);
            cairo_destroy(cr);
            cairo_surface_destroy(c);
        }
        for (int v = 3; v >= 0; v--) {
            box_style_set_variant(v);
            cairo_surface_t *c = cairo_image_surface_create(CAIRO_FORMAT_RGB24, sizes[z][0], sizes[z][1]);
            cairo_t *cr = cairo_create(c);
            skin_geom_t g;
            skin_geom(sizes[z][0], sizes[z][1], &g);
            box_style_draw_static(cr, &g);
            box_style_draw_controls(cr, &g, &st, 1);
            CHECK(hash_canvas(c) == first[v], "%s at %dx%d: the picture after switching back is the first one", names[v], sizes[z][0], sizes[z][1]);
            cairo_destroy(cr);
            cairo_surface_destroy(c);
        }
        // fast mode draws something else in between, and the settled picture equals the first again
        box_style_set_variant(1);
        box_style_set_fast(1);
        cairo_surface_t *c = cairo_image_surface_create(CAIRO_FORMAT_RGB24, sizes[z][0], sizes[z][1]);
        cairo_t *cr = cairo_create(c);
        skin_geom_t g;
        skin_geom(sizes[z][0], sizes[z][1], &g);
        box_style_draw_static(cr, &g);
        box_style_draw_controls(cr, &g, &st, 1);
        cairo_destroy(cr);
        cairo_surface_destroy(c);
        box_style_set_fast(0);
        c = cairo_image_surface_create(CAIRO_FORMAT_RGB24, sizes[z][0], sizes[z][1]);
        cr = cairo_create(c);
        box_style_draw_static(cr, &g);
        box_style_draw_controls(cr, &g, &st, 1);
        CHECK(hash_canvas(c) == first[1], "RETRO at %dx%d: after the quick drawing the settled picture is the first one", sizes[z][0], sizes[z][1]);
        cairo_destroy(cr);
        cairo_surface_destroy(c);
    }
    box_style_set_variant(0);
}

int main(void) {
    test_sizes_and_layout();
    test_hit();
    test_outlines();
    test_decorations();
    test_deterministic_and_distinct();
    test_looks();
    test_placing();
    if (failures == 0) {
        printf("box_retro_test: all passed\n");
    }
    return failures ? 1 : 0;
}
