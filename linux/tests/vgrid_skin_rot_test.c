/*
 * vgrid_skin_rot_test.c (M41, docs/port/phase-m41.md): the drawing and the hit test of the virtual grid window with the device turned, and the proof that the Mac picture is the old one.
 * built twice by run_all.sh: with -DNORNS_LINUX_DESKTOP (ROTATE and the pending outline are there) and without (what the macOS build compiles: nothing new may show).
 *
 *   cc -std=gnu11 -Wall -Wextra [-DNORNS_LINUX_DESKTOP -DEXPECT_ROTATE] -I matron/src/platform/macos $(pkg-config --cflags cairo) linux/tests/vgrid_skin_rot_test.c \
 *      matron/src/platform/macos/vgrid_skin.c -lm $(pkg-config --libs cairo) -o /tmp/vsr && /tmp/vsr
 */
#include <cairo.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "vgrid_skin.h"
#if defined(EXPECT_ROTATE) && !defined(VGRID_ROTATE)
#error "the Linux desktop build has no ROTATE (VGRID_ROTATE is not defined by vgrid_skin.h)"
#endif
#ifdef VGRID_ROTATE
#include "../linux/vgrid_view.h"
#endif

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

// the drawing's own numbers (vgrid_skin.c)
#define PITCH 44.0
#define KEY 31.0
#define EDGE 26.5
#define MARGIN 18.0

// the plate before M41 (the rows above the bar, FNV-1a of the pixels at one pixel per unit), made with the old vgrid_skin.c
static const unsigned long long golden[4] = {0, 0xf66ad4c6374ad6acULL, 0xf22304715880915cULL, 0xb2d4e5b62044728dULL};

typedef struct {
    cairo_surface_t *sf;
    int w, h;
    vgrid_geom_t g;
} img_t;

static void render(img_t *im, int size, int rot, const uint8_t level[VGRID_MAX][VGRID_MAX], const uint8_t held[VGRID_MAX][VGRID_MAX]) {
    int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1];
#ifdef VGRID_ROTATE
    vgrid_skin_units_rot(cols, rows, rot, &im->w, &im->h);
#else
    (void)rot;
    vgrid_skin_units(cols, rows, &im->w, &im->h);
#endif
    im->sf = cairo_image_surface_create(CAIRO_FORMAT_RGB24, im->w, im->h);
    cairo_t *cr = cairo_create(im->sf);
#ifdef VGRID_ROTATE
    vgrid_skin_geom_rot(im->w, im->h, cols, rows, rot, &im->g);
#else
    vgrid_skin_geom(im->w, im->h, cols, rows, &im->g);
#endif
    vgrid_skin_draw(cr, &im->g, im->w, im->h, level, 15, held, size);
    cairo_destroy(cr);
    cairo_surface_flush(im->sf);
}

#ifdef VGRID_ROTATE
static void px(const img_t *im, double x, double y, int *r, int *g, int *b) {
    unsigned char *d = cairo_image_surface_get_data(im->sf);
    int st = cairo_image_surface_get_stride(im->sf);
    unsigned v = *(unsigned *)(d + (int)y * st + (int)x * 4);
    *r = (v >> 16) & 255;
    *g = (v >> 8) & 255;
    *b = v & 255;
}

#endif

static unsigned long long plate_hash(const img_t *im) {
    unsigned char *d = cairo_image_surface_get_data(im->sf);
    int st = cairo_image_surface_get_stride(im->sf);
    unsigned long long h = 1469598103934665603ULL;
    for (int y = 0; y < im->h - 62; y++) {
        for (int x = 0; x < im->w * 4; x++) {
            h ^= d[y * st + x];
            h *= 1099511628211ULL;
        }
    }
    return h;
}

static void test_old_picture(void) {
    for (int size = 1; size <= 3; size++) {
        uint8_t level[VGRID_MAX][VGRID_MAX] = {{0}}, held[VGRID_MAX][VGRID_MAX] = {{0}};
        level[0][1] = 15;
        level[2][3] = 8;
        held[1][1] = VGRID_HELD_MOUSE;
        held[3][4] = VGRID_HELD_LATCH;
        img_t im;
        render(&im, size, 0, level, held);
        CHECK(plate_hash(&im) == golden[size], "size %d: the plate is the picture it was before M41 (hash %016llx, wanted %016llx)", size, plate_hash(&im), golden[size]);
        cairo_surface_destroy(im.sf);
    }
}

