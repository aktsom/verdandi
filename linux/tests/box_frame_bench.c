/*
 * box_frame_bench.c: how long one frame of the window takes, by component, over a sequence of window sizes (docs/port/box-style-plan.md, "Scaling the window"). it does what the bridge's redraw(true)
 * does after a resize: (A) make the layers for the new size: a static layer with the box (skin_draw_static), (B) paint it on the canvas, (C) the controls (skin_draw_controls), (D) the screen picture
 * (skin_draw_oled: a whole multiple of 128 x 64 when the size allows, else the filtered in-between), (E) hand the canvas to the window (SDL_BlitSurface and SDL_UpdateWindowSurfaceRects, when there is a display;
 * under Xvfb this is the X server's copy, not a real screen). plus (F) a frame that only changes the screen picture (what every refresh of a script does).
 *   box_frame_bench MODE [--check]      MODE: alu | tint | pixel | retro | 8bit | 16bit (the look), env BENCH_ORIG=1 when built against the old device_skin.c that has no skin_set_look
 * without --check it prints the table; with --check it also compares the final image after the whole sequence with a direct draw at the final size (a cache must never show an old size) and
 * exits 1 over the time budget (BENCH_BUDGET_MS per frame, default 250: generous, a headless machine and a loaded test run are slow) or on a difference
 */
#include <cairo.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef HAVE_SDL
#include <SDL.h>
#endif

#include "device_skin.h"

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

typedef struct {
    double a, b, c, d, e, f;
    int n;
} acc_t;

static cairo_surface_t *make_oled(int shade) {
    cairo_surface_t *o = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *p = (uint32_t *)cairo_image_surface_get_data(o);
    int stride = cairo_image_surface_get_stride(o) / 4;
    for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 128; x++) {
            int v = ((x / 4 + y / 4 + shade) % 2) ? 220 : (x * 2) & 0xff;
            p[y * stride + x] = 0xff000000u | (v << 16) | (v << 8) | v;
        }
    }
    cairo_surface_mark_dirty(o);
    return o;
}

typedef struct {
    int w, h;
    cairo_surface_t *stat, *canvas;
    skin_geom_t g;
} frame_t;

static void layers(frame_t *f, int w, int h) {
    if (f->stat) cairo_surface_destroy(f->stat);
    if (f->canvas) cairo_surface_destroy(f->canvas);
    f->w = w;
    f->h = h;
    skin_geom(w, h, &f->g);
    f->stat = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    f->canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    cairo_t *cr = cairo_create(f->stat);
    skin_draw_static(cr, &f->g);
    cairo_destroy(cr);
}

static void compose(frame_t *f, const skin_state_t *st, cairo_surface_t *oled, double *tb, double *tc, double *td) {
    cairo_t *cr = cairo_create(f->canvas);
    double t0 = now_ms();
    cairo_set_source_surface(cr, f->stat, 0, 0);
    cairo_paint(cr);
    double t1 = now_ms();
    skin_draw_controls(cr, &f->g, st);
    double t2 = now_ms();
    skin_draw_oled(cr, &f->g, oled);
    double t3 = now_ms();
    cairo_destroy(cr);
    cairo_surface_flush(f->canvas);
    *tb = t1 - t0;
    *tc = t2 - t1;
    *td = t3 - t2;
}

