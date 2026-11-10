/*
 * audio_device.h (M2): the sound card of the Windows build. norns.exe opens ONE output stream (WASAPI through PortAudio, shared mode) and runs crone's blocks in its callback
 * (verdandi_jack_null_process); scsynth is fed through the audio bridge (verdandi_bridge.h). The decisions (which device, which rate and block, what to say when it does not work,
 * falling back to silence) are in audio_device.c and use only the small backend interface below, so they run in a test on Linux with a fake card; audio_backend_pa.c is the PortAudio backend.
 */
#ifndef VERDANDI_AUDIO_DEVICE_H
#define VERDANDI_AUDIO_DEVICE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char uid[160];  /* what audio.conf stores: "wasapi:" and the device's name (the order of the list changes between runs, the name does not) */
    char name[128]; /* what the AUDIO page shows */
    int is_default;
    int out_channels;
    double default_rate;
} vaud_device;

typedef enum { VAUD_OK = 0, VAUD_NOT_FOUND, VAUD_BUSY, VAUD_BAD_RATE, VAUD_FAILED } vaud_error;

typedef struct {
    char device_name[128];
    char host_api[40];
    unsigned rate;        /* what the stream really runs at */
    unsigned frames;
    double latency_ms;    /* the output latency the host API reports */
} vaud_opened;

/* called by the card in its own thread: interleaved stereo float, `frames` frames */
typedef void (*vaud_callback)(float *interleaved_out, unsigned frames, void *user);

typedef struct {
    const char *name;
    int (*list)(vaud_device *out, int max);                         /* output devices; number found (0 = none) */
    /* open (not started) the stream for the device `uid` ("" = the default device) */
    vaud_error (*open)(const char *uid, unsigned rate, unsigned frames, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn);
    int (*start)(char *err, size_t errn);                           /* 0 = ok */
    void (*close)(void);
} vaud_backend;

typedef struct {
    char output[160];   /* audio.conf output=, "" = the default device */
    unsigned rate;      /* audio.conf rate= */
    unsigned period;    /* audio.conf period= (frames per block) */
    int force_null;     /* VERDANDI_AUDIO=null in the environment, or output=null in audio.conf */
    char notes[256];    /* what was wrong with the values (plain words), "" if nothing */
} vaud_config;

typedef enum { VAUD_MODE_NONE = 0, VAUD_MODE_DEVICE, VAUD_MODE_NULL, VAUD_MODE_FALLBACK } vaud_mode;

typedef struct {
    vaud_mode mode;
    vaud_opened opened;       /* valid in VAUD_MODE_DEVICE */
    unsigned rate, frames;    /* what crone runs at in every mode */
    char note[320];           /* for the screen and the log: why null audio, which device replaced the chosen one; "" when all is as chosen */
} vaud_state;

/* the values: defaults (default device, 48000, 512), audio.conf in `home` (may be NULL), then the environment. out-of-range values are replaced and said in cfg->notes */
void vaud_config_load(vaud_config *cfg, const char *home);
/* the same checks for values that are already in cfg (the AUDIO page writes the file, the test calls this) */
void vaud_config_check(vaud_config *cfg);

/* opens the card as chosen, or says why not and goes on with the null backend. `bridge_name`: the name of the shared memory for scsynth (NULL: no bridge). Never blocks, never fails:
 * the worst case is silence with a note. Logs one line per decision to stderr. */
void vaud_start(const vaud_backend *be, const vaud_config *cfg, const char *bridge_name, vaud_state *st);
void vaud_stop(void);

/* the state of the running audio for the AUDIO page and the log: mode, device, rate, frames, latency, bridge counters */
const vaud_state *vaud_get_state(void);
/* "uid\tname\tinputs\toutputs" per line, for SYSTEM > AUDIO (the same format as the macOS audio tool) */
int vaud_list_text(const vaud_backend *be, char *out, size_t n);
void vaud_bridge_stats(unsigned long long *to_sc, unsigned long long *from_sc, unsigned long long *underruns, unsigned long long *drops, int *scsynth_attached);

#ifdef __cplusplus
}
#endif
#endif
