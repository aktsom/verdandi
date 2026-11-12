/* audio_device.c (M2, extended in M3): see audio_device.h. portable C11 + pthreads; the only operating system calls are in the backend. */
#include "audio_device.h"

#include <math.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "audio_bridge_host.h"

extern void verdandi_jack_null_configure(unsigned rate, unsigned frames);
extern void verdandi_jack_null_external_clock(int on);
extern int verdandi_jack_null_process(unsigned nframes, const float *cap_l, const float *cap_r, float *play_l, float *play_r);

#define DEFAULT_RATE 48000u
#define DEFAULT_PERIOD 128u /* the ENGINE block (M3 round 2): independent of the card's buffer */
#define MAXF 2048u

static vaud_state S;
static const vaud_backend *BE;
static int bridge_up;
static int sys_open;
static atomic_int in_mode; /* vaud_input_mode */
static float scratch_l[MAXF], scratch_r[MAXF], cap_l[MAXF], cap_r[MAXF], mic_tmp[2 * MAXF], sys_tmp[2 * MAXF];

/* ---- a ring of stereo frames between a thread of the backend (the input stream) and the card's callback: one writer, one reader. the reader keeps the fill near one block (clocks of two devices drift:
 * too much is dropped, too little is padded with silence and counted) ---- */
#define RING_FRAMES 16384u
typedef struct {
    float buf[2 * RING_FRAMES];
    atomic_uint w, r; /* frames written / read, free running */
    atomic_uint underruns, drops;
    atomic_int active;
} vring;
static vring mic_ring, sys_ring;

static void ring_reset(vring *g) {
    atomic_store(&g->w, 0);
    atomic_store(&g->r, 0);
    atomic_store(&g->underruns, 0);
    atomic_store(&g->drops, 0);
}
static void ring_push(vring *g, const float *x, unsigned n) {
    unsigned w = atomic_load(&g->w), r = atomic_load(&g->r);
    if (n > RING_FRAMES - (w - r)) { /* the reader is not there: keep the newest */
        atomic_store(&g->r, w - (RING_FRAMES / 2));
        atomic_fetch_add(&g->drops, 1);
    }
    for (unsigned i = 0; i < n; i++) {
        unsigned k = (w + i) % RING_FRAMES;
        g->buf[2 * k] = x[2 * i];
        g->buf[2 * k + 1] = x[2 * i + 1];
    }
    atomic_store(&g->w, w + n);
}
/* n frames into out (interleaved); returns 1 when it was complete */
static int ring_pull(vring *g, float *out, unsigned n) {
    unsigned w = atomic_load(&g->w), r = atomic_load(&g->r);
    unsigned fill = w - r;
    int complete = fill >= n;
    unsigned take = complete ? n : fill;
    for (unsigned i = 0; i < take; i++) {
        unsigned k = (r + i) % RING_FRAMES;
        out[2 * i] = g->buf[2 * k];
        out[2 * i + 1] = g->buf[2 * k + 1];
    }
    for (unsigned i = take; i < n; i++) {
        out[2 * i] = out[2 * i + 1] = 0.f;
    }
    r += take;
    if (!complete) {
        atomic_fetch_add(&g->underruns, 1);
    } else if (w - r > 2 * n) { /* more than two blocks waiting: this device runs faster than the card; drop the surplus */
        r = w - n;
        atomic_fetch_add(&g->drops, 1);
    }
    atomic_store(&g->r, r);
    return complete;
}

void vaud_push_mic(const float *interleaved, unsigned frames) {
    if (atomic_load(&mic_ring.active)) ring_push(&mic_ring, interleaved, frames);
}
void vaud_push_sys(const float *interleaved, unsigned frames) {
    if (atomic_load(&sys_ring.active)) ring_push(&sys_ring, interleaved, frames);
}

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
static int period_ok(unsigned p) { return p >= 64 && p <= 1024 && p % 64 == 0; }
static int buffer_ok(unsigned b) { return b == 0 || (b >= 32 && b <= 2048 && b % 32 == 0); }
static const char *shown(const char *uid) {
    const char *c = strchr(uid, ':');
    return c ? c + 1 : uid;
}

