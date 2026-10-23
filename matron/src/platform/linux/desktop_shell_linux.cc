/*
 * desktop_shell_linux.cc: see platform/common/desktop_shell.h
 *
 * the desktop pieces of the window on Linux (the keyboard as a hid device: hid_virtual.cc). step 3 of phase 2 has the window; the menu and the
 * file picker (step 4) and the MIDI keys (step 5) are still stubs here.
 */

#include <SDL2/SDL.h>
#include <stdint.h>

#include "platform/common/desktop_shell.h"

static void (*cb_item)(int id) = NULL;
static void (*cb_import)(const char *path, int mode) = NULL;
static void (*cb_note)(const char *text) = NULL;
static void (*cb_input)(const char *mode, const char *bundle, const char *name) = NULL;

static int keys_up = 0;

void shell_install(void (*on_item)(int id), void (*on_import)(const char *path, int mode),
                   void (*on_note)(const char *text),
                   void (*on_input)(const char *mode, const char *bundle, const char *name)) {
    cb_item = on_item;
    cb_import = on_import;
    cb_note = on_note;
    cb_input = on_input;
}

void shell_set_app_name(const char *name) {
    (void)name;
}

void shell_set_input(int input) {
    (void)input;
}

void shell_set_recording(int on) {
    (void)on;
}

int shell_option_held(void) {
    return (SDL_GetModState() & KMOD_SHIFT) != 0;
}

void shell_adopt_windows(void) {
}

void shell_choose_file(const char *dir, const char *dust, void (*done)(const char *path)) {
    (void)dir;
    (void)dust;
    (void)done;
}

void shell_choose_file_close(void) {
}

int shell_keys_open(void) {
    keys_up = 1;
    return 0;
}

void shell_keys_close(void) {
    keys_up = 0;
}

int shell_keys_is_open(void) {
    return keys_up;
}

void shell_keys_send(uint8_t status, uint8_t d1, uint8_t d2) {
    (void)status;
    (void)d1;
    (void)d2;
}
