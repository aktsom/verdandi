/*
 * sdl_bridge.cc
 *
 * main-thread side of the macOS screen/input path (see sdl_bridge.h).
 *
 * the window shows the device (device_skin.h): the oled behind its bezel and K1-K3 /
 * E1-E3 where they sit on a standard norns. click a key to press it (held while the
 * button is held); drag a knob up/right or down/left, or use the wheel over it, to turn
 * it. the wheel elsewhere turns the nearest knob. keys and knobs show what norns
 * receives, whatever sent it (mouse, keyboard, midi mapping): matron reports every
 * key/enc event back through sdl_bridge_show_control().
 *
 * keyboard: plain keys go to norns as the usb keyboard, where lua/core/keyboard.lua turns
 * 1 2 3 / QW AS ZX into K1-3 / E1-3 when nothing else wants them. window_keys.h adds the
 * overrides for scripts that use the keyboard: Option + those keys, and Option+Esc to force
 * them without Option. the computer keyboard is not mapped to keys/encs: while the
 * window has focus it is the norns usb keyboard (virtual hid device, linux key codes), as
 * on hardware.
 */

#include <cairo.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "event_types.h"
#include "events.h"

#include "device_monitor_macos.h"
#include "device_skin.h"
#include "window_keys.h"
#include "sdl_bridge.h"

typedef enum {
    BRIDGE_CREATE_WINDOW,
    BRIDGE_PRESENT,
    BRIDGE_DESTROY_WINDOW,
} bridge_op_t;

typedef struct {
    bridge_op_t op;
    const char *title;
    int w, h;
    SDL_Window *window;
    SDL_Surface *src;
    dispatch_semaphore_t done;
} bridge_req_t;

static Uint32 bridge_event_type = (Uint32)-1;
static Uint32 show_event_type = (Uint32)-1;
static pthread_t main_thread;

//--- drawing (main thread only)

static SDL_Window *the_window = NULL;
static skin_state_t skin = {};
static skin_geom_t geom = {};
// the last oled frame, kept so the window can be redrawn without matron
static cairo_surface_t *oled = NULL;
static int have_frame = 0;
// the device without the oled, at the current size
static cairo_surface_t *static_layer = NULL;
// what goes to the window
static cairo_surface_t *canvas = NULL;
static SDL_Surface *canvas_sdl = NULL;

static void free_layers(void) {
    if (canvas_sdl != NULL) {
        SDL_FreeSurface(canvas_sdl);
        canvas_sdl = NULL;
    }
    if (canvas != NULL) {
        cairo_surface_destroy(canvas);
        canvas = NULL;
    }
    if (static_layer != NULL) {
        cairo_surface_destroy(static_layer);
        static_layer = NULL;
    }
}

// (re)build the layers for a w x h pixel window surface; false if out of memory
static bool ensure_layers(int w, int h) {
    if (canvas != NULL && geom.w == w && geom.h == h) {
        return true;
    }
    free_layers();
    skin_geom(w, h, &geom);
    static_layer = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    if (cairo_surface_status(static_layer) != CAIRO_STATUS_SUCCESS ||
        cairo_surface_status(canvas) != CAIRO_STATUS_SUCCESS) {
        free_layers();
        return false;
    }
    cairo_t *cr = cairo_create(static_layer);
    skin_draw_static(cr, &geom);
    cairo_destroy(cr);
    // cairo RGB24 is native-endian xRGB, which is SDL's RGB888
    cairo_surface_flush(canvas);
    canvas_sdl = SDL_CreateRGBSurfaceWithFormatFrom(cairo_image_surface_get_data(canvas), w, h, 32,
                                                    cairo_image_surface_get_stride(canvas), SDL_PIXELFORMAT_RGB888);
    if (canvas_sdl == NULL) {
        free_layers();
        return false;
    }
    SDL_SetSurfaceBlendMode(canvas_sdl, SDL_BLENDMODE_NONE);
    return true;
}

static void draw_oled(cairo_t *cr) {
    if (have_frame) {
        skin_draw_oled(cr, &geom, oled);
    }
}

