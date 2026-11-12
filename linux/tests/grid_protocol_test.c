/*
 * grid_protocol_test.c: the monome serial protocol between the real libmonome and fake grids, as the Windows build uses it: two pseudo terminals play the owner's grids (a 128 with a serial of the new family,
 * a 256 of 2011 with an "M<digits>" serial), a third has a serial that is no monome's, a fourth is a monome that never answers. the Windows reader loop (matron/src/platform/windows/grid/grid_reader.c) runs on
 * each. checked at the protocol level: the size the grid reports, the serial, the LED level map that reaches the device (16 levels), keys that come back as events, all-off, a port that is not a monome is never
 * written to, a monome that does not answer does not hang the open, a device that vanishes ends the reader.
 *
 * cc -std=gnu11 -Wall -I matron/src/platform/macos -I matron/src/platform/windows/grid -I/usr/local/include linux/tests/grid_protocol_test.c matron/src/platform/macos/vgrid_proto.c \
 *    matron/src/platform/windows/grid/grid_reader.c -L/usr/local/lib -lmonome -lpthread -o /tmp/gpt && LD_LIBRARY_PATH=/usr/local/lib /tmp/gpt
 */
#define _GNU_SOURCE
#include <monome.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>

#include "grid_handshake.h"
#include "grid_reader.h"
#include "vgrid_proto.h"

typedef struct {
    int master;
    vgrid_proto_t proto;
    pthread_mutex_t lock;
    volatile int stop, mute;       /* mute: reads and answers nothing (a monome that does not answer) */
    volatile unsigned long long bytes_in; /* bytes the host wrote */
    pthread_t th;
    char link[200];
} fake_t;

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static void *device(void *arg) {
    fake_t *f = arg;
    uint8_t in[256], reply[256];
    while (!f->stop) {
        struct pollfd pfd = {f->master, POLLIN, 0};
        if (poll(&pfd, 1, 20) <= 0) continue;
        ssize_t n = read(f->master, in, sizeof in);
        if (n <= 0) continue;
        f->bytes_in += (unsigned long long)n;
        if (f->mute) continue;
        int changed = 0;
        pthread_mutex_lock(&f->lock);
        size_t r = vgrid_proto_feed(&f->proto, in, (size_t)n, reply, sizeof reply, &changed);
        pthread_mutex_unlock(&f->lock);
        if (r > 0 && write(f->master, reply, r) < 0) perror("reply");
    }
    return NULL;
}

static int fake_open(fake_t *f, const char *dir, const char *link_name, const char *id, int cols, int rows) {
    memset(f, 0, sizeof *f);
    pthread_mutex_init(&f->lock, NULL);
    f->master = posix_openpt(O_RDWR | O_NOCTTY);
    if (f->master < 0 || grantpt(f->master) || unlockpt(f->master)) return -1;
    snprintf(f->link, sizeof f->link, "%s/%s", dir, link_name);
    if (symlink(ptsname(f->master), f->link) != 0) return -1;
    vgrid_proto_init(&f->proto, id, cols, rows);
    pthread_create(&f->th, NULL, device, f);
    return 0;
}
static void fake_close(fake_t *f) {
    f->stop = 1;
    pthread_join(f->th, NULL);
    close(f->master);
    unlink(f->link);
}

static volatile int keys_down, keys_up, last_x, last_y;
static void on_down(const monome_event_t *e, void *p) { (void)p; keys_down++; last_x = e->grid.x; last_y = e->grid.y; }
static void on_up(const monome_event_t *e, void *p) { (void)p; keys_up++; (void)e; }

typedef struct { monome_t *m; volatile int stop; int rc; } reader_t;
static void *reader(void *arg) { reader_t *r = arg; r->rc = vgrid_read_loop(r->m, &r->stop); return NULL; }

