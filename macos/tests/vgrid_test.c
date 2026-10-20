/*
 * vgrid_test.c: the virtual grid and arc (platform/macos/vgrid_proto.c, vgrid_device.c),
 * first the protocol on its own, then end to end through the real libmonome, as matron
 * uses it.
 *
 * P=<deps>/prefix; cc -std=c11 -Wall -Wextra -I matron/src/platform/macos -I $P/include \
 *    macos/tests/vgrid_test.c matron/src/platform/macos/vgrid_proto.c \
 *    matron/src/platform/macos/vgrid_device.c -L $P/lib -lmonome -o /tmp/vgt && \
 *    DYLD_LIBRARY_PATH=$P/lib /tmp/vgt
 */

#include <monome.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "vgrid_device.h"
#include "vgrid_proto.h"

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

static void test_proto(void) {
    vgrid_proto_t p;
    uint8_t reply[128];
    int changed;
    vgrid_proto_init(&p, "virtual grid", 16, 8);

    // handshake: query, id, size; split across feeds
    uint8_t hs[] = {0x00, 0x01, 0x05};
    size_t n = vgrid_proto_feed(&p, hs, 2, reply, sizeof reply, &changed);
    n += vgrid_proto_feed(&p, hs + 2, 1, reply + n, sizeof reply - n, &changed);
    CHECK(n == 3 + 33 + 3, "handshake reply %zu bytes", n);
    CHECK(reply[0] == 0x00 && reply[3] == 0x01 && !strcmp((char *)reply + 4, "virtual grid"), "query/id reply");
    CHECK(reply[36] == 0x03 && reply[37] == 16 && reply[38] == 8, "size reply %d %d", reply[37], reply[38]);

    // level set, then a level map of the right quad arriving in two pieces
    uint8_t set[] = {0x18, 3, 2, 9};
    vgrid_proto_feed(&p, set, sizeof set, reply, sizeof reply, &changed);
    CHECK(changed && p.level[2][3] == 9, "level set");
    uint8_t map[35] = {0x1A, 8, 0};
    for (int i = 0; i < 32; i++) {
        map[3 + i] = (uint8_t)((i % 16) << 4 | 15);
    }
    vgrid_proto_feed(&p, map, 10, reply, sizeof reply, &changed);
    CHECK(!changed, "half a message changes nothing");
    vgrid_proto_feed(&p, map + 10, sizeof map - 10, reply, sizeof reply, &changed);
    CHECK(changed && p.level[0][8] == 0 && p.level[0][9] == 15 && p.level[1][10] == 5, "level map %d %d %d",
          p.level[0][8], p.level[0][9], p.level[1][10]);

    // bit-wise commands and intensity
    uint8_t all_on[] = {0x13}, off[] = {0x10, 0, 0}, row[] = {0x15, 0, 7, 0x81}, inten[] = {0x17, 4};
    vgrid_proto_feed(&p, all_on, 1, reply, sizeof reply, &changed);
    CHECK(p.level[7][15] == 15, "all on");
    vgrid_proto_feed(&p, off, 3, reply, sizeof reply, &changed);
    CHECK(p.level[0][0] == 0, "off");
    vgrid_proto_feed(&p, row, 4, reply, sizeof reply, &changed);
    CHECK(p.level[7][0] == 15 && p.level[7][1] == 0 && p.level[7][7] == 15, "row");
    vgrid_proto_feed(&p, inten, 2, reply, sizeof reply, &changed);
    CHECK(p.intensity == 4, "intensity");
    // out of range is ignored
    uint8_t far[] = {0x18, 40, 40, 15};
    vgrid_proto_feed(&p, far, 4, reply, sizeof reply, &changed);
    CHECK(!changed, "out of range");

    uint8_t k[3];
    vgrid_proto_key(5, 6, 1, k);
    CHECK(k[0] == 0x21 && k[1] == 5 && k[2] == 6, "key down message");
    vgrid_proto_key(5, 6, 0, k);
    CHECK(k[0] == 0x20, "key up message");
}

