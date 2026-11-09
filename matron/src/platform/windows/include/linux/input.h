/* linux/input.h for Windows (M1): the few event constants the shared desktop layer names (hid_virtual.cc builds a virtual keyboard from them). values are those of the Linux input API (they are
 * part of norns's Lua interface: script code receives these numbers). real HID devices are not supported in M1. */
#ifndef VERDANDI_WIN_LINUX_INPUT_H
#define VERDANDI_WIN_LINUX_INPUT_H
#include <stdint.h>
#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_REL 0x02
#define EV_ABS 0x03
#define BUS_USB 0x03
#define BUS_VIRTUAL 0x06
#endif
