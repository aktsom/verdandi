/*
 * device_skin.c: see device_skin.h
 */

#include <math.h>
#include <stddef.h>
#include <stdint.h>

#include "device_skin.h"
#ifdef NORNS_LINUX_DESKTOP
#include "../linux/box_palette.h"
#include "../linux/box_style.h"
#endif

typedef struct {
    double x, y;
} pt_t;

#ifdef NORNS_LINUX_DESKTOP
// the look of the box (box_palette.h): see skin_set_look
static int look_style = SKIN_STYLE_ALUMINIUM;
static int look_shown = 1; // the page buttons are shown (the right-click item)
static int look_muted = 0;  // for the hit test of the MUTE chip while the row is hidden
static box_rgb_t look_col[BOX_PARTS];
static int part_tinted[BOX_PARTS];
#endif

// the button row along the top: menu pages on the left, tools on the right
typedef struct {
    double x;
    const char *label;
} button_t;

#ifdef NORNS_LINUX_DESKTOP
// ---- the Linux window (docs/port/ui-plan.md section 1.6, arrangement A) ----
// the box and the window are as on the Mac (960 x 630 units). margins of 36 units on all four sides: the button row from x 36 to x 924 at y 36, the
// bezel's left edge at x 36 and its bottom edge 36 above the box's. the screen is 512 x 256 units: exactly 4 device pixels per screen pixel at scale 1.
// keys and encoders are 15 percent bigger than on the Mac. no OUT fader (MUTE is the last button of the row), no K1..E3 text
static const pt_t key_pos[3] = {{71.65, 188.33}, {655.65, 517.48}, {785.65, 517.48}};
static const pt_t enc_pos[3] = {{194.7, 188.33}, {745.35, 377.18}, {875.35, 377.18}};
static const double key_r = 35.65;
static const double enc_r = 43.7; // washer; the knob itself is 35.65
static const double bezel_x = 36, bezel_y = 300.667, bezel_w = 556, bezel_h = 293.333; // the screen 512 x 256 in it: margins of 22 and 18.67 (the Mac's proportions)
static const double bezel_pad = 14;
// pages MIX TAPE HOME PARAMS, then MIC GRID ARC KEYS, MAIDEN MANUAL, MUTE: three group gaps of 25.33 fill the row between x 36 and x 924
static const button_t buttons[] = {
    {36, "MIX"},       {112, "TAPE"},     {188, "HOME"},     {264, "PARAMS"}, // SKIN_PAGE1..4
    {359.3333, "MIC"}, {435.3333, "GRID"}, {511.3333, "ARC"}, {587.3333, "KEYS"}, // SKIN_MIC..KEYS
    {682.6667, "MAIDEN"}, {758.6667, "MANUAL"},                                  // SKIN_MAIDEN, MANUAL
    {854, "MUTE"},                                                               // SKIN_MUTE
};
static const double button_y = 36, button_w = 70, button_h = 40;
// sizes of the drawn parts (the Mac's 25, 23, 31, 25 and the well's inset 4, times 1.15)
#define KEY_CAP 28.75
#define KEY_CAP_DOWN 26.45
#define KEY_WELL_INSET 4.6
#define KNOB_R 35.65
#define KNOB_TOP 28.75
#else
// ---- the Mac window ----
// standard norns, in layout units
static const pt_t key_pos[3] = {{109, 252}, {594, 542}, {749, 542}};
static const pt_t enc_pos[3] = {{216, 252}, {672, 420}, {827, 420}};
static const double key_r = 31;
static const double enc_r = 38; // washer; the knob itself is 31
static const double bezel_x = 77, bezel_y = 356, bezel_w = 417, bezel_h = 220;
// the OUT fader and MUTE, right of E3
static const double fader_x = 913, fader_top = 196, fader_bottom = 486;
static const double fader_cap_w = 34, fader_cap_h = 18;
static const double mute_x = 886, mute_y = 520, mute_w = 54, mute_h = 34;
static const double bezel_pad = 14;
static const button_t buttons[] = {
    {77, "MIX"}, {153, "TAPE"}, {229, "HOME"}, {305, "PARAMS"}, // SKIN_PAGE1..4
    {398, "MIC"},
    {474, "GRID"},
    {550, "ARC"},
    {626, "KEYS"}, // SKIN_MIC..KEYS
    {719, "MAIDEN"},
    {795, "MANUAL"}, // SKIN_MAIDEN, MANUAL
};
static const double button_y = 70, button_w = 70, button_h = 40;
#define KEY_CAP 25
#define KEY_CAP_DOWN 23
#define KEY_WELL_INSET 4
#define KNOB_R 31
#define KNOB_TOP 25
#endif
#define NBUTTONS ((int)(sizeof buttons / sizeof buttons[0]))

