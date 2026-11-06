#pragma once

#include "device.h"
#include <lualib.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

extern void dev_list_init(void);
extern void dev_list_add(device_t type, const char *node, const char *name, lua_State *l);
extern void dev_list_remove(device_t type, const char *node);
#ifdef NORNS_LINUX_DESKTOP
// every grid and arc gets all LEDs off (level maps of zero: the same bytes a script clear writes), each device on a thread of its own, waiting at most timeout_ms for all of them (a stalled port does not hold norns
// back: libmonome gives up on a write after a second). for the ways norns ends: quit, a signal, a crash (docs/port/KNOWN-ISSUES.md 30). takes no lock: it must work from a signal-safe worker and from a crashed process
extern void dev_list_monome_all_off(int timeout_ms);
// is this monome device (a pointer a script holds) still in the list? a removed device is freed: a call through a stale pointer writes into freed memory
extern bool dev_list_has_monome(struct dev_monome *md);
// the MIDI devices of ALSA rawmidi nodes (/dev/snd/midiC<n>D<m>) in the list: those whose read thread found the device gone, or whose node is not there any more, are removed (the removal reaches Lua before anything is added
// again); returns how many. the periodic check of the device monitor calls it, so an unplug without a udev remove is not remembered forever
extern int dev_list_midi_sweep(void);
// how many ports of this node are in the list
extern int dev_list_midi_ports_listed(const char *node);
#endif

#ifdef __cplusplus
}
#endif
