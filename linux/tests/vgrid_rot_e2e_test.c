/*
 * vgrid_rot_e2e_test.c (M41, docs/port/phase-m41.md): the virtual grid through the real libmonome, as matron uses it, with the window's turn and multi-press on top:
 *   1. for every size (64, 128, 256), every rotation a script can ask libmonome for (grid:rotation) and every turn of the window (ROTATE): a script's LED (x, y) lights a device key; the window draws
 *      that key where the turned plate has it; a click there finds that device key; its press reaches the script as (x, y). LEDs, hit test and key presses agree at all 16 combinations
 *   2. the quad writes of matron (device_monome.cc: level maps with the quad offsets, swapped for the second quad of a 16 x 8 when it is turned) light the key a single LED write lights, for every
 *      rotation, also on the 16 x 16 (the quad offsets of the 256 had not been tested)
 *   3. the multi-press through the device: the burst of key-downs arrives in the collected order, the held keys let go in order, nothing arrives when the pending set is thrown away
 *
 *   cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I matron/src/platform/macos -I matron/src/platform/linux -I/usr/local/include $(pkg-config --cflags cairo) linux/tests/vgrid_rot_e2e_test.c \
 *      matron/src/platform/macos/vgrid_device.c matron/src/platform/macos/vgrid_proto.c matron/src/platform/macos/vgrid_skin.c -L/usr/local/lib -lmonome -lpthread -lutil -lm \
 *      $(pkg-config --libs cairo) -o /tmp/vre && LD_LIBRARY_PATH=/usr/local/lib /tmp/vre
 */
#define _GNU_SOURCE
#include <monome.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vgrid_device.h"
#include "vgrid_skin.h"
#include "vgrid_view.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

#define PITCH 44.0
#define KEY 31.0
#define EDGE 26.5
#define MARGIN 18.0

static void changed(void *ctx) { (void)ctx; }

typedef struct { int n; int x[512], y[512], z[512]; } events_t;
static events_t ev;
static void on_down(const monome_event_t *e, void *u) { (void)u; if (ev.n < 512) { ev.x[ev.n] = e->grid.x; ev.y[ev.n] = e->grid.y; ev.z[ev.n] = 1; ev.n++; } }
static void on_up(const monome_event_t *e, void *u) { (void)u; if (ev.n < 512) { ev.x[ev.n] = e->grid.x; ev.y[ev.n] = e->grid.y; ev.z[ev.n] = 0; ev.n++; } }

// events until `want` have come or the time (ms) is up
static void pump(monome_t *m, int want, int ms) {
    struct pollfd p = {monome_get_fd(m), POLLIN, 0};
    int waited = 0;
    while (ev.n < want && waited < ms) {
        if (poll(&p, 1, 5) > 0) {
            monome_event_handle_next(m);
        } else {
            waited += 5;
        }
    }
}

static int lit_key(vgrid_device_t *g, int *c, int *r, int *count) {
    uint8_t lv[VGRID_MAX][VGRID_MAX];
    int in;
    vgrid_levels(g, lv, &in);
    *count = 0;
    for (int y = 0; y < VGRID_MAX; y++) {
        for (int x = 0; x < VGRID_MAX; x++) {
            if (lv[y][x]) {
                *c = x;
                *r = y;
                (*count)++;
            }
        }
    }
    return *count;
}

static void wait_dark(vgrid_device_t *g) {
    int c, r, n;
    for (int t = 0; t < 1000; t++) {
        if (!lit_key(g, &c, &r, &n)) return;
        usleep(1000);
    }
}

// the one lit key, once the led has arrived
static int wait_one(vgrid_device_t *g, int *c, int *r) {
    int n;
    for (int t = 0; t < 1000; t++) {
        if (lit_key(g, c, r, &n) && n == 1) return 1;
        usleep(1000);
    }
    return 0;
}

