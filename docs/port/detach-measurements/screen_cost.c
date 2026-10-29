// a measurement for the plan (not product code): the cost of one frame of the screen at several window sizes, using the same cairo calls as skin_draw_oled
#include <cairo.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static void frame(cairo_t *cr, cairo_surface_t *oled, int ow, int ox, int oy) {
    int px = (int)lround(ow / 128.0);
    if (ow == 128 * px) {
        cairo_save(cr); cairo_translate(cr, ox, oy); cairo_scale(cr, px, px);
        cairo_set_source_surface(cr, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
        cairo_rectangle(cr, 0, 0, 128, 64); cairo_fill(cr); cairo_restore(cr);
    } else {
        int m = (int)ceil(ow / 128.0);
        cairo_surface_t *big = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128 * m, 64 * m);
        cairo_t *bc = cairo_create(big); cairo_scale(bc, m, m);
        cairo_set_source_surface(bc, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(bc), CAIRO_FILTER_NEAREST); cairo_paint(bc); cairo_destroy(bc);
        cairo_save(cr); cairo_translate(cr, ox, oy);
        cairo_scale(cr, (double)ow / (128 * m), (double)ow / 2 / (64 * m));
        cairo_set_source_surface(cr, big, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
        cairo_rectangle(cr, 0, 0, 128 * m, 64 * m); cairo_fill(cr); cairo_restore(cr);
        cairo_surface_destroy(big);
    }
}
int main(void) {
    cairo_surface_t *oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    unsigned char *d = cairo_image_surface_get_data(oled); int st = cairo_image_surface_get_stride(oled);
    for (int y = 0; y < 64; y++) for (int x = 0; x < 128; x++) { unsigned g = ((x * 7 + y * 13) % 16) * 17; ((unsigned *)(d + y * st))[x] = g << 16 | g << 8 | g; }
    cairo_surface_mark_dirty(oled);
    struct { const char *name; int w, h, ow; } cases[] = {
        {"window 1024x512 (8x, whole)", 1024, 512, 1024}, {"fullscreen 1920x1080 (15x, whole; 1920x960 used)", 1920, 1080, 1920},
        {"fullscreen 2560x1440 (20x, whole)", 2560, 1440, 2560}, {"fullscreen 3840x2160 (30x, whole)", 3840, 2160, 3840},
        {"window 1500x800 (11.7x, filtered)", 1500, 800, 1500}, {"fullscreen 1366x768 (10.67x, filtered)", 1366, 768, 1366},
        {"fullscreen 3440x1440 (22.5x of height, filtered)", 3440, 1440, 2880},
    };
    for (unsigned i = 0; i < sizeof cases / sizeof *cases; i++) {
        int w = cases[i].w, h = cases[i].h;
        cairo_surface_t *canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
        unsigned char *copy = malloc((size_t)cairo_image_surface_get_stride(canvas) * h);
        int n = 40; double t0 = now();
        for (int k = 0; k < n; k++) {
            cairo_t *cr = cairo_create(canvas);
            cairo_set_source_rgb(cr, 0, 0, 0); cairo_paint(cr);
            frame(cr, oled, cases[i].ow, (w - cases[i].ow) / 2, (h - cases[i].ow / 2) / 2);
            cairo_destroy(cr); cairo_surface_flush(canvas);
            memcpy(copy, cairo_image_surface_get_data(canvas), (size_t)cairo_image_surface_get_stride(canvas) * h); // the blit to the window surface
        }
        printf("%-52s %6.1f ms per frame\n", cases[i].name, (now() - t0) / n);
        free(copy); cairo_surface_destroy(canvas);
    }
    return 0;
}
