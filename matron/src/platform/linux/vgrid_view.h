/*
 * vgrid_view.h: the pure parts of the virtual grid window's new controls (docs/port/phase-m41.md), header only, no SDL, no cairo, so that a plain C test can run them
 * (linux/tests/vgrid_view_test.c):
 *   - ROTATE: turning the DEVICE in the window by k x 90 degrees clockwise. the device, libmonome and the script do not change; only the drawing and the mapping of a click back to
 *     the device key. the mapping, and the file that keeps the choice ($HOME/.vgrid-rotation: one number 0 to 3)
 *   - shift multi-press: shift collects keys in a pending set (nothing is sent), letting go of shift sends all their key-downs in one burst, the keys then stay held until the next plain
 *     click, Esc or the window closing, which lets them all go in one burst. a state machine that says what to do (vgv_act_t); the window code does it
 * Linux desktop only (the macOS and Windows builds never include this file).
 */

#pragma once

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VGV_MAX 16
#define VGV_MAXKEYS (VGV_MAX * VGV_MAX)
// one call gives at most the whole chord released and the whole pending set pressed
#define VGV_MAXACT (2 * VGV_MAXKEYS)

//---------------------------------------------------------------- rotation

// the plate as it is drawn: columns and rows on the screen for a device of cols x rows turned rot x 90 degrees (odd: the plate stands up)
static inline void vgv_screen_dims(int rot, int cols, int rows, int *scols, int *srows) {
    if (rot & 1) {
        *scols = rows;
        *srows = cols;
    } else {
        *scols = cols;
        *srows = rows;
    }
}

// where the device key (c, r) is drawn: clockwise turns, so for 90 degrees the top left key goes to the top right
static inline void vgv_to_screen(int rot, int cols, int rows, int c, int r, int *sc, int *sr) {
    switch (rot & 3) {
    case 1:
        *sc = rows - 1 - r;
        *sr = c;
        break;
    case 2:
        *sc = cols - 1 - c;
        *sr = rows - 1 - r;
        break;
    case 3:
        *sc = r;
        *sr = cols - 1 - c;
        break;
    default:
        *sc = c;
        *sr = r;
        break;
    }
}

// the device key under the drawn key (sc, sr): the inverse of vgv_to_screen
static inline void vgv_to_device(int rot, int cols, int rows, int sc, int sr, int *c, int *r) {
    switch (rot & 3) {
    case 1:
        *c = sr;
        *r = rows - 1 - sc;
        break;
    case 2:
        *c = cols - 1 - sc;
        *r = rows - 1 - sr;
        break;
    case 3:
        *c = cols - 1 - sr;
        *r = sc;
        break;
    default:
        *c = sc;
        *r = sr;
        break;
    }
}

// the saved choice: the text of the file -> 0 to 3. a bad text (empty, not a number, a number out of range, junk after it) is 0
static inline int vgv_parse_rot(const char *text) {
    if (text == NULL) {
        return 0;
    }
    char *end = NULL;
    long v = strtol(text, &end, 10);
    if (end == text || v < 0 || v > 3) {
        return 0;
    }
    while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') {
        end++;
    }
    return *end == '\0' ? (int)v : 0;
}

// read the file: 0 when it is missing or bad
static inline int vgv_load_rot(const char *path) {
    char buf[64];
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = '\0';
    return vgv_parse_rot(buf);
}

// write the file: 0 when written, -1 when it could not be (the choice then only lasts until the program ends)
static inline int vgv_save_rot(const char *path, int rot) {
    FILE *f = fopen(path, "w");
    if (f == NULL) {
        return -1;
    }
    int ok = fprintf(f, "%d\n", rot & 3) > 0;
    ok = fclose(f) == 0 && ok;
    return ok ? 0 : -1;
}

//---------------------------------------------------------------- shift multi-press

// what the window must do: down = 1: hold the key (key-down, and it stays held like a latched key); down = 0: let it go (key-up unless something else holds it)
typedef struct {
    uint8_t x, y;
    int down;
} vgv_act_t;

typedef struct {
    uint8_t pend[VGV_MAX][VGV_MAX]; // the pending set (drawn with a white outline; nothing is sent while a key is pending)
    uint8_t order[VGV_MAXKEYS][2];  // the pending keys in the order they were collected: the order of the burst
    int n_order;
    uint8_t chord[VGV_MAXKEYS][2]; // the keys held after the apply, in the order they went down: the order of the release
    int n_chord;
    int shift;      // shift is down (as the window last heard)
    int mouse;      // the left button is down on a collecting click or drag
    int apply_wait; // shift was let go while the left button was still down: the burst waits for the button
    int last_c, last_r;
} vgv_t;

static inline void vgv_reset(vgv_t *m) {
    memset(m, 0, sizeof *m);
    m->last_c = m->last_r = -1;
}

static inline int vgv_is_pending(const vgv_t *m, int c, int r) {
    return c >= 0 && r >= 0 && c < VGV_MAX && r < VGV_MAX && m->pend[r][c] != 0;
}

static inline int vgv_in_chord(const vgv_t *m, int c, int r) {
    for (int i = 0; i < m->n_chord; i++) {
        if (m->chord[i][0] == c && m->chord[i][1] == r) {
            return 1;
        }
    }
    return 0;
}

static inline void vgv_pend_add(vgv_t *m, int c, int r) {
    if (c < 0 || r < 0 || c >= VGV_MAX || r >= VGV_MAX || m->pend[r][c] || m->n_order >= VGV_MAXKEYS) {
        return;
    }
    m->pend[r][c] = 1;
    m->order[m->n_order][0] = (uint8_t)c;
    m->order[m->n_order][1] = (uint8_t)r;
    m->n_order++;
}

