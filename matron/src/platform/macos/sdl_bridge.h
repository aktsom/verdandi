/*
 * sdl_bridge.h
 *
 * cocoa only allows windows and the event pump on the main thread, but matron draws from
 * its own thread. on macOS the main thread runs sdl_bridge_run(); matron asks it to create
 * the window and to present frames, and it turns window input into key/enc events.
 */

#pragma once

#include <SDL2/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

// main thread only
extern void sdl_bridge_init(void);
extern void sdl_bridge_run(void); // does not return; window close quits matron

// any thread; blocks until the main thread has done the work
extern SDL_Window *sdl_bridge_create_window(const char *title, int w, int h);
extern void sdl_bridge_present(SDL_Window *window, SDL_Surface *src);
extern void sdl_bridge_destroy_window(SDL_Window *window);

// any thread, does not block: a key (value 0/1) or enc (value = delta) event reached
// norns; the window moves the control to match
#define SDL_BRIDGE_SHOW_KEY 1
#define SDL_BRIDGE_SHOW_ENC 2
#define SDL_BRIDGE_SHOW_PAGE 3 // n = menu page 1-4, 0 = script
extern void sdl_bridge_show_control(int kind, int n, int value);

// any thread, does not block: open or close the virtual grid window
extern void sdl_bridge_toggle_grid(void);

#ifdef __cplusplus
}
#endif
