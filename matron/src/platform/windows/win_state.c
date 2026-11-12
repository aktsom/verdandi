/* win_state.c: see win_state.h */
#include "win_state.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ws_format(const ws_t *s, char *buf, size_t n) {
    int at = 0;
    buf[0] = 0;
    if (s->has_pos) at += snprintf(buf + at, n - (size_t)at, "x=%d\ny=%d\n", s->x, s->y);
    if (s->has_size) at += snprintf(buf + at, n - (size_t)at, "w=%d\nh=%d\n", s->w, s->h);
    return at;
}

void ws_parse(const char *text, ws_t *s) {
    memset(s, 0, sizeof *s);
    int hx = 0, hy = 0, hw = 0, hh = 0;
    for (const char *p = text; p && *p;) {
        int v;
        char *end;
        if ((p[0] == 'x' || p[0] == 'y' || p[0] == 'w' || p[0] == 'h') && p[1] == '=') {
            v = (int)strtol(p + 2, &end, 10);
            if (end != p + 2) {
                if (p[0] == 'x') { s->x = v; hx = 1; }
                if (p[0] == 'y') { s->y = v; hy = 1; }
                if (p[0] == 'w') { s->w = v; hw = 1; }
                if (p[0] == 'h') { s->h = v; hh = 1; }
            }
        }
        const char *nl = strchr(p, '\n');
        p = nl ? nl + 1 : NULL;
    }
    s->has_pos = hx && hy;
    s->has_size = hw && hh && s->w > 0 && s->h > 0;
}

int ws_place(const ws_t *saved, const ws_rect *screens, int ns, int min_w, int min_h, ws_t *out) {
    memset(out, 0, sizeof *out);
    if (!saved->has_size && !saved->has_pos) return 0;
    int maxw = 0, maxh = 0;
    for (int i = 0; i < ns; i++) {
        if (screens[i].w > maxw) maxw = screens[i].w;
        if (screens[i].h > maxh) maxh = screens[i].h;
    }
    if (saved->has_size) {
        out->has_size = 1;
        out->w = saved->w < min_w ? min_w : saved->w;
        out->h = saved->h < min_h ? min_h : saved->h;
        if (maxw > 0 && out->w > maxw) out->w = maxw;
        if (maxh > 0 && out->h > maxh) out->h = maxh;
    }
    if (saved->has_pos) {
        for (int i = 0; i < ns; i++) {
            /* the band of the title bar: 120 x 40 at the top left corner must be on this screen at least 80 x 30 */
            int x0 = saved->x, y0 = saved->y, x1 = x0 + 120, y1 = y0 + 40;
            int ix0 = x0 > screens[i].x ? x0 : screens[i].x, iy0 = y0 > screens[i].y ? y0 : screens[i].y;
            int ix1 = x1 < screens[i].x + screens[i].w ? x1 : screens[i].x + screens[i].w, iy1 = y1 < screens[i].y + screens[i].h ? y1 : screens[i].y + screens[i].h;
            if (ix1 - ix0 >= 80 && iy1 - iy0 >= 30) {
                out->has_pos = 1;
                out->x = saved->x;
                out->y = saved->y;
                break;
            }
        }
    }
    return out->has_pos || out->has_size;
}

int ws_load(const char *path, ws_t *s) {
    memset(s, 0, sizeof *s);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char text[256];
    size_t n = fread(text, 1, sizeof text - 1, f);
    fclose(f);
    text[n] = 0;
    ws_parse(text, s);
    return s->has_pos || s->has_size;
}

int ws_save(const char *path, const ws_t *s) {
    char text[128], tmp[1100];
    ws_format(s, text, sizeof text);
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (!f) return -1;
    int ok = fputs(text, f) >= 0;
    ok = fclose(f) == 0 && ok;
    if (ok) {
        remove(path); /* Windows: rename() does not replace */
        ok = rename(tmp, path) == 0;
    }
    if (!ok) {
        remove(tmp);
        return -1;
    }
    return 0;
}
