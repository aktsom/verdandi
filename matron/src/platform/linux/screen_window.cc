/*
 * screen_window.cc: see screen_window.h. the geometry rule is screen_window_geom.c, the state file screen_window_conf.c (both pure C, unit tested).
 *
 * drawing is the box's own software path: a cairo canvas the size of the window surface, blitted with SDL_UpdateWindowSurface. a whole multiple of 128 x 64 is
 * drawn with nearest neighbour; in between the picture is enlarged with nearest to a whole multiple and scaled with a bilinear filter (the box uses the
 * slow "best" filter for that, which costs 70 to 320 ms a frame at the sizes of a big window: docs/port/detach-measurements/).
 */

#include "screen_window.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "screen_window_conf.h"
#include "screen_window_geom.h"

static SDL_Window *win = NULL;
static sw_conf_t conf;
static char conf_path[1024] = "";
static Uint32 own_event = (Uint32)-1;
enum { EV_SAVE = 1, EV_HIDE_CURSOR = 2 };
static unsigned save_gen = 0, hide_gen = 0;
static Uint32 ignore_resize_until = 0;
static bool wanted_at_start = false;

// the canvas (the window's surface size) and the enlarged copy of the picture for the in-between sizes, kept between frames
static cairo_surface_t *canvas = NULL;
static SDL_Surface *canvas_sdl = NULL;
static int canvas_w = 0, canvas_h = 0;
static cairo_surface_t *big = NULL;
static int big_m = 0;

static void log_line(const char *line) {
    fprintf(stderr, "%s\n", line);
}

static void free_canvas(void) {
    if (canvas_sdl != NULL) {
        SDL_FreeSurface(canvas_sdl);
        canvas_sdl = NULL;
    }
    if (canvas != NULL) {
        cairo_surface_destroy(canvas);
        canvas = NULL;
    }
    if (big != NULL) {
        cairo_surface_destroy(big);
        big = NULL;
    }
    canvas_w = canvas_h = big_m = 0;
}

static Uint32 timer_cb(Uint32 interval, void *param) {
    (void)interval;
    SDL_Event ev;
    SDL_zero(ev);
    ev.type = own_event;
    ev.user.code = (Sint32)((uintptr_t)param & 0xff);
    ev.user.data1 = (void *)((uintptr_t)param >> 8);
    SDL_PushEvent(&ev);
    return 0;
}

static void after(Uint32 ms, int code, unsigned gen) {
    SDL_AddTimer(ms, timer_cb, (void *)(((uintptr_t)gen << 8) | (uintptr_t)code));
}

void screen_window_init(void) {
    sw_conf_defaults(&conf);
    own_event = SDL_RegisterEvents(1);
    const char *home = getenv("HOME");
    snprintf(conf_path, sizeof conf_path, "%s/screen-window.conf", home != NULL && home[0] != '\0' ? home : ".");
    sw_conf_load(conf_path, &conf, log_line);
    wanted_at_start = conf.detached != 0;
}

bool screen_window_wanted_at_start(void) {
    return wanted_at_start;
}

bool screen_window_is_open(void) {
    return win != NULL;
}

Uint32 screen_window_id(void) {
    return win != NULL ? SDL_GetWindowID(win) : 0;
}

// the windowed rectangle, as the window has it now (not while fullscreen: SDL then reports the display)
static void track(void) {
    if (win == NULL || conf.fullscreen || SDL_GetTicks() < ignore_resize_until) {
        return;
    }
    if (SDL_GetWindowFlags(win) & (SDL_WINDOW_MINIMIZED | SDL_WINDOW_MAXIMIZED | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP)) {
        return;
    }
    SDL_GetWindowPosition(win, &conf.x, &conf.y);
    SDL_GetWindowSize(win, &conf.w, &conf.h);
    conf.has_pos = 1;
}

static void schedule_save(void) {
    save_gen++;
    after(500, EV_SAVE, save_gen);
}

void screen_window_save_now(void) {
    if (conf_path[0] == '\0') {
        return;
    }
    if (win != NULL) {
        track();
        conf.detached = 1;
    }
    if (sw_conf_save(conf_path, &conf) != 0) {
        fprintf(stderr, "screen-window.conf: could not write %s\n", conf_path);
    }
}