void vaud_config_check(vaud_config *cfg) {
    /* "default" in every spelling is the Windows default device: no name */
    if (!strcmp(cfg->output, "default") || !strcmp(cfg->output, "wasapi:default") || !strcmp(cfg->output, "wasapi:")) {
        cfg->output[0] = 0;
    }
    if (!strcmp(cfg->input, "none") || !strcmp(cfg->input, "default") || !strcmp(cfg->input, "off")) {
        cfg->input[0] = 0;
    }
    if (!rate_ok(cfg->rate)) {
        if (cfg->rate != 0) {
            note_add(cfg->notes, sizeof cfg->notes, "rate %u is not 44100, 48000, 88200 or 96000: using %u. ", cfg->rate, DEFAULT_RATE);
        }
        cfg->rate = DEFAULT_RATE;
    }
    if (!period_ok(cfg->period)) {
        if (cfg->period != 0) {
            note_add(cfg->notes, sizeof cfg->notes, "block %u is not a multiple of 64 from 64 to 1024: using %u. ", cfg->period, DEFAULT_PERIOD);
        }
        cfg->period = DEFAULT_PERIOD;
    }
    if (!buffer_ok(cfg->buffer)) {
        note_add(cfg->notes, sizeof cfg->notes, "buffer %u is not auto or a multiple of 32 up to 2048: using auto. ", cfg->buffer);
        cfg->buffer = 0;
    }
    cfg->exclusive = cfg->exclusive ? 1 : 0;
    if (cfg->out_first < 1 || cfg->out_first > 64) {
        if (cfg->out_first != 0) note_add(cfg->notes, sizeof cfg->notes, "out_first %d is not a channel from 1 to 64: using 1. ", cfg->out_first);
        cfg->out_first = 1;
    }
    if (cfg->in_l < 1 || cfg->in_l > 64) {
        if (cfg->in_l != 0) note_add(cfg->notes, sizeof cfg->notes, "in_l %d is not a channel from 1 to 64: using 1. ", cfg->in_l);
        cfg->in_l = 1;
    }
    if (cfg->in_r < 1 || cfg->in_r > 64) {
        if (cfg->in_r != 0) note_add(cfg->notes, sizeof cfg->notes, "in_r %d is not a channel from 1 to 64: using %d. ", cfg->in_r, cfg->in_l + 1 > 64 ? 1 : cfg->in_l + 1);
        cfg->in_r = cfg->in_l + 1 > 64 ? 1 : cfg->in_l + 1;
    }
}

static void parse_line(vaud_config *cfg, char *line) {
    line[strcspn(line, "\r\n")] = 0;
    char *eq = strchr(line, '=');
    if (!eq) {
        return;
    }
    *eq = 0;
    const char *k = line, *v = eq + 1;
    if (!strcmp(k, "output")) {
        snprintf(cfg->output, sizeof cfg->output, "%s", v);
    } else if (!strcmp(k, "input")) {
        snprintf(cfg->input, sizeof cfg->input, "%s", v);
    } else if (!strcmp(k, "rate")) {
        cfg->rate = (unsigned)strtoul(v, NULL, 10);
    } else if (!strcmp(k, "block")) {
        cfg->period = (unsigned)strtoul(v, NULL, 10);
    } else if (!strcmp(k, "buffer")) {
        cfg->buffer = !strcmp(v, "auto") ? 0 : (unsigned)strtoul(v, NULL, 10);
    } else if (!strcmp(k, "exclusive")) {
        cfg->exclusive = atoi(v);
    } else if (!strcmp(k, "period")) {
        /* the key of versions up to 0.3: it was the card's block and the engine's at once. it is read no more (the engine block is block=, the card's buffer is buffer=; the AUDIO page writes both) */
        note_add(cfg->notes, sizeof cfg->notes, "period= is no longer used (block= is the engine block, buffer= the card's buffer; the AUDIO page writes them). ");
    } else if (!strcmp(k, "out_first")) {
        cfg->out_first = atoi(v);
    } else if (!strcmp(k, "in_l")) {
        cfg->in_l = atoi(v);
    } else if (!strcmp(k, "in_r")) {
        cfg->in_r = atoi(v);
    }
}