// the knobs are endless encoders: no pointer, only the knurl moves. one detent turns it by
// a third of the knurl spacing, so it always visibly moves the right way
#define KNURLS 60
#define KNURL_STEP (2 * M_PI / KNURLS / 3)

#ifdef NORNS_LINUX_DESKTOP
void skin_set_look(int style, const char *box, const char *keys, const char *encoders, const char *buttons, const char *font) {
    const char *in[BOX_PARTS] = {box, keys, encoders, buttons, font};
    look_style = style == SKIN_STYLE_PIXEL ? SKIN_STYLE_PIXEL : SKIN_STYLE_ALUMINIUM;
    for (int i = 0; i < BOX_PARTS; i++) {
        box_rgb_t c;
        unsigned d = box_default_rgb[i];
        if (in[i] == NULL || !box_parse_hex(in[i], &c)) {
            c.r = (d >> 16) & 0xff;
            c.g = (d >> 8) & 0xff;
            c.b = d & 0xff;
        }
        look_col[i] = c;
        part_tinted[i] = ((unsigned)c.r << 16 | (unsigned)c.g << 8 | c.b) != d;
    }
    box_style_set_colours(look_col);
}

// while the window is being resized (docs/port/box-style-plan.md): the screen picture and the pixel box are placed with the cheap filter; the quality frame follows when the size settles
static int look_fast = 0;
void skin_set_fast(int fast) {
    look_fast = fast != 0;
    box_style_set_fast(fast);
}

void skin_set_pixel_look(int look) {
    box_style_set_variant(look);
}

void skin_set_buttons_shown(int shown) {
    look_shown = shown != 0;
}

int skin_buttons_shown(void) {
    return look_shown;
}

void skin_note_muted(int muted) {
    look_muted = muted != 0;
}

int skin_look_style(void) {
    return look_style;
}
#endif

void skin_geom(int w, int h, skin_geom_t *g) {
    g->w = w;
    g->h = h;
    double sx = (double)w / (SKIN_W + 2 * SKIN_MARGIN);
    double sy = (double)h / (SKIN_H + 2 * SKIN_MARGIN);
    g->s = sx < sy ? sx : sy;
    g->ox = (w - SKIN_W * g->s) / 2;
    g->oy = (h - SKIN_H * g->s) / 2;
#ifdef NORNS_LINUX_DESKTOP
    // the screen scales with the window: 512 x 256 units. a whole multiple of 128 x 64 when the scale is within 0.02 of one (crisp), else
    // an even width in between (the drawing then enlarges and filters, skin_draw_oled)
    double k = 4 * g->s;
    long r = lround(k);
    g->oled_w = (r >= 1 && fabs(k - r) <= 0.02) ? (int)(128 * r) : 2 * (int)lround(256 * g->s);
    if (g->oled_w < 128) {
        g->oled_w = 128;
    }
    g->oled_h = g->oled_w / 2;
    g->oled_px = r < 1 ? 1 : (int)r;
    g->oled_x = (int)lround(g->ox + (bezel_x + bezel_w / 2) * g->s - g->oled_w / 2.0);
    g->oled_y = (int)lround(g->oy + (bezel_y + bezel_h / 2) * g->s - g->oled_h / 2.0);
    return;
#endif
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
#ifdef NORNS_LINUX_DESKTOP
    if (look_style == SKIN_STYLE_PIXEL) {
        return box_style_hit(g, x, y, look_shown, look_muted);
    }
#endif
    pt_t p = to_units(g, x, y);
    for (int i = 0; i < NBUTTONS; i++) {
#ifdef NORNS_LINUX_DESKTOP
        // the row hidden: no button is there, except the MUTE chip while muted
        if (!look_shown && !(SKIN_PAGE1 + i == SKIN_MUTE && look_muted)) {
            continue;
        }
#endif
        if (p.x >= buttons[i].x - 3 && p.x <= buttons[i].x + button_w + 3 && p.y >= button_y - 3 &&
            p.y <= button_y + button_h + 3) {
            return SKIN_PAGE1 + i;
        }
    }
    for (int i = 0; i < 3; i++) {
        if (dist(p, key_pos[i]) <= key_r + 6) {
            return SKIN_K1 + i;
        }
        if (dist(p, enc_pos[i]) <= enc_r + 6) {
            return SKIN_E1 + i;
        }
    }
#ifndef NORNS_LINUX_DESKTOP
    if (fabs(p.x - fader_x) <= fader_cap_w / 2 + 6 && p.y >= fader_top - fader_cap_h && p.y <= fader_bottom + fader_cap_h) {
        return SKIN_FADER;
    }
    if (p.x >= mute_x - 3 && p.x <= mute_x + mute_w + 3 && p.y >= mute_y - 3 && p.y <= mute_y + mute_h + 3) {
        return SKIN_MUTE;
    }
#endif
    return SKIN_NONE;
}

