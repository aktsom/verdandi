/*
 * device_skin_linux_test.c: the Linux window layout (arrangement A of docs/port/ui-plan.md section 1.6): geometry, hit testing and the rendered window of
 * platform/macos/device_skin.c built with -DNORNS_LINUX_DESKTOP. the Mac layout is tested by macos/tests/device_skin_test.c (built without the define).
 *
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos $(pkg-config --cflags cairo) linux/tests/device_skin_linux_test.c \
 *      matron/src/platform/macos/device_skin.c matron/src/platform/macos/window_keys.c -o /tmp/dsl $(pkg-config --libs cairo) -lm && /tmp/dsl [out.png]
 *
 * the window is 992 x 662 pixels (960 x 630 units and a margin of 16), one unit a pixel. positions in units; a window pixel is a unit plus 16.
 */
#include <math.h>
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
static const double KEY[3][2] = {{71.65, 193.0}, {639.65, 522.15}, {779.65, 522.15}};
static const double ENC[3][2] = {{194.70, 193.0}, {729.35, 381.85}, {869.35, 381.85}};
static const double KEY_R = 35.65, ENC_R = 43.7;
static const double BTN_X[11] = {36, 112, 188, 264, 359.3333, 435.3333, 511.3333, 587.3333, 682.6667, 758.6667, 854};
static const double BTN_Y = 36, BTN_W = 70, BTN_H = 40;
static const double BEZEL_X = 36, BEZEL_Y = 310, BEZEL_W = 540, BEZEL_H = 284;

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
    CHECK(g.oled_x == 66 && g.oled_y == 340, "screen at %d,%d (units 50,324: the bezel's 36,310 and its 14 of frame; the window's margin of 16 added)", g.oled_x, g.oled_y);
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
    CHECK(hit(&g, 1, 1) == SKIN_NONE, "the corner");
    // the nearest encoder for a wheel anywhere
    CHECK(skin_nearest_enc(&g, px(&g, 100), py(&g, 400)) == 1, "wheel at the left turns E1");
    CHECK(skin_nearest_enc(&g, px(&g, 700), py(&g, 300)) == 2, "wheel at the right, left half, turns E2");
    CHECK(skin_nearest_enc(&g, px(&g, 900), py(&g, 300)) == 3, "wheel at the right turns E3");
    // the screen's pixel under a point (the mouse on the MIX page)
    int ox = -1, oy = -1;
    CHECK(skin_oled_pixel(&g, g.oled_x, g.oled_y, &ox, &oy) && ox == 0 && oy == 0, "screen pixel 0,0");
    CHECK(skin_oled_pixel(&g, g.oled_x + 511, g.oled_y + 255, &ox, &oy) && ox == 127 && oy == 63, "screen pixel 127,63");
    CHECK(!skin_oled_pixel(&g, g.oled_x + 512, g.oled_y + 100, &ox, &oy), "just right of the screen");
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
    CHECK(min_lum(s, 918, 195, 940, 500) > 150, "something dark where the OUT slider was (darkest %d)", min_lum(s, 918, 195, 940, 500));
    CHECK(min_lum(s, 880, 515, 945, 560) > 150, "something dark where the old MUTE was (darkest %d)", min_lum(s, 880, 515, 945, 560));
    // the OUT label's place
    CHECK(min_lum(s, 900, 168, 925, 182) > 150, "the OUT text is still there (darkest %d)", min_lum(s, 900, 168, 925, 182));
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
    test_keys_unchanged();
    printf(failures ? "device_skin_linux_test: %d failed\n" : "device_skin_linux_test: all passed\n", failures);
    return failures != 0;
}
