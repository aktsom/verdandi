/*
 * window_actions_test.c: the 14 window actions (matron/src/platform/linux/window_actions.c, docs/port/midi-actions-plan.md): the names are exactly the ones lua knows, in the page's order;
 * each one is a control of the window (the click's control id) or fullscreen / screenshot; an unknown, empty, wrong-case or NULL name finds nothing; nothing quits or answers to F6-F8;
 * the messages are the ones the plan names. The names are read from lua/core/midimap_settings.lua, so a name added on one side only is caught here.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device_skin.h"
#include "window_actions.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL " __VA_ARGS__);                                                                               \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

int main(int argc, char **argv) {
    const char *want[14] = {"mix", "tape", "home", "params", "input", "grid", "arc", "keys", "maiden", "manual", "mute", "detach", "fullscreen", "screenshot"};
    CHECK(window_action_count() == 14, "14 actions (got %d)", window_action_count());
    for (int i = 0; i < 14; i++) {
        const wa_entry_t *e = window_action_get(i);
        CHECK(e != NULL && strcmp(e->name, want[i]) == 0, "action %d is %s (got %s)", i, want[i], e ? e->name : "NULL");
        CHECK(window_action_find(want[i]) == i, "%s is found at %d", want[i], i);
    }
    CHECK(window_action_get(-1) == NULL && window_action_get(14) == NULL, "out of range is NULL");
    const char *bad[] = {NULL, "", "MIX", "Mix", "mix ", " mix", "quit", "menu", "f6", "F6", "F7", "F8", "up", "down", "esc", "screen", "gif", "mixx", "mi"};
    for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        CHECK(window_action_find(bad[i]) == -1, "'%s' is no action", bad[i] ? bad[i] : "NULL");
    }
    // the controls
    struct { const char *n; int c; } ctl[] = {{"mix", SKIN_PAGE1}, {"tape", SKIN_PAGE1 + 1}, {"home", SKIN_PAGE1 + 2}, {"params", SKIN_PAGE1 + 3}, {"input", SKIN_MIC}, {"grid", SKIN_GRID},
                                              {"arc", SKIN_ARC}, {"keys", SKIN_KEYS}, {"maiden", SKIN_MAIDEN}, {"manual", SKIN_MANUAL}, {"mute", SKIN_MUTE}, {"detach", 99}};
    for (unsigned i = 0; i < sizeof ctl / sizeof ctl[0]; i++) {
        const wa_entry_t *e = window_action_get(window_action_find(ctl[i].n));
        CHECK(e != NULL && e->kind == WA_CONTROL && e->control == ctl[i].c, "%s is control %d", ctl[i].n, ctl[i].c);
    }
    const wa_entry_t *fs = window_action_get(window_action_find("fullscreen")), *ss = window_action_get(window_action_find("screenshot"));
    CHECK(fs != NULL && fs->kind == WA_FULLSCREEN, "fullscreen kind");
    CHECK(ss != NULL && ss->kind == WA_SCREENSHOT, "screenshot kind");
    CHECK(WA_DETACH_CONTROL == 99, "the detach control is the placeholder's id");
    // the messages
    CHECK(strcmp(window_action_fullscreen_message(), "FULLSCREEN: DETACH THE SCREEN FIRST (F9)") == 0, "the fullscreen message");
    CHECK(strcmp(window_actions_switch_message(1), "MIDI actions on") == 0, "on message");
    CHECK(strcmp(window_actions_switch_message(0), "MIDI actions off") == 0, "off message");
    // the lua side names the same 14, in the same order
    if (argc > 1) {
        FILE *f = fopen(argv[1], "r");
        CHECK(f != NULL, "can read %s", argv[1]);
        if (f) {
            char line[1024];
            int found = 0;
            while (fgets(line, sizeof line, f)) {
                char *p = strstr(line, "M.ACTION_IDS = {");
                if (!p) continue;
                found = 1;
                p += strlen("M.ACTION_IDS = {");
                char *end = strchr(p, '}');
                CHECK(end != NULL, "the lua list ends");
                if (!end) break;
                *end = 0;
                int i = 0;
                for (char *tok = strtok(p, ", \""); tok; tok = strtok(NULL, ", \"")) {
                    CHECK(i < 14 && strcmp(tok, want[i]) == 0, "lua's action %d is '%s' (C has '%s')", i, tok, i < 14 ? want[i] : "-");
                    i++;
                }
                CHECK(i == 14, "lua lists 14 actions (got %d)", i);
            }
            CHECK(found, "found ACTION_IDS in lua");
            fclose(f);
        }
    }
    if (fails == 0) printf("window actions: all passed\n");
    return fails == 0 ? 0 : 1;
}