static SDL_HitTestResult hit_test(SDL_Window *w, const SDL_Point *a, void *data) {
    (void)data;
    int ww = 0, wh = 0;
    SDL_GetWindowSize(w, &ww, &wh);
    const int e = 8;
    int l = a->x < e, r = a->x >= ww - e, t = a->y < e, b = a->y >= wh - e;
    if (t && l) return SDL_HITTEST_RESIZE_TOPLEFT;
    if (t && r) return SDL_HITTEST_RESIZE_TOPRIGHT;
    if (b && l) return SDL_HITTEST_RESIZE_BOTTOMLEFT;
    if (b && r) return SDL_HITTEST_RESIZE_BOTTOMRIGHT;
    if (t) return SDL_HITTEST_RESIZE_TOP;
    if (b) return SDL_HITTEST_RESIZE_BOTTOM;
    if (l) return SDL_HITTEST_RESIZE_LEFT;
    if (r) return SDL_HITTEST_RESIZE_RIGHT;
    return SDL_HITTEST_DRAGGABLE;
}

// a window with no frame is moved by dragging its picture and resized at its edge; with the frame the desktop does both
static void apply_border(void) {
    if (win == NULL) {
        return;
    }
    SDL_SetWindowBordered(win, conf.border ? SDL_TRUE : SDL_FALSE);
    if (!conf.border && !conf.fullscreen) {
        SDL_SetWindowHitTest(win, hit_test, NULL);
    } else {
        SDL_SetWindowHitTest(win, NULL, NULL);
    }
}

static int title_height(SDL_Window *w) {
    int top = 0, left, bottom, right;
    if (w == NULL || SDL_GetWindowBordersSize(w, &top, &left, &bottom, &right) != 0 || top <= 0) {
        top = 28;
    }
    return top;
}

bool screen_window_open(SDL_Window *main, void (*decorate)(SDL_Window *)) {
    if (win != NULL) {
        return true;
    }
    int d = main != NULL ? SDL_GetWindowDisplayIndex(main) : 0;
    SDL_Rect u;
    if (SDL_GetDisplayUsableBounds(d < 0 ? 0 : d, &u) != 0) {
        u.x = u.y = 0;
        u.w = 1280;
        u.h = 800;
    }
    int w = conf.w, h = conf.h;
    if (w <= 0 || h <= 0) {
        sw_default_window(u.w, u.h, title_height(main), &w, &h);
    }
    int x = SDL_WINDOWPOS_UNDEFINED, y = SDL_WINDOWPOS_UNDEFINED;
    bool placed = false;
    if (conf.has_pos) {
        sw_rect_t displays[16];
        int n = SDL_GetNumVideoDisplays();
        if (n > 16) {
            n = 16;
        }
        for (int i = 0; i < n; i++) {
            SDL_Rect b;
            SDL_GetDisplayBounds(i, &b);
            displays[i] = {b.x, b.y, b.w, b.h};
        }
        sw_rect_t r = {conf.x, conf.y, w, h};
        if (sw_rect_visible(&r, displays, n)) {
            x = conf.x;
            y = conf.y;
            placed = true;
        } else {
            fprintf(stderr, "screen-window.conf: the saved place is not on any display, using the default place\n");
        }
    }
    if (!placed && main != NULL) {
        // beside the box: to its right if the display has room, else below it, else over it
        int mx, my, mw, mh, gap = 12;
        SDL_GetWindowPosition(main, &mx, &my);
        SDL_GetWindowSize(main, &mw, &mh);
        if (mx + mw + gap + w <= u.x + u.w) {
            x = mx + mw + gap;
            y = my;
        } else if (my + mh + gap + title_height(main) + h <= u.y + u.h) {
            x = mx;
            y = my + mh + gap + title_height(main);
        } else {
            x = mx + (mw - w) / 2;
            y = my + (mh - h) / 2;
        }
    }
    Uint32 flags = SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE;
    if (!conf.border) {
        flags |= SDL_WINDOW_BORDERLESS;
    }
    win = SDL_CreateWindow("Verdandi screen", x, y, w, h, flags);
    if (win == NULL) {
        fprintf(stderr, "screen window: SDL_CreateWindow failed: %s\n", SDL_GetError());
        return false;
    }
    SDL_SetWindowMinimumSize(win, 256, 128);
    if (decorate != NULL) {
        decorate(win);
    }
    conf.w = w;
    conf.h = h;
    conf.detached = 1;
    int fs = conf.fullscreen;
    conf.fullscreen = 0;
    track();
    conf.fullscreen = fs;
    apply_border();
    if (conf.fullscreen) {
        SDL_SetWindowFullscreen(win, SDL_WINDOW_FULLSCREEN_DESKTOP);
        apply_border();
    }
    schedule_save();
    return true;
}

void screen_window_close(void) {
    if (win == NULL) {
        return;
    }
    track();
    conf.detached = 0;
    SDL_ShowCursor(SDL_ENABLE);
    SDL_DestroyWindow(win);
    win = NULL;
    free_canvas();
    screen_window_save_now();
}