#ifndef NORNS_LINUX_DESKTOP
double skin_fader_value(const skin_geom_t *g, double y) {
    double v = (fader_bottom - (y - g->oy) / g->s) / (fader_bottom - fader_top);
    return v < 0 ? 0 : v > 1 ? 1
                             : v;
}
#endif

int skin_oled_pixel(const skin_geom_t *g, double x, double y, int *ox, int *oy) {
#ifdef NORNS_LINUX_DESKTOP
    if (x < g->oled_x || y < g->oled_y || x >= g->oled_x + g->oled_w || y >= g->oled_y + g->oled_h) {
        return 0;
    }
    int px = (int)floor((x - g->oled_x) * 128 / g->oled_w), py = (int)floor((y - g->oled_y) * 64 / g->oled_h);
#else
    int px = (int)floor((x - g->oled_x) / g->oled_px), py = (int)floor((y - g->oled_y) / g->oled_px);
#endif
    if (px < 0 || px > 127 || py < 0 || py > 63) {
        return 0;
    }
    *ox = px;
    *oy = py;
    return 1;
}

int skin_nearest_enc(const skin_geom_t *g, double x, double y) {
#ifdef NORNS_LINUX_DESKTOP
    if (look_style == SKIN_STYLE_PIXEL) {
        return box_style_nearest_enc(g, x, y);
    }
#endif
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

#ifdef NORNS_LINUX_DESKTOP
// the five colours of the Linux box (docs/port/box-style-plan.md): a part whose colour is not its default is drawn with the original gradients remapped onto that colour (box_palette.c),
// a part at its default is drawn by the original code, byte for byte

static void stopt(cairo_pattern_t *p, double at, const char *rgb, double a, int part) {
    if (!part_tinted[part]) {
        stop(p, at, rgb, a);
        return;
    }
    unsigned v = 0;
    for (const char *c = rgb; *c; c++) {
        v = v * 16 + (unsigned)(*c <= '9' ? *c - '0' : (*c | 0x20) - 'a' + 10);
    }
    box_rgb_t t = box_tint_stop(v, part, look_col[part]);
    cairo_pattern_add_color_stop_rgba(p, at, t.r / 255.0, t.g / 255.0, t.b / 255.0, a);
}
#else
#define stopt(p, at, rgb, a, part) stop(p, at, rgb, a)
#endif

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
    stopt(p, 0, "dfe1e4", 1, BOX_PART_BOX);
    stopt(p, 1, "c4c7cb", 1, BOX_PART_BOX);
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

    // the whole window black, as the oled's own black: no frame around the pixels
    rounded_rect(cr, bezel_x, bezel_y, bezel_w, bezel_h, 7);
    hex(cr, "000000", 1);
    cairo_fill(cr);
}

