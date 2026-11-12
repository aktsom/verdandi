// midi_winmm.h: the WinMM (midiIn / midiOut) backend of the Windows MIDI layer. docs/port/phase-m4.md, "Why WinMM".
#pragma once
#include "midi_port.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const vmidi_backend vmidi_winmm_backend;

/* the calling thread joins MMCSS ("Pro Audio"); 1 = done */
int vmidi_mmcss_enter(void);

/* a hidden window on its own thread hears WM_DEVICECHANGE (a USB MIDI device was plugged or pulled) and calls poke(). 0 = ok */
int vmidi_winmm_watch(void (*poke)(void));
void vmidi_winmm_watch_stop(void);

#ifdef __cplusplus
}
#endif
