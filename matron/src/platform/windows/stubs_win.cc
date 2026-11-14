/*
 * stubs_win.cc: what the Windows build of milestone M1 does NOT have, as stand-ins with one plain log line each (the first time it is asked, never repeated):
 *   serial devices (crow), MIDI, HID, grids and arcs (libmonome, the pty virtual grid), the hot-plug monitor, Ableton Link, listening to another program's sound,
 *   the file picker, the MIDI auto-connect, notes that the Linux build shows about plug-ins and serialosc, the Pi's GPIO.
 * each replaces a file of the Linux or macOS build (named at each block) with the same function names, so that the shared code links unchanged and no #ifdef is needed there.
 * M2 and later milestones replace the stubs one by one (docs/port/windows-plan.md). the log lines are what the owner sees in logs\norns.log.
 */
#ifdef _WIN32

#include "platform/windows/midi/midi_win.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" {
#include "device/device.h"
#include "device/device_crow.h"
#include "device/device_hid.h"
#include "device/device_midi.h"
#include "device/device_monitor.h"
#include "device/device_monome.h"
#include "device/device_list.h"
#include "device/device_serial.h"
#include "platform/linux/hid_virtual.h"
#include "hardware/stat.h"
#include "platform/macos/app_audio.h"
#include "platform/macos/open_url.h"
#include "platform/macos/vgrid_device.h"
}
#include "clocks/clock_link.h"
#include "platform/linux/aseq_out.h"
#include "platform/linux/file_picker.h"
#include "platform/linux/input_route.h"
#include "platform/linux/keys_midi.h"
#include "platform/linux/mi_foreign_note.h"
#include "platform/linux/plugin_arch_note.h"
#include "platform/linux/serialosc_check.h"

#include <windows.h>
#include <shellapi.h>

// one line, once, per feature
static void not_yet(const char *what) {
    static char said[64][48];
    static int n;
    for (int i = 0; i < n; i++) {
        if (strncmp(said[i], what, sizeof said[i] - 1) == 0) {
            return;
        }
    }
    if (n < 64) {
        snprintf(said[n++], sizeof said[0], "%s", what);
    }
    fprintf(stderr, "windows: %s: not in this build yet (milestone M1 has no sound devices, grids, MIDI or Link)\n", what);
}

extern "C" {

/* ---- device_crow.cc, device_serial.cc: serial ports ---- */
int dev_crow_init(void *self) {
    (void)self;
    not_yet("crow (USB serial)");
    return -1;
}
void dev_crow_send(struct dev_crow *d, const char *line) {
    (void)d, (void)line;
}
int dev_serial_init(void *self, lua_State *l) {
    (void)self, (void)l;
    not_yet("serial devices");
    return -1;
}
void dev_serial_send(struct dev_serial *d, const char *line, size_t len) {
    (void)d, (void)line, (void)len;
}

/* ---- device_hid.cc: see hid_win.cc (the window keyboard is the only HID device for now) ---- */
// 16 bit words of a device id as 32 hex digits (the part of the guid the Lua side compares); device_hid_iohid.cc does the same on macOS
void guid_to_string(uint16_t *guid, char *guidstr) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 8; i++) {
        guidstr[i * 4 + 0] = hex[(guid[i] >> 4) & 15];
        guidstr[i * 4 + 1] = hex[guid[i] & 15];
        guidstr[i * 4 + 2] = hex[(guid[i] >> 12) & 15];
        guidstr[i * 4 + 3] = hex[(guid[i] >> 8) & 15];
    }
    guidstr[32] = 0;
}

/* ---- device_midi.cc and the device monitor: the MIDI devices are platform/windows/midi (WinMM); the computer keyboard is the HID device of the window ---- */
void dev_monitor_init(void) {
    vmidi_win_monitor_init();
    vgrid_win_monitor_init();
}
void dev_monitor_deinit(void) {
    vgrid_win_monitor_deinit();
    vmidi_win_monitor_deinit();
}
int dev_monitor_scan(void) {
    // the computer keyboard, through the norns window (hid_win.cc), as the Linux scan does
    dev_list_add(DEV_TYPE_HID, LINUX_SDL_KEYBOARD_PATH, strdup("keyboard"), NULL);
    // the MIDI devices: the first scan and the thread that looks again
    vmidi_win_monitor_start();
    vgrid_win_monitor_start();
    return 0;
}

