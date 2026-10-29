/*
 * desktop_shell_linux.cc: see platform/common/desktop_shell.h
 *
 * the desktop pieces of the window on Linux: the in-window menu (menu_skin.c), the file dialogs
 * (file_picker.cc), opening folders (open_url.c: xdg-open), the keyboard as a hid device
 * (hid_virtual.cc), the "norns keys" MIDI source (keys_midi.cc).
 */

#include <atomic>
#include <SDL2/SDL.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>

#include "../macos/app_audio.h"
#include "file_picker.h"
#include "input_route.h"
#include "keys_midi.h"
#include "menu_skin.h"
#include "platform/common/desktop_shell.h"

static void (*cb_item)(int id) = NULL;
static void (*cb_import)(const char *path, int mode) = NULL;
static void (*cb_note)(const char *text) = NULL;
static void (*cb_input)(const char *mode, const char *bundle, const char *name) = NULL;

static menu_t menu = {};
#define MENU_APPS 6
static char menu_app[MENU_APPS][128]; // the applications in the menu, as built
static int input_now = 1; // SKIN_INPUT_MIC until lua says otherwise
static int recording = 0;
static int copy_samples = 0;
static int screen_out = 0; // the screen is in its own window
static std::atomic<int> file_dialog{0}; // "Open the file dialog when a script loads a file": lua owns the value (ui.conf), this is the tick
static int import_mode = SHELL_IMPORT_LINK;

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
    input_now = input;
}

void shell_set_recording(int on) {
    recording = on;
}

int shell_option_held(void) {
    return (SDL_GetModState() & KMOD_SHIFT) != 0;
}

void shell_adopt_windows(void) {
}

//--- file dialogs

static void note(const char *text) {
    if (cb_note != NULL) {
        cb_note(text);
    }
}

static std::string user_home(void) {
    struct passwd *pw = getpwuid(getuid());
    const char *home = pw != NULL && pw->pw_dir != NULL ? pw->pw_dir : getenv("HOME");
    return home != NULL ? home : "/";
}

// a script's file (lua's fileselect): one path, nothing on cancel
static void single_done(const char *const *paths, int n, void *ctx) {
    if (n > 0) {
        ((void (*)(const char *))ctx)(paths[0]);
    }
}

void shell_choose_file(const char *dir, const char *dust, void (*done)(const char *path)) {
    const char *start = dir != NULL && dir[0] != '\0' ? dir : dust;
    if (picker_open(PICK_FILE, start, "Choose a file", single_done, (void *)done) != 0) {
        note("no file dialog (install zenity or an xdg-desktop-portal)");
    }
}

void shell_choose_file_close(void) {
    picker_close();
}

void shell_set_screen_out(int on) {
    screen_out = on ? 1 : 0;
}

void shell_set_file_dialog(int on) {
    file_dialog = on ? 1 : 0;
}

int shell_get_file_dialog(void) {
    return file_dialog.load();
}

// the menu's Import: every chosen path goes through the import callback
static void import_done(const char *const *paths, int n, void *ctx) {
    (void)ctx;
    for (int i = 0; i < n; i++) {
        if (cb_import != NULL) {
            cb_import(paths[i], import_mode);
        }
    }
}

static void menu_import(int folder) {
    import_mode = copy_samples ? SHELL_IMPORT_COPY : SHELL_IMPORT_LINK;
    if (picker_open(folder ? PICK_FOLDER : PICK_FILES, user_home().c_str(),
                    folder ? "Import a folder into dust" : "Import samples or scripts into dust", import_done,
                    NULL) != 0) {
        note("no file dialog (install zenity or an xdg-desktop-portal)");
    }
}

//--- the in-window menu

static void add_item(int id, const char *label, const char *hint, int checked) {
    if (menu.n >= MENU_MAX) {
        return;
    }
    menu_item_t *it = &menu.item[menu.n++];
    memset(it, 0, sizeof *it);
    it->id = id;
    snprintf(it->label, sizeof it->label, "%s", label);
    snprintf(it->hint, sizeof it->hint, "%s", hint);
    it->checked = checked;
}

static void add_separator(void) {
    if (menu.n < MENU_MAX) {
        menu_item_t *it = &menu.item[menu.n++];
        memset(it, 0, sizeof *it);
        it->separator = 1;
    }
}

