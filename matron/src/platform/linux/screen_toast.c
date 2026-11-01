/*
 * screen_toast.c: see screen_toast.h
 */
#include "screen_toast.h"

#include <math.h>

static double measure(void *ctx, const char *s) {
    cairo_text_extents_t te;
    cairo_text_extents((cairo_t *)ctx, s, &te);
    return te.x_advance;
}

void screen_toast_layout(int w, int h, const char *text, int recording, screen_toast_t *out) {
    double k = fmin(2.0, fmax(0.8, w / 992.0));
    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_A8, 8, 8);
    cairo_t *cr = cairo_create(surf);
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 14 * k);
    out->k = k;
    out->font = 14 * k;
    out->dot = recording ? 22 * k : 0;
    toast_fit(text, measure, cr, (w - 20) - 36 * k - out->dot, &out->lines);
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    out->line_h = 17 * k;
    out->w = out->lines.widest + 36 * k + out->dot;
    out->h = 36 * k + (out->lines.n - 1) * out->line_h;
    out->x = (w - out->w) / 2;
    out->y = h - out->h - 14 * k;
}

void screen_toast_draw(cairo_t *cr, int w, int h, const char *text, int recording) {
    screen_toast_t t;
    screen_toast_layout(w, h, text, recording, &t);
    double k = t.k;
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, t.font);
    double r = fmin(t.h / 2, 18 * k);
    double x = t.x, y = t.y, pw = t.w, ph = t.h;
    cairo_new_path(cr);
    cairo_arc(cr, x + pw - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + pw - r, y + ph - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + ph - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
    cairo_set_source_rgba(cr, 0.114, 0.118, 0.129, 0.92);
    cairo_fill(cr);
    if (recording) {
        cairo_arc(cr, x + 22 * k, y + 18 * k, 6 * k, 0, 2 * M_PI);
        cairo_set_source_rgb(cr, 1, 0.27, 0.23);
        cairo_fill(cr);
    }
    cairo_set_source_rgb(cr, 0.949, 0.953, 0.961);
    for (int i = 0; i < t.lines.n; i++) {
        cairo_text_extents_t te;
        cairo_text_extents(cr, t.lines.line[i], &te);
        cairo_move_to(cr, x + 18 * k + t.dot - te.x_bearing, y + 18 * k + i * t.line_h - te.height / 2 - te.y_bearing);
        cairo_show_text(cr, t.lines.line[i]);
    }
}
