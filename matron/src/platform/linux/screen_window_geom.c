/*
 * screen_window_geom.c: see screen_window_geom.h
 */

#include "screen_window_geom.h"

#include <math.h>

void sw_picture_fit(int win_w, int win_h, sw_picture_t *p) {
    p->x = p->y = p->w = p->h = 0;
    p->scale = 0;
    if (win_w < 2 || win_h < 1) {
        return;
    }
    double k = fmin(win_w / 128.0, win_h / 64.0);
    int r = (int)floor(k + 1e-9);
    if (r >= 1 && k - r <= 0.02 + 1e-9) {
        p->scale = r;
        p->w = 128 * r;
        p->h = 64 * r;
    } else {
        int w = 2 * (int)floor(k * 64 + 1e-9);
        p->w = w < 2 ? 2 : w;
        p->h = p->w / 2;
    }
    p->x = (win_w - p->w) / 2;
    p->y = (win_h - p->h) / 2;
}

int sw_picture_contains(const sw_picture_t *p, int x, int y) {
    return x >= p->x && x < p->x + p->w && y >= p->y && y < p->y + p->h;
}

void sw_default_window(int usable_w, int usable_h, int title_h, int *w, int *h) {
    for (int r = 5; r >= 2; r--) {
        if (128 * r <= usable_w - 16 && 64 * r + title_h <= usable_h - 16) {
            *w = 128 * r;
            *h = 64 * r;
            return;
        }
    }
    *w = 256;
    *h = 128;
}

int sw_rect_visible(const sw_rect_t *r, const sw_rect_t *displays, int n) {
    for (int i = 0; i < n; i++) {
        int x0 = r->x > displays[i].x ? r->x : displays[i].x;
        int y0 = r->y > displays[i].y ? r->y : displays[i].y;
        int x1 = r->x + r->w < displays[i].x + displays[i].w ? r->x + r->w : displays[i].x + displays[i].w;
        int y1 = r->y + r->h < displays[i].y + displays[i].h ? r->y + r->h : displays[i].y + displays[i].h;
        if (x1 - x0 >= 64 && y1 - y0 >= 64) {
            return 1;
        }
    }
    return 0;
}
