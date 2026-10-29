/*
 * screen_window_geom_test.c: platform/linux/screen_window_geom.c (docs/port/detach-plan.md section 3.2) without a window.
 *
 * cc -std=gnu11 -I matron/src/platform/linux linux/tests/screen_window_geom_test.c matron/src/platform/linux/screen_window_geom.c -lm -o /tmp/swg && /tmp/swg
 *
 * the picture of the screen window: a whole multiple of 128 x 64 (drawn with nearest neighbour) when the window is that size or up to 0.02 of a scale step above it,
 * else the widest even width in between that fits (the enlargement-and-filter rule). always 2:1, always inside the window, centred.
 */

#include <stdio.h>

#include "screen_window_geom.h"

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

static void fit(int w, int h, sw_picture_t *p) {
    sw_picture_fit(w, h, p);
}

static void test_whole_scales(void) {
    int ws[] = {1, 2, 3, 4, 5, 8, 10, 15, 20, 30};
    for (unsigned i = 0; i < sizeof ws / sizeof *ws; i++) {
        int r = ws[i];
        sw_picture_t p;
        fit(128 * r, 64 * r, &p);
        CHECK(p.scale == r && p.w == 128 * r && p.h == 64 * r && p.x == 0 && p.y == 0, "%d x: exact window: scale %d, %d x %d at %d,%d", r, p.scale, p.w, p.h, p.x, p.y);
        // a window a hair bigger (up to 0.02 of a scale step): still the whole scale, centred, with black margins
        fit(128 * r + 2, 64 * r + 1, &p);
        CHECK(p.scale == r && p.w == 128 * r && p.x == 1 && p.y == 0, "%d x: 2 x 1 pixels more: scale %d at %d,%d", r, p.scale, p.x, p.y);
        // a visibly bigger one is in between (nothing snaps by itself; the whole scales are the exact sizes)
        fit(128 * r + 12, 64 * r + 6, &p);
        CHECK(p.scale == 0 && p.w > 128 * r, "%d x: 12 x 6 pixels more is in between (scale %d, %d wide)", r, p.scale, p.w);
    }
    // the whole scale up to 0.02 of a step above (the main window's tolerance, one direction so that nothing is ever cut off)
    sw_picture_t p;
    fit((int)(128 * 10.02), 64 * 20, &p);
    CHECK(p.scale == 10 && p.w == 1280, "10.02 x: still whole 10 (%d, scale %d)", p.w, p.scale);
    fit((int)(128 * 10.03), 64 * 20, &p);
    CHECK(p.scale == 0, "10.03 x: in between (scale %d)", p.scale);
    // just below a whole number: in between (the whole one would not fit), never wider than the window
    fit(1278, 700, &p);
    CHECK(p.scale == 0 && p.w <= 1278 && p.w % 2 == 0 && p.h == p.w / 2, "just under 10 x: %d x %d scale %d", p.w, p.h, p.scale);
}

