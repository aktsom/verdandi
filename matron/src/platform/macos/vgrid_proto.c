/*
 * vgrid_proto.c: see vgrid_proto.h. message layout from libmonome src/proto/mext.h:
 * one header byte (subsystem << 4 | command), then a payload of fixed length.
 */

#include <string.h>

#include "vgrid_proto.h"

enum { SS_SYSTEM = 0, SS_LED_GRID = 1, SS_KEY_GRID = 2, SS_LED_RING = 9, SS_TILT = 8 };

// payload length of every host -> device message
static int payload_length(int ss, int cmd) {
    switch (ss) {
    case SS_SYSTEM: {
        static const int len[16] = {[0x2] = 32, [0x4] = 3, [0x6] = 2, [0x8] = 2};
        return len[cmd];
    }
    case SS_LED_GRID: {
        static const int len[16] = {2, 2, 0, 0, 10, 3, 3, 1, 3, 1, 34, 6, 6};
        return len[cmd];
    }
    case SS_LED_RING: {
        static const int len[16] = {3, 2, 33, 4, 2};
        return len[cmd];
    }
    case SS_TILT: {
        static const int len[16] = {0, 1, 1};
        return len[cmd];
    }
    default:
        return 0;
    }
}

void vgrid_proto_init(vgrid_proto_t *p, const char *id) {
    memset(p, 0, sizeof *p);
    p->intensity = 15;
    p->id = id;
}

static void set(vgrid_proto_t *p, int x, int y, int l, int *changed) {
    if (x < 0 || x >= VGRID_COLS || y < 0 || y >= VGRID_ROWS) {
        return;
    }
    l &= 0x0f;
    if (p->level[y][x] != l) {
        p->level[y][x] = (uint8_t)l;
        *changed = 1;
    }
}

static size_t put(uint8_t *reply, size_t at, size_t cap, const uint8_t *m, size_t n) {
    if (at + n <= cap) {
        memcpy(reply + at, m, n);
        return at + n;
    }
    return at;
}

// one whole message
static size_t handle(vgrid_proto_t *p, const uint8_t *m, uint8_t *reply, size_t at, size_t cap, int *changed) {
    int ss = m[0] >> 4, cmd = m[0] & 0x0f;
    const uint8_t *d = m + 1;
    if (ss == SS_SYSTEM) {
        if (cmd == 0x0) { // query: one grid
            uint8_t r[3] = {0x00, SS_LED_GRID, 1};
            at = put(reply, at, cap, r, 3);
        } else if (cmd == 0x1) { // id
            uint8_t r[33] = {0x01};
            strncpy((char *)r + 1, p->id ? p->id : "", 32);
            at = put(reply, at, cap, r, 33);
        } else if (cmd == 0x5) { // grid size
            uint8_t r[3] = {0x03, VGRID_COLS, VGRID_ROWS};
            at = put(reply, at, cap, r, 3);
        }
        return at;
    }
    if (ss != SS_LED_GRID) {
        return at;
    }
    int x = d[0], y = d[1];
    switch (cmd) {
    case 0x0: // off
    case 0x1: // on
        set(p, x, y, cmd ? 15 : 0, changed);
        break;
    case 0x2: // all off
    case 0x3: // all on
        for (int r = 0; r < VGRID_ROWS; r++) {
            for (int c = 0; c < VGRID_COLS; c++) {
                set(p, c, r, cmd == 0x3 ? 15 : 0, changed);
            }
        }
        break;
    case 0x4: // map: 8x8 bits from x,y (multiples of 8)
        for (int r = 0; r < 8; r++) {
            for (int c = 0; c < 8; c++) {
                set(p, (x & ~7) + c, (y & ~7) + r, (d[2 + r] >> c) & 1 ? 15 : 0, changed);
            }
        }
        break;
    case 0x5: // row: 8 bits from x
        for (int c = 0; c < 8; c++) {
            set(p, (x & ~7) + c, y, (d[2] >> c) & 1 ? 15 : 0, changed);
        }
        break;
    case 0x6: // column: 8 bits from y
        for (int r = 0; r < 8; r++) {
            set(p, x, (y & ~7) + r, (d[2] >> r) & 1 ? 15 : 0, changed);
        }
        break;
    case 0x7: // intensity
        if (p->intensity != (d[0] & 0x0f)) {
            p->intensity = d[0] & 0x0f;
            *changed = 1;
        }
        break;
    case 0x8: // level set
        set(p, x, y, d[2], changed);
        break;
    case 0x9: // level all
        for (int r = 0; r < VGRID_ROWS; r++) {
            for (int c = 0; c < VGRID_COLS; c++) {
                set(p, c, r, d[0], changed);
            }
        }
        break;
    case 0xA: // level map: 64 levels, two per byte (high nibble first)
        for (int i = 0; i < 64; i++) {
            int b = d[2 + i / 2];
            set(p, (x & ~7) + i % 8, (y & ~7) + i / 8, i % 2 ? b & 0x0f : b >> 4, changed);
        }
        break;
    case 0xB: // level row: 8 levels from x
        for (int i = 0; i < 8; i++) {
            int b = d[2 + i / 2];
            set(p, (x & ~7) + i, y, i % 2 ? b & 0x0f : b >> 4, changed);
        }
        break;
    case 0xC: // level column: 8 levels from y
        for (int i = 0; i < 8; i++) {
            int b = d[2 + i / 2];
            set(p, x, (y & ~7) + i, i % 2 ? b & 0x0f : b >> 4, changed);
        }
        break;
    default:
        break;
    }
    return at;
}

size_t vgrid_proto_feed(vgrid_proto_t *p, const uint8_t *data, size_t len, uint8_t *reply, size_t reply_cap,
                        int *changed) {
    size_t out = 0;
    *changed = 0;
    for (size_t i = 0; i < len; i++) {
        p->buf[p->have++] = data[i];
        size_t need = 1 + (size_t)payload_length(p->buf[0] >> 4, p->buf[0] & 0x0f);
        if (p->have >= need) {
            out = handle(p, p->buf, reply, out, reply_cap, changed);
            p->have = 0;
        }
    }
    return out;
}

void vgrid_proto_key(int x, int y, int down, uint8_t out[3]) {
    out[0] = (uint8_t)((SS_KEY_GRID << 4) | (down ? 0x1 : 0x0));
    out[1] = (uint8_t)x;
    out[2] = (uint8_t)y;
}