static void set_fullscreen(bool on) {
    if (win == NULL || (conf.fullscreen != 0) == on) {
        return;
    }
    if (on) {
        track();
        conf.fullscreen = 1;
        SDL_SetWindowFullscreen(win, SDL_WINDOW_FULLSCREEN_DESKTOP);
        apply_border();
    } else {
        conf.fullscreen = 0;
        SDL_ShowCursor(SDL_ENABLE);
        SDL_SetWindowFullscreen(win, 0);
        // back to the windowed place and size (SDL reports the display's while it leaves)
        ignore_resize_until = SDL_GetTicks() + 800;
        if (conf.w > 0 && conf.h > 0) {
            SDL_SetWindowSize(win, conf.w, conf.h);
        }
        if (conf.has_pos) {
            SDL_SetWindowPosition(win, conf.x, conf.y);
        }
        apply_border();
    }
    schedule_save();
}

static void set_border(bool on) {
    if (win == NULL) {
        return;
    }
    conf.border = on ? 1 : 0;
    apply_border();
    schedule_save();
}

// ---- drawing ----

static bool ensure_canvas(int w, int h) {
    if (canvas != NULL && canvas_w == w && canvas_h == h) {
        return true;
    }
    free_canvas();
    canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    if (cairo_surface_status(canvas) != CAIRO_STATUS_SUCCESS) {
        free_canvas();
        return false;
    }
    cairo_surface_flush(canvas);
    canvas_sdl = SDL_CreateRGBSurfaceWithFormatFrom(cairo_image_surface_get_data(canvas), w, h, 32, cairo_image_surface_get_stride(canvas),
                                                    SDL_PIXELFORMAT_RGB888);
    if (canvas_sdl == NULL) {
        free_canvas();
        return false;
    }
    SDL_SetSurfaceBlendMode(canvas_sdl, SDL_BLENDMODE_NONE);
    canvas_w = w;
    canvas_h = h;
    return true;
}

static void draw_toast(cairo_t *cr, int w, int h, const char *text, bool recording) {
    double k = fmin(2.0, fmax(0.8, w / 992.0));
    cairo_select_font_face(cr, "Helvetica Neue", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 14 * k);
    cairo_text_extents_t te;
    cairo_text_extents(cr, text, &te);
    double dot = recording ? 22 * k : 0;
    double pw = te.x_advance + 36 * k + dot, ph = 36 * k;
    if (pw > w - 20) {
        pw = w - 20;
    }
    double x = (w - pw) / 2, y = h - ph - 14 * k;
    cairo_new_path(cr);
    cairo_arc(cr, x + ph / 2, y + ph / 2, ph / 2, M_PI / 2, 3 * M_PI / 2);
    cairo_arc(cr, x + pw - ph / 2, y + ph / 2, ph / 2, -M_PI / 2, M_PI / 2);
    cairo_close_path(cr);
    cairo_set_source_rgba(cr, 0.114, 0.118, 0.129, 0.92);
    cairo_fill(cr);
    if (recording) {
        cairo_arc(cr, x + 22 * k, y + ph / 2, 6 * k, 0, 2 * M_PI);
        cairo_set_source_rgb(cr, 1, 0.27, 0.23);
        cairo_fill(cr);
    }
    cairo_save(cr);
    cairo_rectangle(cr, x + 12 * k, y, pw - 24 * k, ph);
    cairo_clip(cr);
    cairo_move_to(cr, x + 18 * k + dot - te.x_bearing, y + ph / 2 - te.height / 2 - te.y_bearing);
    cairo_set_source_rgb(cr, 0.949, 0.953, 0.961);
    cairo_show_text(cr, text);
    cairo_restore(cr);
}

