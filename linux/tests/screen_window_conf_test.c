/*
 * screen_window_conf_test.c: platform/linux/screen_window_conf.c (docs/port/detach-plan.md section 4): the state file of the screen window.
 *
 * cc -std=gnu11 -I matron/src/platform/linux linux/tests/screen_window_conf_test.c matron/src/platform/linux/screen_window_conf.c -o /tmp/swc && /tmp/swc
 *
 * defaults, every damaged value (that value only falls back, with a log line that names it), unknown keys, a round trip, an atomic write.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "screen_window_conf.h"

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

static char logged[16][256];
static int nlogged = 0;
static void keep(const char *line) {
    if (nlogged < 16) {
        snprintf(logged[nlogged++], sizeof logged[0], "%s", line);
    }
}
static int logs(const char *what) {
    for (int i = 0; i < nlogged; i++)
        if (strstr(logged[i], what) != NULL)
            return 1;
    return 0;
}
static void parse(const char *text, sw_conf_t *c) {
    nlogged = 0;
    sw_conf_parse(text, c, keep);
}

static void test_defaults(void) {
    sw_conf_t c;
    sw_conf_defaults(&c);
    CHECK(c.detached == 0 && c.fullscreen == 0 && c.border == 1 && c.has_pos == 0 && c.w == 0 && c.h == 0, "defaults: docked, windowed, framed, no place, default size");
    parse("", &c);
    CHECK(c.detached == 0 && c.border == 1 && nlogged == 0, "an empty file: the defaults, no log line (%d)", nlogged);
}

static void test_good(void) {
    sw_conf_t c;
    parse("detached=1\nx=1480\ny=-120\nw=1024\nh=512\nfullscreen=1\nborder=0\n", &c);
    CHECK(c.detached == 1 && c.has_pos && c.x == 1480 && c.y == -120 && c.w == 1024 && c.h == 512 && c.fullscreen == 1 && c.border == 0 && nlogged == 0, "a good file is read as written (%d log lines)", nlogged);
    parse("# a comment\n\n detached = on \nborder=OFF\nfullscreen=true\n", &c);
    CHECK(c.detached == 1 && c.border == 0 && c.fullscreen == 1, "on/off/true/false in any case, blanks around, comments and empty lines");
    parse("w=800\nw=900\n", &c);
    CHECK(c.w == 900, "a key twice: the last one wins");
}

static void test_damaged(void) {
    sw_conf_t c;
    parse("w=abc\nh=512\n", &c);
    CHECK(c.w == 0 && c.h == 512 && logs("w='abc'"), "w=abc: the default width, h is kept, a line names w");
    parse("w=64\nh=99999\n", &c);
    CHECK(c.w == 0 && c.h == 0 && logs("w='64'") && logs("h='99999'"), "sizes out of 128..16384: both default, both named");
    parse("x=12\n", &c);
    CHECK(c.has_pos == 0, "x without y: no place");
    parse("x=12\ny=zzz\n", &c);
    CHECK(c.has_pos == 0 && logs("y='zzz'"), "a bad y: no place, y named");
    parse("x=99999999\ny=5\n", &c);
    CHECK(c.has_pos == 0 && logs("x='99999999'"), "x out of range: no place");
    parse("detached=2\nfullscreen=maybe\nborder=\n", &c);
    CHECK(c.detached == 0 && c.fullscreen == 0 && c.border == 1 && logs("detached='2'") && logs("fullscreen='maybe'") && logs("border=''"), "bad flags: their defaults, each named");
    parse("colour=red\nnonsense\nw=700\n", &c);
    CHECK(c.w == 700 && logs("unknown key 'colour'") && logs("without '='"), "an unknown key and a line without '=' are ignored with a line each; the rest is read");
    parse("w=1e3\nh=12.5\n", &c);
    CHECK(c.w == 0 && c.h == 0, "no floats, no exponents");
    char big[4096];
    memset(big, 'x', sizeof big - 1);
    big[sizeof big - 1] = 0;
    parse(big, &c);
    CHECK(c.detached == 0 && c.border == 1, "a long line of rubbish does not break the parser");
}

static void test_roundtrip(void) {
    sw_conf_t a, b;
    sw_conf_defaults(&a);
    a.detached = 1;
    a.has_pos = 1;
    a.x = -300;
    a.y = 40;
    a.w = 1000;
    a.h = 500;
    a.fullscreen = 1;
    a.border = 0;
    char buf[512];
    CHECK(sw_conf_format(&a, buf, sizeof buf) > 0, "format");
    parse(buf, &b);
    CHECK(nlogged == 0 && b.detached == 1 && b.has_pos && b.x == -300 && b.y == 40 && b.w == 1000 && b.h == 500 && b.fullscreen == 1 && b.border == 0, "format then parse gives the same state, no log line");
    sw_conf_defaults(&a);
    sw_conf_format(&a, buf, sizeof buf);
    CHECK(strstr(buf, "x=") == NULL && strstr(buf, "w=") == NULL && strstr(buf, "detached=0") != NULL, "the defaults write no place and no size");
    CHECK(sw_conf_format(&a, buf, 8) < 0, "a buffer that is too small is an error, not a cut-off file");
}

static void test_files(void) {
    char dir[] = "/tmp/swc-XXXXXX";
    CHECK(mkdtemp(dir) != NULL, "temp dir");
    char path[512], tmp[540];
    snprintf(path, sizeof path, "%s/screen-window.conf", dir);
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    sw_conf_t c;
    nlogged = 0;
    CHECK(sw_conf_load(path, &c, keep) == 0 && c.detached == 0 && c.border == 1 && nlogged == 0, "no file: the defaults, nothing logged (the file is optional)");
    c.detached = 1;
    c.has_pos = 1;
    c.x = 10;
    c.y = 20;
    c.w = 640;
    c.h = 320;
    CHECK(sw_conf_save(path, &c) == 0, "save");
    CHECK(access(tmp, F_OK) != 0, "no temporary file is left behind (written, then renamed)");
    sw_conf_t d;
    nlogged = 0;
    CHECK(sw_conf_load(path, &d, keep) == 0 && d.detached == 1 && d.x == 10 && d.y == 20 && d.w == 640 && d.h == 320, "load gives back what was saved");
    FILE *f = fopen(path, "w");
    fputs("w=oops\nh=400\n", f);
    fclose(f);
    nlogged = 0;
    CHECK(sw_conf_load(path, &d, keep) == 0 && d.w == 0 && d.h == 400 && logs("w='oops'"), "a damaged file on disk: the value falls back, a line says so");
    CHECK(sw_conf_save("/nonexistent-folder/x.conf", &d) != 0, "an unwritable place is reported, not ignored");
    unlink(path);
    rmdir(dir);
}

int main(void) {
    test_defaults();
    test_good();
    test_damaged();
    test_roundtrip();
    test_files();
    printf(failures ? "screen_window_conf_test: %d failed\n" : "screen_window_conf_test: all passed\n", failures);
    return failures != 0;
}