static long pty_write(void *ctx, const uint8_t *d, size_t n) { return write(*(int *)ctx, d, n); }
static long pty_read(void *ctx, uint8_t *d, size_t n, int ms) {
    int fd = *(int *)ctx;
    struct pollfd pfd = {fd, POLLIN, 0};
    int r = poll(&pfd, 1, ms);
    if (r <= 0) return r;
    return read(fd, d, n);
}

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec / 1e9; }

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    char dir[] = "/tmp/gptXXXXXX";
    if (!mkdtemp(dir)) return 2;
    fake_t g128, g256, plain, mute;
    if (fake_open(&g128, dir, "grid-m1234567", "monome 128", 16, 8) || fake_open(&g256, dir, "grid-M0000163", "monome 256", 16, 16) ||
        fake_open(&plain, dir, "grid-A9B8C7", "not a monome", 16, 8) || fake_open(&mute, dir, "grid-m7654321", "silent", 16, 8)) { perror("pty"); return 2; }

    /* the handshake that comes before libmonome: the host side of a pty is the slave. open the slave here as the Windows probe opens the COM port */
    {
        int fa = open(g128.link, O_RDWR | O_NOCTTY), fm = open(mute.link, O_RDWR | O_NOCTTY);
        struct termios t;
        tcgetattr(fa, &t); cfmakeraw(&t); tcsetattr(fa, TCSANOW, &t);
        tcgetattr(fm, &t); cfmakeraw(&t); tcsetattr(fm, TCSANOW, &t);
        vgrid_io ia = {&fa, pty_write, pty_read}, im = {&fm, pty_write, pty_read};
        mute.mute = 1;
        double t0 = now();
        CHECK(vgrid_handshake(&ia) == 1, "the handshake: a grid answers the system query");
        CHECK(vgrid_handshake(&im) == 0, "the handshake: a monome that does not answer is told so");
        CHECK(now() - t0 < 4.0, "and it does not take long (%.1f s)", now() - t0);
        mute.mute = 0;
        close(fa); close(fm);
    }
    monome_t *a = monome_open(g128.link), *b = monome_open(g256.link);
    CHECK(a && b, "both grids open");
    if (!a || !b) return 1;
    CHECK(monome_get_cols(a) == 16 && monome_get_rows(a) == 8, "the 128 reports 16 x 8 (%d x %d)", monome_get_cols(a), monome_get_rows(a));
    CHECK(monome_get_cols(b) == 16 && monome_get_rows(b) == 16, "the 256 reports 16 x 16 (%d x %d)", monome_get_cols(b), monome_get_rows(b));
    CHECK(monome_get_serial(a) && !strcmp(monome_get_serial(a), "m1234567"), "serial of the 128: %s", monome_get_serial(a));
    CHECK(monome_get_serial(b) && !strcmp(monome_get_serial(b), "M0000163"), "serial of the 256 (M and digits): %s", monome_get_serial(b));

    monome_register_handler(a, MONOME_BUTTON_DOWN, on_down, NULL);
    monome_register_handler(a, MONOME_BUTTON_UP, on_up, NULL);
    reader_t ra = {a, 0, 99}, rb = {b, 0, 99};
    pthread_t ta, tb;
    pthread_create(&ta, NULL, reader, &ra);
    pthread_create(&tb, NULL, reader, &rb);

    puts("# readers running");
    /* LEDs: 16 levels through the level map, both grids at once */
    uint8_t map[64];
    for (int i = 0; i < 64; i++) map[i] = (uint8_t)(i % 16);
    monome_led_level_map(a, 0, 0, map);
    monome_led_level_map(a, 8, 0, map);
    monome_led_level_map(b, 8, 8, map);
    usleep(300000);
    pthread_mutex_lock(&g128.lock);
    int ok128 = g128.proto.level[0][5] == 5 && g128.proto.level[7][7] == 15 && g128.proto.level[3][12] == (uint8_t)(((3 * 8) + 4) % 16);
    pthread_mutex_unlock(&g128.lock);
    CHECK(ok128, "the 128 got its 16 brightness levels (%d %d)", g128.proto.level[0][5], g128.proto.level[7][7]);
    pthread_mutex_lock(&g256.lock);
    CHECK(g256.proto.level[8][9] == 1 && g256.proto.level[15][15] == 15 && g256.proto.level[0][0] == 0, "the 256 got the quad at 8,8 (%d %d)", g256.proto.level[8][9], g256.proto.level[15][15]);
    pthread_mutex_unlock(&g256.lock);

    /* keys come back as events on the reader thread */
    uint8_t k[3];
    vgrid_proto_key(3, 2, 1, k);
    CHECK(write(g128.master, k, 3) == 3, "device write");
    vgrid_proto_key(3, 2, 0, k);
    usleep(50000);
    CHECK(write(g128.master, k, 3) == 3, "device write");
    usleep(300000);
    CHECK(keys_down == 1 && keys_up == 1 && last_x == 3 && last_y == 2, "a key press and release are events (down %d up %d at %d,%d)", keys_down, keys_up, last_x, last_y);

    /* all off, safe on both */
    monome_led_all(a, 0);
    monome_led_all(b, 0);
    monome_led_level_all(a, 0);
    monome_led_level_all(b, 0);
    usleep(200000);
    pthread_mutex_lock(&g128.lock);
    int sum = 0;
    for (int y = 0; y < 8; y++) for (int x = 0; x < 16; x++) sum += g128.proto.level[y][x];
    pthread_mutex_unlock(&g128.lock);
    CHECK(sum == 0, "all off: every LED of the 128 is dark (%d)", sum);

    /* the reader ends when asked, and when the device vanishes */
    ra.stop = 1;
    pthread_join(ta, NULL);
    CHECK(ra.rc == 0, "the reader of the 128 ended when asked (%d)", ra.rc);
    close(g256.master); /* unplugged */
    g256.master = -1;
    pthread_join(tb, NULL); /* ends by itself with an error, or on request below */
    CHECK(rb.rc == -1 || rb.rc == 0, "the reader of a vanished device ends (%d)", rb.rc);
    monome_close(a);
    monome_close(b);

    puts("# reader ends done");
    /* a port that is no monome: libmonome does not take it, and nothing was written to it */
    monome_t *x = monome_open(plain.link);
    CHECK(x == NULL, "a serial that is no monome's is not opened by libmonome");
    CHECK(plain.bytes_in == 0, "and not a byte was written to that port (%llu)", plain.bytes_in);
    if (x) monome_close(x);

    puts("# plain done");
    /* (a monome that does not answer is caught by the handshake above: libmonome itself waits for ever, so it is never opened) */
    fake_close(&g128); fake_close(&plain); fake_close(&mute);
    g256.stop = 1; pthread_join(g256.th, NULL); unlink(g256.link);
    printf(fails == 0 ? "grid_protocol: all checks pass\n" : "grid_protocol: %d failures\n", fails);
    return fails != 0;
}
