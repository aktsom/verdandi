/*
 * render_look.c: the aluminium window as the real skin code draws it (device_skin.c and box_style.c with NORNS_LINUX_DESKTOP) with a look set through skin_set_look. the oled image is a 128 x 64 png.
 *   [RENDER_STYLE=pixel] render_look OUT.png OLED.png BOX KEYS ENCODERS BUTTONS FONT [key_down(1-3) muted]   ("-" = that part's default; RENDER_STYLE=pixel draws the pixel style)
 */
#include <cairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device_skin.h"

int main(int argc, char **argv) {
    if (argc < 8) {
        fprintf(stderr, "usage: render_look OUT.png OLED.png BOX KEYS ENCODERS BUTTONS FONT [key_down muted]\n");
        return 2;
    }
    const char *c[5];
    for (int i = 0; i < 5; i++) {
        c[i] = strcmp(argv[3 + i], "-") == 0 ? NULL : argv[3 + i];
    }
    skin_set_look(getenv("RENDER_STYLE") != NULL && strcmp(getenv("RENDER_STYLE"), "pixel") == 0 ? SKIN_STYLE_PIXEL : SKIN_STYLE_ALUMINIUM, c[0], c[1], c[2], c[3], c[4]);
    cairo_surface_t *src = cairo_image_surface_create_from_png(argv[2]);
    if (cairo_surface_status(src) != CAIRO_STATUS_SUCCESS) {
        fprintf(stderr, "oled png\n");
        return 2;
    }
    const int W = SKIN_W + 2 * SKIN_MARGIN, H = SKIN_H + 2 * SKIN_MARGIN;
    cairo_surface_t *canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, W, H);
    cairo_t *cr = cairo_create(canvas);
    skin_geom_t g;
    skin_geom(W, H, &g);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    if (argc > 8 && atoi(argv[8]) >= 1 && atoi(argv[8]) <= 3) {
        st.key_down[atoi(argv[8]) - 1] = 1;
    }
    st.out_muted = argc > 9 ? atoi(argv[9]) : 0;
    skin_draw_static(cr, &g);
    skin_draw_controls(cr, &g, &st);
    skin_draw_oled(cr, &g, src);
    cairo_surface_write_to_png(canvas, argv[1]);
    return 0;
}