/* ---- vgrid_device.c: the virtual grid and arc are a pty that libmonome opens; Windows has no ptys (an OSC virtual grid comes with M2, PLAN.md Phase 5.5) ---- */
vgrid_device_t *vgrid_open(const char *id, int cols, int rows, void (*on_change)(void *ctx), void *ctx) {
    (void)id, (void)cols, (void)rows, (void)on_change, (void)ctx;
    not_yet("the virtual grid");
    return NULL;
}
vgrid_device_t *vgrid_open_arc(const char *id, int rings, void (*on_change)(void *ctx), void *ctx) {
    (void)id, (void)rings, (void)on_change, (void)ctx;
    not_yet("the virtual arc");
    return NULL;
}
void vgrid_close(vgrid_device_t *g) { (void)g; }
const char *vgrid_path(const vgrid_device_t *g) {
    (void)g;
    return "";
}
void vgrid_unlink(vgrid_device_t *g) { (void)g; }
void vgrid_key(vgrid_device_t *g, int x, int y, int down) { (void)g, (void)x, (void)y, (void)down; }
void vgrid_enc(vgrid_device_t *g, int n, int delta) { (void)g, (void)n, (void)delta; }
void vgrid_enc_key(vgrid_device_t *g, int n, int down) { (void)g, (void)n, (void)down; }
void vgrid_levels(vgrid_device_t *g, uint8_t level[VGRID_MAX][VGRID_MAX], int *intensity) {
    (void)g;
    memset(level, 0, (size_t)VGRID_MAX * VGRID_MAX);
    if (intensity) {
        *intensity = 15;
    }
}
void vgrid_rings(vgrid_device_t *g, uint8_t ring[VARC_RINGS][VARC_LEDS], int *intensity) {
    (void)g;
    memset(ring, 0, (size_t)VARC_RINGS * VARC_LEDS);
    if (intensity) {
        *intensity = 15;
    }
}

/* ---- platform/linux/app_audio_linux.cc, input_route: listening to another program's sound (SYS/APP input) and the MIC/OFF routing ---- */
int app_audio_available(void) { return 0; }
int app_audio_list(app_audio_app_t *out, int max) {
    (void)out, (void)max;
    return 0;
}
int app_audio_select(const char *bundle) {
    (void)bundle;
    not_yet("listening to another program's sound (SYS / APP input)");
    return -1;
}
const char *app_audio_current(void) { return ""; }
void input_route_mic(int live) {
    (void)live;
    not_yet("the MIC / OFF input switch (there is no sound input yet)");
}
int input_route_monitor_enabled(void) { return 0; }

/* ---- platform/linux/aseq_out.cc, keys_midi.cc, midi_autoconnect.cc: the "Verdandi out" MIDI port, the keys as MIDI, the auto-connect ---- */
int aseq_out_link_status(char *names, size_t n) {
    if (names && n) {
        names[0] = 0;
    }
    return 0;
}
int keys_midi_open(void) {
    not_yet("the window keys as a MIDI device");
    return -1;
}
void keys_midi_close(void) {}
int keys_midi_is_open(void) { return 0; }
void keys_midi_send(uint8_t status, uint8_t d1, uint8_t d2) { (void)status, (void)d1, (void)d2; }
int midi_autoconnect_start(const char *prefix_list) {
    (void)prefix_list;
    return 0;
}
int midi_autoconnect_start_out(const char *prefix_list) {
    (void)prefix_list;
    return 0;
}
int midi_autoconnect_status(int *count, char *names, size_t n) {
    if (count) {
        *count = 0;
    }
    if (names && n) {
        names[0] = 0;
    }
    return 0;
}

/* ---- platform/linux/file_picker.cc: the file chooser. the folder picker of Windows is folder_picker_win.cc; choosing files is not in this build yet (picker_open there returns -1) ---- */

/* ---- the notes the Linux build shows about plug-ins and serialosc: nothing to say yet ---- */
const char *mi_foreign_note_text(void) { return ""; }
const char *mi_foreign_fix_text(void) { return ""; }
const char *plugin_arch_note_text(void) { return ""; }
void serialosc_device_added(int id, const char *path, const char *serial) { (void)id, (void)path, (void)serial; }
void serialosc_device_removed(int id) { (void)id; }
const char *serialosc_conflict_text(void) { return ""; }

/* ---- hardware/stat.cc (the Pi's temperature, disk, wifi) ---- */
// (stat_init / stat_deinit are in stat_win.cc: free disk and the processor load for the HOME page)

/* ---- platform/macos/open_url.c: the MAIDEN / MANUAL buttons open a page in the browser. the function keeps its macOS name because the shared code calls it ---- */
int macos_open_url(const char *url) {
    if (!url || !*url) {
        return -1;
    }
    HINSTANCE r = ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
    return (INT_PTR)r > 32 ? 0 : -1;
}

} // extern "C"

#endif