#ifndef NORNS_LINUX_DESKTOP
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
#endif

static void draw_washer(cairo_t *cr, pt_t c) {
    circle(cr, c.x, c.y, enc_r);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, c.y - enc_r, 0, c.y + enc_r);
    stopt(p, 0, "a3a6ab", 1, BOX_PART_ENCODERS);
    stopt(p, 1, "d3d5d8", 1, BOX_PART_ENCODERS);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1);
    circle(cr, c.x, c.y, enc_r - 0.5);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.3);
    cairo_stroke(cr);
}

void skin_draw_static(cairo_t *cr, const skin_geom_t *g) {
#ifdef NORNS_LINUX_DESKTOP
    if (look_style == SKIN_STYLE_PIXEL) {
        box_style_draw_static(cr, g);
        return;
    }
#endif
    cairo_save(cr);
    hex(cr, "1a1a1c", 1);
    cairo_paint(cr);

    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    draw_box(cr, g);
    draw_bezel(cr);
#ifndef NORNS_LINUX_DESKTOP
    static const char *names[3][2] = {{"K1", "E1"}, {"K2", "E2"}, {"K3", "E3"}};
#endif
    for (int i = 0; i < 3; i++) {
        draw_washer(cr, enc_pos[i]);
        // key well
        circle(cr, key_pos[i].x, key_pos[i].y, key_r);
        cairo_pattern_t *p = cairo_pattern_create_linear(0, key_pos[i].y - key_r, 0, key_pos[i].y + key_r);
        stopt(p, 0, "8e9196", 1, BOX_PART_BOX);
        stopt(p, 1, "e3e5e8", 1, BOX_PART_BOX);
        cairo_set_source(cr, p);
        cairo_fill(cr);
        cairo_pattern_destroy(p);
        circle(cr, key_pos[i].x, key_pos[i].y, key_r - KEY_WELL_INSET);
        hex(cr, "161618", 1);
        cairo_fill(cr);

#ifndef NORNS_LINUX_DESKTOP
        draw_label(cr, key_pos[i], key_r, names[i][0]);
        draw_label(cr, enc_pos[i], enc_r, names[i][1]);
#endif
    }
    cairo_restore(cr);
}

static void draw_key(cairo_t *cr, pt_t c, int down, int hover) {
    double dy = down ? 2 : 0;
    double r = down ? KEY_CAP_DOWN : KEY_CAP;
    // cap; pressed it sinks into the well and loses its highlight
    circle(cr, c.x, c.y + dy, r);
    cairo_pattern_t *p = down ? cairo_pattern_create_radial(c.x, c.y + dy + 6, 2, c.x, c.y + dy, r)
                              : cairo_pattern_create_radial(c.x - 7, c.y - 9, 2, c.x, c.y, r);
    stopt(p, 0, down ? "2c2d30" : "5b5e63", 1, BOX_PART_KEYS);
    stopt(p, 1, down ? "0e0e10" : "26272a", 1, BOX_PART_KEYS);
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
    const double r = KNOB_R, top = KNOB_TOP;
    double a = ticks * KNURL_STEP;

    // shadow on the washer
    circle(cr, c.x + 2, c.y + 4, r + 1);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.28);
    cairo_fill(cr);

    // knurled side
    circle(cr, c.x, c.y, r);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, c.y - r, 0, c.y + r);
    stopt(p, 0, "f1f2f4", 1, BOX_PART_ENCODERS);
    stopt(p, 1, "8f9399", 1, BOX_PART_ENCODERS);
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
    stopt(p, 0, "fbfbfc", 1, BOX_PART_ENCODERS);
    stopt(p, 1, "c0c3c8", 1, BOX_PART_ENCODERS);
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