void vaud_config_parse_text(vaud_config *cfg, const char *text) {
    char line[512];
    const char *p = text;
    while (p && *p) {
        size_t n = strcspn(p, "\n");
        snprintf(line, sizeof line, "%.*s", (int)(n < sizeof line - 1 ? n : sizeof line - 1), p);
        parse_line(cfg, line);
        p += n;
        if (*p == '\n') {
            p++;
        }
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
                parse_line(cfg, line);
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
    e = getenv("VERDANDI_AUDIO_INPUT");
    if (e && *e) {
        snprintf(cfg->input, sizeof cfg->input, "%s", e);
    }
    e = getenv("VERDANDI_AUDIO_RATE");
    if (e && *e) {
        cfg->rate = (unsigned)strtoul(e, NULL, 10);
    }
    e = getenv("VERDANDI_AUDIO_PERIOD");
    if (e && *e) {
        cfg->period = (unsigned)strtoul(e, NULL, 10);
    }
    e = getenv("VERDANDI_AUDIO_BUFFER");
    if (e && *e) {
        cfg->buffer = !strcmp(e, "auto") ? 0 : (unsigned)strtoul(e, NULL, 10);
    }
    vaud_config_check(cfg);
}

/* ---- the card's callback ---- */
static volatile int measure_state;        /* 0 idle, 1 armed (the click goes out in the next block), 2 waiting for the answer */
static volatile unsigned measure_frames;  /* frames since the click */

static double to_db(double x) { return x <= 1e-6 ? -120.0 : 20.0 * log10(x); }

/* a fifo of stereo frames used by the card's thread only */
#define FIFO_FRAMES 8192u
typedef struct {
    float l[FIFO_FRAMES], r[FIFO_FRAMES];
    unsigned head, n;
} vfifo;
static vfifo fi, fo;
static int fifos_primed;
static void fifo_reset(vfifo *f) { f->head = f->n = 0; }
static void fifo_push1(vfifo *f, float l, float r) {
    if (f->n >= FIFO_FRAMES) { /* cannot happen with blocks up to 2048 and 1024; if it does, the oldest frame goes */
        f->head = (f->head + 1) % FIFO_FRAMES;
        f->n--;
    }
    unsigned k = (f->head + f->n) % FIFO_FRAMES;
    f->l[k] = l;
    f->r[k] = r;
    f->n++;
}
static void fifo_pop1(vfifo *f, float *l, float *r) {
    *l = f->l[f->head];
    *r = f->r[f->head];
    f->head = (f->head + 1) % FIFO_FRAMES;
    f->n--;
}

/* the self-test (TEST without cables): the callbacks' timing and the engine's answers for two seconds */
static volatile int st_active;
static double st_sum_ms, st_t0_ms, st_last_ms;
static int st_n;
static unsigned long long st_blocks0, st_late0, st_x0;
static double mono_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}
static void selftest_tick(void) {
    double now = mono_ms();
    vaud_selftest *t = &S.selftest;
    if (st_last_ms > 0) {
        double dt = now - st_last_ms;
        st_sum_ms += dt;
        st_n++;
        if (dt > t->interval_max_ms) t->interval_max_ms = dt;
    }
    st_last_ms = now;
    t->callbacks++;
    if (now - st_t0_ms >= 2000.0) {
        unsigned long long to, from, under, drops;
        int att;
        verdandi_bridge_host_stats(&to, &from, &under, &drops, &att);
        t->interval_avg_ms = st_n ? st_sum_ms / st_n : 0.0;
        t->engine_blocks = from - st_blocks0;
        t->late = under - st_late0;
        t->glitches = S.card_xruns - st_x0;
        if (t->interval_max_ms > 3.0 * t->interval_expect_ms + 5.0) t->verdict = VAUD_ST_CARD_LATE;
        else if (t->glitches > 0) t->verdict = VAUD_ST_GLITCHES;
        else if (!att || t->engine_blocks == 0) t->verdict = VAUD_ST_NO_SCSYNTH;
        else if (t->late > 2) t->verdict = VAUD_ST_ENGINE_LATE;
        else t->verdict = VAUD_ST_OK;
        t->state = 2;
        st_active = 0;
    }
}

void vaud_selftest_start(void) {
    memset(&S.selftest, 0, sizeof S.selftest);
    if (S.mode != VAUD_MODE_DEVICE) {
        S.selftest.state = 2;
        S.selftest.verdict = VAUD_ST_NO_CARD;
        return;
    }
    unsigned long long to, from, under, drops;
    int att;
    verdandi_bridge_host_stats(&to, &from, &under, &drops, &att);
    st_blocks0 = from;
    st_late0 = under;
    st_x0 = S.card_xruns;
    st_sum_ms = 0;
    st_n = 0;
    st_last_ms = 0;
    st_t0_ms = mono_ms();
    S.selftest.interval_expect_ms = 1000.0 * (S.card_frames ? S.card_frames : S.frames) / (S.rate ? S.rate : 48000);
    S.selftest.state = 1;
    st_active = 1;
}

