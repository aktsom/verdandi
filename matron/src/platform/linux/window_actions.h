/*
 * window_actions.h: the names of the MIDI actions (lua/core/midimap_settings.lua ACTION_IDS) and what each one does in the window (docs/port/midi-actions-plan.md).
 * pure data and lookups, no SDL: sdl_bridge.cc runs the action on the main thread, the same way a click on the button does (button_action), so a mapped note and the mouse
 * produce the same effect. Linux desktop only. no action quits, moves in the menu, or answers to F6, F7 or F8 as a key: only these 14 names exist.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

enum {
    WA_CONTROL = 1,  // the same as a click on a control of the window (button_action(control))
    WA_FULLSCREEN,   // the screen window's fullscreen (F11); only while the screen is detached
    WA_SCREENSHOT,   // the screen as png
};

// the control id of the placeholder where the screen was (the detach button): sdl_bridge.cc's HIT_PLACEHOLDER
#define WA_DETACH_CONTROL 99

typedef struct {
    const char *name;
    int kind;
    int control; // WA_CONTROL only
} wa_entry_t;

extern int window_action_count(void);
extern const wa_entry_t *window_action_get(int i); // NULL out of range
extern int window_action_find(const char *name);   // the index, or -1 (NULL, empty, wrong case, anything but the 14 names)

// the short messages shown in the window
extern const char *window_action_fullscreen_message(void); // the screen is not detached
extern const char *window_actions_switch_message(int on);  // the master switch changed (Ctrl+Shift+M)

#ifdef __cplusplus
}
#endif
