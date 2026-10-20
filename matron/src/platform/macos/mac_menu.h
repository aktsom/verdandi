/*
 * mac_menu.h
 *
 * the macOS menu bar of the norns window (SDL only makes the app and window menus):
 * File for getting samples and scripts in and recordings out, Devices for the virtual
 * grid, arc and keyboard windows. every item calls back with its MAC_MENU_ id on the main
 * thread.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

enum {
    MAC_MENU_IMPORT = 1, // the open panel; the chosen paths come to the import callback
    MAC_MENU_DUST,       // dust in Finder
    MAC_MENU_TAPE,       // dust/audio/tape in Finder
    MAC_MENU_SCREENSHOT, // the screen as png
    MAC_MENU_GIF,        // start / stop a gif recording of the screen
    MAC_MENU_GRID,
    MAC_MENU_ARC,
    MAC_MENU_KEYS,
};

// main thread, after SDL_Init(SDL_INIT_VIDEO)
extern void mac_menu_install(void (*on_item)(int id), void (*on_import)(const char *path));

// the GIF item says "Stop" while recording
extern void mac_menu_set_recording(int on);

// the import panel (MAC_MENU_IMPORT calls this itself); does not block
extern void mac_menu_choose_import(void);

#ifdef __cplusplus
}
#endif
