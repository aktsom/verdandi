// repro for docs/port/KNOWN-ISSUES.md item 9. build: gcc text_center.c -o text_center $(pkg-config --cflags --libs cairo freetype2) -lm ; run: ./text_center code|adv|round default|none|full gray|none|subpixel "modulation" 64
// (with another cairo: LD_LIBRARY_PATH=<folder with its libcairo.so.2>). the norns screen text code (matron/src/hardware/screen.cc) outside norns: same surface, same font file, same options, text_center as in the code
#include <cairo-ft.h>
#include <cairo.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static cairo_surface_t *surface;
static cairo_t *cr;

static void text_center(const char *s) {
    cairo_text_extents_t e;
    cairo_text_extents(cr, s, &e);
    cairo_rel_move_to(cr, -e.width * 0.5, 0);
    cairo_show_text(cr, s);
}
static void text_center_adv(const char *s) { // the other way: the advance, then rounded to a whole pixel
    cairo_text_extents_t e;
    cairo_text_extents(cr, s, &e);
    cairo_rel_move_to(cr, -floor(e.x_advance * 0.5 + 0.5), 0);
    cairo_show_text(cr, s);
}
static void text_center_round(const char *s) { // the code's centre, rounded to a whole pixel
    cairo_text_extents_t e;
    cairo_text_extents(cr, s, &e);
    double x, y;
    cairo_get_current_point(cr, &x, &y);
    cairo_move_to(cr, floor(x - e.width * 0.5 + 0.5), y);
    cairo_show_text(cr, s);
}

static void dump(int y0, int y1, int x0, int x1) {
    unsigned char *d = cairo_image_surface_get_data(surface);
    int stride = cairo_image_surface_get_stride(surface);
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            unsigned a = d[y * stride + x * 4 + 3];
            putchar(a == 0 ? '.' : a == 255 ? '#' : (a > 170 ? '+' : (a > 85 ? '-' : ':')));
        }
        putchar('\n');
    }
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "code";   // code | adv | round
    const char *hint = argc > 2 ? argv[2] : "default"; // default | none | full
    const char *aa = argc > 3 ? argv[3] : "gray";
    const char *str = argc > 4 ? argv[4] : "modulation";
    double cx = argc > 5 ? atof(argv[5]) : 64.0;
    FT_Library lib;
    FT_Face face;
    FT_Init_FreeType(&lib);
    if (FT_New_Face(lib, "resources/norns.ttf", 0, &face)) {
        return 1;
    }
    surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 128, 64);
    cr = cairo_create(surface);
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_font_options_t *fo = cairo_font_options_create();
    cairo_font_options_set_antialias(fo, !strcmp(aa, "none") ? CAIRO_ANTIALIAS_NONE : !strcmp(aa, "subpixel") ? CAIRO_ANTIALIAS_SUBPIXEL : CAIRO_ANTIALIAS_GRAY);
    if (!strcmp(hint, "none")) {
        cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_NONE);
        cairo_font_options_set_hint_metrics(fo, CAIRO_HINT_METRICS_OFF);
    } else if (!strcmp(hint, "full")) {
        cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_FULL);
        cairo_font_options_set_hint_metrics(fo, CAIRO_HINT_METRICS_ON);
    }
    cairo_set_font_options(cr, fo);
    cairo_set_font_face(cr, cairo_ft_font_face_create_for_ft_face(face, 0));
    cairo_set_font_size(cr, 8.0);
    cairo_set_source_rgba(cr, 1, 1, 1, 1);
    cairo_text_extents_t e;
    cairo_text_extents(cr, str, &e);
    cairo_move_to(cr, cx, 10);
    if (!strcmp(mode, "adv")) text_center_adv(str);
    else if (!strcmp(mode, "round")) text_center_round(str);
    else text_center(str);
    double x, y;
    cairo_get_current_point(cr, &x, &y);
    printf("%s | mode=%s hint=%s aa=%s | ink width %.3f advance %.3f x_bearing %.3f | centre x %.3f => start %.3f\n", str, mode, hint, aa, e.width, e.x_advance, e.x_bearing, cx, cx - (strcmp(mode,"adv")? e.width*0.5 : floor(e.x_advance*0.5+0.5)));
    int x0 = (int)(cx - e.width / 2) - 3;
    if (x0 < 0) x0 = 0;
    dump(3, 13, x0, x0 + (int)e.width + 8);
    return 0;
}