#ifdef VGRID_ROTATE
// the centre of the drawn key (sc, sr) in image pixels at one pixel per unit
static void key_centre(int sc, int sr, double *x, double *y) {
    *x = MARGIN + EDGE + sc * PITCH + KEY / 2;
    *y = MARGIN + EDGE + sr * PITCH + KEY / 2;
}

static void test_geometry(void) {
    for (int size = 1; size <= 3; size++) {
        int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1];
        int u0w, u0h, u1w, u1h;
        vgrid_skin_units_rot(cols, rows, 0, &u0w, &u0h);
        vgrid_skin_units_rot(cols, rows, 1, &u1w, &u1h);
        int tw, th;
        vgrid_skin_units(rows, cols, &tw, &th);
        CHECK(u1w == tw && u1h == th, "%dx%d: turned 90 the window has the units of the %dx%d plate (%dx%d, wanted %dx%d)", cols, rows, rows, cols, u1w, u1h, tw, th);
        int u2w, u2h, u3w, u3h;
        vgrid_skin_units_rot(cols, rows, 2, &u2w, &u2h);
        vgrid_skin_units_rot(cols, rows, 3, &u3w, &u3h);
        CHECK(u2w == u0w && u2h == u0h && u3w == u1w && u3h == u1h, "%dx%d: 180 is the shape of 0 and 270 the shape of 90", cols, rows);
        for (int rot = 0; rot < 4; rot++) {
            int w, h;
            vgrid_skin_units_rot(cols, rows, rot, &w, &h);
            vgrid_geom_t g;
            vgrid_skin_geom_rot(w, h, cols, rows, rot, &g);
            CHECK(g.s > 0.999 && g.s < 1.001 && g.rot == rot, "%dx%d rot %d: scale 1", cols, rows, rot);
            int bad = 0;
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    int sc, sr;
                    vgv_to_screen(rot, cols, rows, c, r, &sc, &sr);
                    double x, y;
                    key_centre(sc, sr, &x, &y);
                    int hc = -1, hr = -1;
                    if (!vgrid_skin_hit(&g, x, y, &hc, &hr) || hc != c || hr != r) {
                        bad++;
                    }
                    // anywhere in its cell (the corners of the cell, as the hit test says)
                    int hc2 = -1, hr2 = -1;
                    if (!vgrid_skin_hit(&g, x - KEY / 2 + 1, y - KEY / 2 + 1, &hc2, &hr2) || hc2 != c || hr2 != r) {
                        bad++;
                    }
                }
            }
            CHECK(bad == 0, "%dx%d rot %d: %d keys are not found under their drawn place", cols, rows, rot, bad);
            int hc, hr;
            CHECK(!vgrid_skin_hit(&g, 2, 2, &hc, &hr), "%dx%d rot %d: the corner of the window is no key", cols, rows, rot);
            // the buttons: 1 2 3 4 from left to right, 4 is ROTATE
            double by = MARGIN + (EDGE * 2 + (g.srows - 1) * PITCH + KEY) + 25 + 4 + 13; // the middle of the button row
            int order[5] = {0}, last = 0, seq_ok = 1;
            for (int x = 0; x < w; x++) {
                int b = vgrid_skin_hit_size(&g, x, by);
                if (b != 0 && b != last) {
                    if (b != last + 1) {
                        seq_ok = 0;
                    }
                    last = b;
                }
                if (b >= 0 && b <= 4) {
                    order[b]++;
                }
            }
            CHECK(seq_ok && last == 4 && order[4] > 40, "%dx%d rot %d: four buttons from left to right, the fourth is ROTATE (%d wide)", cols, rows, rot, order[4]);
            CHECK(vgrid_skin_hit_size(&g, w / 2.0, 5) == 0, "%dx%d rot %d: no button on the plate", cols, rows, rot);
        }
    }
}