// full: the whole device; otherwise only the oled
static void redraw(bool full) {
    if (the_window == NULL) {
        return;
    }
    SDL_Surface *dst = SDL_GetWindowSurface(the_window);
    if (dst == NULL || !ensure_layers(dst->w, dst->h)) {
        return;
    }
    cairo_t *cr = cairo_create(canvas);
    SDL_Rect r;
    if (full) {
        cairo_set_source_surface(cr, static_layer, 0, 0);
        cairo_paint(cr);
        skin_draw_controls(cr, &geom, &skin);
        draw_oled(cr);
        r = {0, 0, dst->w, dst->h};
    } else {
        draw_oled(cr);
        // the bezel interior, generously
        int pad = (int)(20 * geom.s);
        r = {geom.oled_x - pad, geom.oled_y - pad, 128 * geom.oled_px + 2 * pad, 64 * geom.oled_px + 2 * pad};
    }
    cairo_destroy(cr);
    cairo_surface_flush(canvas);
    SDL_Rect clip = r;
    SDL_BlitSurface(canvas_sdl, &clip, dst, &r);
    SDL_UpdateWindowSurfaceRects(the_window, &r, 1);
}

static void present(SDL_Window *window, SDL_Surface *src) {
    // a frame for a window that is gone (quit) is dropped
    if (src == NULL || window == NULL || window != the_window) {
        return;
    }
    if (oled == NULL) {
        oled = cairo_image_surface_create(CAIRO_FORMAT_RGB24, src->w, src->h);
    }
    cairo_surface_flush(oled);
    SDL_ConvertPixels(src->w, src->h, src->format->format, src->pixels, src->pitch, SDL_PIXELFORMAT_RGB888,
                      cairo_image_surface_get_data(oled), cairo_image_surface_get_stride(oled));
    cairo_surface_mark_dirty(oled);
    bool first = !have_frame;
    have_frame = 1;
    redraw(first || canvas == NULL);
}

// dock icon from the png in NORNS_ICON (set by macos/norns.sh)
static void set_icon(SDL_Window *window) {
    const char *path = getenv("NORNS_ICON");
    if (path == NULL) {
        return;
    }
    cairo_surface_t *img = cairo_image_surface_create_from_png(path);
    if (cairo_surface_status(img) == CAIRO_STATUS_SUCCESS) {
        // cairo ARGB32 is native-endian ARGB, which is SDL's ARGB8888
        SDL_Surface *s = SDL_CreateRGBSurfaceWithFormatFrom(
            cairo_image_surface_get_data(img), cairo_image_surface_get_width(img), cairo_image_surface_get_height(img),
            32, cairo_image_surface_get_stride(img), SDL_PIXELFORMAT_ARGB8888);
        if (s != NULL) {
            SDL_SetWindowIcon(window, s);
            SDL_FreeSurface(s);
        }
    }
    cairo_surface_destroy(img);
}

static void bridge_do(bridge_req_t *req) {
    switch (req->op) {
    case BRIDGE_CREATE_WINDOW:
        // the window is the device: one layout unit per point (sdl.cc's 512x256 is for the bare oled)
        (void)req->w;
        (void)req->h;
        req->window =
            SDL_CreateWindow(req->title, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, SKIN_W + 2 * SKIN_MARGIN,
                             SKIN_H + 2 * SKIN_MARGIN, SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE);
        if (req->window == NULL) {
            fprintf(stderr, "sdl_bridge: SDL_CreateWindow failed: %s\n", SDL_GetError());
        } else {
            SDL_SetWindowMinimumSize(req->window, (SKIN_W + 2 * SKIN_MARGIN) / 2, (SKIN_H + 2 * SKIN_MARGIN) / 2);
            set_icon(req->window);
            the_window = req->window;
        }
        break;
    case BRIDGE_PRESENT:
        present(req->window, req->src);
        break;
    case BRIDGE_DESTROY_WINDOW:
        if (the_window == req->window) {
            the_window = NULL;
            free_layers();
        }
        SDL_DestroyWindow(req->window);
        break;
    }
}

static void bridge_call(bridge_req_t *req) {
    if (pthread_equal(pthread_self(), main_thread)) {
        bridge_do(req);
        return;
    }
    req->done = dispatch_semaphore_create(0);
    SDL_Event ev;
    SDL_zero(ev);
    ev.type = bridge_event_type;
    ev.user.data1 = req;
    if (SDL_PushEvent(&ev) < 1) {
        fprintf(stderr, "sdl_bridge: SDL_PushEvent failed: %s\n", SDL_GetError());
    } else {
        dispatch_semaphore_wait(req->done, DISPATCH_TIME_FOREVER);
    }
    dispatch_release(req->done);
}

//--- input

