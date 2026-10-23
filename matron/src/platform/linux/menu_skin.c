/*
 * menu_skin.c: see menu_skin.h
 */

#include "menu_skin.h"

#include <math.h>
#include <string.h>

#define ROW_H 26.0
#define SEP_H 9.0
#define PAD 6.0
#define TEXT_PX 13.0
#define CHECK_W 22.0
#define GAP 28.0
#define MIN_W 190.0

static void measure(const menu_t *m, cairo_t *cr, double s, double *label_w, double *hint_w) {
    cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, TEXT_PX * s);
    *label_w = 0;
    *hint_w = 0;
    for (int i = 0; i < m->n; i++) {
        cairo_text_extents_t e;
        if (m->item[i].separator) {
            continue;
        }
        cairo_text_extents(cr, m->item[i].label, &e);
        if (e.x_advance > *label_w) {
            *label_w = e.x_advance;
        }
        if (m->item[i].hint[0] != '\0') {
            cairo_text_extents(cr, m->item[i].hint, &e);
            if (e.x_advance > *hint_w) {
                *hint_w = e.x_advance;
            }
        }
    }
}

void menu_skin_open(menu_t *m, double anchor_x, double anchor_y, double scale, int win_w, int win_h) {
    cairo_surface_t *probe = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    cairo_t *cr = cairo_create(probe);
    double lw, hw;
    if (scale < 0.5) {
        scale = 0.5;
    }
    measure(m, cr, scale, &lw, &hw);
    cairo_destroy(cr);
    cairo_surface_destroy(probe);

    m->scale = scale;
    m->pad = PAD * scale;
    m->row = ROW_H * scale;
    m->sep = SEP_H * scale;
    m->w = fmax(MIN_W * scale, CHECK_W * scale + lw + (hw > 0 ? GAP * scale + hw : 0) + 2 * m->pad + 14 * scale);
    m->h = 2 * m->pad;
    for (int i = 0; i < m->n; i++) {
        m->h += m->item[i].separator ? m->sep : m->row;
    }
    m->anchor_x = anchor_x;
    m->anchor_y = anchor_y;
    // at the pointer, moved back inside the window
    m->x = fmin(fmax(anchor_x, 4), fmax(4, win_w - m->w - 4));
    m->y = fmin(fmax(anchor_y, 4), fmax(4, win_h - m->h - 4));
    m->hover = -1;
    m->open = 1;
}

void menu_skin_close(menu_t *m) {
    m->open = 0;
    m->hover = -1;
}

int menu_skin_inside(const menu_t *m, double px, double py) {
    return m->open && px >= m->x && px < m->x + m->w && py >= m->y && py < m->y + m->h;
}

int menu_skin_hit(const menu_t *m, double px, double py) {
    if (!menu_skin_inside(m, px, py)) {
        return -1;
    }
    double y = m->y + m->pad;
    for (int i = 0; i < m->n; i++) {
        double h = m->item[i].separator ? m->sep : m->row;
        if (py >= y && py < y + h) {
            return (m->item[i].separator || m->item[i].disabled || px < m->x + 3 || px >= m->x + m->w - 3) ? -1 : i;
        }
        y += h;
    }
    return -1;
}

void menu_skin_move(menu_t *m, int dir) {
    if (m->n == 0) {
        return;
    }
    int i = m->hover;
    for (int tries = 0; tries < m->n + 1; tries++) {
        i = i < 0 ? (dir > 0 ? 0 : m->n - 1) : (i + dir + m->n) % m->n;
        if (!m->item[i].separator && !m->item[i].disabled) {
            m->hover = i;
            return;
        }
    }
}

static void round_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

void menu_skin_draw(cairo_t *cr, const menu_t *m) {
    if (!m->open) {
        return;
    }
    double s = m->scale;
    cairo_save(cr);
    // shadow, panel
    round_rect(cr, m->x + 2 * s, m->y + 4 * s, m->w, m->h, 8 * s);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.35);
    cairo_fill(cr);
    round_rect(cr, m->x, m->y, m->w, m->h, 8 * s);
    cairo_set_source_rgb(cr, 0.13, 0.14, 0.16);
    cairo_fill_preserve(cr);
    cairo_set_source_rgb(cr, 0.34, 0.35, 0.38);
    cairo_set_line_width(cr, 1.0);
    cairo_stroke(cr);

    cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, TEXT_PX * s);
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    double y = m->y + m->pad;
    for (int i = 0; i < m->n; i++) {
        const menu_item_t *it = &m->item[i];
        if (it->separator) {
            cairo_set_source_rgb(cr, 0.30, 0.31, 0.34);
            cairo_rectangle(cr, m->x + m->pad, y + m->sep / 2, m->w - 2 * m->pad, 1);
            cairo_fill(cr);
            y += m->sep;
            continue;
        }
        if (i == m->hover && !it->disabled) {
            round_rect(cr, m->x + 3 * s, y, m->w - 6 * s, m->row, 5 * s);
            cairo_set_source_rgb(cr, 0.91, 0.64, 0.24); // the orange of the lit buttons
            cairo_fill(cr);
        }
        double base = y + (m->row + fe.ascent - fe.descent) / 2;
        int lit = i == m->hover && !it->disabled;
        if (it->disabled) {
            cairo_set_source_rgb(cr, 0.45, 0.46, 0.48);
        } else if (lit) {
            cairo_set_source_rgb(cr, 0.08, 0.08, 0.09);
        } else {
            cairo_set_source_rgb(cr, 0.92, 0.93, 0.94);
        }
        if (it->checked) {
            // a check mark
            double cx = m->x + m->pad + 4 * s, cy = y + m->row / 2;
            cairo_set_line_width(cr, 2.0 * s);
            cairo_move_to(cr, cx, cy);
            cairo_line_to(cr, cx + 4 * s, cy + 4 * s);
            cairo_line_to(cr, cx + 11 * s, cy - 5 * s);
            cairo_stroke(cr);
        }
        cairo_move_to(cr, m->x + m->pad + CHECK_W * s, base);
        cairo_show_text(cr, it->label);
        if (it->hint[0] != '\0') {
            cairo_text_extents_t e;
            cairo_text_extents(cr, it->hint, &e);
            if (!it->disabled) {
                if (lit) {
                    cairo_set_source_rgb(cr, 0.25, 0.18, 0.05);
                } else {
                    cairo_set_source_rgb(cr, 0.62, 0.63, 0.66);
                }
            }
            cairo_move_to(cr, m->x + m->w - m->pad - 8 * s - e.x_advance, base);
            cairo_show_text(cr, it->hint);
        }
        y += m->row;
    }
    cairo_restore(cr);
}
