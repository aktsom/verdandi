/*
 * vgrid_proto.h
 *
 * the device side of the monome "mext" serial protocol, for the virtual grid and arc: what
 * they answer when libmonome opens them, the LED commands they understand and the key /
 * encoder messages they send. pure C with no I/O (macos/tests/vgrid_test.c).
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// the sizes of the monome grids: 64 (8x8), 128 (16x8), 256 (16x16)
#define VGRID_MAX 16
// an arc: 4 rings of 64 leds
#define VARC_RINGS 4
#define VARC_LEDS 64

typedef struct {
    int cols, rows;                      // 0 x 0 for an arc: that is how libmonome tells them apart
    int rings;                           // an arc's rings, 0 for a grid
    uint8_t level[VGRID_MAX][VGRID_MAX]; // [y][x], 0-15 as sent by the host
    uint8_t ring[VARC_RINGS][VARC_LEDS]; // arc leds, 0-15, led 0 at the top, clockwise
    uint8_t intensity;                   // 0-15, scales all leds
    const char *id;                      // answered to "get id" (up to 32 chars)
    // partial message between feeds
    uint8_t buf[64];
    size_t have;
} vgrid_proto_t;

extern void vgrid_proto_init(vgrid_proto_t *p, const char *id, int cols, int rows);
extern void vgrid_proto_init_arc(vgrid_proto_t *p, const char *id, int rings);

// bytes from the host. leds are updated; replies (handshake answers) are appended to
// reply (at most reply_cap bytes), their length returned. *changed is set when leds changed
extern size_t vgrid_proto_feed(vgrid_proto_t *p, const uint8_t *data, size_t len, uint8_t *reply, size_t reply_cap,
                               int *changed);

// the 3-byte message for key x,y down (1) or up (0)
extern void vgrid_proto_key(int x, int y, int down, uint8_t out[3]);

// arc: the 3-byte message for ring n turned by delta (clamped to -128..127), and the 2-byte
// one for its push button down (1) or up (0)
extern void vgrid_proto_enc(int n, int delta, uint8_t out[3]);
extern void vgrid_proto_enc_key(int n, int down, uint8_t out[2]);

#ifdef __cplusplus
}
#endif
