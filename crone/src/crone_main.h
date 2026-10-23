#ifndef _CRONE_MAIN_H_
#define _CRONE_MAIN_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int crone_main();
void crone_cleanup();
void crone_stop();

#ifdef NORNS_LINUX_DESKTOP
// which: 0 warning text (empty if none), 1 input client crone connected to, 2 output client
void crone_audio_status(int which, char *out, size_t n);
#endif

#ifdef __cplusplus
}
#endif

#endif