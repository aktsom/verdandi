/*
 * box_style_retro.inc: the three retro looks of the pixel style (docs/port/retro-look-plan.md): RETRO, 8-BIT, 16-BIT. included by box_style.c after the pixel renderers (it uses their statics: the colours,
 * the pixel writes, the font); PIXEL's code is not touched by anything in here. every shape is drawn in BLOCKS (4 units for RETRO and 8-BIT, 3 for 16-BIT) into the image's cells (2 units, 16-BIT: 1 unit),
 * so a label's text pixel stays 2 units (one cell, or two). the layout is the aluminium style's, snapped to the block grid: every position moves by half a block at most.
 */

typedef struct {
    int cu, bl;                                  // layout units of an image cell, cells in a block
    int btn_w, btn_h, key_n, enc_n;              // blocks
    int bevel_btn, bevel_key, cut_btn, cut_key, cut_box, rim;
    int nhi;
    signed char hi[4][2];                        // the pixel highlight on an encoder: block offsets from the centre
    int dropsh, grille, speckle, band, scan;     // speckle: 1 in this many blocks (0 none)
    int enc_dith, key_dith, btn_dith;            // BOX_DITHER_*
    int tshadow, cap;
} vp_t;

static const vp_t VP[BOX_LOOKS] = {
    {0},
    // RETRO (the recommended look, plan section 3)
    {2, 2, 18, 10, 28, 20, 1, 1, 1, 3, 6, 2, 4, {{-4, -5}, {-3, -5}, {-5, -4}, {-4, -4}}, 1, 1, 190, 1, 0, BOX_DITHER_BAYER, BOX_DITHER_NONE, BOX_DITHER_NONE, 1, 1},
    // 8-BIT (alternative A: chunky, plain)
    {2, 2, 18, 10, 28, 20, 1, 2, 1, 3, 6, 2, 2, {{-4, -5}, {-3, -5}, {0, 0}, {0, 0}}, 1, 0, 0, 1, 0, BOX_DITHER_NONE, BOX_DITHER_NONE, BOX_DITHER_NONE, 0, 0},
    // 16-BIT (alternative B: dithered, 3 unit blocks)
    {1, 3, 24, 13, 37, 27, 2, 1, 1, 3, 6, 3, 3, {{-5, -6}, {-4, -6}, {-6, -5}, {0, 0}}, 0, 0, 110, 1, 1, BOX_DITHER_BAYER, BOX_DITHER_BAYER, BOX_DITHER_CHECKER, 0, 1},
};

#define VB (VP[variant].cu * VP[variant].bl)           // the block in layout units
#define VOX (16 / VP[variant].cu)                       // the box's origin in cells (the window's 16 unit margin)
static int vsn(double units) { return (int)floor(units / (double)VB + 0.5); }
static int vbox_w(void) { return SKIN_W / VB; }
static int vbox_h(void) { return (SKIN_H + VB - 1) / VB; }

// a block (bx, by) of the box, relative to the box's corner
static void vcell(uint32_t *px, int bx, int by, uint32_t c) {
    const vp_t *v = &VP[variant];
    int x0 = VOX + bx * v->bl, y0 = VOX + by * v->bl;
    for (int y = 0; y < v->bl; y++) {
        for (int x = 0; x < v->bl; x++) {
            put(px, x0 + x, y0 + y, c);
        }
    }
}

static void vrect(uint32_t *px, int x0, int y0, int x1, int y1, uint32_t c) {
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            vcell(px, x, y, c);
        }
    }
}

// the colours: the ramp of each of the five parts, and a few blends
static box_rgb_t ramps[BOX_PARTS][BOX_RAMP];
static void make_ramps(void) {
    for (int i = 0; i < BOX_PARTS; i++) {
        box_ramp(sh[i].base, ramps[i]);
    }
}
static box_rgb_t mulc(box_rgb_t c, double f) {
    box_rgb_t o = {(unsigned char)fmin(255, c.r * f + 0.5), (unsigned char)fmin(255, c.g * f + 0.5), (unsigned char)fmin(255, c.b * f + 0.5)};
    return o;
}
static box_rgb_t litc(box_rgb_t c, double t) {
    box_rgb_t o = {(unsigned char)(c.r + (255 - c.r) * t + 0.5), (unsigned char)(c.g + (255 - c.g) * t + 0.5), (unsigned char)(c.b + (255 - c.b) * t + 0.5)};
    return o;
}