static void apply_look(const char *mode) {
#ifndef BENCH_ORIG
    skin_set_pixel_look(0);
    if (strcmp(mode, "retro") == 0 || strcmp(mode, "8bit") == 0 || strcmp(mode, "16bit") == 0) {
        // the retro looks of the pixel style (docs/port/retro-look-plan.md)
        skin_set_look(SKIN_STYLE_PIXEL, "2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea");
        skin_set_pixel_look(strcmp(mode, "retro") == 0 ? 1 : strcmp(mode, "8bit") == 0 ? 2 : 3);
    } else if (strcmp(mode, "pixel") == 0) {
        skin_set_look(SKIN_STYLE_PIXEL, "2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea");
    } else if (strcmp(mode, "tint") == 0) {
        skin_set_look(SKIN_STYLE_ALUMINIUM, "3b6ea8", "e8a317", NULL, NULL, NULL);
    } else {
        skin_set_look(SKIN_STYLE_ALUMINIUM, NULL, NULL, NULL, NULL, NULL);
    }
#else
    (void)mode;
#endif
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "alu";
    int check = 0, fast = 0;
    for (int i = 2; i < argc; i++) {
        check |= strcmp(argv[i], "--check") == 0;
        fast |= strcmp(argv[i], "--fast") == 0; // the way the window draws while it is being dragged
    }
    double budget = getenv("BENCH_BUDGET_MS") ? atof(getenv("BENCH_BUDGET_MS")) : 250;
    apply_look(mode);
#ifndef BENCH_ORIG
    skin_set_fast(fast);
#endif
#ifdef HAVE_SDL
    SDL_Window *win = NULL;
    if (getenv("DISPLAY") != NULL && SDL_Init(SDL_INIT_VIDEO) == 0) {
        win = SDL_CreateWindow("bench", 0, 0, 992, 662, SDL_WINDOW_RESIZABLE);
    }
#endif
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    cairo_surface_t *oled0 = make_oled(0), *oled1 = make_oled(1);
    frame_t f;
    memset(&f, 0, sizeof f);
    acc_t all = {0}, at100 = {0};
    double worst = 0;
    int nsizes = 0, last_w = 0, last_h = 0;
    printf("%s: width x height | A layers  B paint  C controls  D screen  E present | F screen-only | total\n", mode);
    for (int w = 640; w <= 1600; w += 8) {
        int h = (int)lround(w * 662.0 / 992.0);
        double t0 = now_ms();
        layers(&f, w, h);
        double ta = now_ms() - t0, tb, tc, td, te = -1;
        compose(&f, &st, oled0, &tb, &tc, &td);
#ifdef HAVE_SDL
        if (win != NULL) {
            double p0 = now_ms();
            SDL_SetWindowSize(win, w, h);
            SDL_Surface *ws = SDL_GetWindowSurface(win);
            if (ws != NULL) {
                SDL_Surface *src = SDL_CreateRGBSurfaceWithFormatFrom(cairo_image_surface_get_data(f.canvas), w, h, 32, cairo_image_surface_get_stride(f.canvas), SDL_PIXELFORMAT_RGB888);
                SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE);
                SDL_Rect r = {0, 0, w < ws->w ? w : ws->w, h < ws->h ? h : ws->h};
                SDL_BlitSurface(src, &r, ws, &r);
                SDL_UpdateWindowSurfaceRects(win, &r, 1);
                SDL_FreeSurface(src);
            }
            te = now_ms() - p0;
        }
#endif
        // a screen-only frame (a script's refresh): the screen picture on the canvas, nothing else
        double f0 = now_ms();
        {
            cairo_t *cr = cairo_create(f.canvas);
            skin_draw_oled(cr, &f.g, oled1);
            cairo_destroy(cr);
            cairo_surface_flush(f.canvas);
        }
        double tf = now_ms() - f0;
        double total = ta + tb + tc + td + (te > 0 ? te : 0);
        if (total > worst) worst = total;
        acc_t *as[2] = {&all, w == 992 ? &at100 : NULL};
        for (int i = 0; i < 2; i++) {
            if (as[i]) {
                as[i]->a += ta; as[i]->b += tb; as[i]->c += tc; as[i]->d += td; as[i]->e += te > 0 ? te : 0; as[i]->f += tf; as[i]->n++;
            }
        }
        if (w % 128 == 0 || w == 992) {
            printf("  %4d x %4d | %6.1f %6.1f %6.1f %6.1f %6.1f | %6.1f | %6.1f ms\n", w, h, ta, tb, tc, td, te > 0 ? te : 0, tf, total);
        }
        nsizes++;
        last_w = w;
        last_h = h;
    }
    printf("  average over %d sizes (ms): A layers %.1f, B paint %.1f, C controls %.1f, D screen %.1f, E present %.1f, F screen-only %.1f, total %.1f; worst frame %.1f ms\n", all.n,
           all.a / all.n, all.b / all.n, all.c / all.n, all.d / all.n, all.e / all.n, all.f / all.n, (all.a + all.b + all.c + all.d + all.e) / all.n, worst);
    if (at100.n) {
        printf("  at 100 percent (992 x 662): layers %.1f, controls %.1f, screen %.1f, present %.1f ms\n", at100.a, at100.c, at100.d, at100.e);
    }
    int rc = 0;
    if (check) {
        // the final image of the sequence equals a direct draw at the final size (nothing stale from an earlier size)
        // (what the settle timer does: the quick drawing off, the layers made again at the final size)
#ifndef BENCH_ORIG
        skin_set_fast(0);
#endif
        layers(&f, last_w, last_h);
        frame_t fresh;
        memset(&fresh, 0, sizeof fresh);
        apply_look(mode); // empties every cache: this one is a cold draw
        layers(&fresh, last_w, last_h);
        double a, b, c;
        compose(&f, &st, oled0, &a, &b, &c);
        compose(&fresh, &st, oled0, &a, &b, &c);
        int sa = cairo_image_surface_get_stride(f.canvas), sb = cairo_image_surface_get_stride(fresh.canvas);
        long diff = 0;
        for (int y = 0; y < last_h; y++) {
            diff += memcmp(cairo_image_surface_get_data(f.canvas) + (size_t)y * sa, cairo_image_surface_get_data(fresh.canvas) + (size_t)y * sb, (size_t)last_w * 4) != 0;
        }
        printf("  final image after %d sizes vs a direct draw at %d x %d: %ld rows differ\n", nsizes, last_w, last_h, diff);
        if (diff != 0) rc = 1;
        double avg = (all.a + all.b + all.c + all.d + all.e) / all.n;
        if (avg > budget) {
            printf("  OVER BUDGET: %.1f ms per frame on average (budget %.0f)\n", avg, budget);
            rc = 1;
        }
    }
    return rc;
}
