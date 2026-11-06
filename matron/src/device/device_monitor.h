#pragma once

#ifdef __cplusplus
extern "C" {
#endif

extern void dev_monitor_init(void);
extern void dev_monitor_deinit(void);
// scan connected devices
extern int dev_monitor_scan(void);
#ifdef NORNS_LINUX_DESKTOP
// Linux desktop: the watch loop looks at the MIDI devices again soon (a read thread found a device gone)
extern void dev_monitor_poke(void);
// the periodic look at the MIDI devices (every few seconds from the watch loop, at once after a poke): devices that went without a udev remove leave the list, sound cards whose MIDI ports are not (all) in the list are added
// (a card that was not ready when its udev event came, a port that was busy). udev events stay the fast path
extern void dev_monitor_midi_check(void);
// what the watch loop does every round (about 100 ms): the check every 3 seconds, at once after a poke. `last` is the time of the last check (monotonic seconds), 0 at the start
extern void dev_monitor_watch_tick(double *last);
#endif

#ifdef __cplusplus
}
#endif