// a rectangle whose corners are cut in steps (cut = the size of the staircase, 0 = square): is block (x, y) of a w x h shape inside
static int shape_in(int w, int h, int cut, int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) {
        return 0;
    }
    int dx = x < w - 1 - x ? x : w - 1 - x, dy = y < h - 1 - y ? y : h - 1 - y;
    if (cut > 0 && dx < cut && dy < cut && dx + dy < cut && (cut - dx) + (cut - dy) > cut + (cut < 3 ? 0 : cut / 3)) {
        return 0;
    }
    return 1;
}

// outline, then `bevel` blocks of light on the top and left and of dark on the bottom and right, then the face (dithered from fill to fill2 down the shape when dmode is set)
static void vrrect(uint32_t *px, int x0, int y0, int w, int h, int cut, uint32_t fill, uint32_t outline, uint32_t hi, uint32_t lo, int bevel, int dmode, uint32_t fill2) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if (!shape_in(w, h, cut, x, y)) {
                continue;
            }
            uint32_t c = fill;
            if (dmode != BOX_DITHER_NONE && box_dither_pick(x0 + x, y0 + y, 1.0 - (double)y / (h > 1 ? h - 1 : 1), dmode)) {
                c = fill2;
            }
            if (!(shape_in(w, h, cut, x - 1, y) && shape_in(w, h, cut, x + 1, y) && shape_in(w, h, cut, x, y - 1) && shape_in(w, h, cut, x, y + 1))) {
                c = outline;
            } else {
                for (int d = 1; d <= bevel; d++) {
                    if (!(shape_in(w, h, cut, x - 1 - d, y) && shape_in(w, h, cut, x, y - 1 - d))) {
                        c = hi;
                        break;
                    }
                    if (!(shape_in(w, h, cut, x + 1 + d, y) && shape_in(w, h, cut, x, y + 1 + d))) {
                        c = lo;
                        break;
                    }
                }
            }
            vcell(px, x0 + x, y0 + y, c);
        }
    }
}

// ---------------------------------------------------------------- the layout (blocks), the same numbers as the PIXEL look's table snapped to the grid
static int v_control_blocks(int control, int *x0, int *y0, int *x1, int *y1) {
    const vp_t *v = &VP[variant];
    for (int i = 0; i < NCTL; i++) {
        if (ctls[i].id != control) {
            continue;
        }
        int n = ctls[i].shape == 'c' ? v->enc_n : v->key_n;
        *x0 = vsn(ctls[i].cx) - n / 2;
        *y0 = vsn(ctls[i].cy) - n / 2;
        *x1 = *x0 + n;
        *y1 = *y0 + n;
        return 1;
    }
    int b = control - SKIN_PAGE1;
    if (b >= 0 && b < NBUTTONS && control >= SKIN_PAGE1 && (control <= SKIN_MAIDEN + 1 || control == SKIN_MUTE)) {
        *x0 = vsn(buttons[b].x);
        *y0 = vsn(BTN_Y);
        *x1 = *x0 + v->btn_w;
        *y1 = *y0 + v->btn_h;
        return 1;
    }
    return 0;
}

static int v_control_rect(int control, double *x0, double *y0, double *x1, double *y1) {
    int a, b, c, d;
    if (!v_control_blocks(control, &a, &b, &c, &d)) {
        return 0;
    }
    *x0 = a * (double)VB;
    *y0 = b * (double)VB;
    *x1 = c * (double)VB;
    *y1 = d * (double)VB;
    return 1;
}

static double vslop(void) { return VP[variant].cu == 1 ? 1 : BTN_SLOP; } // 16-BIT's buttons are 3 units apart: a smaller margin keeps their hit areas apart

