/*
 * screen_window.h: the detached screen window (docs/port/detach-plan.md). Linux desktop only.
 *
 * a second SDL window ("Verdandi screen") that shows only the screen: the picture the box would show, through the same look (SYSTEM > UI), nothing around
 * it, resizable, fullscreen on F11, the desktop's title bar or none (Shift+F11). everything runs on the main thread (sdl_bridge.cc's event loop). the box
 * (sdl_bridge.cc) decides what the rest of norns sees: while this window is open it draws a placeholder where the screen was.
 *
 * keys: F9 detaches and brings it back (from any window), F11 is fullscreen, Shift+F11 the frame; closing the window brings the screen back. the state
 * (size, place, fullscreen, frame, detached) is saved in <norns home>/screen-window.conf (screen_window_conf.h).
 */

#pragma once

#include <SDL2/SDL.h>
#include <cairo.h>

typedef enum {
    SW_NONE = 0,
    SW_TOGGLE, // F9: detach or bring back
    SW_REDOCK, // the window's close button: bring the screen back
    SW_REDRAW, // the window needs its picture again (resized, exposed)
} sw_action_t;

// once, on the main thread after SDL_Init: reads the state file, registers the window's own timer event
extern void screen_window_init(void);
extern bool screen_window_wanted_at_start(void); // the file says detached
extern bool screen_window_is_open(void);
extern Uint32 screen_window_id(void);

// opens the window near main (placement, display); decorate gives it the icon. false if SDL could not make it
extern bool screen_window_open(SDL_Window *main, void (*decorate)(SDL_Window *));
// closes it; the state file then says docked
extern void screen_window_close(void);
// the picture (the screen as the box would show it: raw or through the look), with the toast pill at the bottom while there is one
extern void screen_window_draw(cairo_surface_t *picture, const char *toast, bool recording);

// every SDL event goes through here first: true if the window (or its timers, or F9/F11) used it; *act says what the box has to do
extern bool screen_window_event(const SDL_Event *ev, sw_action_t *act);
// fullscreen on and back, as F11 does (a MIDI action, docs/port/midi-actions-plan.md); false when the screen is not in its own window
extern bool screen_window_toggle_fullscreen(void);

// at quit: writes the state now (it also saves itself half a second after a change)
extern void screen_window_save_now(void);