static inline void vgv_pend_remove(vgv_t *m, int c, int r) {
    if (!vgv_is_pending(m, c, r)) {
        return;
    }
    m->pend[r][c] = 0;
    int j = 0;
    for (int i = 0; i < m->n_order; i++) {
        if (m->order[i][0] == c && m->order[i][1] == r) {
            continue;
        }
        m->order[j][0] = m->order[i][0];
        m->order[j][1] = m->order[i][1];
        j++;
    }
    m->n_order = j;
}

static inline void vgv_pend_clear(vgv_t *m) {
    memset(m->pend, 0, sizeof m->pend);
    m->n_order = 0;
}

// the pending keys go down in one burst and become the held chord
static inline int vgv_apply(vgv_t *m, vgv_act_t *out) {
    int n = 0;
    for (int i = 0; i < m->n_order; i++) {
        int c = m->order[i][0], r = m->order[i][1];
        out[n].x = (uint8_t)c;
        out[n].y = (uint8_t)r;
        out[n].down = 1;
        n++;
        if (!vgv_in_chord(m, c, r) && m->n_chord < VGV_MAXKEYS) {
            m->chord[m->n_chord][0] = (uint8_t)c;
            m->chord[m->n_chord][1] = (uint8_t)r;
            m->n_chord++;
        }
    }
    vgv_pend_clear(m);
    return n;
}

// the held chord lets go in one burst
static inline int vgv_release_chord(vgv_t *m, vgv_act_t *out) {
    int n = 0;
    for (int i = 0; i < m->n_chord; i++) {
        out[n].x = m->chord[i][0];
        out[n].y = m->chord[i][1];
        out[n].down = 0;
        n++;
    }
    m->n_chord = 0;
    return n;
}

// the state of the shift keys, from a key event or by asking SDL (SDL_GetModState): called with every mouse event and every shift key event, so a shift key-up that never came to the window
// is found at the next mouse event. returns the number of actions
static inline int vgv_shift(vgv_t *m, int shift_now, vgv_act_t *out) {
    shift_now = shift_now != 0;
    if (shift_now == m->shift) {
        return 0;
    }
    m->shift = shift_now;
    if (shift_now) {
        return 0;
    }
    // shift let go: the burst, at once, or when the left button comes up if it is still collecting
    if (m->mouse) {
        m->apply_wait = 1;
        return 0;
    }
    return vgv_apply(m, out);
}

// the left button went down on the device key (c, r). *consumed: 1 = this click collected (shift): the window must not press the key. 0 = a plain click: a held chord was let go first (the actions),
// and the window goes on with the normal press
static inline int vgv_mouse_down(vgv_t *m, int c, int r, int shift_now, vgv_act_t *out, int *consumed) {
    int n = vgv_shift(m, shift_now, out);
    *consumed = 0;
    if (m->shift) {
        if (vgv_is_pending(m, c, r)) {
            vgv_pend_remove(m, c, r);
        } else {
            vgv_pend_add(m, c, r);
        }
        m->mouse = 1;
        m->last_c = c;
        m->last_r = r;
        *consumed = 1;
        return n;
    }
    n += vgv_release_chord(m, out + n);
    return n;
}

// the pointer moved onto the device key (c, r) with the left button down. 1 = it was a collecting drag (the key joins the pending set; a drag only adds), the window does nothing else
static inline int vgv_motion(vgv_t *m, int c, int r) {
    if (!m->mouse || !m->shift) {
        return m->mouse;
    }
    if (c == m->last_c && r == m->last_r) {
        return 1;
    }
    m->last_c = c;
    m->last_r = r;
    vgv_pend_add(m, c, r);
    return 1;
}

// the left button came up
static inline int vgv_mouse_up(vgv_t *m, vgv_act_t *out) {
    if (!m->mouse) {
        return 0;
    }
    m->mouse = 0;
    m->last_c = m->last_r = -1;
    if (m->apply_wait) {
        m->apply_wait = 0;
        return vgv_apply(m, out);
    }
    return 0;
}

// Esc in the grid window: the chord lets go, the pending set is thrown away (nothing sent). *used: 1 when there was something, so that the key is not passed on
static inline int vgv_esc(vgv_t *m, vgv_act_t *out, int *used) {
    *used = m->n_chord > 0 || m->n_order > 0;
    vgv_pend_clear(m);
    m->apply_wait = 0;
    return vgv_release_chord(m, out);
}

// the window lost the focus: whatever was pending is thrown away, nothing is sent (the shift key-up may go to another window: no stuck keys). a held chord stays, as a latched key does
static inline void vgv_focus_lost(vgv_t *m) {
    vgv_pend_clear(m);
    m->shift = 0;
    m->mouse = 0;
    m->apply_wait = 0;
    m->last_c = m->last_r = -1;
}

// the rotation changed while keys were pending: the pending set is thrown away, nothing is sent (the keys the user meant are not where they were). a held chord stays: those are device keys
static inline void vgv_rotation_changed(vgv_t *m) {
    vgv_pend_clear(m);
    m->apply_wait = 0;
}

// the window closed or the size changed (the device is plugged out and in again): everything goes, nothing is sent (the device is gone, the new one starts with no key down)
static inline void vgv_device_gone(vgv_t *m) {
    int shift = m->shift;
    vgv_reset(m);
    m->shift = shift;
}

#ifdef __cplusplus
}
#endif