void screen_window_draw(cairo_surface_t *picture, const char *toast, bool recording) {
    if (win == NULL || picture == NULL) {
        return;
    }
    SDL_Surface *dst = SDL_GetWindowSurface(win);
    if (dst == NULL || !ensure_canvas(dst->w, dst->h)) {
        return;
    }
    sw_picture_t p;
    sw_picture_fit(dst->w, dst->h, &p);
    cairo_t *cr = cairo_create(canvas);
    cairo_set_source_rgb(cr, 0, 0, 0);
    cairo_paint(cr);
    if (p.w > 0) {
        if (p.scale > 0) {
            cairo_save(cr);
            cairo_translate(cr, p.x, p.y);
            cairo_scale(cr, p.scale, p.scale);
            cairo_set_source_surface(cr, picture, 0, 0);
            cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
            cairo_rectangle(cr, 0, 0, 128, 64);
            cairo_fill(cr);
            cairo_restore(cr);
        } else {
            // between whole multiples: nearest to a whole multiple (no blur inside a pixel), then scaled down
            int m = (int)ceil(p.w / 128.0);
            if (big == NULL || big_m != m) {
                if (big != NULL) {
                    cairo_surface_destroy(big);
                }
                big = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128 * m, 64 * m);
                big_m = m;
            }
            cairo_t *bc = cairo_create(big);
            cairo_scale(bc, m, m);
            cairo_set_source_surface(bc, picture, 0, 0);
            cairo_pattern_set_filter(cairo_get_source(bc), CAIRO_FILTER_NEAREST);
            cairo_paint(bc);
            cairo_destroy(bc);
            cairo_save(cr);
            cairo_translate(cr, p.x, p.y);
            cairo_scale(cr, (double)p.w / (128 * m), (double)p.h / (64 * m));
            cairo_set_source_surface(cr, big, 0, 0);
            cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR);
            cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
            cairo_rectangle(cr, 0, 0, 128 * m, 64 * m);
            cairo_fill(cr);
            cairo_restore(cr);
        }
    }
    if (toast != NULL && toast[0] != '\0') {
        draw_toast(cr, dst->w, dst->h, toast, recording);
    }
    cairo_destroy(cr);
    cairo_surface_flush(canvas);
    SDL_BlitSurface(canvas_sdl, NULL, dst, NULL);
    SDL_UpdateWindowSurface(win);
}

// ---- events ----

bool screen_window_toggle_fullscreen(void) {
    if (win == NULL) {
        return false;
    }
    set_fullscreen(!conf.fullscreen);
    return true;
}

bool screen_window_event(const SDL_Event *ev, sw_action_t *act) {
    *act = SW_NONE;
    if (ev->type == own_event) {
        unsigned gen = (unsigned)(uintptr_t)ev->user.data1;
        if (ev->user.code == EV_SAVE && gen == save_gen) {
            screen_window_save_now();
        } else if (ev->user.code == EV_HIDE_CURSOR && gen == hide_gen && win != NULL && conf.fullscreen) {
            SDL_ShowCursor(SDL_DISABLE);
        }
        return true;
    }
    if (ev->type == SDL_KEYDOWN || ev->type == SDL_KEYUP) {
        SDL_Scancode sc = ev->key.keysym.scancode;
        if (sc == SDL_SCANCODE_F9) {
            if (ev->type == SDL_KEYDOWN && !ev->key.repeat) {
                *act = SW_TOGGLE;
            }
            return true;
        }
        if (sc == SDL_SCANCODE_F11) {
            // F11 is the screen window's: fullscreen there (Shift: the frame); nothing in the box, and it is not passed on to scripts
            if (ev->type == SDL_KEYDOWN && !ev->key.repeat && win != NULL && ev->key.windowID == SDL_GetWindowID(win)) {
                if (ev->key.keysym.mod & KMOD_SHIFT) {
                    set_border(!conf.border);
                } else {
                    set_fullscreen(!conf.fullscreen);
                }
            }
            return true;
        }
    }
    if (win == NULL) {
        return false;
    }
    Uint32 id = SDL_GetWindowID(win);
    switch (ev->type) {
    case SDL_MOUSEMOTION:
        if (ev->motion.windowID != id) {
            return false;
        }
        if (conf.fullscreen) {
            SDL_ShowCursor(SDL_ENABLE);
            hide_gen++;
            after(2000, EV_HIDE_CURSOR, hide_gen);
        }
        return true;
    case SDL_MOUSEBUTTONDOWN:
        if (ev->button.windowID != id) {
            return false;
        }
        // a double click is fullscreen, and back (with no frame the drag area keeps the clicks, F11 does it)
        if (ev->button.button == SDL_BUTTON_LEFT && ev->button.clicks >= 2) {
            set_fullscreen(!conf.fullscreen);
        }
        return true;
    case SDL_MOUSEBUTTONUP:
    case SDL_MOUSEWHEEL:
        return (ev->type == SDL_MOUSEBUTTONUP ? ev->button.windowID : ev->wheel.windowID) == id;
    case SDL_WINDOWEVENT:
        if (ev->window.windowID != id) {
            return false;
        }
        switch (ev->window.event) {
        case SDL_WINDOWEVENT_CLOSE:
            *act = SW_REDOCK;
            break;
        case SDL_WINDOWEVENT_MOVED:
            track();
            schedule_save();
            break;
        case SDL_WINDOWEVENT_SIZE_CHANGED:
        case SDL_WINDOWEVENT_RESIZED:
            track();
            schedule_save();
            *act = SW_REDRAW;
            break;
        case SDL_WINDOWEVENT_EXPOSED:
        case SDL_WINDOWEVENT_RESTORED:
        case SDL_WINDOWEVENT_SHOWN:
            *act = SW_REDRAW;
            break;
        default:
            break;
        }
        return true;
    default:
        return false;
    }
}
