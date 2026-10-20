/*
 * vgrid_skin.c: see vgrid_skin.h
 */

#include <math.h>

#include "vgrid_skin.h"

void vgrid_skin_geom(int w, int h, vgrid_geom_t *g) {
    double sx = (double)w / VGRID_SKIN_W, sy = (double)h / VGRID_SKIN_H;
    g->s = sx < sy ? sx : sy;
    g->ox = (w - VGRID_SKIN_W * g->s) / 2;
    g->oy = (h - VGRID_SKIN_H * g->s) / 2;
}

int vgrid_skin_hit(const vgrid_geom_t *g, double x, double y, int *col, int *row) {
    double ux = (x - g->ox) / g->s - VGRID_SKIN_PAD + (VGRID_SKIN_PITCH - VGRID_SKIN_KEY) / 2.0;
    double uy = (y - g->oy) / g->s - VGRID_SKIN_PAD + (VGRID_SKIN_PITCH - VGRID_SKIN_KEY) / 2.0;
    int c = (int)floor(ux / VGRID_SKIN_PITCH), r = (int)floor(uy / VGRID_SKIN_PITCH);
    if (c < 0 || c >= VGRID_COLS || r < 0 || r >= VGRID_ROWS) {
        return 0;
    }
    *col = c;
    *row = r;
    return 1;
}

static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

void vgrid_skin_draw(cairo_t *cr, const vgrid_geom_t *g, int w, int h,
                     const uint8_t level[VGRID_ROWS][VGRID_COLS], int intensity,
                     const uint8_t held[VGRID_ROWS][VGRID_COLS]) {
    cairo_save(cr);
    cairo_set_source_rgb(cr, 0.10, 0.10, 0.11);
    cairo_rectangle(cr, 0, 0, w, h);
    cairo_fill(cr);
    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);

    // the case: dark, lighter at the top edge
    rounded_rect(cr, 2, 2, VGRID_SKIN_W - 4, VGRID_SKIN_H - 4, 16);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, 0, 0, VGRID_SKIN_H);
    cairo_pattern_add_color_stop_rgb(p, 0, 0.17, 0.17, 0.18);
    cairo_pattern_add_color_stop_rgb(p, 1, 0.12, 0.12, 0.13);
    cairo_set_source(cr, p);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1.5);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.10);
    cairo_stroke(cr);

    double k = VGRID_SKIN_KEY, scale = (intensity < 0 ? 15 : intensity) / 15.0;
    // glows first, so the keys around a lit key do not cut its glow off
    for (int r = 0; r < VGRID_ROWS; r++) {
        for (int c = 0; c < VGRID_COLS; c++) {
            double x = VGRID_SKIN_PAD + c * VGRID_SKIN_PITCH, y = VGRID_SKIN_PAD + r * VGRID_SKIN_PITCH;
            double l = level[r][c] / 15.0 * scale;
            if (l > 0) {
                cairo_pattern_t *gl = cairo_pattern_create_radial(x + k / 2, y + k / 2, k * 0.3, x + k / 2, y + k / 2, k);
                cairo_pattern_add_color_stop_rgba(gl, 0, 1.0, 0.86, 0.62, 0.35 * l);
                cairo_pattern_add_color_stop_rgba(gl, 1, 1.0, 0.86, 0.62, 0);
                cairo_set_source(cr, gl);
                cairo_rectangle(cr, x - k / 2, y - k / 2, k * 2, k * 2);
                cairo_fill(cr);
                cairo_pattern_destroy(gl);
            }
        }
    }
    for (int r = 0; r < VGRID_ROWS; r++) {
        for (int c = 0; c < VGRID_COLS; c++) {
            double x = VGRID_SKIN_PAD + c * VGRID_SKIN_PITCH, y = VGRID_SKIN_PAD + r * VGRID_SKIN_PITCH;
            double l = level[r][c] / 15.0 * scale;
            int down = held[r][c] != 0;
            // key: grey silicone mixed towards warm white by its level
            double base = down ? 0.15 : 0.20;
            double rr = base + (1.0 - base) * l, gg = base + (0.94 - base) * l, bb = base + (0.82 - base) * l;
            double inset = down ? 1.5 : 0;
            rounded_rect(cr, x + inset, y + inset, k - 2 * inset, k - 2 * inset, 6);
            cairo_pattern_t *kp = cairo_pattern_create_linear(0, y, 0, y + k);
            cairo_pattern_add_color_stop_rgb(kp, 0, fmin(rr + 0.05, 1), fmin(gg + 0.05, 1), fmin(bb + 0.05, 1));
            cairo_pattern_add_color_stop_rgb(kp, 1, rr * 0.9, gg * 0.9, bb * 0.9);
            cairo_set_source(cr, kp);
            cairo_fill(cr);
            cairo_pattern_destroy(kp);
            // latched keys keep a ring
            if (held[r][c] & VGRID_HELD_LATCH) {
                rounded_rect(cr, x - 2.5, y - 2.5, k + 5, k + 5, 8);
                cairo_set_line_width(cr, 2);
                cairo_set_source_rgba(cr, 1.0, 0.69, 0.29, 0.9);
                cairo_stroke(cr);
            }
        }
    }
    cairo_restore(cr);
}
