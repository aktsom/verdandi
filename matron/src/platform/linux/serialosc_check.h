/*
 * serialosc_check.h: Linux desktop. norns has opened a monome grid or arc at path: is serialosc's serialosc-device process on it too?
 * (serialosc_conflict.h for what and why). all calls from matron's main thread.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// a device was opened (id: its norns device id) / is gone. added: checks at once and logs a conflict, once
extern void serialosc_device_added(int id, const char *path, const char *serial);
extern void serialosc_device_removed(int id);

// the note (three lines, serialosc_conflict.h) if serialosc runs and has a grid, whether or not norns has it open, else NULL. looks again each call: processes, systemd unit, devices
extern const char *serialosc_conflict_text(void);

#ifdef __cplusplus
}
#endif