// a lit (amber) or dark led
static void draw_led(cairo_t *cr, double x, double y, int on) {
    if (on) {
        cairo_pattern_t *p = cairo_pattern_create_radial(x, y, 0, x, y, 11);
        stop(p, 0, "ffb04a", 0.55);
        stop(p, 1, "ffb04a", 0);
        cairo_set_source(cr, p);
        circle(cr, x, y, 11);
        cairo_fill(cr);
        cairo_pattern_destroy(p);
    }
    circle(cr, x, y, 3.6);
    hex(cr, on ? "ffc46b" : "3b3c40", 1);
    cairo_fill(cr);
}

// "opens elsewhere": a small arrow up and right
static void draw_out_arrow(cairo_t *cr, double x, double y) {
    cairo_set_line_width(cr, 1.6);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_move_to(cr, x - 3.5, y + 3.5);
    cairo_line_to(cr, x + 3.5, y - 3.5);
    cairo_move_to(cr, x - 1, y - 3.5);
    cairo_line_to(cr, x + 3.5, y - 3.5);
    cairo_line_to(cr, x + 3.5, y + 1);
    hex(cr, "8d9096", 1);
    cairo_stroke(cr);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
}

static void draw_button(cairo_t *cr, int i, const skin_state_t *st) {
    const button_t *b = &buttons[i];
    int id = SKIN_PAGE1 + i;
    int down = st->button_down == id;
    int lit = (id <= SKIN_PAGE4 && st->page == i + 1) || (id == SKIN_GRID && st->grid_open) ||
              (id == SKIN_ARC && st->arc_open) || (id == SKIN_KEYS && st->keys_open) ||
              (id == SKIN_MIC && st->input != SKIN_INPUT_OFF)
#ifdef NORNS_LINUX_DESKTOP
              || (id == SKIN_MUTE && st->out_muted)
#endif
        ;
    double x = b->x, y = button_y, dy = down ? 1.2 : 0;

    // well
    rounded_rect(cr, x - 2.5, y - 2.5, button_w + 5, button_h + 5, 10);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, y - 2.5, 0, y + button_h + 2.5);
    stopt(p, 0, "8e9196", 1, BOX_PART_BOX);
    stopt(p, 1, "e3e5e8", 1, BOX_PART_BOX);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);

    // face
    rounded_rect(cr, x, y + dy, button_w, button_h, 8);
    p = cairo_pattern_create_linear(0, y + dy, 0, y + dy + button_h);
    stopt(p, 0, down ? "232427" : "3d3f43", 1, BOX_PART_BUTTONS);
    stopt(p, 1, down ? "17181a" : "232427", 1, BOX_PART_BUTTONS);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_set_line_width(cr, 1);
    rounded_rect(cr, x + 0.5, y + dy + 0.5, button_w - 1, button_h - 1, 7.5);
    p = cairo_pattern_create_linear(0, y + dy, 0, y + dy + button_h);
    stop(p, 0, "ffffff", down ? 0.06 : 0.22);
    stop(p, 0.5, "ffffff", 0);
    cairo_set_source(cr, p);
    cairo_stroke(cr);
    cairo_pattern_destroy(p);
    if (st->hover == id && !down) {
        rounded_rect(cr, x, y, button_w, button_h, 8);
        cairo_set_source_rgba(cr, 1, 1, 1, 0.07);
        cairo_fill(cr);
    }

    // led or arrow on the left, label in the rest
    double mid = y + dy + button_h / 2;
#ifdef NORNS_LINUX_DESKTOP
    if (id <= SKIN_KEYS || id == SKIN_MUTE) {
#else
    if (id <= SKIN_KEYS) {
#endif
        draw_led(cr, x + 12, mid, lit);
    } else {
        draw_out_arrow(cr, x + 12, mid);
    }
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    double area = x + 20, area_w = button_w - 23;
    static const char *input_label[] = {"OFF", "MIC", "SYS", "APP"};
    const char *label = b->label;
    if (id == SKIN_MIC && st->input >= SKIN_INPUT_OFF && st->input <= SKIN_INPUT_APP) {
        label = input_label[st->input];
    }
    // long labels get a smaller size rather than touching the edge
    double size = 12;
    cairo_text_extents_t te;
    for (;;) {
        cairo_set_font_size(cr, size);
        cairo_text_extents(cr, label, &te);
        if (te.width <= area_w - 2 || size <= 8) {
            break;
        }
        size -= 0.5;
    }
    cairo_move_to(cr, area + (area_w - te.width) / 2 - te.x_bearing, mid - te.height / 2 - te.y_bearing);
#ifdef NORNS_LINUX_DESKTOP
    if (part_tinted[BOX_PART_FONT]) {
        cairo_set_source_rgb(cr, look_col[BOX_PART_FONT].r / 255.0, look_col[BOX_PART_FONT].g / 255.0, look_col[BOX_PART_FONT].b / 255.0);
    } else
#endif
    hex(cr, lit ? "ffffff" : "c3c6cb", 1);
    cairo_show_text(cr, label);
}

