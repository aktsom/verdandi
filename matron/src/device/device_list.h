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
#ifndef NORNS_WINDOWS
// M45 (docs/port/phase-m45.md): the real grid that takes part in the copy of the LEDs at a switch between it and the virtual grid. core/grid.lua tells it (_norns.grid_peer): the grid that is in slot 1 now,
// or, while the virtual grid is on, the one it pushed out of slot 1; none when slot 1 has no real grid (then nothing is copied either way, a real grid in another slot is never written to)
extern void dev_list_grid_peer_set(const char *path);
// 1 and its path in `out` when there is a peer and it is in the list, else 0
extern int dev_list_grid_peer(char *out, size_t n);
// the LEDs of the grid at from_path are copied to the grid at to_path and written out (the script's picture appears on the grid that takes over). 1 when both were found
extern int dev_list_grid_copy_leds(const char *from_path, const char *to_path);
// M37: the ports that could not be opened (busy: another program has the raw port open), one line "name: reason" each. returns how many
extern int dev_list_midi_skipped_text(char *buf, size_t n);
#endif
#ifdef NORNS_WINDOWS
#include <stddef.h>
#include "device.h"
// Windows: is a device of this type with this path in the list (the grid monitor asks whether libmonome took the port)
extern int dev_list_path_listed(device_t type, const char *path);
// Windows: what the monome device at this path is: libmonome's name and serial, columns and rows (0 and 0 for an arc). 0 = no such device
extern int dev_list_monome_info(const char *path, char *name, size_t namen, char *serial, size_t serialn, int *cols, int *rows);
#endif
// let go of every port of this node at once (its handles are closed, Lua is told): for a card that must not be open (the virtual MIDI card a DAW reads); unlike dev_list_remove it does not wait for the card to
// vanish. returns how many ports were released
extern int dev_list_midi_release(const char *node);
#endif

#ifdef __cplusplus
}
#endif
