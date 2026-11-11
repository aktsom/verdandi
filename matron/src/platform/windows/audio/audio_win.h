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
/* "uid\tname\tinputs\toutputs\tapi\tlow_out_ms\tlow_in_ms\tloopback" per line */
int verdandi_audio_devices_text(char *out, size_t n);
/* for the AUDIO page and the log */
typedef struct {
    const char *mode; /* "device", "null", "fallback" */
    char device[128];
    char in_device[128];
    char host_api[40];
    char host_apis[120]; /* the host APIs this build has: "WASAPI ASIO" */
    const char *input;   /* "off", "mic", "system" */
    unsigned rate, frames;
    double out_latency_ms, in_latency_ms; /* what the host API reports */
    double block_ms;                      /* one block of the stream */
    double engine_ms;                     /* what the engine adds: the bridge's block (scsynth) plus the re-blocking delay, in ms */
    double total_ms;                      /* output latency + engine_ms: the estimate for an engine sound, key to ear, without the Windows mixer's own variation */
    unsigned card_frames;                 /* the block of the card's callback, 0 = not known yet */
    int exclusive;
    char config_text[512];                /* what runs, as audio.conf lines (the AUDIO page starts from it) */
    double peak_db;                       /* the input level */
    double measured_ms;                   /* -1 none yet, -2 no signal */
    int in_active;
    char note[480];
    char in_note[200];
    char sys_note[200];
    unsigned long long to_sc, from_sc, underruns, drops, card_xruns;
    int scsynth_attached;
} verdandi_audio_info_t;
void verdandi_audio_info(verdandi_audio_info_t *out);
/* MIC / OFF / SYS as _norns.mic_input and _norns.app_input call it. returns 0 = ok, 1 = that one cannot (see sys_note / in_note) */
int verdandi_audio_input(int mic_on, int sys_on);
void verdandi_audio_measure(void);
/* the AUDIO page's choices as audio.conf lines; applied live (the stream is reopened, the engine runs on). returns 0 = runs, 1 = reverted (msg says why), 2 = silence. the file is written by the caller on 0 only */
int verdandi_audio_apply(const char *conf_text, char *msg, size_t n);

#ifdef __cplusplus
}
#endif
#endif