static void test_agree(int size) {
    int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1];
    vgrid_device_t *g = vgrid_open("virtual grid", cols, rows, changed, NULL);
    monome_t *m = g ? monome_open(vgrid_path(g)) : NULL;
    CHECK(g && m, "%dx%d: the virtual grid opens through libmonome", cols, rows);
    if (!g || !m) return;
    monome_register_handler(m, MONOME_BUTTON_DOWN, on_down, NULL);
    monome_register_handler(m, MONOME_BUTTON_UP, on_up, NULL);
    for (int srot = 0; srot < 4; srot++) {
        monome_set_rotation(m, (monome_rotate_t)srot);
        int scols = monome_get_cols(m), srows = monome_get_rows(m);
        CHECK(((srot & 1) ? (scols == rows && srows == cols) : (scols == cols && srows == rows)), "%dx%d script rotation %d: the script sees %dx%d", cols, rows, srot, scols, srows);
        int bad_led = 0, bad_hit = 0, bad_key = 0;
        for (int y = 0; y < srows; y++) {
            for (int x = 0; x < scols; x++) {
                monome_led_all(m, 0);
                wait_dark(g);
                monome_led_level_set(m, x, y, 15);
                int dc = -1, dr = -1;
                if (!wait_one(g, &dc, &dr)) { bad_led++; continue; }
                // every turn of the window: drawn where the turned plate has it, found there by a click
                for (int view = 0; view < 4; view++) {
                    int w, h;
                    vgrid_skin_units_rot(cols, rows, view, &w, &h);
                    vgrid_geom_t geo;
                    vgrid_skin_geom_rot(w, h, cols, rows, view, &geo);
                    int sc, sr;
                    vgv_to_screen(view, cols, rows, dc, dr, &sc, &sr);
                    double px = MARGIN + EDGE + sc * PITCH + KEY / 2, py = MARGIN + EDGE + sr * PITCH + KEY / 2;
                    int hc = -1, hr = -1;
                    if (!vgrid_skin_hit(&geo, px, py, &hc, &hr) || hc != dc || hr != dr) bad_hit++;
                }
                // the click on that device key reaches the script at the place it lit
                ev.n = 0;
                vgrid_key(g, dc, dr, 1);
                pump(m, 1, 500);
                vgrid_key(g, dc, dr, 0);
                pump(m, 2, 500);
                if (ev.n != 2 || ev.x[0] != x || ev.y[0] != y || ev.z[0] != 1 || ev.z[1] != 0) bad_key++;
            }
        }
        CHECK(bad_led == 0, "%dx%d script rotation %d: %d leds never lit a single key", cols, rows, srot, bad_led);
        CHECK(bad_hit == 0, "%dx%d script rotation %d: %d keys are not found under their drawn place (any turn of the window)", cols, rows, srot, bad_hit);
        CHECK(bad_key == 0, "%dx%d script rotation %d: %d presses did not reach the script at the place its led was", cols, rows, srot, bad_key);
        printf("  %dx%d script rotation %d (script sees %dx%d): %d keys, 4 window turns each: led, hit and press agree\n", cols, rows, srot, scols, srows, scols * srows);
    }
    monome_close(m);
    vgrid_close(g);
}

// matron's quad writes (device_monome.cc: quad offsets {0,8,0,8} {0,0,8,8}; dev_monome_set_rotation swaps the second quad of a grid with two quads when it is turned 90 or 270)
static void test_quads(int size) {
    int cols = vgrid_sizes[size][0], rows = vgrid_sizes[size][1], quads = cols * rows / 64;
    vgrid_device_t *g = vgrid_open("virtual grid", cols, rows, changed, NULL);
    monome_t *m = g ? monome_open(vgrid_path(g)) : NULL;
    if (!g || !m) { CHECK(0, "%dx%d: quad test: cannot open", cols, rows); return; }
    for (int rot = 0; rot < 4; rot++) {
        monome_set_rotation(m, (monome_rotate_t)rot);
        int xoff[4] = {0, 8, 0, 8}, yoff[4] = {0, 0, 8, 8};
        if (quads == 2) {
            if (rot == 0 || rot == 2) { xoff[1] = 8; yoff[1] = 0; } else { xoff[1] = 0; yoff[1] = 8; }
        }
        int bad = 0, total = 0;
        for (int q = 0; q < quads; q++) {
            for (int qy = 0; qy < 8; qy++) {
                for (int qx = 0; qx < 8; qx++) {
                    monome_led_all(m, 0);
                    wait_dark(g);
                    monome_led_level_set(m, xoff[q] + qx, yoff[q] + qy, 15);
                    int ac = -1, ar = -1;
                    wait_one(g, &ac, &ar);
                    monome_led_all(m, 0);
                    wait_dark(g);
                    uint8_t data[64];
                    memset(data, 0, sizeof data);
                    data[qy * 8 + qx] = 15;
                    monome_led_level_map(m, xoff[q], yoff[q], data);
                    int bc = -1, br = -1;
                    wait_one(g, &bc, &br);
                    total++;
                    if (ac < 0 || ac != bc || ar != br) bad++;
                }
            }
        }
        CHECK(bad == 0, "%dx%d script rotation %d: %d of %d quad writes light another key than a single led write", cols, rows, rot, bad, total);
        printf("  %dx%d script rotation %d: %d quad writes (%d quads) light the key a single led write lights\n", cols, rows, rot, total, quads);
    }
    monome_close(m);
    vgrid_close(g);
}