static void test_drawing(void) {
    for (int size = 1; size <= 3; size++) {
        int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1];
        for (int rot = 0; rot < 4; rot++) {
            int keys[3][2] = {{1, 0}, {cols - 1, rows - 1}, {cols / 2, rows / 2}};
            for (int k = 0; k < 3; k++) {
                int c = keys[k][0], r = keys[k][1];
                uint8_t level[VGRID_MAX][VGRID_MAX] = {{0}}, held[VGRID_MAX][VGRID_MAX] = {{0}};
                level[r][c] = 15;
                img_t im;
                render(&im, size, rot, level, held);
                int sc, sr;
                vgv_to_screen(rot, cols, rows, c, r, &sc, &sr);
                double x, y;
                key_centre(sc, sr, &x, &y);
                int R, G, B;
                px(&im, x, y, &R, &G, &B);
                CHECK(R > 235 && B < 200 && R - B > 60, "%dx%d rot %d: the lit key (%d,%d) is lit where the turned plate has it (%d,%d): rgb %d %d %d", cols, rows, rot, c, r, sc, sr, R, G, B);
                // the place it would have without the turn is not lit (unless it is the same place)
                if (rot != 0) {
                    int oc = c, or_ = r;
                    if (oc != sc || or_ != sr) {
                        if (oc < im.g.scols && or_ < im.g.srows) {
                            double x0, y0;
                            key_centre(oc, or_, &x0, &y0);
                            px(&im, x0, y0, &R, &G, &B);
                            CHECK(R - B < 60, "%dx%d rot %d: the unturned place of key (%d,%d) is not lit: rgb %d %d %d", cols, rows, rot, c, r, R, G, B);
                        }
                    }
                }
                cairo_surface_destroy(im.sf);
            }
            // the white outline of a pending key, and not of the others; the latch outline is still orange
            uint8_t level[VGRID_MAX][VGRID_MAX] = {{0}}, held[VGRID_MAX][VGRID_MAX] = {{0}};
            int pc = 0, pr = rows - 1, lc = cols - 1, lr = 0;
            held[pr][pc] = VGRID_HELD_PENDING;
            held[lr][lc] = VGRID_HELD_LATCH;
            img_t im;
            render(&im, size, rot, level, held);
            int sc, sr, R, G, B;
            vgv_to_screen(rot, cols, rows, pc, pr, &sc, &sr);
            double x = MARGIN + EDGE + sc * PITCH - 3.5, y = MARGIN + EDGE + sr * PITCH + KEY / 2;
            px(&im, x, y, &R, &G, &B);
            CHECK(R > 245 && G > 245 && B > 245, "%dx%d rot %d: a pending key has a white outline at its drawn place: rgb %d %d %d", cols, rows, rot, R, G, B);
            vgv_to_screen(rot, cols, rows, lc, lr, &sc, &sr);
            x = MARGIN + EDGE + sc * PITCH - 3.5;
            y = MARGIN + EDGE + sr * PITCH + KEY / 2;
            px(&im, x, y, &R, &G, &B);
            CHECK(R > 200 && B < 120, "%dx%d rot %d: a latched key keeps its orange outline: rgb %d %d %d", cols, rows, rot, R, G, B);
            cairo_surface_destroy(im.sf);
        }
    }
}
#else
static void test_mac(void) {
    // the Mac build: three buttons, no rotate, nothing new in the window
    for (int size = 1; size <= 3; size++) {
        int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1], w, h;
        vgrid_skin_units(cols, rows, &w, &h);
        vgrid_geom_t g;
        vgrid_skin_geom(w, h, cols, rows, &g);
        int seen[8] = {0};
        for (int x = 0; x < w; x++) {
            for (int y = 0; y < h; y++) {
                int b = vgrid_skin_hit_size(&g, x, y);
                if (b >= 0 && b < 8) seen[b]++;
            }
        }
        CHECK(seen[1] > 0 && seen[2] > 0 && seen[3] > 0 && seen[4] == 0, "size %d: three size buttons and no fourth", size);
    }
}
#endif

int main(void) {
    test_old_picture();
#ifdef VGRID_ROTATE
    test_geometry();
    test_drawing();
#else
    test_mac();
#endif
    if (fails) {
        printf("vgrid_skin_rot_test: %d failed\n", fails);
        return 1;
    }
    printf("vgrid_skin_rot_test: all passed (%s)\n",
#ifdef VGRID_ROTATE
           "Linux desktop build"
#else
           "the build the Mac compiles"
#endif
    );
    return 0;
}
