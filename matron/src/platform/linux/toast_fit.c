/*
 * toast_fit.c: see toast_fit.h
 */
#include "toast_fit.h"

#include <string.h>

// the byte length of the UTF-8 character that starts at s (1 for a broken one)
static size_t char_len(const unsigned char *s) {
    size_t l = s[0] < 0x80 ? 1 : (s[0] >> 5) == 6 ? 2 : (s[0] >> 4) == 14 ? 3 : (s[0] >> 3) == 30 ? 4 : 1;
    for (size_t i = 1; i < l; i++) {
        if ((s[i] & 0xC0) != 0x80) return 1;
    }
    return l;
}

typedef struct {
    toast_lines_t *o;
    toast_measure_fn m;
    void *ctx;
    double max_w;
    int full; // all lines used and text left over
} fit_t;

// the end of the last line: ".." and as many characters off as it takes
static void ellipsize(fit_t *f, int i) {
    char *l = f->o->line[i];
    for (;;) {
        char tmp[TOAST_LINE_MAX + 4];
        size_t n = strlen(l);
        if (n + 2 >= sizeof tmp) n = sizeof tmp - 3;
        memcpy(tmp, l, n);
        strcpy(tmp + n, "..");
        if (f->m(f->ctx, tmp) <= f->max_w || n == 0) {
            strncpy(l, tmp, TOAST_LINE_MAX - 1);
            l[TOAST_LINE_MAX - 1] = 0;
            f->o->width[i] = f->m(f->ctx, l);
            return;
        }
        // drop the last character
        size_t k = n;
        while (k > 0 && ((unsigned char)l[k - 1] & 0xC0) == 0x80) k--;
        if (k > 0) k--;
        l[k] = 0;
    }
}

// a finished line; false if there is no room for another
static int push(fit_t *f, const char *s) {
    if (f->o->n >= TOAST_MAX_LINES) {
        f->full = 1;
        return 0;
    }
    int i = f->o->n++;
    strncpy(f->o->line[i], s, TOAST_LINE_MAX - 1);
    f->o->line[i][TOAST_LINE_MAX - 1] = 0;
    f->o->width[i] = f->m(f->ctx, f->o->line[i]);
    return 1;
}

void toast_fit(const char *text, toast_measure_fn measure, void *ctx, double max_w, toast_lines_t *out) {
    memset(out, 0, sizeof *out);
    fit_t f = {out, measure, ctx, max_w, 0};
    if (text == NULL) text = "";
    char cur[TOAST_LINE_MAX] = "";
    const unsigned char *p = (const unsigned char *)text;
    int stop = 0;
    while (!stop) {
        // one paragraph: up to the next "\n"
        const unsigned char *e = p;
        while (*e != 0 && *e != '\n') e++;
        const unsigned char *w = p;
        while (w < e && !stop) {
            while (w < e && *w == ' ') w++;
            const unsigned char *we = w;
            while (we < e && *we != ' ') we++;
            if (we == w) break;
            char word[TOAST_LINE_MAX];
            size_t wl = (size_t)(we - w);
            if (wl >= sizeof word) wl = sizeof word - 1;
            memcpy(word, w, wl);
            word[wl] = 0;
            w = we;
            char try_[TOAST_LINE_MAX * 2];
            if (cur[0] == 0) {
                strcpy(try_, word);
            } else {
                size_t cl = strlen(cur);
                if (cl + 1 + wl >= sizeof try_) cl = sizeof try_ - 2 - wl;
                memcpy(try_, cur, cl);
                try_[cl] = ' ';
                memcpy(try_ + cl + 1, word, wl + 1);
            }
            if (strlen(try_) < TOAST_LINE_MAX && measure(ctx, try_) <= max_w) {
                strcpy(cur, try_);
                continue;
            }
            if (cur[0] != 0) {
                if (!push(&f, cur)) { stop = 1; break; }
                cur[0] = 0;
            }
            // the word alone: whole if it fits, else cut between characters
            char *q = word;
            while (*q != 0) {
                size_t take = 0;
                char piece[TOAST_LINE_MAX];
                size_t pl = 0;
                for (;;) {
                    size_t cl = char_len((const unsigned char *)q + take);
                    if (q[take] == 0 || pl + cl >= sizeof piece) break;
                    memcpy(piece, q, take + cl);
                    piece[take + cl] = 0;
                    if (measure(ctx, piece) > max_w && take > 0) break;
                    take += cl;
                    pl = take;
                    if (measure(ctx, piece) > max_w) break; // one character wider than the space: it is a line of its own
                }
                memcpy(piece, q, take);
                piece[take] = 0;
                q += take;
                if (*q == 0) {
                    strcpy(cur, piece);
                } else if (!push(&f, piece)) {
                    stop = 1;
                    break;
                }
            }
        }
        if (stop) break;
        if (*e == 0) {
            if (cur[0] != 0 || out->n == 0) {
                if (!push(&f, cur)) stop = 1;
                cur[0] = 0;
            }
            break;
        }
        // "\n": the line ends here
        if (!push(&f, cur)) { stop = 1; break; }
        cur[0] = 0;
        p = e + 1;
        if (*p == 0) break;
    }
    if (f.full) {
        out->truncated = 1;
        ellipsize(&f, out->n - 1);
    }
    for (int i = 0; i < out->n; i++) {
        if (out->width[i] > out->widest) out->widest = out->width[i];
    }
    if (out->n == 0) {
        out->n = 1;
    }
}
