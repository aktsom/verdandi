/*
 * device_skin_linux_test.c: the Linux window layout (arrangement A of docs/port/ui-plan.md section 1.6, with the margin "grow" of section 1.8 and the
 * window scaling "option A" of section 1.9): geometry, hit testing and the rendered window, at the design size and at other sizes, of
 * platform/macos/device_skin.c built with -DNORNS_LINUX_DESKTOP. the Mac layout is tested by macos/tests/device_skin_test.c (built without the define).
 *
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos $(pkg-config --cflags cairo) linux/tests/device_skin_linux_test.c \
 *      matron/src/platform/macos/device_skin.c matron/src/platform/macos/window_keys.c -o /tmp/dsl $(pkg-config --libs cairo) -lm && /tmp/dsl [out.png]
 *
 * the window is 992 x 662 pixels (960 x 630 units and a margin of 16), one unit a pixel. positions in units; a window pixel is a unit plus 16.
 */
#include <math.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "device_skin.h"
#include "window_keys.h"

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

#define WINDOW_KEYS_CHECKSUM 581825047u // window_keys.c as it was before the layout change
#define W (SKIN_W + 2 * SKIN_MARGIN)
#define H (SKIN_H + 2 * SKIN_MARGIN)

// the chosen layout (units), arrangement A
static const double KEY[3][2] = {{71.65, 188.33}, {655.65, 517.48}, {785.65, 517.48}};
static const double ENC[3][2] = {{194.70, 188.33}, {745.35, 377.18}, {875.35, 377.18}};
static const double KEY_R = 35.65, ENC_R = 43.7;
static const double BTN_X[11] = {36, 112, 188, 264, 359.3333, 435.3333, 511.3333, 587.3333, 682.6667, 758.6667, 854};
static const double BTN_Y = 36, BTN_W = 70, BTN_H = 40;
static const double BEZEL_X = 36, BEZEL_Y = 300.667, BEZEL_W = 556, BEZEL_H = 293.333; // the screen 512 x 256 in it: margins 22 and 18.67

static skin_geom_t geom(void) {
    skin_geom_t g;
    skin_geom(W, H, &g);
    return g;
}
static double px(const skin_geom_t *g, double ux) { return g->ox + ux * g->s; }
static double py(const skin_geom_t *g, double uy) { return g->oy + uy * g->s; }
static int hit(const skin_geom_t *g, double ux, double uy) { return skin_hit(g, px(g, ux), py(g, uy)); }

static void test_size_and_enum(void) {
    CHECK(SKIN_W == 960 && SKIN_H == 630 && SKIN_MARGIN == 16, "box %d x %d margin %d", SKIN_W, SKIN_H, SKIN_MARGIN);
    CHECK(W == 992 && H == 662, "window %d x %d", W, H);
    skin_geom_t g = geom();
    CHECK(g.s == 1.0, "scale %g at the default window size", g.s);
    // the screen: exactly 4 device pixels per screen pixel, 512 x 256, in the bezel's middle
    CHECK(g.oled_px == 4, "device pixels per screen pixel %d", g.oled_px);
    CHECK(g.oled_x == 74 && g.oled_y == 335, "screen at %d,%d (the bezel's centre minus 256 and 128, the window's margin of 16 added)", g.oled_x, g.oled_y);
    CHECK(g.oled_w == 512 && g.oled_h == 256, "screen %d x %d device pixels", g.oled_w, g.oled_h);
    // the window's margin: the box's origin
    CHECK((int)g.ox == 16 && (int)g.oy == 16, "box origin %g,%g", g.ox, g.oy);
    // the enum: MUTE is the 11th button, id 17, and there is no slider id before it
    CHECK(SKIN_MUTE == 17, "SKIN_MUTE is %d", SKIN_MUTE);
    CHECK(SKIN_PAGE1 + 10 == SKIN_MUTE, "the 11th button is id %d, MUTE is %d", SKIN_PAGE1 + 10, SKIN_MUTE);
    CHECK(SKIN_MANUAL == SKIN_PAGE1 + 9, "MANUAL is %d", SKIN_MANUAL);
}

