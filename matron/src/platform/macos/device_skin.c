/*
 * device_skin.c: see device_skin.h
 */

#include <math.h>
#include <stdint.h>

#include "device_skin.h"

typedef struct {
    double x, y;
} pt_t;

// standard norns, in layout units
static const pt_t key_pos[3] = {{109, 252}, {594, 542}, {749, 542}};
static const pt_t enc_pos[3] = {{216, 252}, {672, 420}, {827, 420}};
static const double key_r = 31;
static const double enc_r = 38; // washer; the knob itself is 31
static const double bezel_x = 77, bezel_y = 356, bezel_w = 417, bezel_h = 220;
static const double bezel_pad = 14;

// the knobs are endless encoders: no pointer, only the knurl moves. one detent turns it by
// a third of the knurl spacing, so it always visibly moves the right way
#define KNURLS 60
#define KNURL_STEP (2 * M_PI / KNURLS / 3)

void skin_geom(int w, int h, skin_geom_t *g) {
    g->w = w;
    g->h = h;
    double sx = (double)w / (SKIN_W + 2 * SKIN_MARGIN);
    double sy = (double)h / (SKIN_H + 2 * SKIN_MARGIN);
    g->s = sx < sy ? sx : sy;
    g->ox = (w - SKIN_W * g->s) / 2;
    g->oy = (h - SKIN_H * g->s) / 2;
    double fit_w = (bezel_w - 2 * bezel_pad) * g->s / 128;
    double fit_h = (bezel_h - 2 * bezel_pad) * g->s / 64;
    int px = (int)floor(fit_w < fit_h ? fit_w : fit_h);
    g->oled_px = px < 1 ? 1 : px;
    g->oled_x = (int)lround(g->ox + (bezel_x + bezel_w / 2) * g->s - 64 * g->oled_px);
    g->oled_y = (int)lround(g->oy + (bezel_y + bezel_h / 2) * g->s - 32 * g->oled_px);
}

static pt_t to_units(const skin_geom_t *g, double x, double y) {
    pt_t p = {(x - g->ox) / g->s, (y - g->oy) / g->s};
    return p;
}

static double dist(pt_t a, pt_t b) {
    return hypot(a.x - b.x, a.y - b.y);
}

int skin_hit(const skin_geom_t *g, double x, double y) {
    pt_t p = to_units(g, x, y);
    for (int i = 0; i < 3; i++) {
        if (dist(p, key_pos[i]) <= key_r + 6) {
            return SKIN_K1 + i;
        }
        if (dist(p, enc_pos[i]) <= enc_r + 6) {
            return SKIN_E1 + i;
        }
    }
    return SKIN_NONE;
}

int skin_nearest_enc(const skin_geom_t *g, double x, double y) {
    pt_t p = to_units(g, x, y);
    int best = 0;
    for (int i = 1; i < 3; i++) {
        if (dist(p, enc_pos[i]) < dist(p, enc_pos[best])) {
            best = i;
        }
    }
    return best + 1;
}

static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

static void circle(cairo_t *cr, double x, double y, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x, y, r, 0, 2 * M_PI);
}

