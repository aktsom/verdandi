// grid_handshake.h: does the thing on this serial port answer like a monome? (Windows build) libmonome opens a mext device by asking it who it is and waits for the answer WITHOUT a time limit: a port with a
// "monome" serial that never answers would freeze the thread that opens it. so the monitor asks first, with a limit: the system query (the byte 0x00; the answer is 3 bytes that start with 0x00: type and count),
// twice (the first byte after opening a port can be lost). only for devices of the mext family (CAFE:1110, serials "m<digits>" / "M<digits>"); the older families (series, 40h) do not answer a query and are not
// asked. i/o is passed in, so that the same code runs on a Windows handle and on a pseudo terminal in the tests (linux/tests/grid_protocol_test.c).
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vgrid_io {
    void *ctx;
    long (*write)(void *ctx, const uint8_t *data, size_t n);
    /* reads up to n bytes, waiting at most `ms`; returns the number read (0 = nothing in the time), < 0 = failed */
    long (*read)(void *ctx, uint8_t *data, size_t n, int ms);
} vgrid_io;

/* 1 = a monome answered the system query; 0 = no answer in about 1.5 seconds (or it answered with something else); -1 = the port failed */
static inline int vgrid_handshake(const vgrid_io *io) {
    for (int attempt = 0; attempt < 2; attempt++) {
        const uint8_t q = 0x00;
        if (io->write(io->ctx, &q, 1) < 0) {
            return -1;
        }
        uint8_t buf[16];
        size_t have = 0;
        for (int waited = 0; waited < 700 && have < 3;) {
            long r = io->read(io->ctx, buf + have, sizeof buf - have, 100);
            if (r < 0) {
                return -1;
            }
            if (r == 0) {
                waited += 100;
            } else {
                have += (size_t)r;
            }
        }
        if (have >= 3 && buf[0] == 0x00) {
            return 1;
        }
    }
    return 0;
}

#ifdef __cplusplus
}
#endif