static void test_hits(void) {
    skin_geom_t g = geom();
    // buttons: every centre hits its own id, MUTE as the last, 17
    for (int i = 0; i < 11; i++) {
        int h = hit(&g, BTN_X[i] + BTN_W / 2, BTN_Y + BTN_H / 2);
        CHECK(h == SKIN_PAGE1 + i, "button %d centre hits %d, want %d", i, h, SKIN_PAGE1 + i);
        CHECK(hit(&g, BTN_X[i] + 1, BTN_Y + 1) == SKIN_PAGE1 + i && hit(&g, BTN_X[i] + BTN_W - 1, BTN_Y + BTN_H - 1) == SKIN_PAGE1 + i,
              "button %d corners", i);
    }
    CHECK(hit(&g, BTN_X[10] + 35, BTN_Y + 20) == 17, "the last button of the row is MUTE, id 17");
    // gaps between the groups hit nothing
    CHECK(hit(&g, (BTN_X[3] + BTN_W + BTN_X[4]) / 2, BTN_Y + 20) == SKIN_NONE, "gap after PARAMS");
    CHECK(hit(&g, (BTN_X[7] + BTN_W + BTN_X[8]) / 2, BTN_Y + 20) == SKIN_NONE, "gap after KEYS");
    CHECK(hit(&g, (BTN_X[9] + BTN_W + BTN_X[10]) / 2, BTN_Y + 20) == SKIN_NONE, "gap before MUTE");
    // keys and encoders: centre, and the 15 percent bigger hit circles (key r 35.65 + 6, encoder 43.7 + 6)
    for (int i = 0; i < 3; i++) {
        CHECK(hit(&g, KEY[i][0], KEY[i][1]) == SKIN_K1 + i, "K%d centre", i + 1);
        CHECK(hit(&g, KEY[i][0] + 41.0, KEY[i][1]) == SKIN_K1 + i, "K%d inside its hit circle (41 of 41.65)", i + 1);
        CHECK(hit(&g, KEY[i][0] + 42.5, KEY[i][1]) == SKIN_NONE, "K%d outside its hit circle (42.5)", i + 1);
        CHECK(hit(&g, ENC[i][0], ENC[i][1]) == SKIN_E1 + i, "E%d centre", i + 1);
        CHECK(hit(&g, ENC[i][0] + 49.0, ENC[i][1]) == SKIN_E1 + i, "E%d inside its hit circle (49 of 49.7)", i + 1);
        CHECK(hit(&g, ENC[i][0] + 51.0, ENC[i][1]) == SKIN_NONE, "E%d outside its hit circle (51)", i + 1);
    }
    // the old slider and the old MUTE: nothing there any more
    CHECK(hit(&g, 913, 340) == SKIN_NONE, "the old slider's middle hits %d", hit(&g, 913, 340));
    CHECK(hit(&g, 913, 190) == SKIN_NONE && hit(&g, 913, 495) == SKIN_NONE, "the old slider's ends");
    CHECK(hit(&g, 913, 537) == SKIN_NONE, "the old MUTE place hits %d", hit(&g, 913, 537));
    // the screen and the free areas
    CHECK(hit(&g, BEZEL_X + BEZEL_W / 2, BEZEL_Y + BEZEL_H / 2) == SKIN_NONE, "the screen hits a control");
    CHECK(hit(&g, 480, 140) == SKIN_NONE && hit(&g, 760, 200) == SKIN_NONE, "the free band under the buttons");
    // the bezel grew: its edge and corner hit nothing, and no control's hit area reaches into it (lip 3 units)
    CHECK(hit(&g, BEZEL_X + BEZEL_W - 1, BEZEL_Y + 1) == SKIN_NONE && hit(&g, BEZEL_X + 2, BEZEL_Y + BEZEL_H - 2) == SKIN_NONE, "the bezel's corners");
    CHECK(hit(&g, 1, 1) == SKIN_NONE, "the corner");
    // the nearest encoder for a wheel anywhere
    CHECK(skin_nearest_enc(&g, px(&g, 100), py(&g, 400)) == 1, "wheel at the left turns E1");
    CHECK(skin_nearest_enc(&g, px(&g, 700), py(&g, 300)) == 2, "wheel at the right, left half, turns E2");
    CHECK(skin_nearest_enc(&g, px(&g, 900), py(&g, 300)) == 3, "wheel at the right turns E3");
    // the screen's pixel under a point (the mouse on the MIX page)
    int ox = -1, oy = -1;
    CHECK(skin_oled_pixel(&g, g.oled_x, g.oled_y, &ox, &oy) && ox == 0 && oy == 0, "screen pixel 0,0");
    CHECK(skin_oled_pixel(&g, g.oled_x + g.oled_w - 1, g.oled_y + g.oled_h - 1, &ox, &oy) && ox == 127 && oy == 63, "screen pixel 127,63");
    CHECK(!skin_oled_pixel(&g, g.oled_x + g.oled_w, g.oled_y + 100, &ox, &oy), "just right of the screen");
}