// what the window does with the state machine's answers: key-down / key-up on the device
static void act(vgrid_device_t *g, const vgv_act_t *a, int n) {
    for (int i = 0; i < n; i++) vgrid_key(g, a[i].x, a[i].y, a[i].down);
}

static void test_multi(void) {
    vgrid_device_t *g = vgrid_open("virtual grid", 16, 8, changed, NULL);
    monome_t *m = g ? monome_open(vgrid_path(g)) : NULL;
    if (!g || !m) { CHECK(0, "multi: cannot open"); return; }
    monome_register_handler(m, MONOME_BUTTON_DOWN, on_down, NULL);
    monome_register_handler(m, MONOME_BUTTON_UP, on_up, NULL);
    vgv_t mp;
    vgv_act_t a[VGV_MAXACT];
    int consumed, n;
    vgv_reset(&mp);

    // collected with shift: the script hears nothing
    ev.n = 0;
    vgv_shift(&mp, 1, a);
    vgv_mouse_down(&mp, 2, 1, 1, a, &consumed); vgv_mouse_up(&mp, a);
    vgv_mouse_down(&mp, 9, 4, 1, a, &consumed); vgv_motion(&mp, 10, 4); vgv_motion(&mp, 11, 4); vgv_mouse_up(&mp, a);
    pump(m, 1, 300);
    CHECK(ev.n == 0, "multi: nothing reaches the script while shift is held (%d events)", ev.n);
    // shift let go: the burst, in order
    n = vgv_shift(&mp, 0, a);
    act(g, a, n);
    pump(m, 4, 1000);
    CHECK(ev.n == 4 && ev.z[0] == 1 && ev.z[1] == 1 && ev.z[2] == 1 && ev.z[3] == 1, "multi: four key-downs reach the script (%d)", ev.n);
    CHECK(ev.x[0] == 2 && ev.y[0] == 1 && ev.x[1] == 9 && ev.y[1] == 4 && ev.x[2] == 10 && ev.x[3] == 11, "multi: in the order they were collected");
    // held: nothing else happens
    pump(m, 5, 300);
    CHECK(ev.n == 4, "multi: the keys stay held, no key-up comes by itself (%d)", ev.n);
    // the next plain click lets all go, in order
    n = vgv_mouse_down(&mp, 0, 0, 0, a, &consumed);
    act(g, a, n);
    pump(m, 8, 1000);
    CHECK(ev.n == 8 && ev.z[4] == 0 && ev.z[5] == 0 && ev.z[6] == 0 && ev.z[7] == 0 && ev.x[4] == 2 && ev.x[7] == 11, "multi: four key-ups, in order (%d events)", ev.n);

    // pending and then the focus is lost: nothing is ever sent, nothing is stuck
    ev.n = 0;
    vgv_reset(&mp);
    vgv_shift(&mp, 1, a);
    vgv_mouse_down(&mp, 5, 5, 1, a, &consumed); vgv_mouse_up(&mp, a);
    vgv_focus_lost(&mp);
    n = vgv_shift(&mp, 0, a); // the shift key-up that went to another window
    act(g, a, n);
    pump(m, 1, 400);
    CHECK(n == 0 && ev.n == 0, "multi: focus lost with keys pending sends nothing (%d)", ev.n);

    // Esc with a held chord: key-ups
    ev.n = 0;
    vgv_reset(&mp);
    vgv_shift(&mp, 1, a);
    vgv_mouse_down(&mp, 7, 7, 1, a, &consumed); vgv_mouse_up(&mp, a);
    n = vgv_shift(&mp, 0, a);
    act(g, a, n);
    pump(m, 1, 500);
    int used;
    n = vgv_esc(&mp, a, &used);
    act(g, a, n);
    pump(m, 2, 500);
    CHECK(ev.n == 2 && ev.z[0] == 1 && ev.z[1] == 0 && ev.x[1] == 7 && ev.y[1] == 7, "multi: Esc lets the held key go (%d events)", ev.n);
    monome_close(m);
    vgrid_close(g);
}

int main(void) {
    for (int size = 1; size <= 3; size++) test_agree(size);
    test_quads(1);
    test_quads(2);
    test_quads(3);
    test_multi();
    if (fails) {
        printf("vgrid_rot_e2e_test: %d failed\n", fails);
        return 1;
    }
    printf("vgrid_rot_e2e_test: all passed\n");
    return 0;
}
