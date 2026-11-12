/*
 * audio_device.h (M2, extended in M3): the sound card of the Windows build. norns.exe opens ONE stream (PortAudio: WASAPI shared mode, or ASIO) and runs crone's blocks in its callback
 * (verdandi_jack_null_process); scsynth is fed through the audio bridge (verdandi_bridge.h). M3 adds the host API choice (WASAPI or ASIO), sound INPUT with channel selection, the MIC / OFF / SYS
 * switch (SYS = what the system plays, WASAPI loopback), a measured round trip, and the fallback chain ASIO -> WASAPI -> null audio. The decisions are in audio_device.c and use only the small backend
 * interface below, so they run in a test on Linux with a fake card; audio_backend_pa.c is the PortAudio backend.
 */
#ifndef VERDANDI_AUDIO_DEVICE_H
#define VERDANDI_AUDIO_DEVICE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char uid[192];  /* what audio.conf stores: "wasapi:<name>", "asio:<name>" (the order of the list changes between runs, the name does not) or "loopback:<name>" */
    char name[128]; /* the device's name */
    char api[16];   /* "WASAPI" or "ASIO" */
    int is_default; /* the Windows default device (WASAPI only) */
    int out_channels;
    int in_channels;
    int loopback;   /* an input that records what a render device plays (WASAPI) */
    double default_rate;
    double low_out_ms; /* the driver's low latency for output and input, as PortAudio reports it */
    double low_in_ms;
} vaud_device;

typedef enum { VAUD_OK = 0, VAUD_NOT_FOUND, VAUD_BUSY, VAUD_BAD_RATE, VAUD_FAILED } vaud_error;

typedef struct {
    char out_uid[192]; /* "" = the Windows default output (WASAPI) */
    char in_uid[192];  /* "" = no input */
    unsigned rate;
    unsigned frames;
    int out_first;     /* the first channel of the output pair, 1 based (ASIO: 3 = outputs 3 and 4) */
    int in_l, in_r;    /* the input channels, 1 based; in_r == in_l is a mono source heard on both sides */
    int exclusive;     /* WASAPI exclusive mode (the device is ours alone: lowest delay, nobody else can play on it) */
} vaud_open_req;

typedef struct {
    char device_name[128];
    char in_name[128];   /* "" when there is no input */
    char host_api[40];   /* "Windows WASAPI shared", "ASIO", ... */
    unsigned rate;       /* what the stream really runs at */
    unsigned frames;     /* the block the card calls back with (0 = not known). `frames` of the request: 0 = the card's own period (the default: no re-blocking by the host API) */
    unsigned host_frames; /* the period of the host API under the callbacks (WASAPI shared: 480 at 48000 Hz even when the callbacks are 128): the callbacks may arrive in bursts of host_frames, 0 = same as frames */
    double device_rate;  /* the rate the device runs at (the Windows setting of the device; the card's clock for exclusive and ASIO), 0 = not known */
    int exclusive;       /* the stream is in exclusive mode */
    double out_latency_ms; /* the latencies the host API reports */
    double in_latency_ms;
    int in_active;       /* the input stream runs */
    int in_separate;     /* its blocks arrive through vaud_push_mic() (an input on another device than the output), not in the callback */
    char in_note[200];   /* why the input does not (output only), "" when it does or was not asked for */
} vaud_opened;

/* called by the card in its own thread: `in` is the selected input pair (interleaved stereo, `frames` frames) of a duplex stream, or NULL; `out`: interleaved stereo to fill */
typedef void (*vaud_callback)(const float *in, float *out, unsigned frames, void *user);

