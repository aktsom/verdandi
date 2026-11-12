// grid_reader.h: the thread of a grid that reads its keys (Windows build). libmonome has no event loop on Windows (monome_event_loop prints "unimplemented"), and a thread that sits in a Win32 wait cannot be cancelled
// by pthread_cancel (norns cancels the thread of a device that is removed, then joins it): so the loop waits in slices of 50 ms and looks at the cancel flag between them. portable, so that the Linux tests run the very
// same loop against a pseudo terminal that plays a grid (linux/tests/grid_protocol_test.c).
#pragma once
#include <monome.h>

#ifdef __cplusplus
extern "C" {
#endif

/* returns when *stop is set (0), or when the device is gone or the port failed (-1). each key, encoder or tilt message calls the handlers registered with monome_register_handler */
int vgrid_read_loop(monome_t *m, volatile int *stop);

#ifdef __cplusplus
}
#endif
