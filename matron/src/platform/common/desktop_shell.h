/*
 * desktop_shell.h
 *
 * what sdl_bridge.cc needs from the desktop it runs on: menu, file picker, opening folders and
 * pages, the window keyboard as a hid keyboard, the option key. macOS: the functions it always had
 * (mac_menu.h, open_url.h, device_monitor_macos.h), only renamed here by macros, so nothing in the
 * macOS build changes. Linux: platform/linux/desktop_shell_linux.cc.
 */

#pragma once

#include <stdint.h>

#include "platform/common/desktop_platform.h"

#ifdef __APPLE__

#include "../macos/device_monitor_macos.h"
#include "../macos/mac_menu.h"
#include "../macos/open_url.h"

#define SHELL_MENU_IMPORT MAC_MENU_IMPORT
#define SHELL_MENU_DUST MAC_MENU_DUST
#define SHELL_MENU_TAPE MAC_MENU_TAPE
#define SHELL_MENU_SCREENSHOT MAC_MENU_SCREENSHOT
#define SHELL_MENU_GIF MAC_MENU_GIF
#define SHELL_MENU_GRID MAC_MENU_GRID
#define SHELL_MENU_ARC MAC_MENU_ARC
#define SHELL_MENU_KEYS MAC_MENU_KEYS

#define SHELL_IMPORT_LINK MAC_IMPORT_LINK
#define SHELL_IMPORT_COPY MAC_IMPORT_COPY
#define SHELL_IMPORT_TAKE MAC_IMPORT_TAKE

#define shell_install mac_menu_install
#define shell_set_app_name mac_set_app_name
#define shell_set_input mac_menu_set_input
#define shell_set_recording mac_menu_set_recording
#define shell_option_held mac_option_held
#define shell_adopt_windows mac_drop_adopt_windows
#define shell_choose_file mac_menu_choose_file
#define shell_choose_file_close mac_menu_choose_file_close
#define shell_open_url macos_open_url
#define shell_hid_keyboard_event macos_hid_keyboard_event

// macOS has a menu bar: no menu in the window
#define shell_menu_is_open() 0
#define shell_menu_mouse(type, button, px, py, scale, w, h) 0
#define shell_menu_key(down, scancode, mods, px, py, scale, w, h) 0
#define shell_menu_draw(cr, w, h) ((void)0)

#else // desktop Linux

#include <cairo.h>

#include "../macos/open_url.h"
#define shell_open_url macos_open_url // http(s) or an absolute path, 0 = started (xdg-open here)

#ifdef __cplusplus
extern "C" {
#endif

// every item calls back with its id on the main thread
enum {
    SHELL_MENU_IMPORT = 1, // the file picker; the chosen paths come to the import callback
    SHELL_MENU_DUST,       // dust in the file manager
    SHELL_MENU_TAPE,       // dust/audio/tape in the file manager
    SHELL_MENU_SCREENSHOT, // the screen as png
    SHELL_MENU_GIF,        // start / stop a gif recording of the screen
    SHELL_MENU_GRID,
    SHELL_MENU_ARC,
    SHELL_MENU_KEYS,
    SHELL_MENU_IMPORT_FOLDER, // (handled by the shell, like IMPORT)
    SHELL_MENU_COPY_SAMPLES,  // toggle: audio is copied into dust, not linked (the shell's own)
    SHELL_MENU_INPUT_MIC,     // (the shell calls on_input)
    SHELL_MENU_INPUT_OFF,
    SHELL_MENU_INPUT_SYSTEM,  // all applications but norns
    SHELL_MENU_INPUT_MONITOR, // the monitor of the output card (an option: it hears norns too)
    SHELL_MENU_QUIT,
    SHELL_MENU_SCREEN,      // toggle: the screen in its own window (the bridge does it; the shell only shows the tick)
    SHELL_MENU_FILE_DIALOG, // toggle: a script's file chooser also opens the system's file dialog (saved by lua, ui.conf file_dialog)
    SHELL_MENU_SHOW_BUTTONS, // toggle: the row of page buttons is drawn (saved by lua, box.conf show_buttons; docs/port/box-style-plan.md)
    SHELL_MENU_MUTE,         // Ctrl+M too: the output off and back (the bridge calls lua's output_mute; the shell only shows the tick)
    SHELL_MENU_MAIDEN,       // the menu twins of the MAIDEN and MANUAL buttons, for when the row is hidden
    SHELL_MENU_MANUAL,
    SHELL_MENU_INPUT_APP = 40, // + n: the n-th application of the list
};

// how the import callback takes a path
enum {
    SHELL_IMPORT_LINK = 0, // audio linked from dust/audio/mac (scripts are always copied)
    SHELL_IMPORT_COPY = 1, // copied into dust
    SHELL_IMPORT_TAKE = 2, // copied into dust, then the path is removed
};

// main thread, after SDL_Init. on_note shows a short message on the device (any thread). on_input:
// the audio input menu chose mode "mic", "system", "off" or "app" (NULL bundle/name on linux); lua
// decides, and says so through shell_set_input
extern void shell_install(void (*on_item)(int id), void (*on_import)(const char *path, int mode),
                          void (*on_note)(const char *text),
                          void (*on_input)(const char *mode, const char *bundle, const char *name));
extern void shell_set_app_name(const char *name); // a no-op here
extern void shell_set_input(int input);           // SKIN_INPUT_*: for the menu's checkmarks
extern void shell_set_recording(int on);          // the GIF item says "Stop" while recording
extern int shell_option_held(void);               // shift held: a drop is copied, not linked
extern void shell_adopt_windows(void);            // a no-op here
extern void shell_choose_file(const char *dir, const char *dust, void (*done)(const char *path));
extern void shell_choose_file_close(void);
extern void shell_set_file_dialog(int on); // any thread: lua says what ui.conf holds (the tick in the menu)
extern int shell_get_file_dialog(void);
extern void shell_set_screen_out(int on); // main thread: the screen is in its own window (the tick of "Screen in its own window")
extern void shell_set_buttons_shown(int on); // main thread: the tick of "Show the page buttons"
extern int shell_get_buttons_shown(void);
extern void shell_set_muted(int on); // main thread: the tick of "Mute output"
extern void shell_hid_keyboard_event(uint16_t usage, int value);

// the in-window menu (there is no menu bar). the window gives it the events of the norns window
// (mouse in window pixels) and draws it over the device; scale: pixels per layout unit
// (1.0 at 96 dpi). all return bit 1 if the event was used (the window does not handle it), bit 2
// if the window must be redrawn
#define SHELL_USED 1
#define SHELL_REDRAW 2
extern int shell_menu_is_open(void);
// type 0 motion, 1 button down, 2 button up; button = SDL_BUTTON_*
extern int shell_menu_mouse(int type, int button, double px, double py, double scale, int w, int h);
// a key of the norns window; mods = SDL_Keymod; px, py: where the pointer is (F10 opens the menu there)
extern int shell_menu_key(int down, int scancode, int mods, double px, double py, double scale, int w, int h);
extern void shell_menu_draw(cairo_t *cr, int w, int h);

// the virtual keyboard window's MIDI source ("norns keys", see phase-2.md)
extern int shell_keys_open(void); // 0 = ready
extern void shell_keys_close(void);
extern int shell_keys_is_open(void);
extern void shell_keys_send(uint8_t status, uint8_t d1, uint8_t d2);

#ifdef __cplusplus
}
#endif

#endif