// the window as the program draws it: static layer, controls, screen
static cairo_surface_t *render(int muted, cairo_surface_t *oled) {
    skin_geom_t g = geom();
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, W, H);
    cairo_t *cr = cairo_create(s);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    st.out_muted = muted;
    skin_draw_static(cr, &g);
    skin_draw_controls(cr, &g, &st);
    skin_draw_oled(cr, &g, oled);
    cairo_destroy(cr);
    cairo_surface_flush(s);
    return s;
}
// a render of any window size (the window is resized): the box origin and scale are the ones skin_geom gives
static cairo_surface_t *render_at(int w, int h, cairo_surface_t *oled, skin_geom_t *gout) {
    skin_geom_t g;
    skin_geom(w, h, &g);
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    cairo_t *cr = cairo_create(s);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    skin_draw_static(cr, &g);
    skin_draw_controls(cr, &g, &st);
    skin_draw_oled(cr, &g, oled);
    cairo_destroy(cr);
    cairo_surface_flush(s);
    if (gout) *gout = g;
    return s;
}
static uint32_t rawpix(cairo_surface_t *s, int x, int y) {
    return ((uint32_t *)(cairo_image_surface_get_data(s) + y * cairo_image_surface_get_stride(s)))[x] & 0xffffff;
}
static uint32_t pix(cairo_surface_t *s, double ux, double uy) {
    int x = (int)lround(ux) + SKIN_MARGIN, y = (int)lround(uy) + SKIN_MARGIN;
    return ((uint32_t *)(cairo_image_surface_get_data(s) + y * cairo_image_surface_get_stride(s)))[x] & 0xffffff;
}
static int lum(uint32_t p) { return (((p >> 16) & 0xff) * 3 + ((p >> 8) & 0xff) * 6 + (p & 0xff)) / 10; }
// the darkest pixel in a rectangle of units
static int min_lum(cairo_surface_t *s, double x0, double y0, double x1, double y1) {
    int m = 255;
    for (double y = y0; y <= y1; y++)
        for (double x = x0; x <= x1; x++) {
            int l = lum(pix(s, x, y));
            if (l < m) m = l;
        }
    return m;
}

