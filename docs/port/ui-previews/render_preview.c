/*
 * render_preview.c: the norns window as the real skin code draws it (device_skin.c or a variant of it made by gen_variant.py), with an oled image
 * from the real norns (capture.lua) mapped through a grey table and a brightness. the whole window as a PNG, 992 x 662 like the real one.
 *
 *   render_preview OUT.png OLED.png LUT.txt BRIGHTNESS_PERCENT [FRACTIONAL: 1 = oled at V_UNIT device pixels per oled pixel, nearest neighbour; 2 = the same, bilinear]
 *
 * LUT.txt: 256 numbers, the output grey for every input grey of the oled image. a variant.h is included when the build defines VARIANT.
 * what is NOT the product code: the fractional oled drawing (the product floors to whole pixels and has no grey table or brightness).
 */
#include <cairo.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device_skin.h"
#ifdef VARIANT
#include "variant.h"
#endif

#ifdef VARIANT
static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}
#endif

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: render_preview OUT.png OLED.png LUT.txt BRIGHTNESS_PERCENT [FRACTIONAL]\n");
        return 2;
    }
    int fractional = argc > 5 ? atoi(argv[5]) : 0;
    (void)fractional;
    double bright = atof(argv[4]) / 100.0;
    int lut[256];
    FILE *f = fopen(argv[3], "r");
    if (!f) {
        perror("lut");
        return 2;
    }
    for (int i = 0; i < 256; i++) {
        if (fscanf(f, "%d", &lut[i]) != 1) {
            fprintf(stderr, "lut: %d numbers\n", i);
            return 2;
        }
    }
    fclose(f);

    cairo_surface_t *src = cairo_image_surface_create_from_png(argv[2]);
    if (cairo_surface_status(src) != CAIRO_STATUS_SUCCESS || cairo_image_surface_get_width(src) != 128) {
        fprintf(stderr, "oled png: not 128 wide\n");
        return 2;
    }
    // the oled image as the window gets it: grey through the table, then the brightness
    cairo_surface_t *oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    {
        uint32_t *s = (uint32_t *)cairo_image_surface_get_data(src), *d = (uint32_t *)cairo_image_surface_get_data(oled);
        int ss = cairo_image_surface_get_stride(src) / 4, ds = cairo_image_surface_get_stride(oled) / 4;
        for (int y = 0; y < 64; y++) {
            for (int x = 0; x < 128; x++) {
                int v = (s[y * ss + x] >> 8) & 0xff; // the screen is grey: green is as good as any
                int o = (int)lround(lut[v] * bright);
                o = o < 0 ? 0 : o > 255 ? 255 : o;
                d[y * ds + x] = 0xff000000u | (o << 16) | (o << 8) | o;
            }
        }
        cairo_surface_mark_dirty(oled);
    }

    const int W = SKIN_W + 2 * SKIN_MARGIN, H = SKIN_H + 2 * SKIN_MARGIN;
    cairo_surface_t *canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, W, H);
    cairo_t *cr = cairo_create(canvas);
    skin_geom_t g;
    skin_geom(W, H, &g);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;              // PARAMS lit
    st.input = SKIN_INPUT_MIC; // the MIC button is lit by default
    st.out_level = 0.8;
    st.out_muted = argc > 6 ? atoi(argv[6]) : 0; // 1: MUTE on
    skin_draw_static(cr, &g);
    skin_draw_controls(cr, &g, &st);
#ifdef VARIANT
    if (fractional) {
        // the oled at V_UNIT device pixels per oled pixel, centred in the bezel (nearest neighbour: some oled pixels are one device pixel wider)
        double ox = g.ox + (V_BEZEL_X + V_BEZEL_W / 2) * g.s - 64 * V_UNIT * g.s;
        double oy = g.oy + (V_BEZEL_Y + V_BEZEL_H / 2) * g.s - 32 * V_UNIT * g.s;
        cairo_save(cr);
        cairo_save(cr);
        cairo_translate(cr, g.ox, g.oy);
        cairo_scale(cr, g.s, g.s);
        rounded_rect(cr, V_BEZEL_X, V_BEZEL_Y, V_BEZEL_W, V_BEZEL_H, 7);
        cairo_restore(cr);
        cairo_clip(cr);
        cairo_set_source_rgb(cr, 0, 0, 0);
        cairo_paint(cr);
        cairo_translate(cr, ox, oy);
        cairo_scale(cr, V_UNIT * g.s, V_UNIT * g.s);
        cairo_set_source_surface(cr, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), fractional == 2 ? CAIRO_FILTER_BILINEAR : CAIRO_FILTER_NEAREST);
        cairo_rectangle(cr, 0, 0, 128, 64);
        cairo_fill(cr);
        cairo_restore(cr);
    } else
#endif
    {
        skin_draw_oled(cr, &g, oled);
    }
    cairo_destroy(cr);
    cairo_surface_write_to_png(canvas, argv[1]);
    return 0;
}
