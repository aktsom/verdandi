/*
 * gif_test.c: platform/macos/gif_writer.c, decoded again by macOS's own ImageIO: every
 * pixel of every frame and the frame delays must come back as written.
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos macos/tests/gif_test.c \
 *    matron/src/platform/macos/gif_writer.c -framework ImageIO -framework CoreGraphics \
 *    -framework CoreFoundation -o /tmp/gift && /tmp/gift
 */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "gif_writer.h"

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

#define W 128
#define H 64
#define SCALE 4
#define FRAMES 3

static uint8_t frames[FRAMES][W * H];
static const int delays[FRAMES] = {5, 120, 2};

static void make_frames(void) {
    uint32_t seed = 12345;
    for (int i = 0; i < W * H; i++) {
        // a menu-like frame: mostly black, some text-ish levels
        frames[0][i] = (i % W) < 40 && (i / W) % 10 < 7 ? (uint8_t)((i / 3) % 16) : 0;
        // noise: every level, and enough codes to fill the LZW table and reset it
        seed = seed * 1664525u + 1013904223u;
        frames[1][i] = (uint8_t)(seed >> 28);
        // flat
        frames[2][i] = 15;
    }
}

static double frame_delay(CGImageSourceRef src, size_t i) {
    double d = -1;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
    if (props != NULL) {
        CFDictionaryRef gif = CFDictionaryGetValue(props, kCGImagePropertyGIFDictionary);
        CFNumberRef n = gif != NULL ? CFDictionaryGetValue(gif, kCGImagePropertyGIFUnclampedDelayTime) : NULL;
        if (n != NULL) {
            CFNumberGetValue(n, kCFNumberDoubleType, &d);
        }
        CFRelease(props);
    }
    return d;
}

static void check_frame(CGImageSourceRef src, size_t f) {
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, f, NULL);
    CHECK(img != NULL, "frame %zu decodes", f);
    if (img == NULL) {
        return;
    }
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    CHECK(w == W * SCALE && h == H * SCALE, "frame %zu is %zux%zu", f, w, h);
    uint8_t *rgba = calloc(w * h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, w, h, 8, w * 4, cs, kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    int bad = 0, first_x = -1, first_y = -1, got = 0, want = 0;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            int v = rgba[(y * w + x) * 4 + 1];
            int l = frames[f][(y / SCALE) * W + x / SCALE] * 17;
            // the device rgb space may shift a grey by a step or two, never a level (17)
            if (abs(v - l) > 4) {
                if (bad++ == 0) {
                    first_x = (int)x;
                    first_y = (int)y;
                    got = v;
                    want = l;
                }
            }
        }
    }
    CHECK(bad == 0, "frame %zu: %d pixels wrong, first at %d,%d: %d, want %d", f, bad, first_x, first_y, got, want);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    free(rgba);
    CGImageRelease(img);
}

int main(void) {
    make_frames();
    char path[] = "/tmp/gif_test_XXXXXX";
    int fd = mkstemp(path);
    FILE *f = fdopen(fd, "wb");
    gif_writer_t g;
    CHECK(gif_begin(&g, f, W, H, SCALE), "begin");
    for (int i = 0; i < FRAMES; i++) {
        CHECK(gif_frame(&g, frames[i], delays[i]), "frame %d", i);
    }
    CHECK(gif_end(&g), "end");
    fclose(f);

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
    CHECK(src != NULL, "ImageIO opens the gif");
    if (src != NULL) {
        CHECK(CGImageSourceGetCount(src) == FRAMES, "%zu frames", CGImageSourceGetCount(src));
        for (size_t i = 0; i < FRAMES && i < CGImageSourceGetCount(src); i++) {
            check_frame(src, i);
            double d = frame_delay(src, i);
            CHECK(d > delays[i] / 100.0 - 0.001 && d < delays[i] / 100.0 + 0.001, "frame %zu delay %.3f, want %.2f", i,
                  d, delays[i] / 100.0);
        }
        CFRelease(src);
    }
    CFRelease(url);
    unlink(path);
    printf("%s: %d failures\n", failures ? "FAILED" : "gif ok", failures);
    return failures != 0;
}