static void post_key(int n, int z) {
    union event_data *ev = event_data_new(EVENT_KEY);
    ev->key.n = n;
    ev->key.val = z;
    event_post(ev);
}

static void post_enc(int n, int delta) {
    union event_data *ev = event_data_new(EVENT_ENC);
    ev->enc.n = n;
    ev->enc.delta = delta;
    event_post(ev);
}

// window points -> window surface pixels (retina)
static void to_pixels(Uint32 window_id, int x, int y, double *px, double *py) {
    SDL_Window *window = SDL_GetWindowFromID(window_id);
    int ww = 1, wh = 1;
    if (window != NULL) {
        SDL_GetWindowSize(window, &ww, &wh);
    }
    double k = geom.w > 0 && ww > 0 ? (double)geom.w / ww : 1;
    *px = x * k;
    *py = y * k;
}

static int held_key = 0; // key held by the mouse, 1-3
static int drag_enc = 0; // knob turned by the mouse, 1-3
static double drag_acc = 0;
static int drag_x, drag_y;
// mouse travel per detent, in layout units
#define DRAG_STEP 5.0

static SDL_Cursor *cursor_hand = NULL;
static SDL_Cursor *cursor_arrow = NULL;

static void set_hover(int control) {
    if (control == skin.hover) {
        return;
    }
    skin.hover = control;
    if (cursor_hand == NULL) {
        cursor_hand = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND);
        cursor_arrow = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
    }
    SDL_SetCursor(control != SKIN_NONE ? cursor_hand : cursor_arrow);
    redraw(true);
}

static void handle_button(const SDL_MouseButtonEvent *b) {
    if (b->button != SDL_BUTTON_LEFT) {
        return;
    }
    if (b->type == SDL_MOUSEBUTTONDOWN) {
        if (held_key != 0 || drag_enc != 0) {
            return;
        }
        double px, py;
        to_pixels(b->windowID, b->x, b->y, &px, &py);
        int c = skin_hit(&geom, px, py);
        if (c >= SKIN_K1 && c <= SKIN_K3) {
            held_key = c - SKIN_K1 + 1;
            post_key(held_key, 1);
        } else if (c >= SKIN_E1 && c <= SKIN_E3) {
            drag_enc = c - SKIN_E1 + 1;
            drag_acc = 0;
            drag_x = b->x;
            drag_y = b->y;
            // keep getting motion when the pointer leaves the window
            SDL_CaptureMouse(SDL_TRUE);
        }
    } else {
        if (held_key != 0) {
            post_key(held_key, 0);
            held_key = 0;
        }
        if (drag_enc != 0) {
            drag_enc = 0;
            SDL_CaptureMouse(SDL_FALSE);
        }
    }
}

static void handle_motion(const SDL_MouseMotionEvent *m) {
    if (drag_enc != 0) {
        // up and right turn clockwise
        double px0, py0, px1, py1;
        to_pixels(m->windowID, drag_x, drag_y, &px0, &py0);
        to_pixels(m->windowID, m->x, m->y, &px1, &py1);
        drag_x = m->x;
        drag_y = m->y;
        drag_acc += ((px1 - px0) - (py1 - py0)) / (geom.s > 0 ? geom.s : 1);
        int ticks = (int)(drag_acc / DRAG_STEP);
        if (ticks != 0) {
            drag_acc -= ticks * DRAG_STEP;
            post_enc(drag_enc, ticks);
        }
        return;
    }
    if (held_key != 0) {
        return;
    }
    double px, py;
    to_pixels(m->windowID, m->x, m->y, &px, &py);
    set_hover(skin_hit(&geom, px, py));
}

static void handle_wheel(const SDL_MouseWheelEvent *w) {
    if (w->y == 0) {
        return;
    }
    int mx, my;
    SDL_GetMouseState(&mx, &my);
    double px, py;
    to_pixels(w->windowID, mx, my, &px, &py);
    int c = skin_hit(&geom, px, py);
    int n = c >= SKIN_E1 && c <= SKIN_E3 ? c - SKIN_E1 + 1 : skin_nearest_enc(&geom, px, py);
    int delta = w->direction == SDL_MOUSEWHEEL_FLIPPED ? -w->y : w->y;
    post_enc(n, delta);
}

static window_keys_t keys;

