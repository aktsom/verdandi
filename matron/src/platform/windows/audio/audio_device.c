/* audio_device.c (M2): see audio_device.h. portable C11 + pthreads; the only operating system calls are in the backend. */
#include "audio_device.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_bridge_host.h"

extern void verdandi_jack_null_configure(unsigned rate, unsigned frames);
extern void verdandi_jack_null_external_clock(int on);
extern int verdandi_jack_null_process(unsigned nframes, const float *cap_l, const float *cap_r, float *play_l, float *play_r);

#define DEFAULT_RATE 48000u
#define DEFAULT_PERIOD 512u

static vaud_state S;
static const vaud_backend *BE;
static int bridge_up;
static float scratch_l[2048], scratch_r[2048];

static void note_add(char *dst, size_t n, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static void note_add(char *dst, size_t n, const char *fmt, ...) {
    size_t len = strlen(dst);
    if (len >= n - 1) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(dst + len, n - len, fmt, ap);
    va_end(ap);
}

static int rate_ok(unsigned r) { return r == 44100 || r == 48000 || r == 88200 || r == 96000; }
static int period_ok(unsigned p) { return p >= 64 && p <= 2048 && p % 64 == 0; }

void vaud_config_check(vaud_config *cfg) {
    if (!rate_ok(cfg->rate)) {
        if (cfg->rate != 0) {
            note_add(cfg->notes, sizeof cfg->notes, "rate %u is not 44100, 48000, 88200 or 96000: using %u. ", cfg->rate, DEFAULT_RATE);
        }
        cfg->rate = DEFAULT_RATE;
    }
    if (!period_ok(cfg->period)) {
        if (cfg->period != 0) {
            note_add(cfg->notes, sizeof cfg->notes, "block %u is not a multiple of 64 from 64 to 2048: using %u. ", cfg->period, DEFAULT_PERIOD);
        }
        cfg->period = DEFAULT_PERIOD;
    }
}

void vaud_config_load(vaud_config *cfg, const char *home) {
    memset(cfg, 0, sizeof *cfg);
    if (home && *home) {
        char path[1024];
        snprintf(path, sizeof path, "%s/audio.conf", home);
        FILE *f = fopen(path, "r");
        if (f) {
            char line[512];
            while (fgets(line, sizeof line, f)) {
                line[strcspn(line, "\r\n")] = 0;
                char *eq = strchr(line, '=');
                if (!eq) {
                    continue;
                }
                *eq = 0;
                const char *k = line, *v = eq + 1;
                if (!strcmp(k, "output")) {
                    snprintf(cfg->output, sizeof cfg->output, "%s", v);
                } else if (!strcmp(k, "rate")) {
                    cfg->rate = (unsigned)strtoul(v, NULL, 10);
                } else if (!strcmp(k, "period")) {
                    cfg->period = (unsigned)strtoul(v, NULL, 10);
                }
            }
            fclose(f);
        }
    }
    const char *e = getenv("VERDANDI_AUDIO");
    if (e && !strcmp(e, "null")) {
        cfg->force_null = 1;
    }
    if (!strcmp(cfg->output, "null")) {
        cfg->force_null = 1;
    }
    e = getenv("VERDANDI_AUDIO_OUTPUT"); /* tests and the launcher: the device by name, over audio.conf */
    if (e && *e) {
        snprintf(cfg->output, sizeof cfg->output, "%s", e);
    }
    e = getenv("VERDANDI_AUDIO_RATE");
    if (e && *e) {
        cfg->rate = (unsigned)strtoul(e, NULL, 10);
    }
    e = getenv("VERDANDI_AUDIO_PERIOD");
    if (e && *e) {
        cfg->period = (unsigned)strtoul(e, NULL, 10);
    }
    vaud_config_check(cfg);
}

static void card_callback(float *out, unsigned frames, void *user) {
    (void)user;
    if (frames > 2048 || verdandi_jack_null_process(frames, NULL, NULL, scratch_l, scratch_r) != 0) {
        static int told;
        if (!told) { /* the card gave another block size than the one crone runs at: silence, and one line (never a line per block) */
            told = 1;
            fprintf(stderr, "audio: the card called back with %u frames, not %u: silence for those blocks\n", frames, S.frames);
        }
        memset(out, 0, (size_t)frames * 2 * sizeof(float));
        return;
    }
    for (unsigned i = 0; i < frames; i++) {
        out[2 * i] = scratch_l[i];
        out[2 * i + 1] = scratch_r[i];
    }
}

static const char *error_words(vaud_error e) {
    switch (e) {
    case VAUD_NOT_FOUND: return "was not found";
    case VAUD_BUSY: return "is busy or in use by another program";
    case VAUD_BAD_RATE: return "does not accept this sample rate";
    default: return "could not be opened";
    }
}

int vaud_list_text(const vaud_backend *be, char *out, size_t n) {
    vaud_device dev[64];
    int count = be->list(dev, 64);
    size_t len = 0;
    out[0] = 0;
    for (int i = 0; i < count && len + 400 < n; i++) {
        len += (size_t)snprintf(out + len, n - len, "%s\t%s%s\t0\t%d\n", dev[i].uid, dev[i].name, dev[i].is_default ? " (default)" : "", dev[i].out_channels);
    }
    return count;
}

void vaud_start(const vaud_backend *be, const vaud_config *cfg_in, const char *bridge_name, vaud_state *st_out) {
    vaud_config cfg = *cfg_in;
    memset(&S, 0, sizeof S);
    BE = be;
    vaud_config_check(&cfg);
    S.rate = cfg.rate;
    S.frames = cfg.period;
    if (cfg.notes[0]) {
        fprintf(stderr, "audio: %s\n", cfg.notes);
    }
    int use_card = !cfg.force_null && be != NULL;
    char err[256] = "";
    if (use_card) {
        vaud_opened res;
        memset(&res, 0, sizeof res);
        vaud_error e = be->open(cfg.output, cfg.rate, cfg.period, card_callback, NULL, &res, err, sizeof err);
        if (e == VAUD_NOT_FOUND && cfg.output[0]) {
            /* the chosen device is not there (unplugged, renamed): the default device, and say so */
            fprintf(stderr, "audio: output '%s' %s (%s); trying the default device\n", cfg.output, error_words(e), err);
            vaud_error e2 = be->open("", cfg.rate, cfg.period, card_callback, NULL, &res, err, sizeof err);
            if (e2 == VAUD_OK) {
                note_add(S.note, sizeof S.note, "audio device '%.60s' not found, using the default device", strncmp(cfg.output, "wasapi:", 7) == 0 ? cfg.output + 7 : cfg.output);
            }
            e = e2;
        }
        if (e == VAUD_BAD_RATE && res.rate != 0) {
            /* shared mode keeps the rate the device runs at: follow it */
            fprintf(stderr, "audio: the device does not take %u Hz; trying %u Hz\n", cfg.rate, res.rate);
            cfg.rate = res.rate;
            e = be->open(cfg.output, cfg.rate, cfg.period, card_callback, NULL, &res, err, sizeof err);
        }
        if (e == VAUD_OK) {
            S.opened = res;
            S.rate = res.rate ? res.rate : cfg.rate;
            S.frames = cfg.period;
            verdandi_jack_null_configure(S.rate, S.frames);
            verdandi_jack_null_external_clock(1);
            if (be->start(err, sizeof err) == 0) {
                S.mode = VAUD_MODE_DEVICE;
                fprintf(stderr, "audio: device '%s' (%s), %u Hz, %u frames per block (%.1f ms), output latency %.1f ms\n", res.device_name, res.host_api, S.rate, S.frames,
                        1000.0 * S.frames / S.rate, res.latency_ms);
            } else {
                be->close();
                verdandi_jack_null_external_clock(0);
                e = VAUD_FAILED;
            }
        }
        if (S.mode != VAUD_MODE_DEVICE) {
            const char *shown = strncmp(cfg.output, "wasapi:", 7) == 0 ? cfg.output + 7 : cfg.output;
            note_add(S.note, sizeof S.note, "no sound: audio device %s%.60s%s %s. null audio is used", cfg.output[0] ? "'" : "(default)", shown, cfg.output[0] ? "'" : "", error_words(e));
            fprintf(stderr, "audio: %s (%s)\n", S.note, err);
            S.mode = VAUD_MODE_FALLBACK;
        }
    } else {
        S.mode = VAUD_MODE_NULL;
        fprintf(stderr, "audio: null audio (no sound device is opened)%s\n", cfg.force_null ? ", as chosen" : "");
    }
    if (S.mode != VAUD_MODE_DEVICE) {
        verdandi_jack_null_configure(S.rate, S.frames);
        verdandi_jack_null_external_clock(0);
        fprintf(stderr, "audio: null clock, %u Hz, %u frames per block\n", S.rate, S.frames);
    }
    if (bridge_name && *bridge_name) {
        bridge_up = verdandi_bridge_host_start(bridge_name, S.rate, S.frames) == 0;
    }
    if (st_out) {
        *st_out = S;
    }
}

void vaud_stop(void) {
    if (BE && S.mode == VAUD_MODE_DEVICE) {
        BE->close();
    }
    if (bridge_up) {
        verdandi_bridge_host_stop();
        bridge_up = 0;
    }
    S.mode = VAUD_MODE_NONE;
}

const vaud_state *vaud_get_state(void) { return &S; }

void vaud_bridge_stats(unsigned long long *to_sc, unsigned long long *from_sc, unsigned long long *underruns, unsigned long long *drops, int *attached) {
    verdandi_bridge_host_stats(to_sc, from_sc, underruns, drops, attached);
}
