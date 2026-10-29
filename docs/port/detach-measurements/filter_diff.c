#include <cairo.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static cairo_surface_t *render(cairo_surface_t *oled, int ow, cairo_filter_t f) {
    int m = (int)ceil(ow / 128.0);
    cairo_surface_t *big = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128 * m, 64 * m);
    cairo_t *bc = cairo_create(big); cairo_scale(bc, m, m);
    cairo_set_source_surface(bc, oled, 0, 0); cairo_pattern_set_filter(cairo_get_source(bc), CAIRO_FILTER_NEAREST); cairo_paint(bc); cairo_destroy(bc);
    cairo_surface_t *out = cairo_image_surface_create(CAIRO_FORMAT_RGB24, ow, ow / 2);
    cairo_t *cr = cairo_create(out);
    cairo_scale(cr, (double)ow / (128 * m), (double)(ow / 2) / (64 * m));
    cairo_set_source_surface(cr, big, 0, 0); cairo_pattern_set_filter(cairo_get_source(cr), f); cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
    cairo_rectangle(cr, 0, 0, 128 * m, 64 * m); cairo_fill(cr); cairo_destroy(cr); cairo_surface_destroy(big); cairo_surface_flush(out);
    return out;
}
int main(void) {
    cairo_surface_t *oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    unsigned char *d = cairo_image_surface_get_data(oled); int st = cairo_image_surface_get_stride(oled);
    for (int y = 0; y < 64; y++) for (int x = 0; x < 128; x++) { unsigned g = (((x / 3) ^ (y / 2)) & 1) ? 255 : ((x * 7 + y * 13) % 16) * 17; ((unsigned *)(d + y * st))[x] = g << 16 | g << 8 | g; }
    cairo_surface_mark_dirty(oled);
    int widths[] = {700, 1000, 1366, 1500, 1700, 2900};
    for (int i = 0; i < 6; i++) {
        int ow = widths[i];
        cairo_surface_t *a = render(oled, ow, CAIRO_FILTER_BEST), *b = render(oled, ow, CAIRO_FILTER_BILINEAR);
        unsigned char *pa = cairo_image_surface_get_data(a), *pb = cairo_image_surface_get_data(b);
        int sa = cairo_image_surface_get_stride(a); long sum = 0; int mx = 0, h = ow / 2;
        for (int y = 0; y < h; y++) for (int x = 0; x < ow; x++) { int v = abs(((unsigned *)(pa + y * sa))[x] % 256 - ((unsigned *)(pb + y * sa))[x] % 256); sum += v; if (v > mx) mx = v; }
        printf("ow %4d: mean difference %.2f of 255, largest %d (BEST vs BILINEAR, same nearest enlargement first)\n", ow, (double)sum / ((double)ow * h), mx);
    }
    return 0;
}
