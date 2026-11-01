#pragma once
/*
 * device_dedupe.h: when is a device event a new device? (Linux desktop; docs/port/KNOWN-ISSUES.md 31). pure, no system calls: linux/tests/device_dedupe_test.cpp.
 * upstream's watch loop treats every udev action that is not "remove" as "add": a "change" (another program opening the port: serialosc's reader, ModemManager, a udev rule) or "bind"
 * made the same grid a second device with the same name and serial, so SYSTEM > DEVICES listed it twice and both copies were opened. only "add" is a new device, and a node that is already
 * in the list is never added again.
 */
#include <string.h>

static inline int dev_action_is_add(const char *action) {
    return action != NULL && strcmp(action, "add") == 0;
}

static inline int dev_action_is_remove(const char *action) {
    return action != NULL && strcmp(action, "remove") == 0;
}

// the same device node (a path like /dev/ttyACM0): a second add of it is a duplicate
static inline int dev_same_node(const char *a, const char *b) {
    return a != NULL && b != NULL && a[0] != '\0' && strcmp(a, b) == 0;
}

// two entries of the list that are one physical grid or arc: the same serial (not empty) and the same name
static inline int dev_same_monome(const char *serial_a, const char *name_a, const char *serial_b, const char *name_b) {
    return serial_a != NULL && serial_b != NULL && serial_a[0] != '\0' && strcmp(serial_a, serial_b) == 0 && name_a != NULL && name_b != NULL && strcmp(name_a, name_b) == 0;
}