static void hex(cairo_t *cr, const char *rgb, double a) {
    unsigned v = 0;
    for (const char *c = rgb; *c; c++) {
        v = v * 16 + (unsigned)(*c <= '9' ? *c - '0' : (*c | 0x20) - 'a' + 10);
    }
    cairo_set_source_rgba(cr, ((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0, a);
}

static void stop(cairo_pattern_t *p, double at, const char *rgb, double a) {
    unsigned v = 0;
    for (const char *c = rgb; *c; c++) {
        v = v * 16 + (unsigned)(*c <= '9' ? *c - '0' : (*c | 0x20) - 'a' + 10);
    }
    cairo_pattern_add_color_stop_rgba(p, at, ((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0,
                                      a);
}

// small deterministic noise for the brushed finish
static uint32_t lcg(uint32_t *s) {
    *s = *s * 1664525u + 1013904223u;
    return *s >> 8;
}

static void draw_box(cairo_t *cr, const skin_geom_t *g) {
    const double r = 22;

    // soft shadow under the box
    for (int i = 10; i >= 1; i--) {
        rounded_rect(cr, -i * 0.9, -i * 0.6 + 6, SKIN_W + i * 1.8, SKIN_H + i * 1.8, r + i);
        cairo_set_source_rgba(cr, 0, 0, 0, 0.045);
        cairo_fill(cr);
    }

    rounded_rect(cr, 0, 0, SKIN_W, SKIN_H, r);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, 0, 0, SKIN_H);
    stop(p, 0, "dfe1e4", 1);
    stop(p, 1, "c4c7cb", 1);
    cairo_set_source(cr, p);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(p);

    // brushed aluminium: one faint streak per device pixel row
    cairo_save(cr);
    cairo_clip(cr);
    cairo_identity_matrix(cr);
    uint32_t seed = 0x6e6f726e;
    int y0 = (int)floor(g->oy), y1 = (int)ceil(g->oy + SKIN_H * g->s);
    double x0 = g->ox, x1 = g->ox + SKIN_W * g->s;
    cairo_set_line_width(cr, 1);
    for (int y = y0; y < y1; y++) {
        double a = (lcg(&seed) % 1000) / 1000.0 * 0.07;
        if (lcg(&seed) & 1) {
            cairo_set_source_rgba(cr, 1, 1, 1, a);
        } else {
            cairo_set_source_rgba(cr, 0, 0, 0, a * 0.6);
        }
        cairo_move_to(cr, x0, y + 0.5);
        cairo_line_to(cr, x1, y + 0.5);
        cairo_stroke(cr);
    }
    cairo_restore(cr);

    // edges: light from above
    cairo_set_line_width(cr, 1.5);
    rounded_rect(cr, 0.75, 0.75, SKIN_W - 1.5, SKIN_H - 1.5, r - 0.75);
    p = cairo_pattern_create_linear(0, 0, 0, SKIN_H);
    stop(p, 0, "ffffff", 0.9);
    stop(p, 0.5, "ffffff", 0.15);
    stop(p, 1, "000000", 0.35);
    cairo_set_source(cr, p);
    cairo_stroke(cr);
    cairo_pattern_destroy(p);
}

static void draw_bezel(cairo_t *cr) {
    // the screen sits in a recess: dark lip above, light lip below
    rounded_rect(cr, bezel_x - 3, bezel_y - 3, bezel_w + 6, bezel_h + 6, 9);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, bezel_y - 3, 0, bezel_y + bezel_h + 3);
    stop(p, 0, "000000", 0.45);
    stop(p, 1, "ffffff", 0.85);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);

    rounded_rect(cr, bezel_x, bezel_y, bezel_w, bezel_h, 7);
    hex(cr, "0b0b0c", 1);
    cairo_fill(cr);
}

static void draw_glass(cairo_t *cr) {
    // faint reflection over the screen
    rounded_rect(cr, bezel_x, bezel_y, bezel_w, bezel_h, 7);
    cairo_pattern_t *p = cairo_pattern_create_linear(bezel_x, bezel_y, bezel_x + bezel_w * 0.6, bezel_y + bezel_h);
    stop(p, 0, "ffffff", 0.07);
    stop(p, 0.45, "ffffff", 0.015);
    stop(p, 0.46, "ffffff", 0);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
}

static void draw_label(cairo_t *cr, pt_t c, double r, const char *text) {
    cairo_save(cr);
    double d = r + 5;
    cairo_translate(cr, c.x + d * 0.70, c.y + d * 0.70);
    cairo_rotate(cr, M_PI / 4);
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 17);
    // engraved: highlight below, dark on top
    cairo_move_to(cr, 0.6, 1.4);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.55);
    cairo_show_text(cr, text);
    cairo_move_to(cr, 0, 0);
    hex(cr, "4a4d52", 0.75);
    cairo_show_text(cr, text);
    cairo_restore(cr);
}

static void draw_washer(cairo_t *cr, pt_t c) {
    circle(cr, c.x, c.y, enc_r);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, c.y - enc_r, 0, c.y + enc_r);
    stop(p, 0, "a3a6ab", 1);
    stop(p, 1, "d3d5d8", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1);
    circle(cr, c.x, c.y, enc_r - 0.5);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.3);
    cairo_stroke(cr);
}

void skin_draw_static(cairo_t *cr, const skin_geom_t *g) {
    cairo_save(cr);
    hex(cr, "1a1a1c", 1);
    cairo_paint(cr);

    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    draw_box(cr, g);
    draw_bezel(cr);
    static const char *names[3][2] = {{"K1", "E1"}, {"K2", "E2"}, {"K3", "E3"}};
    for (int i = 0; i < 3; i++) {
        draw_washer(cr, enc_pos[i]);
        // key well
        circle(cr, key_pos[i].x, key_pos[i].y, key_r);
        cairo_pattern_t *p = cairo_pattern_create_linear(0, key_pos[i].y - key_r, 0, key_pos[i].y + key_r);
        stop(p, 0, "8e9196", 1);
        stop(p, 1, "e3e5e8", 1);
        cairo_set_source(cr, p);
        cairo_fill(cr);
        cairo_pattern_destroy(p);
        circle(cr, key_pos[i].x, key_pos[i].y, key_r - 4);
        hex(cr, "161618", 1);
        cairo_fill(cr);

        draw_label(cr, key_pos[i], key_r, names[i][0]);
        draw_label(cr, enc_pos[i], enc_r, names[i][1]);
    }
    cairo_restore(cr);
}

