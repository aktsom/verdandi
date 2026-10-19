/*
 * device_runloop.h
 *
 * one CFRunLoop thread for the macOS device layer. IOKit hotplug notifications,
 * IOHIDManager input callbacks and CoreMIDI client notifications are all delivered
 * on it, which keeps device add/remove on a single thread like the udev watch loop.
 */

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/CoreMIDI.h>

#ifdef __cplusplus
extern "C" {
#endif

// starts the thread on first use
extern CFRunLoopRef device_runloop(void);

// run `block` on the runloop thread and wait for it (runs inline when already there)
extern void device_runloop_sync(void (^block)(void));

// the process-wide CoreMIDI client, created on the runloop thread on first use
extern MIDIClientRef coremidi_client(void);

// called on the runloop thread when the CoreMIDI setup changes (devices added/removed)
extern void coremidi_set_setup_changed(void (*fn)(void));

#ifdef __cplusplus
}
#endif