// a message under the buttons, right of E1: a dark pill like a notification
static void draw_toast(cairo_t *cr, const char *text, int recording) {
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 14);
    cairo_text_extents_t te;
    cairo_text_extents(cr, text, &te);
    double dot = recording ? 22 : 0;
    double w = te.x_advance + 36 + dot, h = 36;
    double right = SKIN_W - 95, cy = 175;
    if (w > right - 300) {
        w = right - 300;
    }
    double x = right - w, y = cy - h / 2;
    rounded_rect(cr, x, y + 2, w, h, h / 2);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
    cairo_fill(cr);
    rounded_rect(cr, x, y, w, h, h / 2);
    hex(cr, "1d1e21", 0.92);
    cairo_fill(cr);
    if (recording) {
        circle(cr, x + 22, cy, 6);
        hex(cr, "ff453a", 1);
        cairo_fill(cr);
    }
    cairo_save(cr);
    rounded_rect(cr, x + 12, y, w - 24, h, 0);
    cairo_clip(cr);
    cairo_move_to(cr, x + 18 + dot - te.x_bearing, cy - te.height / 2 - te.y_bearing);
    hex(cr, "f2f3f5", 1);
    cairo_show_text(cr, text);
    cairo_restore(cr);
}

#ifndef NORNS_LINUX_DESKTOP
// the OUT fader: a slot, the level lit up to the cap, the cap; MUTE under it
static void draw_fader(cairo_t *cr, const skin_state_t *st) {
    double v = st->out_level < 0 ? 0 : st->out_level > 1 ? 1
                                                         : st->out_level;
    double cy = fader_bottom - v * (fader_bottom - fader_top);
    int hover = st->hover == SKIN_FADER;

    // label, engraved like the others
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 15);
    cairo_text_extents_t te;
    cairo_text_extents(cr, "OUT", &te);
    double lx = fader_x - te.width / 2 - te.x_bearing, ly = fader_top - fader_cap_h / 2 - 12;
    cairo_move_to(cr, lx + 0.6, ly + 1.4);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.55);
    cairo_show_text(cr, "OUT");
    cairo_move_to(cr, lx, ly);
    hex(cr, "4a4d52", 0.75);
    cairo_show_text(cr, "OUT");

    // scale marks
    cairo_set_line_width(cr, 1);
    for (int i = 0; i <= 8; i++) {
        double y = fader_top + i * (fader_bottom - fader_top) / 8;
        double w = i % 4 == 0 ? 9 : 5;
        cairo_move_to(cr, fader_x - 11 - w, y + 0.5);
        cairo_line_to(cr, fader_x - 11, y + 0.5);
        cairo_move_to(cr, fader_x + 11, y + 0.5);
        cairo_line_to(cr, fader_x + 11 + w, y + 0.5);
    }
    hex(cr, "7d8086", 0.8);
    cairo_stroke(cr);

    // slot
    rounded_rect(cr, fader_x - 4, fader_top - 3, 8, fader_bottom - fader_top + 6, 4);
    hex(cr, "1a1b1d", 1);
    cairo_fill(cr);
    // the level, unless muted
    if (!st->out_muted && v > 0) {
        rounded_rect(cr, fader_x - 2, cy, 4, fader_bottom - cy + 1, 2);
        hex(cr, "ffb04a", 0.85);
        cairo_fill(cr);
    }

    // cap
    double x = fader_x - fader_cap_w / 2, y = cy - fader_cap_h / 2;
    rounded_rect(cr, x, y + 2, fader_cap_w, fader_cap_h, 4);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.25);
    cairo_fill(cr);
    rounded_rect(cr, x, y, fader_cap_w, fader_cap_h, 4);
    cairo_pattern_t *p = cairo_pattern_create_linear(0, y, 0, y + fader_cap_h);
    stop(p, 0, "5b5e63", 1);
    stop(p, 1, "26272a", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    cairo_move_to(cr, x + 5, cy + 0.5);
    cairo_line_to(cr, x + fader_cap_w - 5, cy + 0.5);
    hex(cr, "c3c6cb", 0.9);
    cairo_stroke(cr);
    if (hover) {
        rounded_rect(cr, x, y, fader_cap_w, fader_cap_h, 4);
        cairo_set_source_rgba(cr, 1, 1, 1, 0.08);
        cairo_fill(cr);
    }

    // MUTE: a small button, lit while muted
    int down = st->button_down == SKIN_MUTE;
    double dy = down ? 1.2 : 0;
    rounded_rect(cr, mute_x - 2.5, mute_y - 2.5, mute_w + 5, mute_h + 5, 9);
    p = cairo_pattern_create_linear(0, mute_y - 2.5, 0, mute_y + mute_h + 2.5);
    stop(p, 0, "8e9196", 1);
    stop(p, 1, "e3e5e8", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    rounded_rect(cr, mute_x, mute_y + dy, mute_w, mute_h, 7);
    p = cairo_pattern_create_linear(0, mute_y + dy, 0, mute_y + dy + mute_h);
    stop(p, 0, down ? "232427" : "3d3f43", 1);
    stop(p, 1, down ? "17181a" : "232427", 1);
    cairo_set_source(cr, p);
    cairo_fill(cr);
    cairo_pattern_destroy(p);
    if (st->hover == SKIN_MUTE && !down) {
        rounded_rect(cr, mute_x, mute_y, mute_w, mute_h, 7);
        cairo_set_source_rgba(cr, 1, 1, 1, 0.07);
        cairo_fill(cr);
    }
    double mid = mute_y + dy + mute_h / 2;
    draw_led(cr, mute_x + 10, mid, st->out_muted);
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 10);
    cairo_text_extents(cr, "MUTE", &te);
    double area = mute_x + 17, area_w = mute_w - 19;
    cairo_move_to(cr, area + (area_w - te.width) / 2 - te.x_bearing, mid - te.height / 2 - te.y_bearing);
    hex(cr, st->out_muted ? "ffffff" : "c3c6cb", 1);
    cairo_show_text(cr, "MUTE");
}
#endif

