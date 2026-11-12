/* the size and place of the main window (matron/src/platform/windows/win_state.c): the file, a monitor that is gone, a size that is too small or too big, a save over a save.
 *   cc -std=gnu11 -Wall -I matron/src/platform/windows linux/tests/win_state_test.c matron/src/platform/windows/win_state.c -o /tmp/wst && /tmp/wst */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "win_state.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    char dir[] = "/tmp/wstXXXXXX", path[300];
    if (!mkdtemp(dir)) return 2;
    snprintf(path, sizeof path, "%s/main-window.conf", dir);
    ws_t s = {1, 120, 80, 1, 1100, 700}, back;
    CHECK(ws_save(path, &s) == 0, "save");
    s.w = 1400; s.h = 900; s.x = 200;
    CHECK(ws_save(path, &s) == 0, "a second save over the first");
    CHECK(ws_load(path, &back) && back.has_pos && back.x == 200 && back.y == 80 && back.w == 1400 && back.h == 900, "the last values come back: %d %d %d %d", back.x, back.y, back.w, back.h);
    char tmp[320]; snprintf(tmp, sizeof tmp, "%s.tmp", path);
    CHECK(access(tmp, F_OK) != 0, "no temporary file left");
    CHECK(!ws_load("/nonexistent/x.conf", &back), "no file: nothing");
    ws_parse("x=5\ny=abc\nw=0\nh=10\n", &back);
    CHECK(!back.has_pos && !back.has_size, "damaged values are not used");
    /* placement */
    ws_rect one[1] = {{0, 0, 1920, 1080}}, two[2] = {{0, 0, 1920, 1080}, {1920, 0, 2560, 1440}};
    ws_t saved = {1, 2500, 100, 1, 1200, 800}, out;
    CHECK(ws_place(&saved, two, 2, 400, 200, &out) && out.has_pos && out.x == 2500 && out.w == 1200, "on the second monitor: kept");
    CHECK(ws_place(&saved, one, 1, 400, 200, &out) && !out.has_pos && out.has_size && out.w == 1200, "the second monitor is gone: the size is kept, the place is not");
    saved.x = 1900; saved.y = 1060;
    CHECK(ws_place(&saved, one, 1, 400, 200, &out) && !out.has_pos, "a corner that is hardly on the screen is not used");
    saved.x = -20; saved.y = 10;
    CHECK(ws_place(&saved, one, 1, 400, 200, &out) && out.has_pos && out.x == -20, "a little over the edge is fine");
    saved.w = 100; saved.h = 50; saved.x = 10; saved.y = 10;
    CHECK(ws_place(&saved, one, 1, 400, 200, &out) && out.w == 400 && out.h == 200, "too small: the minimum");
    saved.w = 9000; saved.h = 9000;
    CHECK(ws_place(&saved, one, 1, 400, 200, &out) && out.w == 1920 && out.h == 1080, "too big: the biggest screen");
    ws_t none = {0};
    CHECK(!ws_place(&none, one, 1, 400, 200, &out), "nothing saved: nothing to do");
    printf(fails == 0 ? "win_state: all checks pass\n" : "win_state: %d failures\n", fails);
    return fails != 0;
}
