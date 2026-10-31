/*
 * extras_layout_test.c: where the virtual grid, arc and keys windows go round a norns window that STAYS WHERE IT IS (matron/src/platform/linux/extras_layout.c, docs/port/arc-plan.md is not involved:
 * this is the fix of "opening F6, F7 or F8 moves and resizes the norns window"). many norns windows (small, the default size, a long way from the screen's middle, on three screens) and one,
 * two or three device windows of many sizes: the scale is at most 1, every device window and its title bar is on the screen, none overlaps the norns window (title bar included) or another, the result
 * does not depend on anything but the arguments, and when there is really no room (the norns window fills the screen) the windows still come back on the screen at the smallest scale.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "extras_layout.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            if (fails < 30) {                                                                                          \
                printf("FAIL " __VA_ARGS__);                                                                           \
                printf("\n");                                                                                          \
            }                                                                                                          \
        }                                                                                                              \
    } while (0)

static int overlap(const xl_rect_t *a, int at, const xl_rect_t *b, int bt) {
    // content rectangles with a title bar of height at / bt above each
    return a->x < b->x + b->w && b->x < a->x + a->w && a->y - at < b->y + b->h && b->y - bt < a->y + a->h;
}

// the best a side can do, worked out here again (not by calling the code): the scale at which the windows fit beside, below or above the norns window, or 0 if there is no space
static double best_side(const xl_rect_t *u, const xl_rect_t *m, int t, int n, const int *uw, const int *uh) {
    double sw = 0, sh = 0, mw = 1, mh = 1;
    for (int i = 0; i < n; i++) {
        sw += uw[i]; sh += uh[i];
        mw = uw[i] > mw ? uw[i] : mw; mh = uh[i] > mh ? uh[i] : mh;
    }
    double row = (u->w - 16 - (n - 1) * 12) / sw, col = (u->h - 16 - n * t - (n - 1) * 12) / sh;
    double below = (u->y + u->h - 8 - (m->y + m->h + 12) - t) / mh, above = ((m->y - t - 12) - (u->y + 8) - t) / mh;
    double right = (u->x + u->w - 8 - (m->x + m->w + 12)) / mw, left = ((m->x - 12) - (u->x + 8)) / mw;
    double best = 0, c[4] = {fmin(row, below), fmin(row, above), fmin(col, right), fmin(col, left)};
    for (int i = 0; i < 4; i++) best = c[i] > best ? c[i] : best;
    return best;
}

int main(void) {
    int screens[3][2] = {{1280, 800}, {1920, 1080}, {1024, 768}};
    int mains[6][2] = {{976, 630}, {800, 516}, {640, 413}, {1100, 710}, {500, 322}, {976, 630}};
    int t = 28;
    long cases = 0;
    srand(7);
    for (int s = 0; s < 3; s++) {
        xl_rect_t usable = {0, 0, screens[s][0], screens[s][1]};
        for (int m = 0; m < 6; m++) {
            for (int trial = 0; trial < 60; trial++) {
                xl_rect_t main = {0, 0, mains[m][0], mains[m][1]};
                // anywhere the window can be with its title bar on the screen, most trials near the middle
                int maxx = usable.w - main.w > 0 ? usable.w - main.w : 0, maxy = usable.h - t - main.h > 0 ? usable.h - t - main.h : 0;
                main.x = trial == 0 ? maxx / 2 : rand() % (maxx + 1);
                main.y = t + (trial == 0 ? maxy / 2 : rand() % (maxy + 1));
                int n = 1 + rand() % 3;
                int uw[3], uh[3];
                for (int i = 0; i < 3; i++) {
                    uw[i] = 200 + rand() % 700;
                    uh[i] = 150 + rand() % 650;
                }
                xl_rect_t out[3], again[3];
                xl_rect_t keep = main;
                double k = extras_layout(&usable, &main, t, n, uw, uh, out);
                double k2 = extras_layout(&usable, &main, t, n, uw, uh, again);
                cases++;
                CHECK(main.x == keep.x && main.y == keep.y && main.w == keep.w && main.h == keep.h, "the norns window was changed");
                CHECK(k > 0 && k <= 1.0, "scale %.3f out of (0, 1] (screen %d, main %dx%d at %d,%d, n %d)", k, screens[s][0], main.w, main.h, main.x, main.y, n);
                CHECK(k == k2, "not deterministic");
                double side = best_side(&usable, &main, t, n, uw, uh);
                int room = side >= 0.6;
                if (room) {
                    CHECK(k >= 0.6 || k >= (side > 1 ? 1 : side) - 0.011, "a side with room (%.2f) but the scale is only %.3f", side, k);
                }
                for (int i = 0; i < n; i++) {
                    CHECK(out[i].x == again[i].x && out[i].y == again[i].y && out[i].w == again[i].w && out[i].h == again[i].h, "window %d not deterministic", i);
                    CHECK(out[i].w >= 1 && out[i].h >= 1, "window %d has no size", i);
                    CHECK(out[i].w <= (int)(uw[i] * k + 1) && out[i].h <= (int)(uh[i] * k + 1), "window %d is larger than its scale", i);
                    CHECK(out[i].x >= usable.x && out[i].x + out[i].w <= usable.x + usable.w, "window %d is off the screen sideways (%d..%d of %d)", i, out[i].x, out[i].x + out[i].w, usable.w);
                    CHECK(out[i].y - t >= usable.y && out[i].y + out[i].h <= usable.y + usable.h, "window %d is off the screen vertically (title %d..%d of %d)", i, out[i].y - t, out[i].y + out[i].h, usable.h);
                    if (!room) {
                        // no useful side: one row at the bottom of the screen, as large as the screen allows, over the norns window
                        CHECK(out[i].y + out[i].h == usable.y + usable.h - 8, "no room: window %d is not at the bottom (%d of %d)", i, out[i].y + out[i].h, usable.h);
                    }
                    if (room) {
                        CHECK(!overlap(&out[i], t, &main, t), "window %d overlaps the norns window (screen %d, main %dx%d at %d,%d)", i, screens[s][0], main.w, main.h, main.x, main.y);
                    }
                    for (int j = i + 1; j < n; j++) {
                        if (room) {
                            CHECK(!overlap(&out[i], t, &out[j], t), "windows %d and %d overlap", i, j);
                        }
                    }
                }
            }
        }
    }
    // the common case, written out: the default norns window in the middle of a 1280 x 800 screen, one grid of 400 x 300 units: below it or beside it, full size, norns unchanged
    {
        xl_rect_t usable = {0, 0, 1920, 1080}, main = {472, 200, 976, 630}, out[1];
        int uw[1] = {400}, uh[1] = {300};
        double k = extras_layout(&usable, &main, 28, 1, uw, uh, out);
        CHECK(k == 1.0, "a roomy screen: full size (got %.3f)", k);
        CHECK(out[0].w == 400 && out[0].h == 300, "a roomy screen: 400 x 300 (got %dx%d)", out[0].w, out[0].h);
    }
    // no room at all: the norns window is the screen
    {
        xl_rect_t usable = {0, 0, 1280, 800}, main = {0, 28, 1280, 772}, out[3];
        int uw[3] = {400, 400, 400}, uh[3] = {300, 300, 300};
        double k = extras_layout(&usable, &main, 28, 3, uw, uh, out);
        CHECK(k > 0 && k <= 1, "no room: still a scale (%.3f)", k);
        for (int i = 0; i < 3; i++) {
            CHECK(out[i].x >= 0 && out[i].x + out[i].w <= 1280 && out[i].y - 28 >= 0 && out[i].y + out[i].h <= 800, "no room: window %d is on the screen", i);
        }
    }
    // a second display or a screen that does not start at 0,0
    {
        xl_rect_t usable = {1920, 30, 1280, 770}, main = {2100, 120, 800, 516}, out[2];
        int uw[2] = {500, 350}, uh[2] = {200, 400};
        double k = extras_layout(&usable, &main, 28, 2, uw, uh, out);
        CHECK(k > 0 && k <= 1, "offset screen: scale");
        for (int i = 0; i < 2; i++) {
            CHECK(out[i].x >= usable.x && out[i].x + out[i].w <= usable.x + usable.w && out[i].y - 28 >= usable.y && out[i].y + out[i].h <= usable.y + usable.h, "offset screen: window %d on the screen", i);
        }
    }
    if (fails == 0) {
        printf("extras_layout: %ld cases: the norns window is never touched; the device windows fit the screen, clear of it and of each other\n", cases);
    }
    return fails == 0 ? 0 : 1;
}
