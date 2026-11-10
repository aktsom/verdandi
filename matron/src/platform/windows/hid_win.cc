/*
 * hid_win.cc: the HID device of the Windows build. only the computer keyboard, through the norns window
 * (platform/linux/hid_virtual.cc, fed by sdl_bridge.cc); USB keyboards and game controllers are not in M1.
 * the same as dev_hid_init / dev_hid_deinit of device_hid.cc do for "sdl:keyboard" on the Linux desktop.
 */

#include <stdlib.h>
#include <string.h>

#include "device/device_hid.h"
#include "platform/linux/hid_virtual.h"

extern "C" {

static void dev_hid_win_deinit(void *self) {
    struct dev_hid *di = (struct dev_hid *)self;
    hid_virtual_deinit(di);
    for (int i = 0; i < di->num_types; i++) {
        free(di->codes[i]);
    }
    free(di->codes);
    free(di->num_codes);
    free(di->types);
}

int dev_hid_init(void *self) {
    struct dev_hid *d = (struct dev_hid *)self;
    struct dev_common *base = (struct dev_common *)self;
    if (d->base.path == NULL || strcmp(d->base.path, LINUX_SDL_KEYBOARD_PATH) != 0) {
        return -1;
    }
    base->start = NULL; // no reader thread: the window posts the events
    base->deinit = &dev_hid_win_deinit;
    return hid_virtual_init(d);
}

} // extern "C"