static void test_render(const char *png) {
    // a screen image whose columns alternate black and white: every column must be 4 device pixels wide, and the rows 4 high
    cairo_surface_t *oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *d = (uint32_t *)cairo_image_surface_get_data(oled);
    int ds = cairo_image_surface_get_stride(oled) / 4;
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 128; x++) d[y * ds + x] = ((x + (y / 8)) & 1) ? 0xffffff : 0x000000;
    cairo_surface_mark_dirty(oled);
    cairo_surface_t *s = render(0, oled);
    if (png) cairo_surface_write_to_png(s, png);
    skin_geom_t g = geom();
    int bad = 0;
    for (int c = 0; c < 128; c++) {
        // row 0 of the screen is y 324 (units: 340 - 16); the pattern in rows 0..7 is (c & 1) ? white : black
        uint32_t want = (c & 1) ? 0xffffff : 0x000000;
        for (int k = 0; k < 4; k++) {
            if (pix(s, g.oled_x - SKIN_MARGIN + 4 * c + k, g.oled_y - SKIN_MARGIN + 2) != want) bad++;
        }
    }
    CHECK(bad == 0, "%d screen pixels in a row are not 4 device pixels wide and even", bad);
    bad = 0;
    // rows: the pattern changes every 8 screen rows (32 device rows): check one column across a boundary: rows 7 and 8 differ, all 4 device rows of a screen row equal
    for (int r = 0; r < 64; r++) {
        uint32_t first = pix(s, g.oled_x - SKIN_MARGIN + 1, g.oled_y - SKIN_MARGIN + 4 * r);
        for (int k = 1; k < 4; k++)
            if (pix(s, g.oled_x - SKIN_MARGIN + 1, g.oled_y - SKIN_MARGIN + 4 * r + k) != first) bad++;
    }
    CHECK(bad == 0, "%d device rows of a screen row differ", bad);
    // the screen covers exactly 512 x 256: the pixel just left of and right of it is the bezel's black, as is above and below
    // the slider is gone: nothing dark where its slot was (x 909..917); E3's washer ends at 913.1, so look right of it, and between its top and the row
    CHECK(min_lum(s, 923, 195, 945, 500) > 150, "something dark where the OUT slider was (darkest %d)", min_lum(s, 923, 195, 945, 500));
    CHECK(min_lum(s, 880, 515, 945, 560) > 150, "something dark where the old MUTE was (darkest %d)", min_lum(s, 880, 515, 945, 560));
    // the OUT label's place
    CHECK(min_lum(s, 925, 168, 945, 182) > 150, "the OUT text is still there (darkest %d)", min_lum(s, 900, 168, 925, 182));
    // MUTE in the top row: a dark button face, with its LED dark when not muted and amber when muted
    CHECK(lum(pix(s, BTN_X[10] + 50, BTN_Y + 30)) < 90, "the MUTE button face is not dark (%d)", lum(pix(s, BTN_X[10] + 50, BTN_Y + 30)));
    uint32_t led_off = pix(s, BTN_X[10] + 12, BTN_Y + 20);
    CHECK(((led_off >> 16) & 0xff) < 100, "the MUTE LED is lit while not muted (%06x)", led_off);
    cairo_surface_t *m = render(1, oled);
    uint32_t led_on = pix(m, BTN_X[10] + 12, BTN_Y + 20);
    CHECK(((led_on >> 16) & 0xff) > 200 && ((led_on >> 8) & 0xff) > 150 && (led_on & 0xff) < 160, "the MUTE LED is not amber when muted (%06x)", led_on);
    // the other buttons keep their look: PARAMS is lit (page 4)
    uint32_t params = pix(s, BTN_X[3] + 12, BTN_Y + 20);
    CHECK(((params >> 16) & 0xff) > 200, "PARAMS is not lit (%06x)", params);
    // the keys and encoders are 15 percent bigger: the key cap (dark) now reaches 28.75 units from the centre and the well (light) 35.65
    CHECK(lum(pix(s, KEY[0][0] + 27, KEY[0][1])) < 90, "K1's cap does not reach 27 units (%d)", lum(pix(s, KEY[0][0] + 27, KEY[0][1])));
    CHECK(lum(pix(s, KEY[0][0] + 32, KEY[0][1])) > 100, "K1's well is not light at 32 units (%d)", lum(pix(s, KEY[0][0] + 32, KEY[0][1])));
    CHECK(lum(pix(s, ENC[1][0] + 33, ENC[1][1])) > 120 && lum(pix(s, ENC[1][0] + 41, ENC[1][1])) > 100, "E2's washer is not light out to 41 units");
    // no K1..E3 text: the places where the labels were (45 degrees below and right of each control) are plain light metal
    for (int i = 0; i < 3; i++) {
        double r = KEY_R + 5, ox = KEY[i][0] + r * 0.70, oy = KEY[i][1] + r * 0.70;
        int l = min_lum(s, ox + 8, oy + 8, ox + 22, oy + 22);
        CHECK(l > 140, "K%d: a label is drawn (darkest %d at %.0f,%.0f)", i + 1, l, ox + 8, oy + 8);
        r = ENC_R + 5, ox = ENC[i][0] + r * 0.70, oy = ENC[i][1] + r * 0.70;
        l = min_lum(s, ox + 8, oy + 8, ox + 22, oy + 22);
        CHECK(l > 140, "E%d: a label is drawn (darkest %d at %.0f,%.0f)", i + 1, l, ox + 8, oy + 8);
    }
    cairo_surface_destroy(s);
    cairo_surface_destroy(m);
    cairo_surface_destroy(oled);
}

