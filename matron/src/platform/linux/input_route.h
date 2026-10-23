/*
 * input_route.h: the card's capture ports on or off crone's input (MIC / OFF), and whether the optional sink
 * monitor input is switched on (NORNS_SYS_MONITOR=1, from audio.conf sys_monitor=1). the rest is app_audio.h.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

extern void input_route_mic(int live);
extern int input_route_monitor_enabled(void);

#ifdef __cplusplus
}
#endif
