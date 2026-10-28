/*
 * gif_writer.c: see gif_writer.h. GIF89a with a 16 colour global table, the NETSCAPE2.0
 * loop extension and plain LZW (4-bit minimum code size, codes up to 12 bits, reset when
 * the table is full).
 */

#include <stdlib.h>
#include <string.h>

#include "gif_writer.h"

static void put16(FILE *f, int v) {
    fputc(v & 0xff, f);
    fputc((v >> 8) & 0xff, f);
}

int gif_begin(gif_writer_t *g, FILE *f, int w, int h, int scale) {
    return gif_begin_palette(g, f, w, h, scale, NULL);
}

int gif_begin_palette(gif_writer_t *g, FILE *f, int w, int h, int scale, const uint8_t *palette) {
    g->f = f;
    g->w = w;
    g->h = h;
    g->scale = scale < 1 ? 1 : scale;
    fwrite("GIF89a", 1, 6, f);
    put16(f, w * g->scale);
    put16(f, h * g->scale);
    fputc(0xf3, f); // global table, 8 bit colour resolution, 16 entries
    fputc(0, f);    // background
    fputc(0, f);    // aspect
    for (int i = 0; i < 16; i++) {
        for (int c = 0; c < 3; c++) {
            fputc(palette != NULL ? palette[i * 3 + c] : i * 17, f);
        }
    }
    // loop forever
    static const uint8_t loop[] = {0x21, 0xff, 0x0b, 'N', 'E', 'T', 'S', 'C', 'A', 'P', 'E',
                                   '2', '.', '0', 0x03, 0x01, 0x00, 0x00, 0x00};
    fwrite(loop, 1, sizeof loop, f);
    return !ferror(f);
}

// LZW output: codes packed lsb first into sub-blocks of up to 255 bytes
typedef struct {
    FILE *f;
    uint32_t acc;
    int bits;
    uint8_t block[255];
    int n;
} bits_t;

static void flush_block(bits_t *b) {
    if (b->n > 0) {
        fputc(b->n, b->f);
        fwrite(b->block, 1, (size_t)b->n, b->f);
        b->n = 0;
    }
}

static void put_code(bits_t *b, int code, int size) {
    b->acc |= (uint32_t)code << b->bits;
    b->bits += size;
    while (b->bits >= 8) {
        b->block[b->n++] = (uint8_t)(b->acc & 0xff);
        b->acc >>= 8;
        b->bits -= 8;
        if (b->n == 255) {
            flush_block(b);
        }
    }
}

#define MIN_CODE 4
#define CLEAR (1 << MIN_CODE)
#define END (CLEAR + 1)
#define MAX_CODES 4096

int gif_frame(gif_writer_t *g, const uint8_t *levels, int delay_cs) {
    FILE *f = g->f;
    // graphic control: no transparency, keep the frame, delay
    fputc(0x21, f);
    fputc(0xf9, f);
    fputc(4, f);
    fputc(0x04, f);
    put16(f, delay_cs < 2 ? 2 : (delay_cs > 65535 ? 65535 : delay_cs));
    fputc(0, f);
    fputc(0, f);
    // image descriptor: the whole canvas, no local table
    fputc(0x2c, f);
    put16(f, 0);
    put16(f, 0);
    put16(f, g->w * g->scale);
    put16(f, g->h * g->scale);
    fputc(0, f);
    fputc(MIN_CODE, f);

    // dictionary: next[prefix * 16 + pixel] = code, 0 = none
    uint16_t *next = (uint16_t *)calloc((size_t)MAX_CODES * 16, sizeof *next);
    if (next == NULL) {
        return 0;
    }
    bits_t b = {f, 0, 0, {0}, 0};
    int size = MIN_CODE + 1, free_code = END + 1, prefix = -1;
    put_code(&b, CLEAR, size);
    int W = g->w * g->scale, H = g->h * g->scale;
    for (int y = 0; y < H; y++) {
        const uint8_t *row = levels + (y / g->scale) * g->w;
        for (int x = 0; x < W; x++) {
            int px = row[x / g->scale] & 0x0f;
            if (prefix < 0) {
                prefix = px;
                continue;
            }
            uint16_t c = next[prefix * 16 + px];
            if (c != 0) {
                prefix = c;
                continue;
            }
            put_code(&b, prefix, size);
            if (free_code < MAX_CODES) {
                next[prefix * 16 + px] = (uint16_t)free_code;
                if (free_code == (1 << size) && size < 12) {
                    size++;
                }
                free_code++;
            } else {
                put_code(&b, CLEAR, size);
                memset(next, 0, (size_t)MAX_CODES * 16 * sizeof *next);
                size = MIN_CODE + 1;
                free_code = END + 1;
            }
            prefix = px;
        }
    }
    if (prefix >= 0) {
        put_code(&b, prefix, size);
    }
    put_code(&b, END, size);
    if (b.bits > 0) {
        put_code(&b, 0, 8 - b.bits);
    }
    flush_block(&b);
    fputc(0, f); // block terminator
    free(next);
    return !ferror(f);
}

int gif_end(gif_writer_t *g) {
    fputc(0x3b, g->f);
    return !ferror(g->f);
}