static void test_proto_arc(void) {
    vgrid_proto_t p;
    uint8_t reply[128];
    int changed;
    vgrid_proto_init_arc(&p, "virtual arc", 4);
    // handshake: 4 encoders, no grid size (that is how libmonome knows an arc)
    uint8_t hs[] = {0x00, 0x01, 0x05};
    size_t n = vgrid_proto_feed(&p, hs, sizeof hs, reply, sizeof reply, &changed);
    CHECK(n == 3 + 33 + 3, "arc handshake reply %zu bytes", n);
    CHECK(reply[0] == 0x00 && reply[1] == 0x05 && reply[2] == 4, "arc query reply %d %d", reply[1], reply[2]);
    CHECK(reply[36] == 0x03 && reply[37] == 0 && reply[38] == 0, "arc size reply");

    uint8_t set[] = {0x90, 2, 63, 9};
    vgrid_proto_feed(&p, set, sizeof set, reply, sizeof reply, &changed);
    CHECK(changed && p.ring[2][63] == 9, "ring set");
    uint8_t all[] = {0x91, 1, 5};
    vgrid_proto_feed(&p, all, sizeof all, reply, sizeof reply, &changed);
    CHECK(p.ring[1][0] == 5 && p.ring[1][63] == 5 && p.ring[0][0] == 0, "ring all");
    // range wraps clockwise past led 0
    uint8_t range[] = {0x93, 3, 60, 2, 12};
    vgrid_proto_feed(&p, range, sizeof range, reply, sizeof reply, &changed);
    CHECK(p.ring[3][60] == 12 && p.ring[3][63] == 12 && p.ring[3][0] == 12 && p.ring[3][2] == 12 &&
              p.ring[3][3] == 0 && p.ring[3][59] == 0,
          "ring range wraps");
    uint8_t map[34] = {0x92, 0};
    for (int i = 0; i < 32; i++) {
        map[2 + i] = (uint8_t)(15 << 4 | (i % 16));
    }
    vgrid_proto_feed(&p, map, 20, reply, sizeof reply, &changed);
    CHECK(!changed, "half a ring map changes nothing");
    vgrid_proto_feed(&p, map + 20, sizeof map - 20, reply, sizeof reply, &changed);
    CHECK(changed && p.ring[0][0] == 15 && p.ring[0][1] == 0 && p.ring[0][3] == 1, "ring map %d %d %d", p.ring[0][0],
          p.ring[0][1], p.ring[0][3]);
    uint8_t inten[] = {0x94, 7, 0};
    vgrid_proto_feed(&p, inten, sizeof inten, reply, sizeof reply, &changed);
    CHECK(p.intensity == 7, "ring intensity");
    // grid commands mean nothing to an arc
    uint8_t grid_set[] = {0x18, 1, 1, 15};
    vgrid_proto_feed(&p, grid_set, sizeof grid_set, reply, sizeof reply, &changed);
    CHECK(!changed, "grid led on an arc");
    uint8_t far[] = {0x90, 7, 0, 15};
    vgrid_proto_feed(&p, far, sizeof far, reply, sizeof reply, &changed);
    CHECK(!changed, "ring out of range");

    uint8_t m[3];
    vgrid_proto_enc(1, -3, m);
    CHECK(m[0] == 0x50 && m[1] == 1 && (int8_t)m[2] == -3, "encoder delta message");
    vgrid_proto_enc(0, 500, m);
    CHECK((int8_t)m[2] == 127, "encoder delta clamped");
    uint8_t k[2];
    vgrid_proto_enc_key(2, 1, k);
    CHECK(k[0] == 0x52 && k[1] == 2, "encoder key down");
    vgrid_proto_enc_key(2, 0, k);
    CHECK(k[0] == 0x51, "encoder key up");
}

static int presses = 0, last_x = -1, last_y = -1;
static void on_press(const monome_event_t *e, void *data) {
    (void)data;
    presses++;
    last_x = (int)e->grid.x;
    last_y = (int)e->grid.y;
}

static int wait_level(vgrid_device_t *g, int x, int y, int want) {
    uint8_t lv[VGRID_MAX][VGRID_MAX];
    int in;
    for (int i = 0; i < 100; i++) {
        vgrid_levels(g, lv, &in);
        if (lv[y][x] == want) {
            return 1;
        }
        usleep(10000);
    }
    return 0;
}

static void test_libmonome(int cols, int rows) {
    vgrid_device_t *g = vgrid_open("virtual grid", cols, rows, NULL, NULL);
    CHECK(g != NULL, "vgrid_open");
    if (g == NULL) {
        return;
    }
    presses = 0;
    monome_t *m = monome_open(vgrid_path(g));
    CHECK(m != NULL, "libmonome opens %s", vgrid_path(g));
    if (m != NULL) {
        CHECK(monome_get_cols(m) == cols && monome_get_rows(m) == rows, "size %dx%d, want %dx%d",
              monome_get_cols(m), monome_get_rows(m), cols, rows);
        CHECK(!strcmp(monome_get_friendly_name(m), "virtual grid"), "name %s", monome_get_friendly_name(m));

        // what matron does: level maps per quad, intensity. the last quad of this size:
        uint8_t q[64] = {0};
        q[0] = 15;
        q[63] = 7;
        monome_led_level_map(m, cols - 8, rows - 8, q);
        CHECK(wait_level(g, cols - 8, rows - 8, 15) && wait_level(g, cols - 1, rows - 1, 7),
              "%dx%d: level map reaches the grid", cols, rows);
        monome_led_level_set(m, 2, 3, 11);
        CHECK(wait_level(g, 2, 3, 11), "level set reaches the grid");

        // a click comes back as a key press
        monome_register_handler(m, MONOME_BUTTON_DOWN, on_press, NULL);
        vgrid_key(g, cols - 3, rows - 4, 1);
        for (int i = 0; i < 100 && presses == 0; i++) {
            while (monome_event_handle_next(m) > 0) {
            }
            usleep(10000);
        }
        CHECK(presses == 1 && last_x == cols - 3 && last_y == rows - 4, "press %d at %d,%d", presses, last_x, last_y);
        monome_close(m);
    }
    char path[128];
    snprintf(path, sizeof path, "%s", vgrid_path(g));
    vgrid_close(g);
    CHECK(access(path, F_OK) != 0, "link removed on close");
}

