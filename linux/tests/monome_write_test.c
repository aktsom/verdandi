/*
 * monome_write_test.c: libmonome's write to a serial port that is slow to take the data. libmonome opens the device O_NONBLOCK; a write that
 * the port takes only in part (or not at all: EAGAIN) used to be dropped, cutting a message of the protocol in the middle, after which a real
 * grid reads the next message as the rest of that one (docs/port/KNOWN-ISSUES.md item 14, linux/patches/libmonome-write-retry.patch).
 *
 * a pseudo terminal plays the grid (the protocol side is the virtual grid's vgrid_proto.c). its reader is stopped for 300 ms while 300 LED maps
 * (35 bytes each, more than the port holds) are written, then it reads on. every map must arrive whole: the last two maps (both halves of
 * a 16x8 grid) are in the device's LED state, and no message is left half read.
 *
 * cc -std=gnu11 -Wall -I matron/src/platform/macos linux/tests/monome_write_test.c matron/src/platform/macos/vgrid_proto.c \
 *    -L/usr/local/lib -lmonome -lpthread -o /tmp/mwt && LD_LIBRARY_PATH=/usr/local/lib /tmp/mwt
 */
#define _GNU_SOURCE
#include <monome.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vgrid_proto.h"

static int master;
static vgrid_proto_t proto;
static volatile int stall = 0, stop = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static void *device(void *arg) {
    (void)arg;
    uint8_t in[256], reply[256];
    while (!stop) {
        if (stall) {
            usleep(1000);
            continue;
        }
        struct pollfd pfd = {master, POLLIN, 0};
        if (poll(&pfd, 1, 20) <= 0) {
            continue;
        }
        ssize_t n = read(master, in, sizeof in);
        if (n <= 0) {
            continue;
        }
        int changed = 0;
        pthread_mutex_lock(&lock);
        size_t r = vgrid_proto_feed(&proto, in, (size_t)n, reply, sizeof reply, &changed);
        pthread_mutex_unlock(&lock);
        if (r > 0 && write(master, reply, r) < 0) {
            perror("reply");
        }
    }
    return NULL;
}

static void *release(void *arg) {
    (void)arg;
    usleep(300 * 1000);
    stall = 0;
    return NULL;
}

int main(void) {
    char dir[] = "/tmp/mwtXXXXXX", link[128];
    int fails = 0;
    if (mkdtemp(dir) == NULL) {
        return 2;
    }
    master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) || unlockpt(master)) {
        perror("pty");
        return 2;
    }
    snprintf(link, sizeof link, "%s/grid-m1234567", dir);
    if (symlink(ptsname(master), link) != 0) {
        perror("symlink");
        return 2;
    }
    vgrid_proto_init(&proto, "write test grid", 16, 8);
    pthread_t dt;
    pthread_create(&dt, NULL, device, NULL);

    monome_t *m = monome_open(link);
    if (m == NULL) {
        printf("FAIL monome_open\n");
        return 1;
    }
    printf("rows=%d cols=%d\n", monome_get_rows(m), monome_get_cols(m));

    uint8_t map[64], last0[64], last8[64];
    stall = 1;
    pthread_t rt;
    pthread_create(&rt, NULL, release, NULL);
    for (int i = 0; i < 300; i++) {
        for (int k = 0; k < 64; k++) {
            map[k] = (uint8_t)((i + k) % 16);
        }
        monome_led_level_map(m, 0, 0, map);
        if (i == 299) {
            memcpy(last0, map, 64);
        }
        for (int k = 0; k < 64; k++) {
            map[k] = (uint8_t)((i + 3 * k + 1) % 16);
        }
        monome_led_level_map(m, 8, 0, map);
        if (i == 299) {
            memcpy(last8, map, 64);
        }
    }
    pthread_join(rt, NULL);
    usleep(500 * 1000); // the device reads what is left
    pthread_mutex_lock(&lock);
    int mismatch0 = 0, mismatch8 = 0;
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            mismatch0 += proto.level[y][x] != last0[y * 8 + x];
            mismatch8 += proto.level[y][x + 8] != last8[y * 8 + x];
        }
    }
    size_t have = proto.have;
    pthread_mutex_unlock(&lock);
    if (mismatch0 || mismatch8) {
        printf("FAIL the last maps are not in the device: %d + %d of 64 cells differ\n", mismatch0, mismatch8);
        fails++;
    } else {
        printf("ok   the last map of each half arrived whole after a stalled port\n");
    }
    if (have != 0) {
        printf("FAIL a message is left half read (%zu bytes)\n", have);
        fails++;
    } else {
        printf("ok   no message is left half read\n");
    }
    stop = 1;
    pthread_join(dt, NULL);
    monome_close(m);
    unlink(link);
    rmdir(dir);
    printf(fails ? "monome_write_test: %d failed\n" : "monome_write_test: all passed\n", fails);
    return fails != 0;
}