static void card_callback(const float *in, float *out, unsigned frames, void *user) {
    if (st_active) {
        selftest_tick();
    }
    (void)user;
    if (frames > MAXF) {
        static int told;
        if (!told) {
            told = 1;
            fprintf(stderr, "audio: the card called back with %u frames, not %u: silence for those blocks\n", frames, S.frames);
        }
        memset(out, 0, (size_t)frames * 2 * sizeof(float));
        return;
    }
    /* the sources: a duplex stream gives `in`; a separate input stream arrives through the ring */
    const float *raw = in;
    if (!raw && atomic_load(&mic_ring.active)) {
        ring_pull(&mic_ring, mic_tmp, frames);
        raw = mic_tmp;
    }
    const float *src = NULL;
    int mode = atomic_load(&in_mode);
    if (mode == VAUD_IN_MIC) {
        src = raw;
    } else if (mode == VAUD_IN_SYS && atomic_load(&sys_ring.active)) {
        ring_pull(&sys_ring, sys_tmp, frames);
        src = sys_tmp;
    }
    double secs_fall = 12.0 * frames / (S.rate ? S.rate : 48000);
    if (src) {
        double peak = 0;
        for (unsigned i = 0; i < frames; i++) {
            double a = fabs(src[2 * i]), b = fabs(src[2 * i + 1]);
            if (a > peak) peak = a;
            if (b > peak) peak = b;
        }
        double db = to_db(peak), fall = S.in_peak_db - secs_fall;
        S.in_peak_db = db > fall ? db : fall;
    } else {
        double fall = S.in_peak_db - secs_fall;
        S.in_peak_db = fall < -120 ? -120 : fall;
    }
    /* the engine runs in blocks of its own size E (crone, scsynth and the bridge are configured for it); the card's callback has the size the card wants (480 on a 10 ms Windows period, 64 on an ASIO
     * buffer, 1024 ...). two small fifos re-block: the input is collected until a block of E is there, the blocks run, the output is handed out in the card's size. when E does not divide the card's size
     * the output is primed with E frames of silence once (one engine block of delay) so that the card never finds the fifo empty. no allocation, no logging, no lock but jack_null's own. */
    if (!fifos_primed) {
        fifos_primed = 1;
        unsigned prime = (frames % S.frames) ? S.frames : 0;
        fifo_reset(&fo);
        fifo_reset(&fi);
        for (unsigned i = 0; i < prime; i++) {
            fifo_push1(&fo, 0.f, 0.f);
        }
        S.card_frames = frames;
        S.engine_prime = prime;
        unsigned hf = S.opened.host_frames > frames ? S.opened.host_frames : frames;
        if (S.opened.exclusive) {
            hf *= 2; /* an exclusive stream is double buffered by the host API: two periods can arrive together */
        }
        S.engine_lag = (hf + S.frames - 1) / S.frames;
        /* scsynth is another program and needs a moment to wake and to compute: never less than about 5 ms of hold-back, whatever the card's buffer (a card buffer of 64 or 128 frames is 1.3 to 2.7 ms) */
        unsigned floor_lag = (S.rate / 200 + S.frames - 1) / S.frames;
        if (S.engine_lag < floor_lag) S.engine_lag = floor_lag;
        if (S.engine_lag < 1) S.engine_lag = 1;
        if (S.engine_lag > 12) S.engine_lag = 12; /* the ring holds 16 blocks, 14 of them can be held back (about 37 ms at 128) */
        verdandi_bridge_host_set_lag(S.engine_lag);
    }
    for (unsigned i = 0; i < frames; i++) {
        fifo_push1(&fi, src ? src[2 * i] : 0.f, src ? src[2 * i + 1] : 0.f);
    }
    while (fi.n >= S.frames) {
        unsigned E = S.frames;
        for (unsigned i = 0; i < E; i++) {
            fifo_pop1(&fi, &cap_l[i], &cap_r[i]);
        }
        if (verdandi_jack_null_process(E, cap_l, cap_r, scratch_l, scratch_r) != 0) {
            memset(scratch_l, 0, E * sizeof(float));
            memset(scratch_r, 0, E * sizeof(float));
        }
        for (unsigned i = 0; i < E; i++) {
            fifo_push1(&fo, scratch_l[i], scratch_r[i]);
        }
    }
    if (fo.n < frames) {
        S.card_xruns += 1; /* the engine did not deliver in time: silence for the missing part (counted as a glitch) */
    }
    for (unsigned i = 0; i < frames; i++) {
        float l = 0.f, r = 0.f;
        if (fo.n > 0) {
            fifo_pop1(&fo, &l, &r);
        }
        out[2 * i] = l;
        out[2 * i + 1] = r;
    }
    /* the round trip: a click on the output, then the raw input is watched for it */
    if (measure_state == 1) {
        for (unsigned i = 0; i < 8 && i < frames; i++) {
            out[2 * i] = 0.9f;
            out[2 * i + 1] = 0.9f;
        }
        measure_state = 2;
        measure_frames = frames; /* the click is at the start of this block: the next block starts `frames` later */
    } else if (measure_state == 2) {
        if (raw) {
            for (unsigned i = 0; i < frames; i++) {
                if (fabsf(raw[2 * i]) > 0.3f || fabsf(raw[2 * i + 1]) > 0.3f) {
                    S.measured_ms = 1000.0 * (measure_frames + i) / (S.rate ? S.rate : 48000);
                    measure_state = 0;
                    return;
                }
            }
        }
        measure_frames += frames;
        if (measure_frames > 2u * (S.rate ? S.rate : 48000)) { /* two seconds: nothing came back */
            S.measured_ms = -2;
            measure_state = 0;
        }
    }
}

void vaud_card_xrun(unsigned n) { S.card_xruns += n; }