static int enc_sum = 0, enc_n = -1, enc_keys = 0;
static void on_delta(const monome_event_t *e, void *data) {
    (void)data;
    enc_sum += e->encoder.delta;
    enc_n = (int)e->encoder.number;
}
static void on_enc_key(const monome_event_t *e, void *data) {
    (void)data;
    (void)e;
    enc_keys++;
}

static int wait_ring(vgrid_device_t *g, int n, int x, int want) {
    uint8_t r[VARC_RINGS][VARC_LEDS];
    int in;
    for (int i = 0; i < 100; i++) {
        vgrid_rings(g, r, &in);
        if (r[n][x] == want) {
            return 1;
        }
        usleep(10000);
    }
    return 0;
}

static void test_libmonome_arc(void) {
    // the name the bridge gives it: lua/core/startup.lua takes "monome arc..." for an arc
    vgrid_device_t *g = vgrid_open_arc("monome arc virtual", 4, NULL, NULL);
    CHECK(g != NULL, "vgrid_open_arc");
    if (g == NULL) {
        return;
    }
    CHECK(strstr(vgrid_path(g), "/arc-m") != NULL, "arc path %s", vgrid_path(g));
    monome_t *m = monome_open(vgrid_path(g));
    CHECK(m != NULL, "libmonome opens %s", vgrid_path(g));
    if (m != NULL) {
        // matron: rows == cols == 0 is an arc (device_monome.cc)
        CHECK(monome_get_cols(m) == 0 && monome_get_rows(m) == 0, "arc size %dx%d", monome_get_cols(m),
              monome_get_rows(m));
        CHECK(!strncmp(monome_get_friendly_name(m), "monome arc", 10), "name %s", monome_get_friendly_name(m));
        // what matron does for arc:led / arc:segment: a ring map per ring
        uint8_t lv[64] = {0};
        lv[0] = 15;
        lv[33] = 6;
        monome_led_ring_map(m, 3, lv);
        CHECK(wait_ring(g, 3, 0, 15) && wait_ring(g, 3, 33, 6), "ring map reaches the arc");
        monome_led_ring_set(m, 1, 10, 9);
        CHECK(wait_ring(g, 1, 10, 9), "ring set reaches the arc");
        monome_led_ring_range(m, 2, 62, 1, 4);
        CHECK(wait_ring(g, 2, 63, 4) && wait_ring(g, 2, 1, 4), "ring range reaches the arc");

        // a turn larger than one message comes back whole
        monome_register_handler(m, MONOME_ENCODER_DELTA, on_delta, NULL);
        monome_register_handler(m, MONOME_ENCODER_KEY_DOWN, on_enc_key, NULL);
        monome_register_handler(m, MONOME_ENCODER_KEY_UP, on_enc_key, NULL);
        vgrid_enc(g, 2, 300);
        vgrid_enc(g, 2, -5);
        vgrid_enc_key(g, 2, 1);
        vgrid_enc_key(g, 2, 0);
        for (int i = 0; i < 100 && (enc_sum != 295 || enc_keys < 2); i++) {
            while (monome_event_handle_next(m) > 0) {
            }
            usleep(10000);
        }
        CHECK(enc_sum == 295 && enc_n == 2, "turns sum %d on ring %d", enc_sum, enc_n);
        CHECK(enc_keys == 2, "push down and up: %d", enc_keys);
        monome_close(m);
    }
    char path[128];
    snprintf(path, sizeof path, "%s", vgrid_path(g));
    vgrid_close(g);
    CHECK(access(path, F_OK) != 0, "arc link removed on close");
}

int main(void) {
    test_proto();
    test_proto_arc();
    test_libmonome_arc();
    test_libmonome(8, 8);
    test_libmonome(16, 8);
    test_libmonome(16, 16);
    printf("%s: %d failures\n", failures ? "FAILED" : "vgrid ok", failures);
    return failures != 0;
}