typedef struct {
    const char *name;
    int (*list)(vaud_device *out, int max);                         /* all devices of all host APIs (output, input, loopback); number found (0 = none) */
    /* open (not started). a duplex stream when the input is on the output's device, else a separate input stream whose blocks arrive through vaud_push_mic(). an input that cannot be opened must not
     * fail the output: the backend then opens the output alone and says why in res->in_note */
    vaud_error (*open)(const vaud_open_req *req, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn);
    int (*start)(char *err, size_t errn);                           /* 0 = ok */
    void (*close)(void);
    /* the system's own sound (WASAPI loopback of the default render device): started now, blocks arrive through vaud_push_sys(). 0 = ok */
    int (*open_sys)(unsigned rate, unsigned frames, char *name, size_t namen, char *err, size_t errn);
    void (*close_sys)(void);
    void (*describe)(char *out, size_t n); /* "PortAudio ...; host APIs: ..." for the log */
    int has_direct_sys;                    /* open_sys can record the system's sound without a loopback device in the list (the direct WASAPI loopback of the Windows build) */
} vaud_backend;

typedef struct {
    char output[192];   /* audio.conf output= ("" = the Windows default device) */
    char input[192];    /* audio.conf input= ("" = no input) */
    unsigned rate;      /* audio.conf rate= */
    unsigned period;    /* audio.conf block= : the ENGINE block (crone, scsynth, the bridge), default 256; independent of the card's buffer */
    unsigned buffer;    /* audio.conf buffer= : the card's buffer in frames, 0 = "auto" (the card's own period; the default) */
    int exclusive;      /* audio.conf exclusive=1: WASAPI exclusive mode */
    int out_first;      /* audio.conf out_first= (1: outputs 1 and 2) */
    int in_l, in_r;     /* audio.conf in_l= in_r= (1 and 2) */
    int force_null;     /* VERDANDI_AUDIO=null in the environment, or output=null in audio.conf */
    char notes[256];    /* what was wrong with the values (plain words), "" if nothing */
} vaud_config;

typedef enum { VAUD_MODE_NONE = 0, VAUD_MODE_DEVICE, VAUD_MODE_NULL, VAUD_MODE_FALLBACK } vaud_mode;
typedef enum { VAUD_IN_OFF = 0, VAUD_IN_MIC, VAUD_IN_SYS } vaud_input_mode;

/* TEST without cables: two seconds of the card's callbacks and the engine's answers are measured */
typedef enum { VAUD_ST_OK = 0, VAUD_ST_NO_CARD, VAUD_ST_NO_SCSYNTH, VAUD_ST_CARD_LATE, VAUD_ST_ENGINE_LATE, VAUD_ST_GLITCHES } vaud_selftest_verdict;
typedef struct {
    int state;              /* 0 never run, 1 running, 2 done */
    int callbacks;          /* callbacks of the card in the test */
    double interval_avg_ms, interval_max_ms, interval_expect_ms; /* time between two callbacks: average, the longest, what it should be (the card's period) */
    unsigned long long engine_blocks, late, glitches; /* blocks scsynth answered, bridge underruns, glitches of the card during the test */
    vaud_selftest_verdict verdict;
} vaud_selftest;

typedef struct {
    vaud_mode mode;
    vaud_opened opened;       /* valid in VAUD_MODE_DEVICE */
    unsigned rate, frames;    /* what crone runs at in every mode */
    char note[480];           /* for the screen and the log: why null audio, which device replaced the chosen one; "" when all is as chosen */
    char host_apis[120];      /* the host APIs of this PortAudio, for the page ("WASAPI ASIO") */
    vaud_input_mode input;    /* what norns hears now */
    int sys_available;        /* SYS (what Windows plays) can be offered: this PortAudio lists a WASAPI loopback device */
    char sys_reason[200];     /* why not, in plain words, "" when it is */
    char sys_note[320];       /* why SYS does not work, "" otherwise */
    double in_peak_db;        /* the peak of the input in the last blocks (-120 .. 0), what the AUDIO page shows as the input level */
    unsigned engine_prime;    /* frames of extra delay of the re-blocking between the card's block and the engine's (0 when the card's block is a multiple of the engine's) */
    unsigned engine_lag;      /* blocks of scsynth's answers held back in the bridge (the engine blocks per card callback) */
    unsigned card_frames;     /* the block of the card's callback (0 = not known) */
    unsigned long long card_xruns; /* callbacks the host API flagged as underflow / overflow (a block was late or lost at the card), counted since the start: the "crackles" counter of the AUDIO page */
    vaud_selftest selftest;
    double measured_ms;       /* the measured round trip (output to input and back to crone), -1 = none yet, -2 = no signal */
} vaud_state;

