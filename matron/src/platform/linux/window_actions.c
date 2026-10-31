/*
 * window_actions.c: the 14 window actions of the MIDI MAP layer, see window_actions.h
 */

#include "window_actions.h"

#include <string.h>

#include "../macos/device_skin.h"

// the order is the order of the list on the MIDI MAP page (lua ACTION_IDS)
static const wa_entry_t table[] = {
    {"mix", WA_CONTROL, SKIN_PAGE1},
    {"tape", WA_CONTROL, SKIN_PAGE1 + 1},
    {"home", WA_CONTROL, SKIN_PAGE1 + 2},
    {"params", WA_CONTROL, SKIN_PAGE1 + 3},
    {"input", WA_CONTROL, SKIN_MIC},
    {"grid", WA_CONTROL, SKIN_GRID},
    {"arc", WA_CONTROL, SKIN_ARC},
    {"keys", WA_CONTROL, SKIN_KEYS},
    {"maiden", WA_CONTROL, SKIN_MAIDEN},
    {"manual", WA_CONTROL, SKIN_MANUAL},
    {"mute", WA_CONTROL, SKIN_MUTE},
    {"detach", WA_CONTROL, WA_DETACH_CONTROL},
    {"fullscreen", WA_FULLSCREEN, 0},
    {"screenshot", WA_SCREENSHOT, 0},
};

int window_action_count(void) {
    return (int)(sizeof table / sizeof table[0]);
}

const wa_entry_t *window_action_get(int i) {
    return (i >= 0 && i < window_action_count()) ? &table[i] : NULL;
}

int window_action_find(const char *name) {
    if (name == NULL) {
        return -1;
    }
    for (int i = 0; i < window_action_count(); i++) {
        if (strcmp(table[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

const char *window_action_fullscreen_message(void) {
    return "FULLSCREEN: DETACH THE SCREEN FIRST (F9)";
}

const char *window_actions_switch_message(int on) {
    return on ? "MIDI actions on" : "MIDI actions off";
}