static void test_in_between(void) {
    struct { int w, h; } sizes[] = {{1366, 768}, {1500, 800}, {1000, 700}, {700, 1000}, {3440, 1440}, {257, 129}, {300, 150}, {1921, 1080}};
    for (unsigned i = 0; i < sizeof sizes / sizeof *sizes; i++) {
        sw_picture_t p;
        fit(sizes[i].w, sizes[i].h, &p);
        int inside = p.x >= 0 && p.y >= 0 && p.x + p.w <= sizes[i].w && p.y + p.h <= sizes[i].h;
        CHECK(inside && p.h * 2 == p.w && p.w % 2 == 0, "%d x %d: %d x %d at %d,%d (inside %d, 2:1)", sizes[i].w, sizes[i].h, p.w, p.h, p.x, p.y, inside);
        // as large as possible: one more pair of pixels would not fit
        int more_w = p.w + 2, more_h = p.h + 1;
        CHECK(more_w > sizes[i].w || more_h > sizes[i].h || p.scale != 0, "%d x %d: the picture %d x %d could be larger", sizes[i].w, sizes[i].h, p.w, p.h);
        // centred to within a pixel
        CHECK(p.x - (sizes[i].w - p.w - p.x) <= 1 && p.x - (sizes[i].w - p.w - p.x) >= -1, "%d x %d: horizontally centred", sizes[i].w, sizes[i].h);
        CHECK(p.y - (sizes[i].h - p.h - p.y) <= 1 && p.y - (sizes[i].h - p.h - p.y) >= -1, "%d x %d: vertically centred", sizes[i].w, sizes[i].h);
    }
    // the height limits: a wide window shows the picture as high as the window
    sw_picture_t p;
    fit(3000, 640, &p);
    CHECK(p.scale == 10 && p.h == 640 && p.x == (3000 - 1280) / 2, "wide window: scale %d, %d x %d at %d,%d", p.scale, p.w, p.h, p.x, p.y);
    // a window smaller than the screen itself: scaled down, never empty
    fit(100, 50, &p);
    CHECK(p.w > 0 && p.h > 0 && p.scale == 0 && p.w <= 100 && p.h <= 50, "tiny window: %d x %d", p.w, p.h);
    fit(0, 0, &p);
    CHECK(p.w == 0 && p.h == 0, "no window: no picture");
}

static void test_contains(void) {
    sw_picture_t p;
    fit(1000, 700, &p);
    CHECK(sw_picture_contains(&p, p.x, p.y) && sw_picture_contains(&p, p.x + p.w - 1, p.y + p.h - 1), "corners are inside");
    CHECK(!sw_picture_contains(&p, p.x - 1, p.y) && !sw_picture_contains(&p, p.x, p.y + p.h), "just outside");
}

static void test_default_window(void) {
    int w, h;
    sw_default_window(1920, 1080, 28, &w, &h);
    CHECK(w == 640 && h == 320, "a big display: 5 x (%d x %d)", w, h);
    sw_default_window(1280, 800, 28, &w, &h);
    CHECK(w == 640 && h == 320, "1280 x 800: 5 x (%d x %d)", w, h);
    sw_default_window(700, 400, 28, &w, &h);
    CHECK(w == 640 && h == 320, "700 x 400 usable: still 5 x (%d x %d)", w, h);
    sw_default_window(600, 400, 28, &w, &h);
    CHECK(w == 512 && h == 256, "600 x 400 usable: 4 x (%d x %d)", w, h);
    sw_default_window(300, 200, 28, &w, &h);
    CHECK(w == 256 && h == 128, "a tiny display: never below 2 x (%d x %d)", w, h);
}

static void test_visible(void) {
    sw_rect_t d[2] = {{0, 0, 1920, 1080}, {1920, 0, 1280, 1024}};
    sw_rect_t on_first = {100, 100, 640, 320}, on_second = {2000, 50, 640, 320}, gone = {5000, 50, 640, 320};
    sw_rect_t edge = {1500, 900, 640, 320}, sliver = {1890, 1070, 640, 320};
    CHECK(sw_rect_visible(&on_first, d, 2), "on the first display");
    CHECK(sw_rect_visible(&on_second, d, 2), "on the second display");
    CHECK(!sw_rect_visible(&gone, d, 2), "on a display that is not there any more");
    CHECK(sw_rect_visible(&edge, d, 2), "partly off the first display but 64 x 64 shows on it");
    CHECK(!sw_rect_visible(&sliver, d, 1), "only a sliver shows: not visible");
    CHECK(!sw_rect_visible(&on_first, d, 0), "no displays: not visible");
}

int main(void) {
    test_whole_scales();
    test_in_between();
    test_contains();
    test_default_window();
    test_visible();
    printf(failures ? "screen_window_geom_test: %d failed\n" : "screen_window_geom_test: all passed\n", failures);
    return failures != 0;
}
