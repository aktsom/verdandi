/*
 * vgrid_view_test.c (M41, docs/port/phase-m41.md): the pure parts of the virtual grid window's ROTATE and shift multi-press (matron/src/platform/linux/vgrid_view.h): the mapping of the device
 * to the turned plate and back for every rotation and every size, the file that keeps the rotation (also a bad one), and the multi-press state machine as tables of events.
 *
 *   cc -std=gnu11 -Wall -Wextra -I matron/src/platform/linux linux/tests/vgrid_view_test.c -o /tmp/vgv && /tmp/vgv
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "vgrid_view.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static const int sizes[3][2] = {{8, 8}, {16, 8}, {16, 16}};

static void test_mapping(void) {
    for (int s = 0; s < 3; s++) {
        int cols = sizes[s][0], rows = sizes[s][1];
        for (int rot = 0; rot < 4; rot++) {
            int sc, sr;
            vgv_screen_dims(rot, cols, rows, &sc, &sr);
            CHECK(sc * sr == cols * rows, "%dx%d rot %d: the plate keeps its number of keys", cols, rows, rot);
            CHECK((rot & 1) ? (sc == rows && sr == cols) : (sc == cols && sr == rows), "%dx%d rot %d: the plate is %dx%d", cols, rows, rot, sc, sr);
            static uint8_t seen[VGV_MAX][VGV_MAX];
            memset(seen, 0, sizeof seen);
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    int a, b, c2, r2;
                    vgv_to_screen(rot, cols, rows, c, r, &a, &b);
                    CHECK(a >= 0 && a < sc && b >= 0 && b < sr, "%dx%d rot %d key (%d,%d) is on the plate", cols, rows, rot, c, r);
                    CHECK(!seen[b][a], "%dx%d rot %d: two keys on one place", cols, rows, rot);
                    seen[b][a] = 1;
                    vgv_to_device(rot, cols, rows, a, b, &c2, &r2);
                    CHECK(c2 == c && r2 == r, "%dx%d rot %d: key (%d,%d) -> (%d,%d) -> back (%d,%d)", cols, rows, rot, c, r, a, b, c2, r2);
                }
            }
            // clockwise: the top left key is where a turned plate has it
            int a, b;
            vgv_to_screen(rot, cols, rows, 0, 0, &a, &b);
            int wa[4] = {0, sc - 1, sc - 1, 0}, wb[4] = {0, 0, sr - 1, sr - 1};
            CHECK(a == wa[rot] && b == wb[rot], "%dx%d rot %d: the top left key is at (%d,%d), wanted (%d,%d) (clockwise)", cols, rows, rot, a, b, wa[rot], wb[rot]);
            // four turns are no turn
            int c3 = 5 % cols, r3 = 3 % rows, x = c3, y = r3, dc = cols, dr = rows;
            for (int i = 0; i < 4; i++) {
                int nx, ny;
                vgv_to_screen(1, dc, dr, x, y, &nx, &ny);
                int t = dc; dc = dr; dr = t;
                x = nx; y = ny;
            }
            CHECK(x == c3 && y == r3 && dc == cols && dr == rows, "%dx%d: four turns of 90 are no turn", cols, rows);
        }
    }
}

static void test_file(void) {
    CHECK(vgv_parse_rot("0") == 0 && vgv_parse_rot("1") == 1 && vgv_parse_rot("2") == 2 && vgv_parse_rot("3") == 3, "0 to 3 are read");
    CHECK(vgv_parse_rot("2\n") == 2 && vgv_parse_rot(" 3 \r\n") == 3 && vgv_parse_rot("1 ") == 1, "space and a newline after the number are fine");
    const char *bad[] = {"", "\n", "4", "-1", "90", "270", "abc", "2x", "1 2", "1.5", "0x1", "9999999999999999999", "++1", NULL};
    for (int i = 0; bad[i]; i++) {
        CHECK(vgv_parse_rot(bad[i]) == 0, "'%s' is a bad file: 0", bad[i]);
    }
    CHECK(vgv_parse_rot(NULL) == 0, "no text: 0");
    char path[256];
    snprintf(path, sizeof path, "/tmp/vgv-rot-%d", (int)getpid());
    remove(path);
    CHECK(vgv_load_rot(path) == 0, "a missing file is 0");
    for (int k = 0; k < 4; k++) {
        CHECK(vgv_save_rot(path, k) == 0, "saved %d", k);
        CHECK(vgv_load_rot(path) == k, "read back %d", k);
    }
    FILE *f = fopen(path, "w");
    fputs("garbage", f);
    fclose(f);
    CHECK(vgv_load_rot(path) == 0, "a file of garbage is 0");
    f = fopen(path, "w");
    for (int i = 0; i < 100; i++) fputs("2222222222", f);
    fclose(f);
    CHECK(vgv_load_rot(path) == 0, "a long file of digits is 0 (and does not overrun)");
    remove(path);
    CHECK(vgv_save_rot("/nonexistent-dir-vgv/x", 1) == -1, "a file that cannot be written says so (the choice then lasts until the program ends)");
    CHECK(vgv_load_rot("/nonexistent-dir-vgv/x") == 0, "a folder that is not there is 0");
}

static int count_down(const vgv_act_t *a, int n, int down) {
    int k = 0;
    for (int i = 0; i < n; i++) k += a[i].down == down;
    return k;
}
static int has(const vgv_act_t *a, int n, int x, int y, int down) {
    for (int i = 0; i < n; i++) if (a[i].x == x && a[i].y == y && a[i].down == down) return 1;
    return 0;
}

static void test_multi(void) {
    vgv_t m;
    vgv_act_t a[VGV_MAXACT];
    int n, consumed;

    // shift collects by click and drag, nothing is sent; shift let go sends the burst in the collected order
    vgv_reset(&m);
    n = vgv_shift(&m, 1, a);
    CHECK(n == 0, "shift down sends nothing");
    n = vgv_mouse_down(&m, 2, 3, 1, a, &consumed);
    CHECK(n == 0 && consumed == 1 && vgv_is_pending(&m, 2, 3), "a shift click collects the key and does not press it");
    n = vgv_mouse_up(&m, a);
    CHECK(n == 0, "the left button up sends nothing while shift is down");
    n = vgv_mouse_down(&m, 5, 1, 1, a, &consumed);
    CHECK(n == 0 && consumed && vgv_is_pending(&m, 5, 1), "a second key");
    CHECK(vgv_motion(&m, 6, 1) == 1 && vgv_motion(&m, 7, 1) == 1 && vgv_motion(&m, 7, 1) == 1, "a drag adds the keys it crosses (and a key twice once)");
    CHECK(vgv_is_pending(&m, 6, 1) && vgv_is_pending(&m, 7, 1) && m.n_order == 4, "four pending keys: %d", m.n_order);
    vgv_mouse_up(&m, a);
    n = vgv_shift(&m, 0, a);
    CHECK(n == 4 && count_down(a, n, 1) == 4, "shift up: one burst of four key-downs (%d)", n);
    CHECK(a[0].x == 2 && a[0].y == 3 && a[1].x == 5 && a[1].y == 1 && a[2].x == 6 && a[3].x == 7, "in the order they were collected");
    CHECK(m.n_order == 0 && m.n_chord == 4 && !vgv_is_pending(&m, 2, 3), "the pending set is empty, the four are the held chord");

    // the next plain click lets the chord go in one burst, in the same order, before its own press
    n = vgv_mouse_down(&m, 0, 0, 0, a, &consumed);
    CHECK(consumed == 0 && n == 4 && count_down(a, n, 0) == 4, "a plain click lets all four go (%d)", n);
    CHECK(a[0].x == 2 && a[3].x == 7 && m.n_chord == 0, "in order, the chord is empty");
    n = vgv_mouse_down(&m, 1, 1, 0, a, &consumed);
    CHECK(n == 0 && consumed == 0, "a second plain click has nothing to let go");

    // a shift click on a pending key takes it out again
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 1, 1, 1, a, &consumed); vgv_mouse_up(&m, a);
    vgv_mouse_down(&m, 1, 1, 1, a, &consumed); vgv_mouse_up(&m, a);
    CHECK(!vgv_is_pending(&m, 1, 1) && m.n_order == 0, "a second shift click on a pending key removes it");
    n = vgv_shift(&m, 0, a);
    CHECK(n == 0, "shift up with nothing pending sends nothing");

    // shift let go while the left button is still down: the burst waits for the button
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 3, 3, 1, a, &consumed);
    vgv_motion(&m, 4, 3);
    n = vgv_shift(&m, 0, a);
    CHECK(n == 0 && m.apply_wait, "shift up with the button down: wait");
    CHECK(vgv_motion(&m, 5, 3) == 1 && !vgv_is_pending(&m, 5, 3), "the rest of that drag adds nothing and presses nothing");
    n = vgv_mouse_up(&m, a);
    CHECK(n == 2 && has(a, n, 3, 3, 1) && has(a, n, 4, 3, 1), "the burst comes with the button up (%d)", n);

    // a shift key-up that never came: the next mouse event asks the modifier state and finds it
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 9, 9, 1, a, &consumed); vgv_mouse_up(&m, a);
    n = vgv_mouse_down(&m, 1, 2, 0, a, &consumed); // shift is not held any more
    CHECK(n == 2 && a[0].down == 1 && a[1].down == 0 && a[0].x == 9 && a[1].x == 9 && consumed == 0, "a plain click with shift gone: the pending key goes down (the shift-up it missed), then the click lets the chord go (%d)", n);

    // Esc: the chord lets go, the pending set is thrown away without sending
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 1, 1, 1, a, &consumed); vgv_mouse_up(&m, a);
    vgv_shift(&m, 0, a);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 2, 2, 1, a, &consumed); vgv_mouse_up(&m, a);
    int used = 0;
    n = vgv_esc(&m, a, &used);
    CHECK(used == 1 && n == 1 && has(a, n, 1, 1, 0) && count_down(a, n, 1) == 0, "Esc: the held key goes up, the pending key sends nothing");
    CHECK(m.n_order == 0 && m.n_chord == 0, "both are empty");
    n = vgv_esc(&m, a, &used);
    CHECK(used == 0 && n == 0, "Esc with nothing to do is not taken (it goes on)");

    // focus lost while shift is held: the pending set goes, nothing is sent; a chord stays like a latch
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 1, 1, 1, a, &consumed); vgv_mouse_up(&m, a);
    vgv_shift(&m, 0, a); // chord: (1,1)
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 4, 4, 1, a, &consumed);
    vgv_focus_lost(&m);
    CHECK(m.n_order == 0 && m.n_chord == 1 && !m.shift && !m.mouse, "focus lost: pending gone, chord stays, shift and mouse state reset");
    n = vgv_shift(&m, 0, a);
    CHECK(n == 0, "the shift key-up that goes to another window changes nothing here");
    n = vgv_mouse_up(&m, a);
    CHECK(n == 0, "and neither does the button up");

    // the rotation changes while keys are pending: they are thrown away, the chord stays
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 1, 1, 1, a, &consumed); vgv_mouse_up(&m, a);
    vgv_shift(&m, 0, a);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 6, 6, 1, a, &consumed); vgv_mouse_up(&m, a);
    vgv_rotation_changed(&m);
    CHECK(m.n_order == 0 && m.n_chord == 1, "a turn throws the pending set away and keeps the chord");
    n = vgv_shift(&m, 0, a);
    CHECK(n == 0, "nothing is sent when shift goes up after the turn");

    // the window closes or the size changes: everything goes, nothing is sent
    vgv_device_gone(&m);
    CHECK(m.n_order == 0 && m.n_chord == 0, "a replug forgets pending and held keys");

    // plain behaviour is not touched: no shift, no state, no action
    vgv_reset(&m);
    n = vgv_mouse_down(&m, 3, 3, 0, a, &consumed);
    CHECK(n == 0 && !consumed, "a plain click is not taken");
    CHECK(vgv_motion(&m, 4, 3) == 0, "a plain drag is not taken");
    n = vgv_mouse_up(&m, a);
    CHECK(n == 0, "a plain release does nothing");

    // the whole 256 grid pending: one burst of 256 and one of 256 (the buffer is enough)
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 0, 0, 1, a, &consumed);
    for (int r = 0; r < 16; r++) for (int c = 0; c < 16; c++) vgv_motion(&m, c, r);
    vgv_mouse_up(&m, a);
    n = vgv_shift(&m, 0, a);
    CHECK(n == 256, "256 keys in one burst (%d)", n);
    n = vgv_mouse_down(&m, 0, 0, 0, a, &consumed);
    CHECK(n == 256 && count_down(a, n, 0) == 256, "256 keys let go in one burst (%d)", n);
}


// M43: Ctrl stage and fire
static void test_chord(void) {
    vgv_t m;
    vgv_act_t a[VGV_MAXACT];
    int n, consumed;

    // Ctrl held: a click stages (nothing is sent), a second click on a staged key takes it out; Ctrl up fires everything staged in one batch of down = 2
    vgv_reset(&m);
    n = vgv_ctrl(&m, 1, a);
    CHECK(n == 0, "Ctrl down sends nothing");
    n = vgv_ctrl_click(&m, 1, 1, 1, a, &consumed);
    CHECK(n == 0 && consumed == 1 && vgv_is_staged(&m, 1, 1), "a Ctrl click stages the key and does not press it");
    vgv_ctrl_mouse_up(&m, a);
    vgv_ctrl_click(&m, 3, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_ctrl_click(&m, 5, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_ctrl_click(&m, 7, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_ctrl_click(&m, 5, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a); // out again
    CHECK(m.n_stage == 3 && !vgv_is_staged(&m, 5, 1), "a second click on a staged key takes it out (3 staged)");
    vgv_ctrl_click(&m, 9, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    CHECK(m.n_stage == 4, "four staged");
    n = vgv_ctrl(&m, 0, a);
    CHECK(n == 4 && count_down(a, n, 2) == 4, "Ctrl up: four key-downs of the chord (down = 2) in one call (%d)", n);
    CHECK(a[0].x == 1 && a[1].x == 3 && a[2].x == 7 && a[3].x == 9, "in the order they were staged");
    CHECK(m.n_stage == 0 && m.n_fire == 4, "nothing is staged any more, the chord waits for its release");
    n = vgv_fire_release(&m, a);
    CHECK(n == 4 && count_down(a, n, 3) == 4 && a[0].x == 1 && a[3].x == 9, "after the hold time: four key-ups (down = 3), in order");
    CHECK(m.n_fire == 0, "the chord is done");
    n = vgv_fire_release(&m, a);
    CHECK(n == 0, "a second release has nothing to do");

    // Ctrl up with nothing staged does nothing
    vgv_reset(&m);
    vgv_ctrl(&m, 1, a);
    n = vgv_ctrl(&m, 0, a);
    CHECK(n == 0, "Ctrl up with nothing staged sends nothing");

    // a Ctrl click when Ctrl is not held (the key-up was missed) is a plain click
    vgv_reset(&m);
    n = vgv_ctrl_click(&m, 2, 2, 0, a, &consumed);
    CHECK(n == 0 && consumed == 0 && m.n_stage == 0, "without Ctrl the click is not taken");

    // a drag with Ctrl and the left button stages the keys it crosses (a drag only adds)
    vgv_reset(&m);
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 0, 4, 1, a, &consumed);
    CHECK(vgv_ctrl_motion(&m, 1, 4) == 1 && vgv_ctrl_motion(&m, 2, 4) == 1 && vgv_ctrl_motion(&m, 2, 4) == 1, "a staging drag is taken");
    CHECK(m.n_stage == 3, "three staged by the drag (%d)", m.n_stage);
    n = vgv_ctrl(&m, 0, a); // Ctrl let go with the button still down: the chord waits for the button
    CHECK(n == 0 && m.n_stage == 3, "Ctrl up with the button down waits for the button");
    n = vgv_ctrl_mouse_up(&m, a);
    CHECK(n == 3 && count_down(a, n, 2) == 3, "the button up fires the chord (%d)", n);

    // Esc and focus lost throw the staged keys away and send nothing; a chord that is already fired is not touched
    vgv_reset(&m);
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 1, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_ctrl_click(&m, 2, 1, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    int used = 0;
    n = vgv_esc(&m, a, &used);
    CHECK(used == 1 && n == 0 && m.n_stage == 0, "Esc throws the staged keys away and sends nothing");
    n = vgv_ctrl(&m, 0, a);
    CHECK(n == 0, "and Ctrl up afterwards fires nothing");
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 4, 4, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_focus_lost(&m);
    CHECK(m.n_stage == 0 && !m.ctrl, "focus lost: staged keys gone, Ctrl state reset");
    n = vgv_ctrl(&m, 0, a);
    CHECK(n == 0, "the Ctrl key-up that went to another window fires nothing");
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 6, 6, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    n = vgv_ctrl(&m, 0, a); // fired: chord in flight
    vgv_focus_lost(&m);
    CHECK(m.n_fire == 1, "a chord that is in the air is not cancelled by a focus loss (its timer lets it go)");
    vgv_rotation_changed(&m);
    CHECK(m.n_fire == 1, "nor by a turn");
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 3, 3, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    vgv_rotation_changed(&m);
    CHECK(m.n_stage == 0, "a turn throws the staged keys away");
    vgv_device_gone(&m);
    CHECK(m.n_fire == 0 && m.n_stage == 0 && m.ctrl == 1, "a replug forgets everything and keeps the Ctrl state");

    // the Shift paths are untouched: shift collect and apply still work with the same machine
    vgv_reset(&m);
    vgv_shift(&m, 1, a);
    vgv_mouse_down(&m, 2, 2, 1, a, &consumed); vgv_mouse_up(&m, a);
    n = vgv_shift(&m, 0, a);
    CHECK(n == 1 && a[0].down == 1 && m.n_chord == 1, "Shift: collect, release, hold (as in M41)");

    // the Ctrl chord and a Shift chord together: the held (Shift) keys stay in their own list, the Ctrl chord has its own
    vgv_ctrl(&m, 1, a);
    vgv_ctrl_click(&m, 8, 3, 1, a, &consumed); vgv_ctrl_mouse_up(&m, a);
    n = vgv_ctrl(&m, 0, a);
    CHECK(n == 1 && a[0].down == 2 && m.n_chord == 1 && m.n_fire == 1, "a Ctrl chord fires while a Shift key stays held");
    vgv_fire_release(&m, a);
    CHECK(m.n_chord == 1, "and the held key is still held after the chord let go");
}

int main(void) {
    test_mapping();
    test_file();
    test_multi();
    test_chord();
    if (fails) {
        printf("vgrid_view_test: %d failed\n", fails);
        return 1;
    }
    printf("vgrid_view_test: all passed\n");
    return 0;
}