static int v_hit(const skin_geom_t *g, double x, double y, int buttons_shown, int muted) {
    const vp_t *v = &VP[variant];
    double px = (x - g->ox) / g->s, py = (y - g->oy) / g->s;
    for (int i = 0; i < NBUTTONS; i++) {
        int id = SKIN_PAGE1 + i;
        double x0, y0, x1, y1;
        if ((!buttons_shown && !(id == SKIN_MUTE && muted)) || !v_control_rect(id, &x0, &y0, &x1, &y1)) {
            continue;
        }
        if (px >= x0 - vslop() && px <= x1 + vslop() && py >= y0 - vslop() && py <= y1 + vslop()) {
            return id;
        }
    }
    for (int i = 0; i < NCTL; i++) {
        double x0, y0, x1, y1;
        v_control_rect(ctls[i].id, &x0, &y0, &x1, &y1);
        double cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, hw = (x1 - x0) / 2;
        double dx = fabs(px - cx), dy = fabs(py - cy);
        if (ctls[i].shape == 'c') {
            if (hypot(dx, dy) <= hw + vslop()) {
                return ctls[i].id;
            }
        } else {
            double r = v->cut_key * (double)VB, in = hw - r;
            double ex = fmax(dx - in, 0), ey = fmax(dy - in, 0);
            if (dx <= hw + vslop() && dy <= hw + vslop() && ex * ex + ey * ey <= (r + vslop()) * (r + vslop())) {
                return ctls[i].id;
            }
        }
    }
    return SKIN_NONE;
}

