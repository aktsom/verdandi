/*
 * file_picker.h
 *
 * the file dialog of the Linux desktop (the macOS port uses the Finder's open panel). in this order:
 *   1. the XDG Desktop Portal, org.freedesktop.portal.FileChooser, over GDBus (glib, no new
 *      dependency): the dialog of the user's desktop, also inside Flatpak
 *   2. zenity --file-selection
 *   3. kdialog --getopenfilename
 * none of them: picker_open returns -1 and the caller says so.
 *
 * NORNS_PICKER=portal|zenity|kdialog|none forces one of them (tests).
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

enum {
    PICK_FILE = 0,   // one file
    PICK_FILES = 1,  // any number of files
    PICK_FOLDER = 2, // one folder
};

// n paths (n = 0: cancelled or failed), called once, on another thread
typedef void (*picker_done_fn)(const char *const *paths, int n, void *ctx);

// the dialog starts in start_dir (may be NULL). 0 = open (or already open: nothing changes),
// -1 = no way to show a dialog
extern int picker_open(int mode, const char *start_dir, const char *title, picker_done_fn done, void *ctx);

// the dialog goes away; done is not called
extern void picker_close(void);

// "portal", "zenity", "kdialog" or "none"
extern const char *picker_backend(void);

#ifdef __cplusplus
}
#endif
