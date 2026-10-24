/*
 * serialosc_check.h: Linux desktop. norns has opened a monome grid or arc at path: is serialosc's serialosc-device process on it too?
 * (serialosc_conflict.h for what and why). all calls from matron's main thread.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// a device was opened (id: its norns device id) / is gone. added: checks at once and logs a conflict, once
extern void serialosc_device_added(int id, const char *path);
extern void serialosc_device_removed(int id);

// the note for the device window if some open device has a serialosc process on it right now, else NULL. looks again each call
extern const char *serialosc_conflict_text(void);

#ifdef __cplusplus
}
#endif
