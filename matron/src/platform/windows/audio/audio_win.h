/* audio_win.h (M2): what norns.exe calls (norns/main.cpp at start, weaver.cc for the AUDIO page). */
#ifndef VERDANDI_AUDIO_WIN_H
#define VERDANDI_AUDIO_WIN_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* before crone starts: reads audio.conf (HOME) and the environment, opens the sound card or falls back to null audio, creates the bridge for scsynth. returns 1 when the program was only asked to
 * list the devices (VERDANDI_AUDIO_LIST=1): the caller exits with 0. */
int verdandi_audio_boot(void);
void verdandi_audio_shutdown(void);
/* "uid\tname\tinputs\toutputs" per line */
int verdandi_audio_devices_text(char *out, size_t n);
/* for the AUDIO page and the log */
typedef struct {
    const char *mode; /* "device", "null", "fallback" */
    char device[128];
    char host_api[40];
    unsigned rate, frames;
    double latency_ms;
    char note[320];
    unsigned long long to_sc, from_sc, underruns, drops;
    int scsynth_attached;
} verdandi_audio_info_t;
void verdandi_audio_info(verdandi_audio_info_t *out);

#ifdef __cplusplus
}
#endif
#endif
