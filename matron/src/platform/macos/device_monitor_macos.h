/*
 * device_monitor_macos.h
 *
 * glue between the macOS device monitor and the device backends.
 */

#pragma once

#include <stdint.h>

// path of the virtual keyboard device fed by the norns window
#define MACOS_SDL_KEYBOARD_PATH "sdl:keyboard"

#ifdef __cplusplus
extern "C" {
#endif

// IOHIDDeviceRef for a hid device path ("iohid:<registry id>"), NULL if unknown
extern void *macos_hid_lookup(const char *path);

// window keyboard -> virtual hid keyboard (usage = USB HID keyboard usage, value 0/1/2)
extern void macos_hid_keyboard_event(uint16_t usage, int value);

#ifdef __cplusplus
}
#endif