// the margin around the screen: the Mac's proportions (ui-plan.md 1.8): 4.30 percent of the screen's width at each side, 7.29 percent of its height above and
// below, measured on a render whose screen is all white: walk from the screen's edge to the first pixel that is not black
static void test_margin(void) {
    cairo_surface_t *white = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *d = (uint32_t *)cairo_image_surface_get_data(white);
    int ds = cairo_image_surface_get_stride(white) / 4;
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 128; x++) d[y * ds + x] = 0xffffff;
    cairo_surface_mark_dirty(white);
    skin_geom_t g;
    cairo_surface_t *s = render_at(W, H, white, &g);
    int cx = g.oled_x + g.oled_w / 2, cy = g.oled_y + g.oled_h / 2;
    int left = 0, right = 0, up = 0, down = 0;
    int x = g.oled_x;
    while (rawpix(s, x - 1 - left, cy) == 0) left++;
    x = g.oled_x + g.oled_w - 1;
    while (rawpix(s, x + 1 + right, cy) == 0) right++;
    int y = g.oled_y;
    while (rawpix(s, cx, y - 1 - up) == 0) up++;
    y = g.oled_y + g.oled_h - 1;
    while (rawpix(s, cx, y + 1 + down) == 0) down++;
    double fx = 100.0 * (left + right) / 2 / g.oled_w, fy = 100.0 * (up + down) / 2 / g.oled_h;
    CHECK(fabs(fx - 4.30) < 0.25, "margin at the sides is %.2f percent of the screen's width (left %d, right %d), want 4.30", fx, left, right);
    CHECK(fabs(fy - 7.29) < 0.35, "margin above and below is %.2f percent of the screen's height (%d, %d), want 7.29", fy, up, down);
    CHECK(g.oled_w == 512, "the screen is 512 wide at the design size");
    cairo_surface_destroy(s);
    cairo_surface_destroy(white);
}

