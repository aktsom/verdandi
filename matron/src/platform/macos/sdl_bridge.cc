/*
 * sdl_bridge.cc
 *
 * main-thread side of the macOS screen/input path (see sdl_bridge.h).
 *
 * window controls: the left / middle / right third of the window is K1+E1 / K2+E2 / K3+E3.
 * a mouse click there presses the key (held while the button is held, so K1 + turn works),
 * the wheel turns the encoder. the computer keyboard is not mapped to keys/encs: while the
 * window has focus it is the norns usb keyboard (virtual hid device, linux key codes), as
 * on hardware.
 */

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

#include "event_types.h"
#include "events.h"

#include "device_monitor_macos.h"
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
static pthread_t main_thread;

static void bridge_do(bridge_req_t *req) {
    switch (req->op) {
    case BRIDGE_CREATE_WINDOW:
        req->window = SDL_CreateWindow(req->title, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, req->w, req->h,
                                       SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI);
        if (req->window == NULL) {
            fprintf(stderr, "sdl_bridge: SDL_CreateWindow failed: %s\n", SDL_GetError());
        }
        break;
    case BRIDGE_PRESENT: {
        SDL_Surface *dst = SDL_GetWindowSurface(req->window);
        if (dst != NULL) {
            SDL_BlitScaled(req->src, NULL, dst, NULL);
            SDL_UpdateWindowSurface(req->window);
        }
        break;
    }
    case BRIDGE_DESTROY_WINDOW:
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

// window third under x -> 1..3
static int window_third(Uint32 window_id, int x) {
    SDL_Window *window = SDL_GetWindowFromID(window_id);
    int ww = 0, wh = 0;
    if (window != NULL) {
        SDL_GetWindowSize(window, &ww, &wh);
    }
    int n = 1 + (x * 3) / (ww > 0 ? ww : 1);
    return n < 1 ? 1 : (n > 3 ? 3 : n);
}

static int held_key = 0;

static void handle_button(const SDL_MouseButtonEvent *b) {
    if (b->button != SDL_BUTTON_LEFT) {
        return;
    }
    if (b->type == SDL_MOUSEBUTTONDOWN && held_key == 0) {
        held_key = window_third(b->windowID, b->x);
        post_key(held_key, 1);
    } else if (b->type == SDL_MOUSEBUTTONUP && held_key != 0) {
        post_key(held_key, 0);
        held_key = 0;
    }
}

static void handle_key(const SDL_KeyboardEvent *k) {
    // SDL scancodes are USB HID keyboard usages; evdev reports autorepeat as value 2
    int value = k->type == SDL_KEYUP ? 0 : (k->repeat ? 2 : 1);
    macos_hid_keyboard_event((uint16_t)k->keysym.scancode, value);
}

static void handle_wheel(const SDL_MouseWheelEvent *w) {
    if (w->y == 0) {
        return;
    }
    int mx, my;
    SDL_GetMouseState(&mx, &my);
    int n = window_third(w->windowID, mx);
    int delta = w->direction == SDL_MOUSEWHEEL_FLIPPED ? -w->y : w->y;
    post_enc(n, delta);
}

void sdl_bridge_init(void) {
    main_thread = pthread_self();
    // keep default SIGINT/SIGTERM behaviour (terminate), as on linux; SDL would otherwise
    // swallow them as SDL_QUIT
    SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "sdl_bridge: SDL_Init failed: %s\n", SDL_GetError());
    }
    bridge_event_type = SDL_RegisterEvents(1);
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