static void draw_key(cairo_t *cr, pt_t c, int down, int hover) {
    double dy = down ? 2 : 0;
    double r = down ? 23 : 25;
    // cap; pressed it sinks into the well and loses its highlight
    circle(cr, c.x, c.y + dy, r);
    cairo_pattern_t *p = down ? cairo_pattern_create_radial(c.x, c.y + dy + 6, 2, c.x, c.y + dy, r)
                              : cairo_pattern_create_radial(c.x - 7, c.y - 9, 2, c.x, c.y, r);
    stop(p, 0, down ? "2c2d30" : "5b5e63", 1);
    stop(p, 1, down ? "0e0e10" : "26272a", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    // rim light
    cairo_set_line_width(cr, 1.2);
    circle(cr, c.x, c.y + dy, r - 0.6);
    p = cairo_pattern_create_linear(0, c.y + dy - r, 0, c.y + dy + r);
    if (down) {
        stop(p, 0, "000000", 0.6);
        stop(p, 1, "ffffff", 0.10);
    } else {
        stop(p, 0, "ffffff", 0.28);
        stop(p, 0.6, "ffffff", 0);
    }
    cairo_set_source(cr, p);
    cairo_stroke(cr);
    cairo_pattern_destroy(p);
    if (hover && !down) {
        circle(cr, c.x, c.y, r);
        cairo_set_source_rgba(cr, 1, 1, 1, 0.06);
        cairo_fill(cr);
    }
}

static void draw_knob(cairo_t *cr, pt_t c, int ticks, int hover) {
    const double r = 31, top = 25;
    double a = ticks * KNURL_STEP;

    // shadow on the washer
    circle(cr, c.x + 2, c.y + 4, r + 1);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.28);
    cairo_fill(cr);

    // knurled side
    circle(cr, c.x, c.y, r);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, c.y - r, 0, c.y + r);
    stop(p, 0, "f1f2f4", 1);
    stop(p, 1, "8f9399", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1.1);
    for (int i = 0; i < KNURLS; i++) {
        double t = a + i * (2 * M_PI / KNURLS);
        cairo_move_to(cr, c.x + cos(t) * (top + 1.5), c.y + sin(t) * (top + 1.5));
        cairo_line_to(cr, c.x + cos(t) * (r - 0.5), c.y + sin(t) * (r - 0.5));
    }
    cairo_set_source_rgba(cr, 0, 0, 0, 0.16);
    cairo_stroke(cr);

    // top face
    circle(cr, c.x, c.y, top);
    p = cairo_pattern_create_radial(c.x - 8, c.y - 10, 1, c.x, c.y, top + 4);
    stop(p, 0, "fbfbfc", 1);
    stop(p, 1, "c0c3c8", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1);
    circle(cr, c.x, c.y, top);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
    cairo_stroke(cr);

    if (hover) {
        circle(cr, c.x, c.y, r);
        cairo_set_source_rgba(cr, 1, 1, 1, 0.12);
        cairo_fill(cr);
    }
}

void skin_draw_controls(cairo_t *cr, const skin_geom_t *g, const skin_state_t *st) {
    cairo_save(cr);
    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    for (int i = 0; i < 3; i++) {
        draw_key(cr, key_pos[i], st->key_down[i], st->hover == SKIN_K1 + i);
        draw_knob(cr, enc_pos[i], st->enc_ticks[i], st->hover == SKIN_E1 + i);
    }
    cairo_restore(cr);
}

void skin_draw_oled(cairo_t *cr, const skin_geom_t *g, cairo_surface_t *oled) {
    cairo_save(cr);
    // bezel interior, in device pixels, so the oled can be redrawn on its own
    cairo_save(cr);
    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    rounded_rect(cr, bezel_x, bezel_y, bezel_w, bezel_h, 7);
    cairo_restore(cr);
    cairo_clip(cr);
    hex(cr, "0b0b0c", 1);
    cairo_paint(cr);

    cairo_save(cr);
    cairo_translate(cr, g->oled_x, g->oled_y);
    cairo_scale(cr, g->oled_px, g->oled_px);
    cairo_set_source_surface(cr, oled, 0, 0);
    cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
    cairo_rectangle(cr, 0, 0, 128, 64);
    cairo_fill(cr);
    cairo_restore(cr);

    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    draw_glass(cr);
    cairo_restore(cr);
}
