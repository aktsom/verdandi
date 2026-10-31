/*
 * extras_layout.c: see extras_layout.h
 */

#include "extras_layout.h"

#include <math.h>

#define GAP 12
#define PAD 8
#define MIN_SCALE 0.6 // a window smaller than this is no use: below it no side is a side and the windows go over the norns window instead

enum { BELOW, RIGHT, LEFT, ABOVE, SIDES };

static int clampi(int v, int lo, int hi) {
    if (hi < lo) {
        return lo;
    }
    return v < lo ? lo : v > hi ? hi : v;
}

double extras_layout(const xl_rect_t *u, const xl_rect_t *m, int t, int n, const int *uw, const int *uh, xl_rect_t *out) {
    double sum_w = 0, sum_h = 0, max_w = 1, max_h = 1;
    for (int i = 0; i < n; i++) {
        sum_w += uw[i];
        sum_h += uh[i];
        max_w = uw[i] > max_w ? uw[i] : max_w;
        max_h = uh[i] > max_h ? uh[i] : max_h;
    }
    double k[SIDES];
    double row_k = (u->w - 2 * PAD - (n - 1) * GAP) / sum_w;
    double col_k = (u->h - 2 * PAD - n * t - (n - 1) * GAP) / sum_h;
    double below_h = u->y + u->h - PAD - (m->y + m->h + GAP);
    double above_h = (m->y - t - GAP) - (u->y + PAD);
    double right_w = u->x + u->w - PAD - (m->x + m->w + GAP);
    double left_w = (m->x - GAP) - (u->x + PAD);
    k[BELOW] = fmin(row_k, (below_h - t) / max_h);
    k[ABOVE] = fmin(row_k, (above_h - t) / max_h);
    k[RIGHT] = fmin(col_k, right_w / max_w);
    k[LEFT] = fmin(col_k, left_w / max_w);
    int best = BELOW;
    for (int i = 1; i < SIDES; i++) {
        if (k[i] > k[best] + 0.01) {
            best = i;
        }
    }
    int fallback = k[best] < MIN_SCALE;
    double s = fallback ? fmin(1.0, fmin(row_k, (u->h - 2 * PAD - t) / max_h)) : fmin(1.0, k[best]); // the fallback: the largest the screen allows, in one row at the bottom, over the norns window
    if (s <= 0) {
        s = 0.05;
    }
    int ew[3], eh[3];
    for (int i = 0; i < n; i++) {
        ew[i] = (int)(uw[i] * s);
        eh[i] = (int)(uh[i] * s);
        ew[i] = ew[i] < 1 ? 1 : ew[i];
        eh[i] = eh[i] < 1 ? 1 : eh[i];
    }
    int row_w = (n - 1) * GAP, col_h = n * t + (n - 1) * GAP;
    for (int i = 0; i < n; i++) {
        row_w += ew[i];
        col_h += eh[i];
    }
    if (fallback || best == BELOW || best == ABOVE) {
        int x = clampi(m->x + m->w / 2 - row_w / 2, u->x + PAD, u->x + u->w - PAD - row_w);
        for (int i = 0; i < n; i++) {
            out[i].x = x;
            out[i].w = ew[i];
            out[i].h = eh[i];
            if (fallback) {
                out[i].y = u->y + u->h - PAD - eh[i];
            } else if (best == BELOW) {
                out[i].y = m->y + m->h + GAP + t;
            } else {
                out[i].y = (m->y - t - GAP) - eh[i];
            }
            x += ew[i] + GAP;
        }
        return s;
    }
    int y = clampi(m->y + m->h / 2 - col_h / 2, u->y + PAD, u->y + u->h - PAD - col_h);
    for (int i = 0; i < n; i++) {
        out[i].w = ew[i];
        out[i].h = eh[i];
        out[i].x = best == RIGHT ? m->x + m->w + GAP : m->x - GAP - ew[i];
        out[i].y = y + t;
        y += t + eh[i] + GAP;
    }
    return s;
}
