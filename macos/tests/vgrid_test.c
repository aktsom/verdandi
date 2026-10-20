/*
 * vgrid_test.c: the virtual grid (platform/macos/vgrid_proto.c, vgrid_device.c), first
 * the protocol on its own, then end to end through the real libmonome, as matron uses it.
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
    vgrid_proto_init(&p, "virtual grid");

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

static int presses = 0, last_x = -1, last_y = -1;
static void on_press(const monome_event_t *e, void *data) {
    (void)data;
    presses++;
    last_x = (int)e->grid.x;
    last_y = (int)e->grid.y;
}

static int wait_level(vgrid_device_t *g, int x, int y, int want) {
    uint8_t lv[VGRID_ROWS][VGRID_COLS];
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

static void test_libmonome(void) {
    vgrid_device_t *g = vgrid_open("virtual grid", NULL, NULL);
    CHECK(g != NULL, "vgrid_open");
    if (g == NULL) {
        return;
    }
    monome_t *m = monome_open(vgrid_path(g));
    CHECK(m != NULL, "libmonome opens %s", vgrid_path(g));
    if (m != NULL) {
        CHECK(monome_get_cols(m) == 16 && monome_get_rows(m) == 8, "size %dx%d", monome_get_cols(m),
              monome_get_rows(m));
        CHECK(!strcmp(monome_get_friendly_name(m), "virtual grid"), "name %s", monome_get_friendly_name(m));

        // what matron does: level maps per quad, intensity
        uint8_t q[64] = {0};
        q[0] = 15;  // 8,0
        q[63] = 7;  // 15,7
        monome_led_level_map(m, 8, 0, q);
        CHECK(wait_level(g, 8, 0, 15) && wait_level(g, 15, 7, 7), "level map reaches the grid");
        monome_led_level_set(m, 2, 3, 11);
        CHECK(wait_level(g, 2, 3, 11), "level set reaches the grid");

        // a click comes back as a key press
        monome_register_handler(m, MONOME_BUTTON_DOWN, on_press, NULL);
        vgrid_key(g, 13, 4, 1);
        for (int i = 0; i < 100 && presses == 0; i++) {
            while (monome_event_handle_next(m) > 0) {
            }
            usleep(10000);
        }
        CHECK(presses == 1 && last_x == 13 && last_y == 4, "press %d at %d,%d", presses, last_x, last_y);
        monome_close(m);
    }
    char path[128];
    snprintf(path, sizeof path, "%s", vgrid_path(g));
    vgrid_close(g);
    CHECK(access(path, F_OK) != 0, "link removed on close");
}

int main(void) {
    test_proto();
    test_libmonome();
    printf("%s: %d failures\n", failures ? "FAILED" : "vgrid ok", failures);
    return failures != 0;
}