#ifdef NORNS_LINUX_DESKTOP
int skin_in_bezel(const skin_geom_t *g, double x, double y) {
    pt_t p = to_units(g, x, y);
    return p.x >= bezel_x && p.x <= bezel_x + bezel_w && p.y >= bezel_y && p.y <= bezel_y + bezel_h;
}

void skin_draw_placeholder(cairo_t *cr, const skin_geom_t *g, int hover) {
    cairo_save(cr);
    cairo_rectangle(cr, g->oled_x, g->oled_y, g->oled_w, g->oled_h);
    cairo_clip(cr);
    hex(cr, hover ? "1c1d21" : "16171a", 1);
    cairo_paint(cr);
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    double size = 17 * g->s;
    static const char *line[2] = {"The screen is in its own window.", "Click here or press F9 to bring it back."};
    cairo_set_font_size(cr, size);
    // a smaller size rather than text that touches the edge, for the longer line
    cairo_text_extents_t te;
    for (;;) {
        cairo_text_extents(cr, line[1], &te);
        if (te.width <= g->oled_w - 24 * g->s || size <= 8) {
            break;
        }
        size -= 0.5;
        cairo_set_font_size(cr, size);
    }
    double cx = g->oled_x + g->oled_w / 2.0, cy = g->oled_y + g->oled_h / 2.0;
    hex(cr, "aaacb2", 1);
    for (int i = 0; i < 2; i++) {
        cairo_text_extents(cr, line[i], &te);
        cairo_move_to(cr, cx - te.width / 2 - te.x_bearing, cy + (i == 0 ? -0.35 : 1.15) * size - te.height / 2 - te.y_bearing);
        cairo_show_text(cr, line[i]);
    }
    cairo_restore(cr);
}
#endif

