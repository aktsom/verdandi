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

#ifdef __cplusplus
}
#endif
