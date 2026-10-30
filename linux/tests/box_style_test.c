/*
 * box_style_test.c: the pixel style (matron/src/platform/linux/box_style.c, through the skin's own entry points) and the hidden row (docs/port/box-style-plan.md 2.2, 2.3, 2.5, 2.8, 2.10; tests 1, 2, 8):
 *   - the layout table and its clearances, the hit tests (every control, rims, the cut corner of a key, the gaps, the screen, the hidden row, the MUTE chip), nearest encoder
 *   - pixels: only whole, opaque colours; no anti-aliasing; the palette from the formula; all keys one colour unless one is pressed; a pressed key moves a block down; lit buttons swap their colours
 *   - sizes: at 100 and 150 percent the window is a flat grid of blocks (2 and 3 device pixels), in between the flat areas keep their colour
 *   - the pixel font: the screen's norns.ttf (when found) and the built-in one: every label fits its button
 *   - the aluminium style with a tint and with the row hidden (the unchanged default is compared by box_aluminium_test.sh)
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos -I matron/src/platform/linux $(pkg-config --cflags cairo freetype2) linux/tests/box_style_test.c
 *      matron/src/platform/macos/device_skin.c matron/src/platform/linux/box_style.c matron/src/platform/linux/box_palette.c -o /tmp/bst $(pkg-config --libs cairo freetype2) -lm && /tmp/bst
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

static skin_geom_t geom_at(int w, int h) {
    skin_geom_t g;
    skin_geom(w, h, &g);
    return g;
}
// device pixel of a layout point at the design size (window 992 x 662, one unit a pixel, margin 16)
static double dp(double units) { return units + 16; }

static double gap(const double a[4], const double b[4]) {
    double dx = fmax(fmax(a[0] - b[2], b[0] - a[2]), 0), dy = fmax(fmax(a[1] - b[3], b[1] - a[3]), 0);
    return hypot(dx, dy);
}

static void rect_of(int id, double r[4]) {
    CHECK(box_style_control_rect(id, &r[0], &r[1], &r[2], &r[3]), "no rectangle for control %d", id);
}

static void test_layout(void) {
    double r[4];
    // the numbers of the plan's table 2.2 (centres and sizes in units)
    struct { int id; double cx, cy, w, h; } t[] = {
        {SKIN_K1, 100, 188, 112, 112}, {SKIN_K1 + 1, 734, 530, 112, 112}, {SKIN_K1 + 2, 864, 530, 112, 112},
        {SKIN_E1, 240, 188, 80, 80},   {SKIN_E1 + 1, 734, 376, 80, 80},   {SKIN_E1 + 2, 864, 376, 80, 80},
    };
    for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
        rect_of(t[i].id, r);
        CHECK(fabs((r[0] + r[2]) / 2 - t[i].cx) < 0.01 && fabs((r[1] + r[3]) / 2 - t[i].cy) < 0.01 && fabs(r[2] - r[0] - t[i].w) < 0.01 && fabs(r[3] - r[1] - t[i].h) < 0.01,
              "control %d: (%g,%g)-(%g,%g)", t[i].id, r[0], r[1], r[2], r[3]);
        CHECK(fmod(r[0], 2) == 0 && fmod(r[1], 2) == 0 && fmod(r[2], 2) == 0 && fmod(r[3], 2) == 0, "control %d is on the 2 unit grid", t[i].id);
    }
    rect_of(SKIN_K1, r);
    double e1[4];
    rect_of(SKIN_E1, e1);
    CHECK(fabs((r[2] - r[0]) / (e1[2] - e1[0]) - 1.4) < 0.001, "key / encoder = 1.40");
    // buttons: 70 x 40 at y 36, the aluminium style's x
    for (int id = SKIN_PAGE1; id <= SKIN_MUTE; id++) {
        rect_of(id, r);
        CHECK(fabs(r[2] - r[0] - 70) < 1e-6 && fabs(r[3] - r[1] - 40) < 1e-6 && fabs(r[1] - 36) < 1e-6, "button %d is 70 x 40 at y 36", id);
    }
    // clearances: the margin of 36, the bezel (x 36 .. 592, y 300.667 .. 594), the other controls
    const double bezel[4] = {36, 300.667, 592, 594}, toast[4] = {300, 157, 865, 193};
    int ids[32], n = 0;
    for (int id = SKIN_K1; id <= SKIN_MUTE; id++) {
        if (id >= SKIN_K1 && id <= SKIN_E3 + 0) ids[n++] = id;
        if (id >= SKIN_PAGE1 && id <= SKIN_MAIDEN + 1) ids[n++] = id;
    }
    ids[n++] = SKIN_MUTE;
    for (int i = 0; i < n; i++) {
        rect_of(ids[i], r);
        CHECK(r[0] >= 36 - 1e-6 && r[1] >= 36 - 1e-6 && r[2] <= 924 + 1e-6 && r[3] <= 594 + 1e-6, "control %d inside the margin", ids[i]);
        if (ids[i] < SKIN_PAGE1) {
            CHECK(gap(r, bezel) >= 20, "control %d clear of the bezel (%g)", ids[i], gap(r, bezel));
            CHECK(gap(r, toast) >= 4, "control %d clear of the toast pill", ids[i]);
            CHECK(r[1] >= 76 + 20, "control %d at least 20 units under the button row", ids[i]);
        }
        for (int j = i + 1; j < n; j++) {
            double q[4];
            rect_of(ids[j], q);
            // the hit areas are 2 units bigger on every side: two rectangles must stay apart by more than 4 (circles are inside their rectangles)
            CHECK(gap(r, q) > 4 - 1e-6, "controls %d and %d are %g apart", ids[i], ids[j], gap(r, q));
        }
    }
}

static void use_pixel(int shown) {
    static const char *c[5] = {"2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea"};
    skin_set_look(SKIN_STYLE_PIXEL, c[0], c[1], c[2], c[3], c[4]);
    skin_set_buttons_shown(shown);
    skin_note_muted(0);
}

static void test_hits(void) {
    use_pixel(1);
    skin_geom_t g = geom_at(992, 662);
    CHECK(skin_look_style() == SKIN_STYLE_PIXEL, "style set");
    // centres
    CHECK(skin_hit(&g, dp(100), dp(188)) == SKIN_K1, "K1 centre");
    CHECK(skin_hit(&g, dp(734), dp(530)) == SKIN_K1 + 1, "K2 centre");
    CHECK(skin_hit(&g, dp(864), dp(530)) == SKIN_K1 + 2, "K3 centre");
    CHECK(skin_hit(&g, dp(240), dp(188)) == SKIN_E1, "E1 centre");
    CHECK(skin_hit(&g, dp(734), dp(376)) == SKIN_E1 + 1, "E2 centre");
    CHECK(skin_hit(&g, dp(864), dp(376)) == SKIN_E1 + 2, "E3 centre");
    // rims: a key's edge middle (inside by 1, outside by 3), an encoder's rim (41 in, 43 out)
    CHECK(skin_hit(&g, dp(100 + 55), dp(188)) == SKIN_K1, "K1 right edge inside");
    CHECK(skin_hit(&g, dp(100 + 59), dp(188)) == SKIN_NONE, "K1 just outside the edge");
    CHECK(skin_hit(&g, dp(240 + 41), dp(188)) == SKIN_E1, "E1 rim inside");
    CHECK(skin_hit(&g, dp(240 + 43), dp(188)) == SKIN_NONE, "E1 just outside");
    // the cut corner of a key: the square's corner is not a hit, the point inside the cut is
    CHECK(skin_hit(&g, dp(100 + 55), dp(188 + 55)) == SKIN_NONE, "K1 corner (cut) is a miss");
    CHECK(skin_hit(&g, dp(100 + 50), dp(188 + 50)) == SKIN_K1, "K1 near the corner, inside the cut");
    // the gap between K2 and K3 (18 units), between buttons, the screen, the free box
    CHECK(skin_hit(&g, dp(799), dp(530)) == SKIN_NONE, "between K2 and K3");
    CHECK(skin_hit(&g, dp(109 + 70 + 3), dp(56)) == SKIN_NONE || skin_hit(&g, dp(109 + 70 + 3), dp(56)) == SKIN_PAGE1 + 1, "between MIX and TAPE");
    CHECK(skin_hit(&g, dp(300), dp(450)) == SKIN_NONE, "the screen is not a control");
    CHECK(skin_hit(&g, dp(500), dp(180)) == SKIN_NONE, "free box");
    // buttons: every centre, and the group gaps
    static const double bx[] = {36, 112, 188, 264, 359.3333, 435.3333, 511.3333, 587.3333, 682.6667, 758.6667, 854};
    for (int i = 0; i < 11; i++) {
        CHECK(skin_hit(&g, dp(bx[i] + 35), dp(56)) == SKIN_PAGE1 + i, "button %d centre", i);
        CHECK(skin_hit(&g, dp(bx[i] + 35), dp(36 + 40 + 1)) == SKIN_PAGE1 + i, "button %d just under the face (slop)", i);
        CHECK(skin_hit(&g, dp(bx[i] + 35), dp(36 + 40 + 4)) == SKIN_NONE, "button %d below the slop", i);
    }
    CHECK(skin_hit(&g, dp(344), dp(56)) == SKIN_NONE, "the gap between PARAMS and MIC");
    // nearest encoder for the wheel
    CHECK(skin_nearest_enc(&g, dp(700), dp(300)) == 2 && skin_nearest_enc(&g, dp(900), dp(300)) == 3 && skin_nearest_enc(&g, dp(250), dp(200)) == 1, "nearest encoder");
    // the hidden row: no buttons, nothing else changes; the MUTE chip answers while muted
    skin_set_buttons_shown(0);
    CHECK(skin_hit(&g, dp(36 + 35), dp(56)) == SKIN_NONE, "hidden row: no MIX");
    CHECK(skin_hit(&g, dp(854 + 35), dp(56)) == SKIN_NONE, "hidden row, not muted: no MUTE");
    CHECK(skin_hit(&g, dp(100), dp(188)) == SKIN_K1 && skin_hit(&g, dp(864), dp(376)) == SKIN_E1 + 2, "hidden row: keys and encoders still hit");
    skin_note_muted(1);
    CHECK(skin_hit(&g, dp(854 + 35), dp(56)) == SKIN_MUTE, "hidden row, muted: the MUTE chip");
    CHECK(skin_hit(&g, dp(36 + 35), dp(56)) == SKIN_NONE, "hidden row, muted: still no MIX");
    // scaled window: the same points at 150 percent
    skin_note_muted(0);
    skin_set_buttons_shown(1);
    skin_geom_t g2 = geom_at(1488, 993);
    CHECK(skin_hit(&g2, g2.ox + 100 * g2.s, g2.oy + 188 * g2.s) == SKIN_K1 && skin_hit(&g2, g2.ox + 864 * g2.s, g2.oy + 530 * g2.s) == SKIN_K1 + 2, "hits scale with the window");
}

typedef struct {
    uint32_t px[BS_W * BS_H];
} img_t;
static img_t stat, ctl;

static uint32_t at(const img_t *im, double ux, double uy) { // a layout point -> the block image
    return im->px[(8 + (int)floor(uy / 2)) * BS_W + 8 + (int)floor(ux / 2)];
}

static void test_pixels(void) {
    use_pixel(1);
    box_style_render_static(stat.px);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    box_style_render_controls(ctl.px, &st, 1);
    box_rgb_t col[5] = {{0x2C, 0x2E, 0x33}, {0x44, 0x48, 0x53}, {0x5D, 0x62, 0x70}, {0x3A, 0x3D, 0x45}, {0xE4, 0xE6, 0xEA}};
    // every pixel of both layers is opaque (static) or fully transparent / opaque (controls): no blending, no anti-aliasing
    long partial = 0, opaque_ctl = 0;
    for (int i = 0; i < BS_W * BS_H; i++) {
        uint32_t a = stat.px[i] >> 24;
        CHECK(a == 255, "static pixel %d has alpha %u", i, a);
        uint32_t c = ctl.px[i] >> 24;
        if (c != 0 && c != 255) {
            partial++;
        }
        if (c == 255) {
            opaque_ctl++;
        }
    }
    CHECK(partial == 0, "%ld controls pixels are partly transparent", partial);
    CHECK(opaque_ctl > 20000, "controls drawn (%ld pixels)", opaque_ctl);
    // a limited palette: the colours of the two layers together
    uint32_t seen[512];
    int nseen = 0;
    for (int layer = 0; layer < 2; layer++) {
        const uint32_t *p = layer ? ctl.px : stat.px;
        for (int i = 0; i < BS_W * BS_H; i++) {
            if ((p[i] >> 24) != 255) {
                continue;
            }
            int found = 0;
            for (int k = 0; k < nseen && !found; k++) {
                found = seen[k] == p[i];
            }
            if (!found && nseen < 512) {
                seen[nseen++] = p[i];
            }
        }
    }
    CHECK(nseen <= 40, "%d distinct colours: the palette is not limited", nseen);
    // the formula: the box face, its outline, its bevel
    box_rgb_t box = col[0], keys = col[1];
    uint32_t want_box = 0xff000000u | (uint32_t)box.r << 16 | (uint32_t)box.g << 8 | box.b;
    CHECK(at(&stat, 500, 200) == want_box, "the box face is the BOX colour: %08X", at(&stat, 500, 200));
    box_rgb_t d = box_darker(box);
    CHECK(at(&stat, 500, 0) == (0xff000000u | (uint32_t)d.r << 16 | (uint32_t)d.g << 8 | d.b), "the box's top edge is the darker shade: %08X", at(&stat, 500, 0));
    box_rgb_t l = box_light(box);
    CHECK(at(&stat, 500, 2) == (0xff000000u | (uint32_t)l.r << 16 | (uint32_t)l.g << 8 | l.b), "the bevel below it is the light shade: %08X", at(&stat, 500, 2));
    CHECK(at(&stat, 300, 450) == 0xff000000u, "the bezel's window is black");
    // keys: all the same colour while none is pressed; a pressed one is darker and sits a block lower
    uint32_t k1 = at(&ctl, 100, 188), k2 = at(&ctl, 734, 530), k3 = at(&ctl, 864, 530);
    CHECK(k1 == k2 && k2 == k3, "the three keys have one colour: %08X %08X %08X", k1, k2, k3);
    CHECK(k1 == (0xff000000u | (uint32_t)keys.r << 16 | (uint32_t)keys.g << 8 | keys.b), "the key face is the KEYS colour");
    st.key_down[2] = 1;
    box_style_render_controls(ctl.px, &st, 1);
    CHECK(at(&ctl, 100, 188) == k1 && at(&ctl, 734, 530) == k2, "K1 and K2 are not changed by K3 being down");
    box_rgb_t kd = box_dark(keys);
    CHECK(at(&ctl, 864, 530) == (0xff000000u | (uint32_t)kd.r << 16 | (uint32_t)kd.g << 8 | kd.b), "a pressed key is the dark shade of KEYS");
    CHECK((at(&ctl, 864, 530 - 56) >> 24) == 0 || (at(&ctl, 864, 530 - 55) >> 24) == 255, "a pressed key moves down one block");
    st.key_down[2] = 0;
    // buttons: lit = the colours swapped (PARAMS is the page shown, MIC the input)
    box_style_render_controls(ctl.px, &st, 1);
    uint32_t params = at(&ctl, 264 + 4, 36 + 6), mix = at(&ctl, 36 + 4, 36 + 6);
    CHECK(params != mix, "the lit PARAMS differs from the unlit MIX");
    CHECK(mix == (0xff000000u | (uint32_t)col[3].r << 16 | (uint32_t)col[3].g << 8 | col[3].b), "an unlit button is the BUTTONS colour: %08X", mix);
    CHECK(params == (0xff000000u | (uint32_t)col[4].r << 16 | (uint32_t)col[4].g << 8 | col[4].b), "a lit button is the FONT colour: %08X", params);
    // the hidden row: nothing of the row is drawn, the keys are
    box_style_render_controls(ctl.px, &st, 0);
    CHECK((at(&ctl, 36 + 35, 36 + 20) >> 24) == 0 && (at(&ctl, 264 + 35, 36 + 20) >> 24) == 0, "hidden row: transparent where the buttons were");
    CHECK((at(&ctl, 100, 188) >> 24) == 255, "hidden row: the key is still drawn");
    st.out_muted = 1;
    box_style_render_controls(ctl.px, &st, 0);
    CHECK((at(&ctl, 854 + 4, 36 + 6) >> 24) == 255 && (at(&ctl, 36 + 35, 36 + 20) >> 24) == 0, "hidden row, muted: only the MUTE chip is drawn");
    CHECK(at(&ctl, 854 + 4, 36 + 6) == (0xff000000u | (uint32_t)col[4].r << 16 | (uint32_t)col[4].g << 8 | col[4].b), "the MUTE chip is lit");
    // an encoder's notch turns with the detents: ticks change the picture, 36 of them are one turn
    st.out_muted = 0;
    static img_t other;
    box_style_render_controls(ctl.px, &st, 1);
    st.enc_ticks[1] = 3;
    box_style_render_controls(other.px, &st, 1);
    CHECK(memcmp(ctl.px, other.px, sizeof ctl.px) != 0, "turning E2 changes the picture");
    st.enc_ticks[1] = 36;
    box_style_render_controls(other.px, &st, 1);
    CHECK(memcmp(ctl.px, other.px, sizeof ctl.px) == 0, "36 detents are one turn");
    st.enc_ticks[1] = -33;
    box_style_render_controls(other.px, &st, 1);
    CHECK(memcmp(ctl.px, other.px, sizeof ctl.px) != 0 || 1, "negative ticks do not crash");
}

static void test_fonts(void) {
    static const char *labels[] = {"MIX", "TAPE", "HOME", "PARAMS", "MIC", "GRID", "ARC", "KEYS", "MAIDEN", "MANUAL", "MUTE", "OFF", "SYS", "APP"};
    box_style_set_font("builtin");
    CHECK(!strcmp(box_style_font_name(), "builtin"), "builtin font selected");
    for (unsigned i = 0; i < sizeof labels / sizeof labels[0]; i++) {
        CHECK(box_style_text_width(labels[i]) <= 31, "built-in: %s is %d blocks wide (31 fit)", labels[i], box_style_text_width(labels[i]));
    }
    CHECK(box_style_text_width("PARAMS") == 23 && box_style_text_width("") == 0, "built-in widths: PARAMS 23, empty 0");
    box_style_set_font("/nonexistent/norns.ttf");
    CHECK(!strcmp(box_style_font_name(), "builtin"), "a missing font file falls back to the built-in font");
    const char *ttf = getenv("NORNS_TEST_TTF");
    if (ttf != NULL && ttf[0]) {
        box_style_set_font(ttf);
        CHECK(!strcmp(box_style_font_name(), "norns.ttf"), "norns.ttf loaded");
        for (unsigned i = 0; i < sizeof labels / sizeof labels[0]; i++) {
            CHECK(box_style_text_width(labels[i]) <= 31, "norns.ttf: %s is %d blocks wide (31 fit)", labels[i], box_style_text_width(labels[i]));
        }
        CHECK(box_style_text_width("PARAMS") >= 28 && box_style_text_width("PARAMS") <= 31, "norns.ttf PARAMS is about 31 blocks: %d", box_style_text_width("PARAMS"));
    } else {
        printf("  (NORNS_TEST_TTF not set: the norns.ttf part is skipped)\n");
    }
    box_style_set_font(NULL);
}

static cairo_surface_t *canvas_at(int w, int h, skin_geom_t *g) {
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    cairo_t *cr = cairo_create(s);
    skin_geom(w, h, g);
    skin_draw_static(cr, g);
    cairo_destroy(cr);
    cairo_surface_flush(s);
    return s;
}

static uint32_t cpx(cairo_surface_t *s, int x, int y) {
    return ((uint32_t *)(cairo_image_surface_get_data(s) + y * cairo_image_surface_get_stride(s)))[x] & 0xffffff;
}

static void test_sizes(void) {
    use_pixel(1);
    // 100 and 150 percent: a flat grid of blocks, 2 and 3 device pixels, aligned to the window's origin
    int sizes[2][3] = {{992, 662, 2}, {1488, 993, 3}};
    for (int z = 0; z < 2; z++) {
        skin_geom_t g;
        cairo_surface_t *s = canvas_at(sizes[z][0], sizes[z][1], &g);
        int k = sizes[z][2];
        long bad = 0;
        for (int y = 0; y + k <= sizes[z][1] - (sizes[z][1] % k); y += k) {
            for (int x = 0; x + k <= sizes[z][0] - (sizes[z][0] % k); x += k) {
                uint32_t c = cpx(s, x, y);
                for (int dy = 0; dy < k; dy++) {
                    for (int dx = 0; dx < k; dx++) {
                        if (cpx(s, x + dx, y + dy) != c) {
                            bad++;
                        }
                    }
                }
            }
        }
        CHECK(bad == 0, "%dx%d: %ld device pixels break the %dx%d block grid", sizes[z][0], sizes[z][1], bad, k, k);
        cairo_surface_destroy(s);
    }
    // in between (125 percent: 2.5 device pixels per block): the flat middle of the box keeps the BOX colour, the surround is the darker shade
    skin_geom_t g;
    cairo_surface_t *s = canvas_at(1240, 828, &g);
    CHECK(cpx(s, (int)(g.ox + 500 * g.s), (int)(g.oy + 200 * g.s)) == 0x2C2E33, "125 percent: the box face is still 2C2E33: %06X", cpx(s, (int)(g.ox + 500 * g.s), (int)(g.oy + 200 * g.s)));
    box_rgb_t d = box_darker((box_rgb_t){0x2C, 0x2E, 0x33});
    CHECK(cpx(s, 6, 6) == ((unsigned)d.r << 16 | (unsigned)d.g << 8 | d.b), "125 percent: the surround is the darker shade (got %06X, want %02X%02X%02X)", cpx(s, 6, 6), d.r, d.g, d.b);
    cairo_surface_destroy(s);
    // a small window (60 percent) and a very wide one draw without trouble and centre the box
    s = canvas_at(600, 400, &g);
    CHECK(g.s > 0.5 && g.s < 0.7, "60 percent scale %g", g.s);
    cairo_surface_destroy(s);
    s = canvas_at(1600, 662, &g);
    CHECK(cpx(s, 5, 300) == ((unsigned)d.r << 16 | (unsigned)d.g << 8 | d.b), "a wide window: the surround fills the sides");
    cairo_surface_destroy(s);
}

static void test_alu_look(void) {
    // the aluminium style with a tint and with the row hidden
    skin_set_look(SKIN_STYLE_ALUMINIUM, "3b6ea8", NULL, NULL, NULL, NULL);
    skin_set_buttons_shown(1);
    skin_geom_t g = geom_at(992, 662);
    cairo_surface_t *a = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 992, 662);
    cairo_t *cr = cairo_create(a);
    skin_draw_static(cr, &g);
    cairo_destroy(cr);
    cairo_surface_flush(a);
    uint32_t p = cpx(a, 500, 250);
    CHECK((p & 0xff) > (p >> 16 & 0xff), "a blue box is bluer than red: %06X", p);
    cairo_surface_destroy(a);
    CHECK(skin_hit(&g, dp(100), dp(188)) == SKIN_K1, "aluminium: K1");
    skin_set_buttons_shown(0);
    CHECK(skin_hit(&g, dp(36 + 35), dp(56)) == SKIN_NONE, "aluminium, hidden row: no MIX");
    skin_note_muted(1);
    CHECK(skin_hit(&g, dp(854 + 35), dp(56)) == SKIN_MUTE, "aluminium, hidden row, muted: the MUTE chip");
    skin_note_muted(0);
    skin_set_buttons_shown(1);
    CHECK(skin_hit(&g, dp(36 + 35), dp(56)) == SKIN_PAGE1, "aluminium, row shown: MIX");
    skin_set_look(SKIN_STYLE_ALUMINIUM, NULL, NULL, NULL, NULL, NULL);
}

int main(void) {
    test_layout();
    test_hits();
    test_pixels();
    test_fonts();
    test_sizes();
    test_alu_look();
    if (failures == 0) {
        printf("box_style_test: all passed\n");
    }
    return failures ? 1 : 0;
}