// window scaling (option A): the screen scales with the window, proportions identical at every size; whole multiples crisp
static void test_scaling(void) {
    static const int pct[] = {50, 60, 75, 80, 100, 125, 130, 150, 160, 200};
    for (unsigned i = 0; i < sizeof pct / sizeof pct[0]; i++) {
        int w = W * pct[i] / 100, h = H * pct[i] / 100;
        skin_geom_t g;
        skin_geom(w, h, &g);
        double want_w = 512 * g.s;
        CHECK(fabs(g.oled_w - want_w) <= 1.0, "%d%%: the screen is %d px wide, the proportional width is %.1f", pct[i], g.oled_w, want_w);
        CHECK(abs(g.oled_w - 2 * g.oled_h) <= 1, "%d%%: the screen is %d x %d, not 2:1", pct[i], g.oled_w, g.oled_h);
        // centred in the bezel, with the same margin fractions
        double bcx = g.ox + (BEZEL_X + BEZEL_W / 2) * g.s, bcy = g.oy + (BEZEL_Y + BEZEL_H / 2) * g.s;
        CHECK(fabs(g.oled_x + g.oled_w / 2.0 - bcx) <= 1.0 && fabs(g.oled_y + g.oled_h / 2.0 - bcy) <= 1.0, "%d%%: the screen is off the bezel's centre", pct[i]);
        double mx = (BEZEL_W * g.s - g.oled_w) / 2 / g.oled_w, my = (BEZEL_H * g.s - g.oled_h) / 2 / g.oled_h;
        CHECK(fabs(mx - 0.0430) < 0.025 && my > 0.065 && my < 0.085, "%d%%: margins %.3f and %.3f of the screen", pct[i], mx, my);
    }
    // whole multiples of the screen scale: 3, 4, 5, 6, 8 device pixels per screen pixel, also at 75 percent where the window's rounding makes 4 s = 2.997
    struct { int w, h, px; } whole[] = {{744, 496, 3}, {992, 662, 4}, {1240, 828, 5}, {1488, 993, 6}, {1984, 1324, 8}};
    cairo_surface_t *oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *d = (uint32_t *)cairo_image_surface_get_data(oled);
    int ds = cairo_image_surface_get_stride(oled) / 4;
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 128; x++) d[y * ds + x] = (x & 1) ? 0xffffff : 0x000000;
    cairo_surface_mark_dirty(oled);
    for (unsigned i = 0; i < sizeof whole / sizeof whole[0]; i++) {
        skin_geom_t g;
        cairo_surface_t *s = render_at(whole[i].w, whole[i].h, oled, &g);
        CHECK(g.oled_w == 128 * whole[i].px, "%dx%d: the screen is %d wide, want %d (%d px per screen pixel)", whole[i].w, whole[i].h, g.oled_w, 128 * whole[i].px, whole[i].px);
        int bad = 0;
        for (int c = 0; c < 128; c++)
            for (int k = 0; k < whole[i].px; k++)
                if (rawpix(s, g.oled_x + whole[i].px * c + k, g.oled_y + 1) != ((c & 1) ? 0xffffffu : 0u)) bad++;
        CHECK(bad == 0, "%dx%d: %d device pixels of the screen are not in even blocks of %d", whole[i].w, whole[i].h, bad, whole[i].px);
        cairo_surface_destroy(s);
    }
    // in between (3.2 px at 80 percent): the screen's four edges are exactly on pixel boundaries, white inside and black just outside
    cairo_surface_t *white = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *wd = (uint32_t *)cairo_image_surface_get_data(white);
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 128; x++) wd[y * ds + x] = 0xffffff;
    cairo_surface_mark_dirty(white);
    int sizes[][2] = {{794, 530}, {595, 397}, {1290, 861}, {1587, 1059}};
    for (unsigned i = 0; i < 4; i++) {
        skin_geom_t g;
        cairo_surface_t *s = render_at(sizes[i][0], sizes[i][1], white, &g);
        int bad = 0;
        for (int t = 0; t < 8; t++) {
            int x = g.oled_x + (g.oled_w - 1) * t / 7, y = g.oled_y + (g.oled_h - 1) * t / 7;
            if (rawpix(s, x, g.oled_y) != 0xffffff || rawpix(s, x, g.oled_y + g.oled_h - 1) != 0xffffff) bad++;
            if (rawpix(s, g.oled_x, y) != 0xffffff || rawpix(s, g.oled_x + g.oled_w - 1, y) != 0xffffff) bad++;
            if (rawpix(s, x, g.oled_y - 1) != 0 || rawpix(s, x, g.oled_y + g.oled_h) != 0) bad++;
            if (rawpix(s, g.oled_x - 1, y) != 0 || rawpix(s, g.oled_x + g.oled_w, y) != 0) bad++;
        }
        CHECK(bad == 0, "%dx%d: the screen's edges are not sharp (%d samples wrong)", sizes[i][0], sizes[i][1], bad);
        cairo_surface_destroy(s);
    }
    // the mouse on the screen: every screen pixel 0..127 and 0..63 is reached, in order, with no gap and no doubling, at any size
    for (unsigned i = 0; i < 4; i++) {
        skin_geom_t g;
        skin_geom(sizes[i][0], sizes[i][1], &g);
        int last = -1, bad = 0, seen = 0;
        for (int dx = 0; dx < g.oled_w; dx++) {
            int ox, oy;
            if (!skin_oled_pixel(&g, g.oled_x + dx + 0.5, g.oled_y + 2, &ox, &oy)) { bad++; continue; }
            if (ox < last || ox > last + 1) bad++;
            if (ox != last) seen++;
            last = ox;
        }
        CHECK(bad == 0 && seen == 128 && last == 127, "%dx%d: mouse mapping on the screen: %d wrong, %d pixels reached, last %d", sizes[i][0], sizes[i][1], bad, seen, last);
        int ox, oy;
        CHECK(!skin_oled_pixel(&g, g.oled_x - 1, g.oled_y + 2, &ox, &oy) && !skin_oled_pixel(&g, g.oled_x + g.oled_w, g.oled_y + 2, &ox, &oy), "%dx%d: just outside the screen", sizes[i][0], sizes[i][1]);
    }
    // hit-testing follows the scale: every key, encoder and button centre at five sizes
    int hs[][2] = {{595, 397}, {794, 530}, {992, 662}, {1290, 861}, {1587, 1059}};
    for (unsigned i = 0; i < 5; i++) {
        skin_geom_t g;
        skin_geom(hs[i][0], hs[i][1], &g);
        int bad = 0;
        for (int k = 0; k < 3; k++) {
            if (skin_hit(&g, px(&g, KEY[k][0]), py(&g, KEY[k][1])) != SKIN_K1 + k) bad++;
            if (skin_hit(&g, px(&g, ENC[k][0]), py(&g, ENC[k][1])) != SKIN_E1 + k) bad++;
        }
        for (int b = 0; b < 11; b++)
            if (skin_hit(&g, px(&g, BTN_X[b] + 35), py(&g, BTN_Y + 20)) != SKIN_PAGE1 + b) bad++;
        if (skin_hit(&g, px(&g, 913), py(&g, 340)) != SKIN_NONE) bad++;
        CHECK(bad == 0, "%dx%d: %d hit tests wrong", hs[i][0], hs[i][1], bad);
    }
    cairo_surface_destroy(white);
    cairo_surface_destroy(oled);
}

