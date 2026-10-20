/*
 * vgrid_proto.h
 *
 * the device side of the monome "mext" serial protocol, for the virtual grid: what a
 * grid answers when libmonome opens it, the LED commands it understands and the key
 * messages it sends. pure C with no I/O (macos/tests/vgrid_test.c).
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// the sizes of the monome grids: 64 (8x8), 128 (16x8), 256 (16x16)
#define VGRID_MAX 16

typedef struct {
    int cols, rows;
    uint8_t level[VGRID_MAX][VGRID_MAX]; // [y][x], 0-15 as sent by the host
    uint8_t intensity;                      // 0-15, scales all leds
    const char *id;                         // answered to "get id" (up to 32 chars)
    // partial message between feeds
    uint8_t buf[64];
    size_t have;
} vgrid_proto_t;

extern void vgrid_proto_init(vgrid_proto_t *p, const char *id, int cols, int rows);

// bytes from the host. leds are updated; replies (handshake answers) are appended to
// reply (at most reply_cap bytes), their length returned. *changed is set when leds changed
extern size_t vgrid_proto_feed(vgrid_proto_t *p, const uint8_t *data, size_t len, uint8_t *reply, size_t reply_cap,
                               int *changed);

// the 3-byte message for key x,y down (1) or up (0)
extern void vgrid_proto_key(int x, int y, int down, uint8_t out[3]);

#ifdef __cplusplus
}
#endif
