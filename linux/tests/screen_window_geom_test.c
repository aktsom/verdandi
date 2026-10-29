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

// the black margin round the picture, in the proportions of the box's bezel (the Mac's): 22 units at each side of a 512 unit wide screen (4.30 percent of the
// width), 18.667 units above and below a 256 unit high one (7.29 percent of the height): the frame (picture + margin) is 139/128 as wide and 55/48 as high as the picture
static int margin_ok(const sw_picture_t *p, int win_w, int win_h) {
    // at least the margin all round (a pixel of rounding), and no more than one extra pair of pixels would fit
    return p->x * 512 >= p->w * 22 - 512 && p->y * 768 >= p->h * 56 - 768 && (win_w - p->w - p->x) * 512 >= p->w * 22 - 512 &&
           (win_h - p->h - p->y) * 768 >= p->h * 56 - 768;
}

static void test_frame_size(void) {
    int w, h;
    sw_frame_size(4, &w, &h);
    CHECK(w == 556 && h == 294, "4 x: the box's bezel is 556 x 293.3 units: %d x %d", w, h);
    sw_frame_size(5, &w, &h);
    CHECK(w == 695 && h == 367, "5 x: %d x %d", w, h);
    sw_frame_size(8, &w, &h);
    CHECK(w == 1112 && h == 587, "8 x: %d x %d", w, h);
    sw_frame_size(1, &w, &h);
    CHECK(w == 139 && h == 74, "1 x: %d x %d", w, h);
}

static void test_whole_scales(void) {
    int ws[] = {1, 2, 3, 4, 5, 8, 10, 14, 15, 20, 30};
    for (unsigned i = 0; i < sizeof ws / sizeof *ws; i++) {
        int r = ws[i], fw, fh;
        sw_frame_size(r, &fw, &fh);
        sw_picture_t p;
        fit(fw, fh, &p);
        CHECK(p.scale == r && p.w == 128 * r && p.h == 64 * r, "%d x: the window of the picture plus its margin (%d x %d) is the whole scale: scale %d, %d x %d", r, fw, fh, p.scale, p.w, p.h);
        CHECK(margin_ok(&p, fw, fh) && p.x == (fw - 128 * r) / 2 && p.y == (fh - 64 * r) / 2, "%d x: centred with the margin (%d,%d)", r, p.x, p.y);
        // a hair bigger (up to 0.02 of a scale step): still the whole scale, centred, with a little more black
        fit(fw + 2, fh + 1, &p);
        CHECK(p.scale == r && p.w == 128 * r, "%d x: 2 x 1 pixels more: scale %d", r, p.scale);
        // visibly bigger: in between (nothing snaps by itself; the whole scales are the exact sizes)
        fit(fw + 20, fh + 10, &p);
        CHECK(p.scale == 0 && p.w > 128 * r, "%d x: 20 x 10 pixels more is in between (scale %d, %d wide)", r, p.scale, p.w);
        // one scale step below the window: the picture is the smaller whole scale only if that is what fits exactly; just under a whole size it is in between
        fit(fw - 3, fh - 2, &p);
        CHECK(p.scale != r && p.w <= 128 * r && margin_ok(&p, fw - 3, fh - 2), "%d x: a little under: scale %d, %d wide, margin kept", r, p.scale, p.w);
    }
}

static void test_in_between(void) {
    struct { int w, h; } sizes[] = {{1366, 768}, {1500, 800}, {1000, 700}, {700, 1000}, {3440, 1440}, {257, 129}, {300, 150}, {1921, 1080}, {1920, 1080}, {2560, 1440}, {3840, 2160}};
    for (unsigned i = 0; i < sizeof sizes / sizeof *sizes; i++) {
        sw_picture_t p;
        fit(sizes[i].w, sizes[i].h, &p);
        int inside = p.x >= 0 && p.y >= 0 && p.x + p.w <= sizes[i].w && p.y + p.h <= sizes[i].h;
        CHECK(inside && p.h * 2 == p.w && p.w % 2 == 0, "%d x %d: %d x %d at %d,%d (inside %d, 2:1)", sizes[i].w, sizes[i].h, p.w, p.h, p.x, p.y, inside);
        CHECK(margin_ok(&p, sizes[i].w, sizes[i].h), "%d x %d: the margin all round (%d,%d for a %d x %d picture)", sizes[i].w, sizes[i].h, p.x, p.y, p.w, p.h);
        // as large as possible: the next pair of pixels would not fit with its margin
        int nw = p.w + 2, nh = p.h + 1;
        int next_fits = nw * 139 <= sizes[i].w * 128 && nh * 55 <= sizes[i].h * 48;
        CHECK(!next_fits || p.scale != 0, "%d x %d: the picture %d x %d could be larger", sizes[i].w, sizes[i].h, p.w, p.h);
        // centred to within a pixel
        CHECK(p.x - (sizes[i].w - p.w - p.x) <= 1 && p.x - (sizes[i].w - p.w - p.x) >= -1, "%d x %d: horizontally centred", sizes[i].w, sizes[i].h);
        CHECK(p.y - (sizes[i].h - p.h - p.y) <= 1 && p.y - (sizes[i].h - p.h - p.y) >= -1, "%d x %d: vertically centred", sizes[i].w, sizes[i].h);
    }
    // the height limits: a wide window shows the picture, with its margin, as high as the window (a hair over 10 x)
    sw_picture_t p;
    fit(3000, 734, &p);
    CHECK(p.scale == 10 && p.h == 640 && p.x == (3000 - 1280) / 2 && p.y == (734 - 640) / 2, "wide window: scale %d, %d x %d at %d,%d", p.scale, p.w, p.h, p.x, p.y);
    // the common full screens are not whole multiples any more (the margin takes some of the width): in between, with the margin
    fit(1920, 1080, &p);
    CHECK(p.scale == 0 && p.w > 128 * 13 && p.w < 128 * 14, "1920 x 1080 fullscreen: scale %d, picture %d wide", p.scale, p.w);
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
    CHECK(w == 695 && h == 367, "a big display: 5 x with its margin (%d x %d)", w, h);
    sw_default_window(1280, 800, 28, &w, &h);
    CHECK(w == 695 && h == 367, "1280 x 800: 5 x (%d x %d)", w, h);
    sw_default_window(700, 400, 28, &w, &h);
    CHECK(w == 556 && h == 294, "700 x 400 usable: 4 x (%d x %d)", w, h);
    sw_default_window(500, 400, 28, &w, &h);
    CHECK(w == 417 && h == 220, "500 x 400 usable: 3 x (%d x %d)", w, h);
    sw_default_window(300, 200, 28, &w, &h);
    CHECK(w == 278 && h == 147, "a tiny display: 2 x (%d x %d)", w, h);
    sw_default_window(200, 150, 28, &w, &h);
    CHECK(w == 256 && h == 128, "a tinier one: the smallest window (%d x %d)", w, h);
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
    test_frame_size();
    test_whole_scales();
    test_in_between();
    test_contains();
    test_default_window();
    test_visible();
    printf(failures ? "screen_window_geom_test: %d failed\n" : "screen_window_geom_test: all passed\n", failures);
    return failures != 0;
}