static void menu_build(void) {
    menu.n = 0;
    add_item(SHELL_MENU_IMPORT, "Import files...", "Ctrl+O", 0);
    add_item(SHELL_MENU_IMPORT_FOLDER, "Import folder...", "", 0);
    add_item(SHELL_MENU_COPY_SAMPLES, "Copy samples into dust", "", copy_samples);
    add_item(SHELL_MENU_FILE_DIALOG, "Open the file dialog when a script loads a file", "", file_dialog.load());
    add_separator();
    add_item(SHELL_MENU_DUST, "Show dust folder", "", 0);
    add_item(SHELL_MENU_TAPE, "Show tape folder", "", 0);
    add_separator();
    add_item(SHELL_MENU_SCREENSHOT, "Screenshot", "Ctrl+Shift+S", 0);
    add_item(SHELL_MENU_GIF, recording ? "Stop GIF recording" : "Record GIF", "", recording);
    add_separator();
    add_item(SHELL_MENU_GRID, "Virtual grid", "F6", 0);
    add_item(SHELL_MENU_ARC, "Virtual arc", "F8", 0);
    add_item(SHELL_MENU_KEYS, "Virtual keyboard", "F7", 0);
    add_item(SHELL_MENU_SCREEN, "Screen in its own window", "F9", screen_out);
    add_separator();
    // what norns hears: the sound card's input, every application but norns, one application, off
    const char *cur = app_audio_current();
    add_item(SHELL_MENU_INPUT_MIC, "Input: microphone", "", input_now == 1);
    add_item(SHELL_MENU_INPUT_SYSTEM, "Input: all apps", "", cur != NULL && strcmp(cur, APP_AUDIO_SYSTEM) == 0);
    if (input_route_monitor_enabled()) {
        add_item(SHELL_MENU_INPUT_MONITOR, "Input: sink monitor (hears norns)", "",
                 cur != NULL && strcmp(cur, APP_AUDIO_SINK_MONITOR) == 0);
    }
    app_audio_app_t apps[MENU_APPS];
    int n = app_audio_list(apps, MENU_APPS);
    for (int i = 0; i < n; i++) {
        char label[48];
        snprintf(menu_app[i], sizeof menu_app[i], "%s", apps[i].bundle);
        snprintf(label, sizeof label, "Input: %s", apps[i].name);
        add_item(SHELL_MENU_INPUT_APP + i, label, "", cur != NULL && strcmp(cur, apps[i].bundle) == 0);
    }
    add_item(SHELL_MENU_INPUT_OFF, "Input: off", "", input_now == 0);
    add_separator();
    add_item(SHELL_MENU_QUIT, "Quit", "Ctrl+Q", 0);
}

static void menu_do(int id) {
    switch (id) {
    case SHELL_MENU_IMPORT:
        menu_import(0);
        break;
    case SHELL_MENU_IMPORT_FOLDER:
        menu_import(1);
        break;
    case SHELL_MENU_COPY_SAMPLES:
        copy_samples = !copy_samples;
        break;
    case SHELL_MENU_FILE_DIALOG:
        file_dialog = !file_dialog.load();
        if (cb_item != NULL) {
            cb_item(id); // the bridge tells lua, which saves it
        }
        break;
    case SHELL_MENU_INPUT_MIC:
        if (cb_input != NULL) {
            cb_input("mic", NULL, NULL);
        }
        break;
    case SHELL_MENU_INPUT_OFF:
        if (cb_input != NULL) {
            cb_input("off", NULL, NULL);
        }
        break;
    case SHELL_MENU_INPUT_SYSTEM:
        if (cb_input != NULL) {
            cb_input("system", NULL, NULL);
        }
        break;
    case SHELL_MENU_INPUT_MONITOR:
        if (cb_input != NULL) {
            cb_input("monitor", NULL, NULL);
        }
        break;
    default:
        if (id >= SHELL_MENU_INPUT_APP && id < SHELL_MENU_INPUT_APP + MENU_APPS) {
            if (cb_input != NULL) {
                cb_input("app", menu_app[id - SHELL_MENU_INPUT_APP], menu_app[id - SHELL_MENU_INPUT_APP]);
            }
        } else if (cb_item != NULL) {
            cb_item(id);
        }
        break;
    }
}

