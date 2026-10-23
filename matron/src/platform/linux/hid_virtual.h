/*
 * hid_virtual.h
 *
 * the computer keyboard as a hid keyboard for scripts: the norns window feeds it (sdl_bridge.cc
 * through shell_hid_keyboard_event), lua/core/keyboard.lua reads it like any usb keyboard. no
 * access to /dev/input needed, and keys typed into other apps never reach scripts. same idea
 * as the "sdl:keyboard" device of platform/macos/device_hid_iohid.cc.
 */

#pragma once

#include "device_hid.h"

#define LINUX_SDL_KEYBOARD_PATH "sdl:keyboard"

#ifdef __cplusplus
extern "C" {
#endif

// dev_hid_init for LINUX_SDL_KEYBOARD_PATH: capabilities, guid, registers the device as the target
extern int hid_virtual_init(struct dev_hid *d);
// dev_hid_deinit: forget the device (the arrays are freed by the caller)
extern void hid_virtual_deinit(struct dev_hid *d);

#ifdef __cplusplus
}
#endif
