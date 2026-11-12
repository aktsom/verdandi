// midi_win.h: what the rest of norns.exe asks of the Windows MIDI layer (glue in midi_win.cc)
#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* the monitor of the MIDI devices (called by dev_monitor_init / _scan / _deinit in stubs_win.cc) */
void vmidi_win_monitor_init(void);
void vmidi_win_monitor_start(void);
void vmidi_win_monitor_deinit(void);
/* the monitor of the grids (platform/windows/grid/grid_win.cc), started and stopped with the MIDI one; the device-change notice reaches both */
void vgrid_win_monitor_init(void);
void vgrid_win_monitor_start(void);
void vgrid_win_monitor_deinit(void);
void vgrid_win_poke(void);
int vgrid_win_status(char *buf, size_t n);
void vgrid_win_leds_off(void);
/* the UDP port of the OSC input (audio.conf osc_in_port=, default 9201, 0 = off) */
int vmidi_win_osc_port(void);
/* the MIDI layer in one table for the DEVICES page: devices, virtual cables, notes ("name: text\n..."), the OSC port, the clock statistics, the last route test. one text, "key=value" lines */
int vmidi_win_status(char *buf, size_t n);
/* route test (docs/port/phase-m4.md, "Measuring the routes"): kind "midi" with the device name of a device that has an input and an output joined by a cable (a loopMIDI port, a Windows MIDI Services loopback
 * endpoint), or "osc" (the OSC input of this program through the loopback of the machine). runs in the background; the result is in vmidi_win_status ("route_*") */
int vmidi_win_route_test(const char *kind, const char *device, char *msg, size_t n);
#ifdef __cplusplus
}
#endif
