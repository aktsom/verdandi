/*
 * libevdev.h shim for macOS: device_crow.h / device_serial.h include it but use nothing
 * from it. hid devices use IOHIDManager (platform/macos/device_hid_iohid.cc).
 */
#pragma once