static int v_nearest_enc(const skin_geom_t *g, double x, double y) {
    double px = (x - g->ox) / g->s, py = (y - g->oy) / g->s, best_d = 1e18;
    int best = 0;
    for (int i = 0; i < 3; i++) {
        double x0, y0, x1, y1;
        v_control_rect(ctls[3 + i].id, &x0, &y0, &x1, &y1);
        double d = hypot(px - (x0 + x1) / 2, py - (y0 + y1) / 2);
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best + 1;
}

// ---------------------------------------------------------------- text at the screen's 2 unit pixel, in cells
static int text_scale(void) { return 2 / VP[variant].cu; } // cells of a text pixel

static void draw_text_ts(uint32_t *px, int x, int y, const char *text, uint32_t c, int builtin, int ts) {
    if (!builtin && font_mode == 1) {
        int top = ft_glyph('H') ? ft_face->glyph->bitmap_top : 0;
        int pen = x;
        for (const char *p = text; *p != '\0'; p++) {
            if (!ft_glyph((unsigned char)*p)) {
                continue;
            }
            FT_GlyphSlot gs = ft_face->glyph;
            for (unsigned row = 0; row < gs->bitmap.rows; row++) {
                for (unsigned col = 0; col < gs->bitmap.width; col++) {
                    if ((gs->bitmap.buffer[row * gs->bitmap.pitch + col / 8] >> (7 - col % 8)) & 1) {
                        for (int j = 0; j < ts; j++) {
                            for (int i = 0; i < ts; i++) {
                                put(px, pen + (gs->bitmap_left + (int)col) * ts + i, y + (top - gs->bitmap_top + (int)row) * ts + j, c);
                            }
                        }
                    }
                }
            }
            pen += (int)(gs->advance.x >> 6) * ts;
        }
        return;
    }
    int pen = x;
    for (const char *p = text; *p != '\0'; p++) {
        const unsigned char *g = font3x5_glyph((unsigned char)*p);
        for (int row = 0; row < FONT3X5_ROWS; row++) {
            for (int col = 0; col < 3; col++) {
                if ((g[row] >> (2 - col)) & 1) {
                    for (int j = 0; j < ts; j++) {
                        for (int i = 0; i < ts; i++) {
                            put(px, pen + col * ts + i, y + row * ts + j, c);
                        }
                    }
                }
            }
        }
        pen += FONT3X5_ADVANCE * ts;
    }
}

// a label centred in a rectangle of cells (the screen's font when it fits with 4 text pixels of room, else the built-in one); shadow: a second copy one text pixel down and right
static void v_label(uint32_t *px, int x, int y, int w, int h, const char *text, uint32_t c, uint32_t shadow, int with_shadow) {
    font_init();
    int ts = text_scale();
    int builtin = font_mode != 1 || width_ft(text) * ts > w - 4 * ts;
    int tw = (builtin ? width_builtin(text) : width_ft(text)) * ts;
    int rows = cap_rows(builtin) * ts;
    int tx = x + (w - tw) / 2, ty = y + (h - rows) / 2;
    if (with_shadow) {
        draw_text_ts(px, tx + ts, ty + ts, text, shadow, builtin, ts);
    }
    draw_text_ts(px, tx, ty, text, c, builtin, ts);
}

// ---------------------------------------------------------------- the static layer
static void render_static_retro(uint32_t *px) {
    ensure_colours();
    make_ramps();
    const vp_t *v = &VP[variant];
    const box_rgb_t *bo = ramps[BOX_PART_BOX];
    int W = vbox_w(), H = vbox_h();
    fill_rect(px, 0, 0, img_w, img_h, argb(bo[1]));
    // the hard shadow, the box: outline in the box's darker shade, a light bevel top and left, a dark one bottom and right
    vrrect(px, 1, 1, W, H, v->cut_box, argb(bo[0]), argb(bo[0]), argb(bo[0]), argb(bo[0]), 0, BOX_DITHER_NONE, 0);
    vrrect(px, 0, 0, W, H, v->cut_box, argb(bo[4]), argb(bo[1]), argb(bo[5]), argb(bo[2]), 1, BOX_DITHER_NONE, 0);
    // where the decoration of the face must keep out: every control (grown by its shadow) and the bezel's frame
    int kp[24][4], nkp = 0;
    for (int id = SKIN_PAGE1; id <= SKIN_MUTE; id++) {
        if (v_control_blocks(id, &kp[nkp][0], &kp[nkp][1], &kp[nkp][2], &kp[nkp][3])) {
            nkp++;
        }
    }
    for (int i = 0; i < NCTL; i++) {
        v_control_blocks(ctls[i].id, &kp[nkp][0], &kp[nkp][1], &kp[nkp][2], &kp[nkp][3]);
        nkp++;
    }
    for (int i = 0; i < nkp; i++) {
        kp[i][0] -= 1;
        kp[i][1] -= 1;
        kp[i][2] += 2;
        kp[i][3] += 2;
    }
    int bx0 = vsn(36), by0 = vsn(300.667), bx1 = vsn(36 + 556), by1 = vsn(300.667 + 293.333);
    // the face: a calm band of dither at the top and the bottom, sparse speckles, a scanline hint (16-BIT)
    for (int y = 2; y < H - 2; y++) {
        for (int x = 2; x < W - 2; x++) {
            if (!(shape_in(W, H, v->cut_box, x - 2, y) && shape_in(W, H, v->cut_box, x + 2, y) && shape_in(W, H, v->cut_box, x, y - 2) && shape_in(W, H, v->cut_box, x, y + 2))) {
                continue;
            }
            int keep = x >= bx0 - 3 && x < bx1 + 3 && y >= by0 - 3 && y < by1 + 3;
            for (int i = 0; i < nkp && !keep; i++) {
                keep = x >= kp[i][0] && x < kp[i][2] && y >= kp[i][1] && y < kp[i][3];
            }
            if (keep) {
                continue;
            }
            int set = 0;
            uint32_t c = 0;
            if (v->band && !(dbg_mask & 4)) {
                if (y < 14) {
                    double t = (1.0 - y / 14.0) * 0.55;
                    c = argb(box_dither_pick(x, y, t, BOX_DITHER_BAYER) ? bo[5] : bo[4]);
                    set = 1;
                } else if (y >= H - 16) {
                    double t = (y - (H - 16)) / 16.0 * 0.8;
                    c = argb(box_dither_pick(x, y, t, BOX_DITHER_BAYER) ? bo[3] : bo[4]);
                    set = 1;
                }
            }
            if (v->speckle && !(dbg_mask & 1) && (((unsigned)x * 73856093u) ^ ((unsigned)y * 19349663u)) % (unsigned)v->speckle == 0) {
                c = argb(((x + y) & 1) ? mulc(bo[4], 0.90) : litc(bo[4], 0.07));
                set = 1;
            }
            if (v->scan && !set && y % 2 == 0) {
                c = argb(box_dither_pick(x, y, 0.14, BOX_DITHER_BAYER) ? bo[3] : bo[4]);
                set = 1;
            }
            if (set) {
                vcell(px, x, y, c);
            }
        }
    }
    // the bezel: the screen's frame (2 blocks of the darker shade, a light line below and right, black inside)
    vrect(px, bx0 - 2, by0 - 2, bx1 + 2, by1 + 2, argb(bo[1]));
    vrect(px, bx0 - 1, by1 + 1, bx1 + 2, by1 + 2, argb(bo[5]));
    vrect(px, bx1 + 1, by0 - 1, bx1 + 2, by1 + 2, argb(bo[5]));
    vrect(px, bx0, by0, bx1, by1, 0xff000000u);
    // a grille of ten short slots above the toast's place
    if (v->grille && !(dbg_mask & 2)) {
        for (int i = 0; i < 10; i++) {
            int gx = vsn(420) + i * 3, gy = vsn(112);
            vrect(px, gx, gy, gx + 2, gy + 6, argb(bo[0]));
            vrect(px, gx, gy + 6, gx + 2, gy + 7, argb(bo[5]));
        }
    }
}

// ---------------------------------------------------------------- the controls layer
static void v_button(uint32_t *px, int i, const skin_state_t *st) {
    const vp_t *v = &VP[variant];
    const box_rgb_t *bt = ramps[BOX_PART_BUTTONS], *fo = ramps[BOX_PART_FONT], *bo = ramps[BOX_PART_BOX];
    int id = SKIN_PAGE1 + i;
    int down = st->button_down == id;
    int lit = (id <= SKIN_PAGE4 && st->page == i + 1) || (id == SKIN_GRID && st->grid_open) || (id == SKIN_ARC && st->arc_open) || (id == SKIN_KEYS && st->keys_open) ||
              (id == SKIN_MIC && st->input != SKIN_INPUT_OFF) || (id == SKIN_MUTE && st->out_muted);
    box_rgb_t face = lit ? fo[4] : bt[4], ink = lit ? bt[4] : fo[4];
    if (st->hover == id && !down) {
        face = box_light(face);
    }
    if (down) {
        face = box_dark(face);
    }
    int dy = down ? 1 : 0;
    int bx0, by0, bx1, by1;
    v_control_blocks(id, &bx0, &by0, &bx1, &by1);
    int w = bx1 - bx0, h = by1 - by0;
    static const char *input_label[] = {"OFF", "MIC", "SYS", "APP"};
    const char *label = buttons[i].label;
    if (id == SKIN_MIC && st->input >= SKIN_INPUT_OFF && st->input <= SKIN_INPUT_APP) {
        label = input_label[st->input];
    }
    if (v->dropsh && !down) {
        vrect(px, bx0 + 1, by0 + 1, bx0 + w + 1, by0 + h + 1, argb(bo[1]));
    }
    box_rgb_t outline = lit ? fo[1] : bt[0];
    vrrect(px, bx0, by0 + dy, w, h - dy, v->cut_btn, argb(face), argb(outline), down ? argb(face) : argb(box_light(face)), argb(box_dark(face)), v->bevel_btn, v->btn_dith, argb(litc(face, 0.12)));
    v_label(px, VOX + bx0 * v->bl, VOX + (by0 + dy) * v->bl, w * v->bl, (h - dy) * v->bl, label, argb(ink), argb(bt[0]), v->tshadow && !lit);
}

// a message right of E1 (a button-style pill, as the PIXEL look's)
static void v_toast(uint32_t *px, const char *text, int recording) {
    const vp_t *v = &VP[variant];
    const box_rgb_t *bt = ramps[BOX_PART_BUTTONS], *fo = ramps[BOX_PART_FONT], *bo = ramps[BOX_PART_BOX];
    font_init();
    int ts = text_scale();
    int builtin = font_mode != 1;
    int tw = (builtin ? width_builtin(text) : box_style_text_width(text)) * 2; // layout units (a text pixel is 2 units)
    int dot_u = recording ? 18 : 0;
    int wu = tw + 28 + dot_u, hu = 36;
    int maxw = (SKIN_W - 95 - 300);
    if (wu > maxw) {
        wu = maxw;
    }
    int w = (wu + VB / 2) / VB, h = (hu + VB / 2) / VB;
    int right = vsn(SKIN_W - 95), cy = vsn(175);
    int x = right - w, y = cy - h / 2;
    vrrect(px, x, y, w, h, v->cut_btn, argb(bt[4]), argb(bt[0]), argb(box_light(bt[4])), argb(bt[2]), 1, BOX_DITHER_NONE, 0);
    (void)bo;
    if (recording) {
        vrect(px, x + 2, cy - 1, x + 4, cy + 1, 0xffff453au);
    }
    int rows = cap_rows(builtin) * ts;
    int cx = VOX + x * v->bl + (7 * 2 / v->cu) + dot_u / v->cu, cyc = VOX + cy * v->bl - rows / 2;
    draw_text_ts(px, cx, cyc, text, argb(fo[4]), builtin, ts);
}

static void v_key(uint32_t *px, int idx, int down, int hover) {
    const vp_t *v = &VP[variant];
    const box_rgb_t *k = ramps[BOX_PART_KEYS], *bo = ramps[BOX_PART_BOX];
    int x0, y0, x1, y1;
    v_control_blocks(SKIN_K1 + idx, &x0, &y0, &x1, &y1);
    int n = x1 - x0, dy = down ? 1 : 0;
    box_rgb_t face = down ? k[2] : (hover ? k[5] : k[4]);
    if (v->dropsh && !down) {
        vrect(px, x0 + 1, y0 + 1, x0 + n + 1, y0 + n + 1, argb(bo[1]));
    }
    vrrect(px, x0, y0 + dy, n, n - dy, v->cut_key, argb(face), argb(k[0]), down ? argb(face) : argb(k[5]), argb(k[2]), v->bevel_key, v->key_dith, argb(k[5]));
}

static void v_encoder(uint32_t *px, int idx, int ticks, int hover) {
    const vp_t *v = &VP[variant];
    const box_rgb_t *e = ramps[BOX_PART_ENCODERS];
    int x0, y0, x1, y1;
    v_control_blocks(SKIN_E1 + idx, &x0, &y0, &x1, &y1);
    double r = (x1 - x0) / 2.0, cx = x0 + r, cy = y0 + r;
    for (int y = y0 - 1; y <= y1; y++) {
        for (int x = x0 - 1; x <= x1; x++) {
            double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d2 = dx * dx + dy * dy;
            if (d2 > r * r) {
                continue;
            }
            box_rgb_t c = e[4];
            if (d2 > (r - 1) * (r - 1)) {
                c = e[0];
            } else if (d2 > (r - 1 - v->rim) * (r - 1 - v->rim)) {
                c = dx + dy < -r * 0.6 ? e[5] : (dx + dy > r * 0.6 ? e[2] : e[3]);
            } else if (d2 <= (r * 0.55) * (r * 0.55)) {
                c = hover ? e[5] : (v->cap ? e[3] : e[4]);
            }
            if (v->enc_dith != BOX_DITHER_NONE && d2 <= (r - 1 - v->rim) * (r - 1 - v->rim) && d2 > (r * 0.55) * (r * 0.55)) {
                double t = (dx + dy) / (2 * r) + 0.5;
                c = box_dither_pick(x, y, t, v->enc_dith) ? e[3] : e[5];
            }
            vcell(px, x, y, argb(c));
        }
    }
    for (int i = 0; i < v->nhi; i++) {
        vcell(px, (int)floor(cx + v->hi[i][0] + 0.5), (int)floor(cy + v->hi[i][1] + 0.5), argb(e[6]));
    }
    // the notch turns with the detents: a 2 x 2 block square
    int step = ((ticks % 36) + 36) % 36;
    double a = (-90.0 + 10.0 * step) * M_PI / 180.0;
    int nx = (int)floor(cx + cos(a) * (r - 3.5) + 0.5) - 1, ny = (int)floor(cy + sin(a) * (r - 3.5) + 0.5) - 1;
    vrect(px, nx, ny, nx + 2, ny + 2, argb(e[0]));
}

static void render_controls_retro(uint32_t *px, const skin_state_t *st, int buttons_shown) {
    ensure_colours();
    make_ramps();
    memset(px, 0, sizeof(uint32_t) * (size_t)img_w * img_h);
    for (int i = 0; i < NBUTTONS; i++) {
        int id = SKIN_PAGE1 + i;
        if (buttons_shown || (id == SKIN_MUTE && st->out_muted)) {
            v_button(px, i, st);
        }
    }
    if (st->toast != NULL && st->toast[0] != '\0') {
        v_toast(px, st->toast, st->recording);
    }
    for (int i = 0; i < 3; i++) {
        v_key(px, i, st->key_down[i], st->hover == SKIN_K1 + i);
        v_encoder(px, i, st->enc_ticks[i], st->hover == SKIN_E1 + i);
    }
}
