/*
 * box_style.c: see box_style.h
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include "box_style.h"

// ---------------------------------------------------------------- the layout table (layout units; docs/port/box-style-plan.md 2.2)
typedef struct {
    int id;
    double cx, cy, hw, hh;
    int shape; // 'q' rounded square, 'c' circle, 'r' rectangle
} ctl_t;

#define KEY_HALF 56   // keys: 112 units square
#define KEY_RADIUS 5  // blocks (the corner is a quarter pixel circle)
#define ENC_RADIUS 20 // blocks: 80 units across
#define BTN_W 70
#define BTN_H 40
#define BTN_Y 36
#define BTN_SLOP 2 // units: the hit area is this much bigger than what is drawn, on every side

static const ctl_t ctls[] = {
    {SKIN_K1, 100, 188, KEY_HALF, KEY_HALF, 'q'},
    {SKIN_K1 + 1, 734, 530, KEY_HALF, KEY_HALF, 'q'},
    {SKIN_K1 + 2, 864, 530, KEY_HALF, KEY_HALF, 'q'},
    {SKIN_E1, 240, 188, 40, 40, 'c'},
    {SKIN_E1 + 1, 734, 376, 40, 40, 'c'},
    {SKIN_E1 + 2, 864, 376, 40, 40, 'c'},
};
#define NCTL ((int)(sizeof ctls / sizeof ctls[0]))

// the button row: the aluminium style's positions, 70 x 40 units
static const struct {
    double x;
    const char *label;
} buttons[] = {
    {36, "MIX"},        {112, "TAPE"},      {188, "HOME"},     {264, "PARAMS"},     // SKIN_PAGE1..4
    {359.3333, "MIC"},  {435.3333, "GRID"}, {511.3333, "ARC"}, {587.3333, "KEYS"},  // SKIN_MIC..KEYS
    {682.6667, "MAIDEN"}, {758.6667, "MANUAL"},                                     // SKIN_MAIDEN, MANUAL
    {854, "MUTE"},                                                                  // SKIN_MUTE
};
#define NBUTTONS ((int)(sizeof buttons / sizeof buttons[0]))

int box_style_control_rect(int control, double *x0, double *y0, double *x1, double *y1) {
    for (int i = 0; i < NCTL; i++) {
        if (ctls[i].id == control) {
            *x0 = ctls[i].cx - ctls[i].hw;
            *y0 = ctls[i].cy - ctls[i].hh;
            *x1 = ctls[i].cx + ctls[i].hw;
            *y1 = ctls[i].cy + ctls[i].hh;
            return 1;
        }
    }
    int b = control - SKIN_PAGE1;
    if (b >= 0 && b < NBUTTONS && control >= SKIN_PAGE1 && (control <= SKIN_MAIDEN + 1 || control == SKIN_MUTE)) {
        *x0 = buttons[b].x;
        *y0 = BTN_Y;
        *x1 = buttons[b].x + BTN_W;
        *y1 = BTN_Y + BTN_H;
        return 1;
    }
    return 0;
}

// ---------------------------------------------------------------- caches (docs/port/box-style-plan.md, "Scaling the window")
// the block images do not depend on the window size: the static one only on the colours, the controls one only on the state. they are drawn once and kept; resizing the window only places them (and the
// enlarged copies that the in-between sizes need are kept too). measured before: 86 ms for the box and 63 ms for the controls per frame at the sizes of a drag, now only the placing
#define MAX_M 8
static uint32_t *blk_static = NULL, *blk_ctl = NULL;
static int static_ok = 0, ctl_ok = 0;
static cairo_surface_t *big_static[MAX_M + 1], *big_ctl[MAX_M + 1];
static int fast_mode = 0; // while the window is being resized: placing is cheap (no enlarging, no filter); the quality frame follows when the size settles

typedef struct {
    int key_down[3], enc_ticks[3], hover, page, grid_open, arc_open, keys_open, input, button_down, recording, out_muted, shown;
    char toast[160];
} ctl_key_t;
static ctl_key_t ctl_key;

static void drop_big(cairo_surface_t **set) {
    for (int i = 0; i <= MAX_M; i++) {
        if (set[i] != NULL) {
            cairo_surface_destroy(set[i]);
            set[i] = NULL;
        }
    }
}

static void invalidate_all(void) {
    static_ok = 0;
    ctl_ok = 0;
    drop_big(big_static);
    drop_big(big_ctl);
}

void box_style_set_fast(int fast) {
    fast_mode = fast != 0;
}

// ---------------------------------------------------------------- the palette in use
typedef struct {
    box_rgb_t base, dark, darker, light;
} shades_t;

static shades_t sh[BOX_PARTS];
static int colours_set = 0;

static void ensure_colours(void) {
    if (colours_set) {
        return;
    }
    box_rgb_t c[BOX_PARTS];
    for (int i = 0; i < BOX_PARTS; i++) {
        unsigned d = box_default_rgb[i];
        c[i].r = (d >> 16) & 0xff;
        c[i].g = (d >> 8) & 0xff;
        c[i].b = d & 0xff;
    }
    box_style_set_colours(c);
}

void box_style_set_colours(const box_rgb_t colours[BOX_PARTS]) {
    for (int i = 0; i < BOX_PARTS; i++) {
        sh[i].base = colours[i];
        sh[i].dark = box_dark(colours[i]);
        sh[i].darker = box_darker(colours[i]);
        sh[i].light = box_light(colours[i]);
    }
    colours_set = 1;
    invalidate_all();
}

box_rgb_t box_style_surround(void) {
    ensure_colours();
    return sh[BOX_PART_BOX].darker;
}

static uint32_t argb(box_rgb_t c) {
    return 0xff000000u | ((uint32_t)c.r << 16) | ((uint32_t)c.g << 8) | c.b;
}

// ---------------------------------------------------------------- pixels
static void put(uint32_t *px, int x, int y, uint32_t c) {
    if (x >= 0 && y >= 0 && x < BS_W && y < BS_H) {
        px[y * BS_W + x] = c;
    }
}

static void fill_rect(uint32_t *px, int x0, int y0, int x1, int y1, uint32_t c) {
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            put(px, x, y, c);
        }
    }
}

// a rounded rectangle w x h blocks with corners that are quarter pixel circles of radius r: is the block (x, y) inside
static int rr_inside(int x, int y, int w, int h, int r) {
    if (x < 0 || y < 0 || x >= w || y >= h) {
        return 0;
    }
    double cx = fmin(fmax(x + 0.5, r), w - r), cy = fmin(fmax(y + 0.5, r), h - r);
    double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
    return dx * dx + dy * dy <= (double)r * r;
}

// outline, then `bevel` blocks of light on the top and left edges and of dark on the bottom and right edges, then the face
static void draw_rr(uint32_t *px, int x0, int y0, int w, int h, int r, uint32_t fill, uint32_t outline, uint32_t light, uint32_t dark, int bevel) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if (!rr_inside(x, y, w, h, r)) {
                continue;
            }
            uint32_t c = fill;
            if (!(rr_inside(x - 1, y, w, h, r) && rr_inside(x + 1, y, w, h, r) && rr_inside(x, y - 1, w, h, r) && rr_inside(x, y + 1, w, h, r))) {
                c = outline;
            } else {
                for (int d = 1; d <= bevel; d++) {
                    if (!(rr_inside(x - 1 - d, y, w, h, r) && rr_inside(x, y - 1 - d, w, h, r))) {
                        c = light;
                        break;
                    }
                    if (!(rr_inside(x + 1 + d, y, w, h, r) && rr_inside(x, y + 1 + d, w, h, r))) {
                        c = dark;
                        break;
                    }
                }
            }
            put(px, x0 + x, y0 + y, c);
        }
    }
}

// a pixel disc: the block is in when its centre is within r of (cx, cy). mode 1: only the light crescent (top left, within `ring` blocks of the rim), 2: the dark one (bottom right)
static void disc(uint32_t *px, double cx, double cy, double r, uint32_t c, int mode, double ring) {
    for (int y = (int)floor(cy - r) - 1; y <= (int)ceil(cy + r) + 1; y++) {
        for (int x = (int)floor(cx - r) - 1; x <= (int)ceil(cx + r) + 1; x++) {
            double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d2 = dx * dx + dy * dy;
            if (d2 > r * r) {
                continue;
            }
            if (mode == 1 && !(dx + dy < -r * 0.62 && d2 > (r - ring) * (r - ring))) {
                continue;
            }
            if (mode == 2 && !(dx + dy > r * 0.62 && d2 > (r - ring) * (r - ring))) {
                continue;
            }
            put(px, x, y, c);
        }
    }
}

// ---------------------------------------------------------------- the font: the screen's norns.ttf at 8 px, else a built-in 3 x 5 font
#include "box_style_font.inc"

static FT_Library ft_lib;
static FT_Face ft_face;
static int font_mode = 0; // 0 not tried, 1 norns.ttf, 2 built-in
static char font_name[16] = "builtin";
static char font_override[512];

void box_style_set_font(const char *path_or_builtin) {
    ctl_ok = 0;
    drop_big(big_ctl);
    if (ft_face != NULL) {
        FT_Done_Face(ft_face);
        ft_face = NULL;
    }
    font_mode = 0;
    font_override[0] = '\0';
    if (path_or_builtin != NULL) {
        snprintf(font_override, sizeof font_override, "%s", path_or_builtin);
    }
}

static void font_init(void) {
    if (font_mode != 0) {
        return;
    }
    font_mode = 2;
    snprintf(font_name, sizeof font_name, "builtin");
    if (strcmp(font_override, "builtin") == 0) {
        return;
    }
    char path[640];
    const char *env = getenv("NORNS_BOX_FONT_PATH"), *home = getenv("HOME");
    if (font_override[0] != '\0') {
        snprintf(path, sizeof path, "%s", font_override);
    } else if (env != NULL && env[0] != '\0') {
        snprintf(path, sizeof path, "%s", env);
    } else if (home != NULL) {
        snprintf(path, sizeof path, "%s/norns/resources/norns.ttf", home); // where matron's screen looks for it
    } else {
        return;
    }
    if (ft_lib == NULL && FT_Init_FreeType(&ft_lib) != 0) {
        ft_lib = NULL;
        return;
    }
    if (FT_New_Face(ft_lib, path, 0, &ft_face) != 0) {
        ft_face = NULL;
        return;
    }
    if (FT_Set_Pixel_Sizes(ft_face, 0, 8) != 0) {
        FT_Done_Face(ft_face);
        ft_face = NULL;
        return;
    }
    font_mode = 1;
    snprintf(font_name, sizeof font_name, "norns.ttf");
}

const char *box_style_font_name(void) {
    font_init();
    return font_name;
}

static int ft_glyph(unsigned char ch) {
    return FT_Load_Char(ft_face, ch, FT_LOAD_RENDER | FT_LOAD_TARGET_MONO) == 0 && ft_face->glyph->bitmap.pixel_mode == FT_PIXEL_MODE_MONO;
}

static int width_ft(const char *text) {
    int w = 0;
    for (const char *c = text; *c != '\0'; c++) {
        w += ft_glyph((unsigned char)*c) ? (int)(ft_face->glyph->advance.x >> 6) : 0;
    }
    return w;
}

static int width_builtin(const char *text) {
    int n = (int)strlen(text);
    return n > 0 ? n * FONT3X5_ADVANCE - 1 : 0;
}

int box_style_text_width(const char *text) {
    font_init();
    return font_mode == 1 ? width_ft(text) : width_builtin(text);
}

// the text with its caps top at row y, in a font of rows `rows` high. builtin: force the built-in font
static int cap_rows(int builtin) {
    if (!builtin && font_mode == 1 && ft_glyph('H')) {
        return (int)ft_face->glyph->bitmap.rows;
    }
    return FONT3X5_ROWS;
}

static void draw_text(uint32_t *px, int x, int y, const char *text, uint32_t c, int builtin) {
    if (!builtin && font_mode == 1) {
        int top = 0;
        if (ft_glyph('H')) {
            top = ft_face->glyph->bitmap_top;
        }
        int pen = x;
        for (const char *p = text; *p != '\0'; p++) {
            if (!ft_glyph((unsigned char)*p)) {
                continue;
            }
            FT_GlyphSlot gs = ft_face->glyph;
            for (unsigned row = 0; row < gs->bitmap.rows; row++) {
                for (unsigned col = 0; col < gs->bitmap.width; col++) {
                    if ((gs->bitmap.buffer[row * gs->bitmap.pitch + col / 8] >> (7 - col % 8)) & 1) {
                        put(px, pen + gs->bitmap_left + (int)col, y + top - gs->bitmap_top + (int)row, c);
                    }
                }
            }
            pen += (int)(gs->advance.x >> 6);
        }
        return;
    }
    int pen = x;
    for (const char *p = text; *p != '\0'; p++) {
        const unsigned char *g = font3x5_glyph((unsigned char)*p);
        for (int row = 0; row < FONT3X5_ROWS; row++) {
            for (int col = 0; col < 3; col++) {
                if ((g[row] >> (2 - col)) & 1) {
                    put(px, pen + col, y + row, c);
                }
            }
        }
        pen += FONT3X5_ADVANCE;
    }
}

// a label centred in a w x h area at (x, y); the screen's font when the label fits (4 blocks of room), else the built-in one
static void label_in(uint32_t *px, int x, int y, int w, int h, const char *text, uint32_t c) {
    font_init();
    int builtin = font_mode != 1 || width_ft(text) > w - 4;
    int tw = builtin ? width_builtin(text) : width_ft(text);
    int rows = cap_rows(builtin);
    draw_text(px, x + (w - tw) / 2, y + (h - rows) / 2, text, c, builtin);
}

// ---------------------------------------------------------------- the layers
static int bx(double units) { return BS_MARGIN + (int)floor(units / BS_BLOCK + 0.5); }

void box_style_render_static(uint32_t *px) {
    ensure_colours();
    const shades_t *b = &sh[BOX_PART_BOX];
    fill_rect(px, 0, 0, BS_W, BS_H, argb(b->darker));
    int w = SKIN_W / BS_BLOCK, h = SKIN_H / BS_BLOCK;
    // the hard shadow: the box's shape moved 2 blocks right and down
    box_rgb_t shadow = box_darker(b->darker);
    draw_rr(px, BS_MARGIN + 2, BS_MARGIN + 2, w, h, 11, argb(shadow), argb(shadow), argb(shadow), argb(shadow), 0);
    draw_rr(px, BS_MARGIN, BS_MARGIN, w, h, 11, argb(b->base), argb(b->darker), argb(b->light), argb(b->dark), 1);
    // the bezel: the aluminium style's rectangle (x 36, y 300.667, 556 x 293.333), a 2 block frame in the darker shade round it, a light line below and right, black inside
    int x0 = bx(36), y0 = bx(300.667), x1 = bx(36 + 556) + 1, y1 = bx(300.667 + 293.333) + 1;
    fill_rect(px, x0 - 2, y0 - 2, x1 + 2, y1 + 2, argb(b->darker));
    fill_rect(px, x0 - 1, y1 + 1, x1 + 2, y1 + 2, argb(b->light));
    fill_rect(px, x1 + 1, y0 - 1, x1 + 2, y1 + 2, argb(b->light));
    fill_rect(px, x0, y0, x1, y1, 0xff000000u);
}

static void draw_button(uint32_t *px, int i, const skin_state_t *st) {
    const shades_t *bt = &sh[BOX_PART_BUTTONS], *fo = &sh[BOX_PART_FONT], *bo = &sh[BOX_PART_BOX];
    int id = SKIN_PAGE1 + i;
    int down = st->button_down == id;
    int lit = (id <= SKIN_PAGE4 && st->page == i + 1) || (id == SKIN_GRID && st->grid_open) || (id == SKIN_ARC && st->arc_open) || (id == SKIN_KEYS && st->keys_open) ||
              (id == SKIN_MIC && st->input != SKIN_INPUT_OFF) || (id == SKIN_MUTE && st->out_muted);
    box_rgb_t face = lit ? fo->base : bt->base, ink = lit ? bt->base : fo->base;
    if (st->hover == id && !down) {
        face = box_light(face);
    }
    if (down) {
        face = box_dark(face);
    }
    int dy = down ? 1 : 0;
    int x = bx(buttons[i].x), y = bx(BTN_Y), w = BTN_W / BS_BLOCK, h = BTN_H / BS_BLOCK;
    static const char *input_label[] = {"OFF", "MIC", "SYS", "APP"};
    const char *label = buttons[i].label;
    if (id == SKIN_MIC && st->input >= SKIN_INPUT_OFF && st->input <= SKIN_INPUT_APP) {
        label = input_label[st->input];
    }
    draw_rr(px, x, y + dy, w, h - dy, 3, argb(face), argb(bo->darker), down ? argb(face) : argb(box_light(face)), argb(box_dark(face)), 1);
    label_in(px, x, y + dy, w, h - dy, label, argb(ink));
}

// a message right of E1 (a button-style pill in the buttons and font colours)
static void draw_toast(uint32_t *px, const char *text, int recording) {
    const shades_t *bt = &sh[BOX_PART_BUTTONS], *fo = &sh[BOX_PART_FONT], *bo = &sh[BOX_PART_BOX];
    font_init();
    int dot = recording ? 9 : 0;
    int tw = box_style_text_width(text);
    int w = tw + 14 + dot, h = 18;
    int right = bx(SKIN_W - 95), cy = bx(175);
    int maxw = (SKIN_W - 95 - 300) / BS_BLOCK;
    if (w > maxw) {
        w = maxw;
    }
    int x = right - w, y = cy - h / 2;
    draw_rr(px, x, y, w, h, 6, argb(bt->base), argb(bo->darker), argb(box_light(bt->base)), argb(bt->dark), 1);
    if (recording) {
        disc(px, x + 8, cy, 3, 0xffff453au, 0, 0);
    }
    // the text, cut at the pill's inner width
    uint32_t *tmp = px;
    int builtin = font_mode != 1;
    int rows = cap_rows(builtin);
    int inner = w - 14 - dot;
    if (tw <= inner) {
        draw_text(tmp, x + 7 + dot, cy - rows / 2, text, argb(fo->base), builtin);
    } else {
        // too long: draw it and let the pill's right edge hide the rest
        draw_text(tmp, x + 7 + dot, cy - rows / 2, text, argb(fo->base), builtin);
        fill_rect(px, x + w - 6, y + 1, x + w, y + h - 1, argb(bt->base));
    }
}

static void draw_key(uint32_t *px, const ctl_t *c, int down, int hover) {
    const shades_t *k = &sh[BOX_PART_KEYS], *bo = &sh[BOX_PART_BOX];
    int s = 2 * KEY_HALF / BS_BLOCK, dy = down ? 1 : 0;
    box_rgb_t face = down ? k->dark : (hover ? k->light : k->base);
    draw_rr(px, bx(c->cx) - s / 2, bx(c->cy) - s / 2 + dy, s, s, KEY_RADIUS, argb(face), argb(bo->darker), down ? argb(face) : argb(k->light), argb(k->dark), 2);
}

static void draw_encoder(uint32_t *px, const ctl_t *c, int ticks, int hover) {
    const shades_t *e = &sh[BOX_PART_ENCODERS], *bo = &sh[BOX_PART_BOX];
    double cx = bx(c->cx), cy = bx(c->cy), r = ENC_RADIUS;
    disc(px, cx, cy, r, argb(bo->darker), 0, 0);
    disc(px, cx, cy, r - 1, argb(e->base), 0, 0);
    disc(px, cx, cy, r - 1, argb(e->light), 1, 4);
    disc(px, cx, cy, r - 1, argb(e->dark), 2, 4);
    disc(px, cx, cy, r - 6, argb(hover ? e->light : e->base), 0, 0);
    int step = ((ticks % 36) + 36) % 36;
    double a = (-90.0 + 10.0 * step) * M_PI / 180.0;
    disc(px, cx + cos(a) * (r - 9), cy + sin(a) * (r - 9), 2.2, argb(e->dark), 0, 0);
}

void box_style_render_controls(uint32_t *px, const skin_state_t *st, int buttons_shown) {
    ensure_colours();
    memset(px, 0, sizeof(uint32_t) * BS_W * BS_H);
    for (int i = 0; i < NBUTTONS; i++) {
        int id = SKIN_PAGE1 + i;
        if (buttons_shown || (id == SKIN_MUTE && st->out_muted)) {
            draw_button(px, i, st);
        }
    }
    if (st->toast != NULL && st->toast[0] != '\0') {
        draw_toast(px, st->toast, st->recording);
    }
    for (int i = 0; i < 3; i++) {
        draw_key(px, &ctls[i], st->key_down[i], st->hover == SKIN_K1 + i);
        draw_encoder(px, &ctls[3 + i], st->enc_ticks[i], st->hover == SKIN_E1 + i);
    }
}

// ---------------------------------------------------------------- placing an image in the window (the screen's rule: whole multiples where the size allows, else slightly soft)
// big: the cache of the enlarged copies of this layer (by the whole multiple m)
static void place(cairo_t *cr, const skin_geom_t *g, uint32_t *px, cairo_surface_t **big) {
    cairo_surface_t *img = cairo_image_surface_create_for_data((unsigned char *)px, CAIRO_FORMAT_ARGB32, BS_W, BS_H, BS_W * 4);
    double k = BS_BLOCK * g->s;
    long r = lround(k);
    cairo_save(cr);
    if (r >= 1 && fabs(k - r) <= 0.01) {
        // crisp: a whole number of device pixels per block, centred on the box
        double cx = g->ox + SKIN_W / 2.0 * g->s, cy = g->oy + SKIN_H / 2.0 * g->s;
        cairo_translate(cr, floor(cx - BS_W * r / 2.0 + 0.5), floor(cy - BS_H * r / 2.0 + 0.5));
        cairo_scale(cr, (double)r, (double)r);
        cairo_set_source_surface(cr, img, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_NONE);
        cairo_rectangle(cr, 0, 0, BS_W, BS_H);
        cairo_fill(cr);
    } else if (fast_mode) {
        // while the size is changing: the block image straight onto the window with the cheap filter (some blocks a device pixel wider); the quality frame follows when the size settles
        cairo_translate(cr, g->ox - BS_MARGIN * BS_BLOCK * g->s, g->oy - BS_MARGIN * BS_BLOCK * g->s);
        cairo_scale(cr, k, k);
        cairo_set_source_surface(cr, img, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_FAST);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_NONE);
        cairo_rectangle(cr, 0, 0, BS_W, BS_H);
        cairo_fill(cr);
    } else {
        // in between: enlarge to a whole multiple with nearest neighbour (no blur inside a block), then scale down with the best filter. the enlarged copy is kept
        int m = (int)ceil(k);
        if (m < 1) {
            m = 1;
        }
        if (m > MAX_M) {
            m = MAX_M;
        }
        if (big[m] == NULL) {
            big[m] = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, BS_W * m, BS_H * m);
            cairo_t *bc = cairo_create(big[m]);
            cairo_scale(bc, m, m);
            cairo_set_source_surface(bc, img, 0, 0);
            cairo_pattern_set_filter(cairo_get_source(bc), CAIRO_FILTER_NEAREST);
            cairo_paint(bc);
            cairo_destroy(bc);
        }
        cairo_translate(cr, g->ox - BS_MARGIN * BS_BLOCK * g->s, g->oy - BS_MARGIN * BS_BLOCK * g->s);
        cairo_scale(cr, k / m, k / m);
        cairo_set_source_surface(cr, big[m], 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_NONE);
        cairo_rectangle(cr, 0, 0, BS_W * m, BS_H * m);
        cairo_fill(cr);
    }
    cairo_restore(cr);
    cairo_surface_destroy(img);
}

static void ensure_static(void) {
    ensure_colours();
    if (blk_static == NULL) {
        blk_static = (uint32_t *)malloc(sizeof(uint32_t) * BS_W * BS_H);
    }
    if (blk_static != NULL && !static_ok) {
        box_style_render_static(blk_static);
        static_ok = 1;
        drop_big(big_static);
    }
}

static void ensure_controls(const skin_state_t *st, int buttons_shown) {
    ensure_colours();
    ctl_key_t k;
    memset(&k, 0, sizeof k);
    for (int i = 0; i < 3; i++) {
        k.key_down[i] = st->key_down[i] != 0;
        k.enc_ticks[i] = ((st->enc_ticks[i] % 36) + 36) % 36;
    }
    k.hover = st->hover;
    k.page = st->page;
    k.grid_open = st->grid_open;
    k.arc_open = st->arc_open;
    k.keys_open = st->keys_open;
    k.input = st->input;
    k.button_down = st->button_down;
    k.recording = st->recording;
    k.out_muted = st->out_muted;
    k.shown = buttons_shown != 0;
    if (st->toast != NULL) {
        snprintf(k.toast, sizeof k.toast, "%s", st->toast);
    }
    if (blk_ctl == NULL) {
        blk_ctl = (uint32_t *)malloc(sizeof(uint32_t) * BS_W * BS_H);
    }
    if (blk_ctl != NULL && (!ctl_ok || memcmp(&k, &ctl_key, sizeof k) != 0)) {
        box_style_render_controls(blk_ctl, st, buttons_shown);
        ctl_key = k;
        ctl_ok = 1;
        drop_big(big_ctl);
    }
}

void box_style_draw_static(cairo_t *cr, const skin_geom_t *g) {
    ensure_colours();
    box_rgb_t s = sh[BOX_PART_BOX].darker;
    cairo_save(cr);
    cairo_set_source_rgb(cr, s.r / 255.0, s.g / 255.0, s.b / 255.0);
    cairo_paint(cr);
    cairo_restore(cr);
    ensure_static();
    if (blk_static != NULL) {
        place(cr, g, blk_static, big_static);
    }
}

void box_style_draw_controls(cairo_t *cr, const skin_geom_t *g, const skin_state_t *st, int buttons_shown) {
    ensure_controls(st, buttons_shown);
    if (blk_ctl != NULL) {
        place(cr, g, blk_ctl, big_ctl);
    }
}

// ---------------------------------------------------------------- hit-testing
int box_style_hit(const skin_geom_t *g, double x, double y, int buttons_shown, int muted) {
    double px = (x - g->ox) / g->s, py = (y - g->oy) / g->s;
    for (int i = 0; i < NBUTTONS; i++) {
        int id = SKIN_PAGE1 + i;
        if (!buttons_shown && !(id == SKIN_MUTE && muted)) {
            continue;
        }
        if (px >= buttons[i].x - BTN_SLOP && px <= buttons[i].x + BTN_W + BTN_SLOP && py >= BTN_Y - BTN_SLOP && py <= BTN_Y + BTN_H + BTN_SLOP) {
            return id;
        }
    }
    for (int i = 0; i < NCTL; i++) {
        const ctl_t *c = &ctls[i];
        double dx = fabs(px - c->cx), dy = fabs(py - c->cy);
        if (c->shape == 'c') {
            if (hypot(dx, dy) <= c->hw + 2) {
                return c->id;
            }
        } else {
            double r = KEY_RADIUS * BS_BLOCK, in = c->hw - r;
            double ex = fmax(dx - in, 0), ey = fmax(dy - in, 0);
            if (dx <= c->hw + 2 && dy <= c->hh + 2 && ex * ex + ey * ey <= (r + 2) * (r + 2)) {
                return c->id;
            }
        }
    }
    return SKIN_NONE;
}

int box_style_nearest_enc(const skin_geom_t *g, double x, double y) {
    double px = (x - g->ox) / g->s, py = (y - g->oy) / g->s;
    int best = 0;
    for (int i = 1; i < 3; i++) {
        if (hypot(px - ctls[3 + i].cx, py - ctls[3 + i].cy) < hypot(px - ctls[3 + best].cx, py - ctls[3 + best].cy)) {
            best = i;
        }
    }
    return best + 1;
}