/* the values: defaults (default device, no input, 48000, 512), audio.conf in `home` (may be NULL), then the environment. out-of-range values are replaced and said in cfg->notes */
void vaud_config_load(vaud_config *cfg, const char *home);
/* the same checks for values that are already in cfg (the AUDIO page writes the file, the test calls this) */
void vaud_config_check(vaud_config *cfg);

/* opens the card as chosen, or says why not and goes on: ASIO busy -> the same device or the default through WASAPI -> null audio. Never blocks, never fails: the worst case is silence with a note. Logs one
 * line per decision to stderr. `bridge_name`: the shared memory for scsynth (NULL: none). The input is OFF at the start whatever is configured (no feedback): vaud_input_set() turns it on. */
void vaud_start(const vaud_backend *be, const vaud_config *cfg, const char *bridge_name, vaud_state *st);
void vaud_stop(void);

const vaud_state *vaud_get_state(void);
/* audio.conf-style text ("key=value" lines) into cfg (the same keys as the file): the AUDIO page hands its choices over this way */
void vaud_config_parse_text(vaud_config *cfg, const char *text);
/* the configuration that runs now */
const vaud_config *vaud_current_config(void);
/* a new device, channels or driver WITHOUT restarting: the stream is closed and reopened, the engine (crone, scsynth, the bridge, the rate and the engine block) keeps running. the input goes OFF.
 * returns 0 = the new setting runs (msg: a note or ""), 1 = it could not be opened and the old one runs again (msg: why, in one plain sentence), 2 = neither could be opened: silence on the engine's own clock. */
int vaud_apply(const vaud_config *want, char *msg, size_t n);
/* "uid\tname\tinputs\toutputs\tapi\tlow_out_ms\tlow_in_ms\tloopback" per line, for SYSTEM > AUDIO */
int vaud_list_text(const vaud_backend *be, char *out, size_t n);
void vaud_bridge_stats(unsigned long long *to_sc, unsigned long long *from_sc, unsigned long long *underruns, unsigned long long *drops, int *scsynth_attached);

/* MIC / OFF / SYS: what crone hears as the sound card's input. SYS has priority over MIC (as in the menu: one at a time). returns 0 = ok, 1 = this one cannot (no input device / no loopback): the note is in
 * vaud_get_state()->sys_note or ->opened.in_note and the input stays as it was */
int vaud_input_set(int mic_on, int sys_on);
/* the round trip: a click goes out, the input is watched for it. needs an input (and a cable or TotalMix Loopback from the output back to it). the result is in vaud_get_state()->measured_ms */
void vaud_measure_start(void);
/* TEST without cables: measures two seconds, the result is in vaud_get_state()->selftest */
void vaud_selftest_start(void);

/* the backend tells the card's glitches (PortAudio's output underflow / input overflow flags): n blocks */
void vaud_card_xrun(unsigned n);
/* for the backends' own threads: blocks of the separate input stream (mic) and of the loopback stream (sys), interleaved stereo */
void vaud_push_mic(const float *interleaved, unsigned frames);
void vaud_push_sys(const float *interleaved, unsigned frames);

/* the channel mapping of the input: `x` is `frames` frames of `channels` interleaved channels, `l` and `r` are 0 based; the stereo pair goes to `dst` (a mono source: l == r, heard on both sides). a channel
 * that is not there (index >= channels) is silence. used by the PortAudio backend and by the tests, so the tests run the same code */
static inline void vaud_pick_pair(const float *x, unsigned frames, int channels, int l, int r, float *dst) {
    for (unsigned i = 0; i < frames; i++) {
        dst[2 * i] = (l >= 0 && l < channels) ? x[(size_t)i * (size_t)channels + (size_t)l] : 0.0f;
        dst[2 * i + 1] = (r >= 0 && r < channels) ? x[(size_t)i * (size_t)channels + (size_t)r] : 0.0f;
    }
}

#ifdef __cplusplus
}
#endif
#endif