static void handle_key(const SDL_KeyboardEvent *k) {
    window_key_event_t out;
    int option = (k->keysym.mod & KMOD_ALT) != 0;
    int shift = (k->keysym.mod & KMOD_SHIFT) != 0;
    // SDL scancodes are USB HID keyboard usages
    if (!window_keys_process(&keys, (int)k->keysym.scancode, k->type == SDL_KEYDOWN, k->repeat, option, shift, &out)) {
        return;
    }
    switch (out.kind) {
    case WK_KEY:
        post_key(out.n, out.value);
        break;
    case WK_ENC:
        post_enc(out.n, out.value);
        break;
    case WK_HID:
        macos_hid_keyboard_event((uint16_t)out.n, out.value);
        break;
    case WK_MODE: {
        SDL_Window *window = SDL_GetWindowFromID(k->windowID);
        if (window != NULL) {
            SDL_SetWindowTitle(window, out.value ? "norns · keys" : "norns");
        }
        break;
    }
    }
}

// a key/enc event reached norns: move the control on screen
static void handle_show(int kind, int n, int value) {
    if (n < 1 || n > 3) {
        return;
    }
    if (kind == SDL_BRIDGE_SHOW_KEY) {
        skin.key_down[n - 1] = value != 0;
    } else {
        skin.enc_ticks[n - 1] += value;
    }
    redraw(true);
}

void sdl_bridge_init(void) {
    main_thread = pthread_self();
    window_keys_init(&keys);
    // keep default SIGINT/SIGTERM behaviour (terminate), as on linux; SDL would otherwise
    // swallow them as SDL_QUIT
    SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
    // the first click into the window already presses a key
    SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "sdl_bridge: SDL_Init failed: %s\n", SDL_GetError());
    }
    bridge_event_type = SDL_RegisterEvents(2);
    show_event_type = bridge_event_type + 1;
}

void sdl_bridge_show_control(int kind, int n, int value) {
    if (show_event_type == (Uint32)-1) {
        return;
    }
    SDL_Event ev;
    SDL_zero(ev);
    ev.type = show_event_type;
    ev.user.code = kind;
    ev.user.data1 = (void *)(intptr_t)n;
    ev.user.data2 = (void *)(intptr_t)value;
    SDL_PushEvent(&ev);
}

void sdl_bridge_run(void) {
    SDL_Event ev;
    for (;;) {
        if (!SDL_WaitEvent(&ev)) {
            continue;
        }
        if (ev.type == bridge_event_type) {
            bridge_req_t *req = (bridge_req_t *)ev.user.data1;
            bridge_do(req);
            dispatch_semaphore_signal(req->done);
            continue;
        }
        if (ev.type == show_event_type) {
            handle_show(ev.user.code, (int)(intptr_t)ev.user.data1, (int)(intptr_t)ev.user.data2);
            continue;
        }
        switch (ev.type) {
        case SDL_QUIT:
            // window closed: let matron leave its event loop; the norns thread cleans up
            // and exits the process
            event_post(event_data_new(EVENT_QUIT));
            break;
        case SDL_KEYDOWN:
        case SDL_KEYUP:
            handle_key(&ev.key);
            break;
        case SDL_MOUSEWHEEL:
            handle_wheel(&ev.wheel);
            break;
        case SDL_MOUSEBUTTONDOWN:
        case SDL_MOUSEBUTTONUP:
            handle_button(&ev.button);
            break;
        case SDL_MOUSEMOTION:
            handle_motion(&ev.motion);
            break;
        case SDL_WINDOWEVENT:
            if (ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED || ev.window.event == SDL_WINDOWEVENT_EXPOSED) {
                redraw(true);
            } else if (ev.window.event == SDL_WINDOWEVENT_LEAVE && held_key == 0 && drag_enc == 0) {
                set_hover(SKIN_NONE);
            }
            break;
        default:
            break;
        }
    }
}

SDL_Window *sdl_bridge_create_window(const char *title, int w, int h) {
    bridge_req_t req = {};
    req.op = BRIDGE_CREATE_WINDOW;
    req.title = title;
    req.w = w;
    req.h = h;
    bridge_call(&req);
    return req.window;
}

void sdl_bridge_present(SDL_Window *window, SDL_Surface *src) {
    bridge_req_t req = {};
    req.op = BRIDGE_PRESENT;
    req.window = window;
    req.src = src;
    bridge_call(&req);
}

void sdl_bridge_destroy_window(SDL_Window *window) {
    bridge_req_t req = {};
    req.op = BRIDGE_DESTROY_WINDOW;
    req.window = window;
    bridge_call(&req);
}