void vaud_measure_start(void) {
    S.measured_ms = -1;
    measure_state = (S.mode == VAUD_MODE_DEVICE) ? 1 : 0;
    if (S.mode != VAUD_MODE_DEVICE) {
        S.measured_ms = -2;
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
    vaud_device dev[96];
    int count = be->list(dev, 96);
    size_t len = 0;
    out[0] = 0;
    for (int i = 0; i < count && len + 600 < n; i++) {
        len += (size_t)snprintf(out + len, n - len, "%s\t%s%s\t%d\t%d\t%s\t%.1f\t%.1f\t%d\n", dev[i].uid, dev[i].name, dev[i].is_default ? " (default)" : "", dev[i].in_channels,
                                dev[i].out_channels, dev[i].api, dev[i].low_out_ms, dev[i].low_in_ms, dev[i].loopback);
    }
    return count;
}

/* the WASAPI device that is the same hardware as an ASIO driver: the same name, or the one the Windows default is. "" = the default */
static void wasapi_twin(const vaud_backend *be, const char *uid, int want_input, char *dst, size_t n) {
    dst[0] = 0;
    if (!uid[0]) {
        return;
    }
    vaud_device dev[96];
    int count = be->list(dev, 96);
    const char *name = shown(uid);
    for (int i = 0; i < count; i++) {
        if (!strcmp(dev[i].api, "WASAPI") && !dev[i].loopback && (want_input ? dev[i].in_channels > 0 : dev[i].out_channels > 0) &&
            (strstr(dev[i].name, name) || strstr(name, dev[i].name))) {
            snprintf(dst, n, "%s", dev[i].uid);
            return;
        }
    }
}

static vaud_config CUR; /* what runs now (the AUDIO page asks, vaud_apply starts from it) */

/* the rate a device runs at now ("" = the Windows default output), 0 when the list does not know it */
static double device_rate_of(const vaud_backend *be, const char *uid) {
    vaud_device dev[96];
    int count = be->list(dev, 96);
    for (int i = 0; i < count; i++) {
        if ((uid[0] && !strcmp(dev[i].uid, uid)) || (!uid[0] && dev[i].is_default && dev[i].out_channels > 0)) {
            return dev[i].default_rate;
        }
    }
    return 0;
}

/* the chain of decisions that turns a configuration into an open (not started) stream, or says why not: the chosen device -> (not found) the default device -> (rate refused) the device's own rate
 * (only when follow_rate: at the start; a live change must keep the engine's rate) -> (exclusive refused) normal mode -> (ASIO busy) the same hardware through WASAPI. notes in plain words go to `note`.
 * cfg is updated to what was really opened. */
static vaud_error open_chain(const vaud_backend *be, vaud_config *cfg, int follow_rate, vaud_opened *res, char *note, size_t noten, char *err, size_t errn) {
    vaud_open_req req;
    memset(&req, 0, sizeof req);
    snprintf(req.out_uid, sizeof req.out_uid, "%s", cfg->output);
    snprintf(req.in_uid, sizeof req.in_uid, "%s", cfg->input);
    req.rate = cfg->rate;
    req.frames = cfg->buffer;
    req.out_first = cfg->out_first;
    req.in_l = cfg->in_l;
    req.in_r = cfg->in_r;
    req.exclusive = cfg->exclusive;
    memset(res, 0, sizeof *res);
    if (follow_rate && (cfg->exclusive || !strncmp(cfg->output, "asio:", 5))) {
        /* exclusive mode and ASIO set the CLOCK of the device to the rate they ask for (the RME follows): so they ask for the rate the device runs at now, and norns follows it. shared mode never needs this */
        double dr = device_rate_of(be, cfg->output);
        if (dr > 0 && rate_ok((unsigned)dr) && (unsigned)dr != cfg->rate) {
            note_add(note, noten, "the device runs at %.0f Hz: norns follows it (%u Hz was asked for) so that its clock is not changed", dr, cfg->rate);
            cfg->rate = (unsigned)dr;
            req.rate = cfg->rate;
        }
    }
    vaud_error e = be->open(&req, card_callback, NULL, res, err, errn);
    if (e != VAUD_OK && req.exclusive) {
        fprintf(stderr, "audio: exclusive mode of '%s' %s (%s); trying the normal (shared) mode\n", cfg->output[0] ? shown(cfg->output) : "the default device", error_words(e), err);
        req.exclusive = 0;
        cfg->exclusive = 0;
        e = be->open(&req, card_callback, NULL, res, err, errn);
        if (e == VAUD_OK) {
            note_add(note, noten, "exclusive mode was refused (%.120s): normal mode is used", err[0] ? err : "another program has the device, or it takes no such format");
        }
    }
    if (e == VAUD_NOT_FOUND && cfg->output[0]) {
        /* the chosen device is not there (unplugged, renamed): the default device, and say so */
        fprintf(stderr, "audio: output '%s' %s (%s); trying the default device\n", cfg->output, error_words(e), err);
        vaud_open_req r2 = req;
        r2.out_uid[0] = 0;
        r2.out_first = 1;
        vaud_error e2 = be->open(&r2, card_callback, NULL, res, err, errn);
        if (e2 == VAUD_OK) {
            req = r2;
            note_add(note, noten, "audio device '%.60s' not found, using the default device", shown(cfg->output));
            cfg->output[0] = 0;
            cfg->out_first = 1;
        }
        e = e2;
    }
    if (e == VAUD_BAD_RATE && res->rate != 0 && follow_rate) {
        /* shared mode keeps the rate the device runs at: follow it */
        fprintf(stderr, "audio: the device does not take %u Hz; trying %u Hz\n", cfg->rate, res->rate);
        cfg->rate = res->rate;
        req.rate = res->rate;
        e = be->open(&req, card_callback, NULL, res, err, errn);
    }
    if ((e == VAUD_BUSY || e == VAUD_FAILED) && !strncmp(req.out_uid, "asio:", 5)) {
        /* an ASIO driver is normally used by one program at a time: the program that has it (the DAW) keeps it. the same hardware through WASAPI shared mode can be used next to it */
        char twin[192], twin_in[192];
        wasapi_twin(be, req.out_uid, 0, twin, sizeof twin);
        wasapi_twin(be, req.in_uid, 1, twin_in, sizeof twin_in);
        fprintf(stderr, "audio: ASIO driver '%s' %s (%s); trying WASAPI%s%s\n", shown(req.out_uid), error_words(e), err, twin[0] ? " on " : "", twin[0] ? shown(twin) : "");
        vaud_open_req r2 = req;
        snprintf(r2.out_uid, sizeof r2.out_uid, "%s", twin);
        snprintf(r2.in_uid, sizeof r2.in_uid, "%s", twin_in);
        r2.out_first = 1;
        r2.frames = 0;
        r2.exclusive = 0;
        vaud_error e2 = be->open(&r2, card_callback, NULL, res, err, errn);
        if (e2 == VAUD_OK) {
            note_add(note, noten, "ASIO driver '%.50s' is busy: another program has it (close its audio, or use the driver's multi-client mode). Using WASAPI%s%.50s instead", shown(req.out_uid),
                     twin[0] ? " on " : "", twin[0] ? shown(twin) : "");
            snprintf(cfg->output, sizeof cfg->output, "%s", twin);
            snprintf(cfg->input, sizeof cfg->input, "%s", twin_in);
            cfg->out_first = 1;
            cfg->buffer = 0;
            cfg->exclusive = 0;
        }
        e = e2;
    }
    return e;
}

/* the stream that was opened runs: the engine takes the card's clock. returns 0 = ok */
static int activate(const vaud_opened *res, const vaud_config *cfg, char *err, size_t errn) {
    S.opened = *res;
    S.card_frames = 0;
    fifos_primed = 0;
    atomic_store(&mic_ring.active, res->in_active && res->in_separate ? 1 : 0); /* (a duplex stream gives its input in the callback; a separate one arrives through vaud_push_mic) */
    verdandi_jack_null_external_clock(1);
    if (BE->start(err, errn) != 0) {
        BE->close();
        verdandi_jack_null_external_clock(0);
        atomic_store(&mic_ring.active, 0);
        return -1;
    }
    CUR = *cfg;
    S.mode = VAUD_MODE_DEVICE;
    return 0;
}

static void log_device(const vaud_opened *res, const vaud_config *cfg) {
    if (res->device_rate > 0) {
        fprintf(stderr, "audio: the device itself runs at %.0f Hz (its Windows setting / clock)%s\n", res->device_rate, (unsigned)res->device_rate == S.rate ? "" : (res->exclusive ? " - DIFFERENT from norns" : ": the Windows mixer converts to norns's rate"));
    }
    fprintf(stderr, "audio: device '%s' (%s%s), %u Hz, engine block %u frames (%.1f ms), card buffer %s, output latency %.1f ms\n", res->device_name, res->host_api, res->exclusive ? ", exclusive" : "", S.rate, S.frames,
            1000.0 * S.frames / S.rate, cfg->buffer ? "asked" : "auto", res->out_latency_ms);
    if (res->in_name[0]) {
        fprintf(stderr, "audio: input '%s'%s, input latency %.1f ms%s%s\n", res->in_name, res->in_active ? "" : " NOT running", res->in_latency_ms, res->in_note[0] ? ": " : "", res->in_note);
    }
}

void vaud_start(const vaud_backend *be, const vaud_config *cfg_in, const char *bridge_name, vaud_state *st_out) {
    vaud_config cfg = *cfg_in;
    memset(&S, 0, sizeof S);
    BE = be;
    sys_open = 0;
    atomic_store(&in_mode, VAUD_IN_OFF);
    ring_reset(&mic_ring);
    ring_reset(&sys_ring);
    atomic_store(&mic_ring.active, 0);
    atomic_store(&sys_ring.active, 0);
    measure_state = 0;
    S.measured_ms = -1;
    S.in_peak_db = -120;
    vaud_config_check(&cfg);
    S.rate = cfg.rate;
    S.frames = cfg.period;
    if (cfg.notes[0]) {
        fprintf(stderr, "audio: %s\n", cfg.notes);
    }
    if (be && be->describe) {
        char d[300];
        be->describe(d, sizeof d);
        const char *h = strstr(d, "host APIs:");
        snprintf(S.host_apis, sizeof S.host_apis, "%.110s", h ? h + 10 : d);
        char *br = strchr(S.host_apis, '['); /* "[no ASIO in this build]" is for the log, not for the page */
        if (br) {
            *br = 0;
        }
    }
    S.sys_available = 1;
    if (be) {
        vaud_device dv[96];
        int n = be->list(dv, 96), loops = 0;
        for (int i = 0; i < n; i++) {
            loops += dv[i].loopback ? 1 : 0;
        }
        if (n > 0 && loops == 0) {
            S.sys_available = 0;
            snprintf(S.sys_reason, sizeof S.sys_reason, "SYS (what Windows plays) is off: this PortAudio has no WASAPI loopback device");
            fprintf(stderr, "audio: %s. MIC and OFF work; the SYS choice is left out of the MIC button\n", S.sys_reason);
        }
    }
    fprintf(stderr, "audio: output chosen: %s%s%s%s, input: %s%s%s, %u Hz, engine block %u, card buffer %s%s%s\n", cfg.output[0] ? "'" : "", cfg.output[0] ? cfg.output : "the Windows default device",
            cfg.output[0] ? "'" : "", cfg.out_first > 1 ? " (outputs from the channel shown below)" : "", cfg.input[0] ? "'" : "", cfg.input[0] ? cfg.input : "none", cfg.input[0] ? "'" : "", cfg.rate,
            cfg.period, cfg.buffer ? "" : "auto", cfg.exclusive ? ", exclusive" : "", cfg.force_null ? " (null audio forced)" : "");
    if (cfg.out_first > 1 || cfg.in_l != 1 || cfg.in_r != 2) {
        fprintf(stderr, "audio: channels: output pair starts at %d, input left %d right %d\n", cfg.out_first, cfg.in_l, cfg.in_r);
    }
    int use_card = !cfg.force_null && be != NULL;
    char err[256] = "";
    CUR = cfg;
    if (use_card) {
        vaud_opened res;
        vaud_error e = open_chain(be, &cfg, 1, &res, S.note, sizeof S.note, err, sizeof err);
        if (e == VAUD_OK) {
            S.rate = res.rate ? res.rate : cfg.rate;
            S.frames = cfg.period;
            verdandi_jack_null_configure(S.rate, S.frames);
            if (activate(&res, &cfg, err, sizeof err) == 0) {
                log_device(&res, &cfg);
                if (res.in_note[0]) {
                    note_add(S.note, sizeof S.note, "%s%s", S.note[0] ? ". " : "", res.in_note);
                }
            } else {
                e = VAUD_FAILED;
            }
        }
        if (S.mode != VAUD_MODE_DEVICE) {
            note_add(S.note, sizeof S.note, "no sound: audio device %s%.60s%s %s. null audio is used", cfg.output[0] ? "'" : "(default)", shown(cfg.output), cfg.output[0] ? "'" : "", error_words(e));
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
    fprintf(stderr, "audio: input is OFF at the start (nothing reaches norns until MIC or SYS is chosen)\n");
    if (bridge_name && *bridge_name) {
        bridge_up = verdandi_bridge_host_start(bridge_name, S.rate, S.frames) == 0;
    }
    if (st_out) {
        *st_out = S;
    }
}

const vaud_config *vaud_current_config(void) { return &CUR; }

int vaud_apply(const vaud_config *want, char *msg, size_t n) {
    msg[0] = 0;
    if (!BE || S.mode == VAUD_MODE_NONE || S.mode == VAUD_MODE_NULL) {
        snprintf(msg, n, "audio is off (null audio was chosen)");
        return 1;
    }
    vaud_config cfg = *want, old = CUR;
    cfg.rate = S.rate; /* the engine's rate and block stay: scsynth and crone run on */
    cfg.period = S.frames;
    cfg.force_null = 0;
    cfg.notes[0] = 0;
    vaud_config_check(&cfg);
    vaud_input_set(0, 0); /* a new device: the input is OFF again (nothing reaches norns by surprise) */
    S.input = VAUD_IN_OFF;
    S.sys_note[0] = 0;
    atomic_store(&mic_ring.active, 0);
    if (S.mode == VAUD_MODE_DEVICE) {
        BE->close(); /* the callback thread is gone when this returns */
    }
    verdandi_jack_null_external_clock(0); /* the engine goes on, on its own clock, while the stream is reopened */
    S.mode = VAUD_MODE_FALLBACK;
    char note[480] = "", err[256] = "", why[256] = "";
    vaud_opened res;
    vaud_error e = open_chain(BE, &cfg, 0, &res, note, sizeof note, err, sizeof err);
    if (e == VAUD_OK && res.rate && res.rate != S.rate) {
        BE->close();
        snprintf(why, sizeof why, "'%.60s' runs at %u Hz and norns at %u Hz (set rate= in audio.conf and restart)", res.device_name, res.rate, S.rate);
        e = VAUD_BAD_RATE;
    } else if (e != VAUD_OK) {
        snprintf(why, sizeof why, "'%.60s' %s", cfg.output[0] ? shown(cfg.output) : "the default device", error_words(e));
    }
    if (e == VAUD_OK && activate(&res, &cfg, err, sizeof err) == 0) {
        S.note[0] = 0;
        note_add(S.note, sizeof S.note, "%s", note);
        if (res.in_note[0]) {
            note_add(S.note, sizeof S.note, "%s%s", S.note[0] ? ". " : "", res.in_note);
        }
        log_device(&res, &cfg);
        snprintf(msg, n, "%s", S.note);
        return 0;
    }
    fprintf(stderr, "audio: the new setting could not be used: %s (%s); back to the old one\n", why, err);
    note[0] = 0;
    vaud_error e2 = open_chain(BE, &old, 0, &res, note, sizeof note, err, sizeof err);
    if (e2 == VAUD_OK && res.rate && res.rate != S.rate) {
        BE->close();
        e2 = VAUD_BAD_RATE;
    }
    if (e2 == VAUD_OK && activate(&res, &old, err, sizeof err) == 0) {
        S.note[0] = 0;
        log_device(&res, &old);
        snprintf(msg, n, "%s: back to %.60s", why, res.device_name);
        return 1;
    }
    S.mode = VAUD_MODE_FALLBACK;
    snprintf(S.note, sizeof S.note, "no sound: %s, and the old device cannot be opened either. null audio is used", why);
    fprintf(stderr, "audio: %s\n", S.note);
    snprintf(msg, n, "%s", S.note);
    return 2;
}

int vaud_input_set(int mic_on, int sys_on) {
    if (sys_on && !S.sys_available) {
        snprintf(S.sys_note, sizeof S.sys_note, "%s", S.sys_reason);
        return 1;
    }
    if (sys_on) {
        if (!sys_open) {
            char name[128] = "", err[200] = "";
            if (!BE || !BE->open_sys) {
                snprintf(S.sys_note, sizeof S.sys_note, "SYS (the system's sound) is not available here");
                return 1;
            }
            ring_reset(&sys_ring);
            atomic_store(&sys_ring.active, 1);
            if (BE->open_sys(S.rate, S.frames, name, sizeof name, err, sizeof err) != 0) {
                atomic_store(&sys_ring.active, 0);
                snprintf(S.sys_note, sizeof S.sys_note, "SYS: %.150s", err[0] ? err : "no loopback device (WASAPI loopback of the default output)");
                fprintf(stderr, "audio: %s\n", S.sys_note);
                return 1;
            }
            sys_open = 1;
            S.sys_note[0] = 0;
            fprintf(stderr, "audio: SYS: listening to what Windows plays ('%s', loopback)\n", name);
        }
        S.input = VAUD_IN_SYS;
        atomic_store(&in_mode, VAUD_IN_SYS);
        return 0;
    }
    if (sys_open && BE && BE->close_sys) {
        atomic_store(&sys_ring.active, 0);
        BE->close_sys();
        sys_open = 0;
    }
    if (mic_on) {
        if (S.mode != VAUD_MODE_DEVICE || !S.opened.in_active) {
            if (S.mode == VAUD_MODE_DEVICE && CUR.input[0]) {
                char why[100] = "";
                if (S.opened.in_note[0]) {
                    snprintf(why, sizeof why, " (%.80s)", S.opened.in_note);
                }
                snprintf(S.sys_note, sizeof S.sys_note, "MIC: '%.40s' did not open%s. Choose it again on SYSTEM > AUDIO > INPUT, or close the program that uses it", shown(CUR.input), why);
            } else if (S.mode != VAUD_MODE_DEVICE) {
                snprintf(S.sys_note, sizeof S.sys_note, "MIC: there is no sound card running (see SYSTEM > AUDIO)");
            } else {
                snprintf(S.sys_note, sizeof S.sys_note, "MIC: no input chosen. Pick one on SYSTEM > AUDIO > INPUT");
            }
            return 1;
        }
        S.sys_note[0] = 0;
        S.input = VAUD_IN_MIC;
        atomic_store(&in_mode, VAUD_IN_MIC);
        return 0;
    }
    S.input = VAUD_IN_OFF;
    atomic_store(&in_mode, VAUD_IN_OFF);
    return 0;
}

void vaud_stop(void) {
    if (BE && sys_open && BE->close_sys) {
        atomic_store(&sys_ring.active, 0);
        BE->close_sys();
        sys_open = 0;
    }
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