static void menu_open_at(double px, double py, double scale, int w, int h) {
    menu_build();
    menu_skin_open(&menu, px, py, scale, w, h);
}

int shell_menu_is_open(void) {
    return menu.open;
}

int shell_menu_mouse(int type, int button, double px, double py, double scale, int w, int h) {
    if (!menu.open) {
        if (type == 1 && button == SDL_BUTTON_RIGHT) {
            menu_open_at(px, py, scale, w, h);
            return SHELL_USED | SHELL_REDRAW;
        }
        return 0;
    }
    if (type == 0) {
        int hover = menu_skin_hit(&menu, px, py);
        if (hover != menu.hover) {
            menu.hover = hover;
            return SHELL_USED | SHELL_REDRAW;
        }
        return SHELL_USED;
    }
    int item = menu_skin_hit(&menu, px, py);
    if (type == 1) {
        // a click outside closes it (and is not passed on); inside, the item acts on release
        if (!menu_skin_inside(&menu, px, py)) {
            menu_skin_close(&menu);
            return SHELL_USED | SHELL_REDRAW;
        }
        return SHELL_USED;
    }
    // button up: over an item it acts; the right button that opened the menu only acts when the
    // pointer has moved to an item since
    if (item >= 0 && (button == SDL_BUTTON_LEFT || item == menu.hover)) {
        int id = menu.item[item].id;
        menu_skin_close(&menu);
        menu_do(id);
        return SHELL_USED | SHELL_REDRAW;
    }
    return SHELL_USED;
}

int shell_menu_key(int down, int scancode, int mods, double px, double py, double scale, int w, int h) {
    bool ctrl = (mods & KMOD_CTRL) != 0, shift = (mods & KMOD_SHIFT) != 0;
    if (!menu.open) {
        if (!down) {
            return 0;
        }
        if (scancode == SDL_SCANCODE_F10) {
            double x = px >= 0 ? px : 20 * scale, y = py >= 0 ? py : 20 * scale;
            menu_open_at(x, y, scale, w, h);
            // highlight the first item for the keyboard
            menu_skin_move(&menu, 1);
            return SHELL_USED | SHELL_REDRAW;
        }
        if (ctrl && scancode == SDL_SCANCODE_Q) {
            menu_do(SHELL_MENU_QUIT);
            return SHELL_USED;
        }
        if (ctrl && scancode == SDL_SCANCODE_O) {
            menu_do(SHELL_MENU_IMPORT);
            return SHELL_USED;
        }
        if (ctrl && shift && scancode == SDL_SCANCODE_S) {
            menu_do(SHELL_MENU_SCREENSHOT);
            return SHELL_USED;
        }
        return 0;
    }
    // open: it takes every key
    if (!down) {
        return SHELL_USED;
    }
    switch (scancode) {
    case SDL_SCANCODE_ESCAPE:
    case SDL_SCANCODE_F10:
        menu_skin_close(&menu);
        break;
    case SDL_SCANCODE_UP:
        menu_skin_move(&menu, -1);
        break;
    case SDL_SCANCODE_DOWN:
        menu_skin_move(&menu, 1);
        break;
    case SDL_SCANCODE_RETURN:
    case SDL_SCANCODE_KP_ENTER:
    case SDL_SCANCODE_SPACE:
        if (menu.hover >= 0) {
            int id = menu.item[menu.hover].id;
            menu_skin_close(&menu);
            menu_do(id);
        }
        break;
    default:
        return SHELL_USED;
    }
    return SHELL_USED | SHELL_REDRAW;
}

void shell_menu_draw(cairo_t *cr, int w, int h) {
    (void)w;
    (void)h;
    menu_skin_draw(cr, &menu);
}

//--- the "norns keys" MIDI source

int shell_keys_open(void) {
    return keys_midi_open();
}

void shell_keys_close(void) {
    keys_midi_close();
}

int shell_keys_is_open(void) {
    return keys_midi_is_open();
}

void shell_keys_send(uint8_t status, uint8_t d1, uint8_t d2) {
    keys_midi_send(status, d1, d2);
}
