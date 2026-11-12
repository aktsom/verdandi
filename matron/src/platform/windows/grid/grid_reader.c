/* grid_reader.c: see grid_reader.h */
#include "grid_reader.h"

#include <pthread.h>

/* libmonome's own, not in its public header: the platform layer's wait (Windows: WaitCommEvent with a time limit, Linux: poll). 0 = data, 1 = nothing in the time, < 0 = the port failed */
extern int monome_platform_wait_for_input(monome_t *monome, unsigned msec);

int vgrid_read_loop(monome_t *m, volatile int *stop) {
    while (!*stop) {
        pthread_testcancel();
        int w = monome_platform_wait_for_input(m, 50);
        if (w < 0) {
            return -1;
        }
#ifdef _WIN32
        /* Windows: the wait is for the event EV_RXCHAR, which fires when a byte ARRIVES while the mask is set: bytes that came before stay unnoticed by it. so every slice reads as well (libmonome's read
         * comes back after its own 25 ms limit when there is nothing) */
        if (monome_event_handle_next(m) < 0) {
            return -1;
        }
#else
        if (w == 0) {
            if (monome_event_handle_next(m) < 0) {
                return -1;
            }
        }
#endif
    }
    return 0;
}