// the keyboard mapping of the window is not touched: a checksum of every answer of window_keys_process
static void test_keys_unchanged(void) {
    uint32_t h = 2166136261u;
    for (int option = 0; option < 2; option++)
        for (int shift = 0; shift < 2; shift++)
            for (int usage = 0; usage < 256; usage++) {
                window_keys_t wk;
                window_keys_init(&wk);
                window_key_event_t ev = {0, 0, 0};
                int got = window_keys_process(&wk, usage, 1, 0, option, shift, &ev);
                uint32_t v = (uint32_t)(got ? (ev.kind * 1000 + ev.n * 10 + (ev.value & 7) + 1) : 0);
                h = (h ^ v) * 16777619u;
                if (got) {
                    window_keys_process(&wk, usage, 0, 0, option, shift, &ev);
                    h = (h ^ (uint32_t)(ev.kind * 100 + ev.n + 500)) * 16777619u;
                }
            }
    // recorded from window_keys.c before the layout change (the file is not edited by it)
    CHECK(h == WINDOW_KEYS_CHECKSUM, "window_keys_process answers changed: checksum %u", h);
}

int main(int argc, char **argv) {
    test_size_and_enum();
    test_hits();
    test_render(argc > 1 ? argv[1] : NULL);
    test_margin();
    test_scaling();
    test_keys_unchanged();
    printf(failures ? "device_skin_linux_test: %d failed\n" : "device_skin_linux_test: all passed\n", failures);
    return failures != 0;
}