void skin_draw_controls(cairo_t *cr, const skin_geom_t *g, const skin_state_t *st) {
#ifdef NORNS_LINUX_DESKTOP
    look_muted = st->out_muted != 0;
    if (look_style == SKIN_STYLE_PIXEL) {
        box_style_draw_controls(cr, g, st, look_shown);
        return;
    }
#endif
    cairo_save(cr);
    cairo_translate(cr, g->ox, g->oy);
    cairo_scale(cr, g->s, g->s);
    for (int i = 0; i < NBUTTONS; i++) {
#ifdef NORNS_LINUX_DESKTOP
        if (!look_shown && !(SKIN_PAGE1 + i == SKIN_MUTE && st->out_muted)) {
            continue; // the row is hidden: only the MUTE chip stays while muted
        }
#endif
        draw_button(cr, i, st);
    }
    if (st->toast != NULL && st->toast[0] != '\0') {
        draw_toast(cr, st->toast, st->recording);
    }
    for (int i = 0; i < 3; i++) {
        draw_key(cr, key_pos[i], st->key_down[i], st->hover == SKIN_K1 + i);
        draw_knob(cr, enc_pos[i], st->enc_ticks[i], st->hover == SKIN_E1 + i);
    }
#ifndef NORNS_LINUX_DESKTOP
    draw_fader(cr, st);
#endif
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
    hex(cr, "000000", 1);
    cairo_paint(cr);

#ifdef NORNS_LINUX_DESKTOP
    if (g->oled_w == 128 * g->oled_px) {
        cairo_save(cr);
        cairo_translate(cr, g->oled_x, g->oled_y);
        cairo_scale(cr, g->oled_px, g->oled_px);
        cairo_set_source_surface(cr, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
        cairo_rectangle(cr, 0, 0, 128, 64);
        cairo_fill(cr);
        cairo_restore(cr);
    } else if (look_fast) {
        // the window is being resized: the picture straight onto the window with the cheap filter (some screen pixels a device pixel wider); the quality frame follows when the size settles
        cairo_save(cr);
        cairo_translate(cr, g->oled_x, g->oled_y);
        cairo_scale(cr, (double)g->oled_w / 128, (double)g->oled_h / 64);
        cairo_set_source_surface(cr, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_FAST);
        cairo_rectangle(cr, 0, 0, 128, 64);
        cairo_fill(cr);
        cairo_restore(cr);
    } else {
        // between whole multiples: enlarge to a whole multiple with nearest (no blur inside a pixel), then scale down with the best filter
        int m = (int)ceil(g->oled_w / 128.0);
        cairo_surface_t *big = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128 * m, 64 * m);
        cairo_t *bc = cairo_create(big);
        cairo_scale(bc, m, m);
        cairo_set_source_surface(bc, oled, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(bc), CAIRO_FILTER_NEAREST);
        cairo_paint(bc);
        cairo_destroy(bc);
        cairo_save(cr);
        cairo_translate(cr, g->oled_x, g->oled_y);
        cairo_scale(cr, (double)g->oled_w / (128 * m), (double)g->oled_h / (64 * m));
        cairo_set_source_surface(cr, big, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
        cairo_rectangle(cr, 0, 0, 128 * m, 64 * m);
        cairo_fill(cr);
        cairo_restore(cr);
        cairo_surface_destroy(big);
    }
#else
    cairo_save(cr);
    cairo_translate(cr, g->oled_x, g->oled_y);
    cairo_scale(cr, g->oled_px, g->oled_px);
    cairo_set_source_surface(cr, oled, 0, 0);
    cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
    cairo_rectangle(cr, 0, 0, 128, 64);
    cairo_fill(cr);
    cairo_restore(cr);
#endif
    cairo_restore(cr);
}
