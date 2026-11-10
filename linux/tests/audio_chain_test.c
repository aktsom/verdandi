/*
 * audio_chain_test.c (M2): the whole Windows audio chain with a FAKE sound card, on Linux (and under Wine): the card's callback -> jack_null (external clock) -> a stand-in for crone -> the bridge host
 * -> a stand-in for scsynth's bridge driver (a thread that uses verdandi_bridge.h as the patch does) -> back into the stand-in for crone -> the card's output. Also: what is said and done when the
 * device is missing, busy or does not take the rate, the audio.conf values, the device list text. One scenario per run (jack_null is process-global): audio_chain_test <scenario>.
 */
#define _GNU_SOURCE 1
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <jack/jack.h>

#include "audio/audio_device.h"
#include "audio/exit_win.h"
#include "audio/verdandi_bridge.h"

extern unsigned verdandi_jack_null_ticks(void);

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL "); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* ---- the fake card ---- */
static pthread_t card_thread;
static atomic_int card_run;
static vaud_callback card_cb;
static unsigned card_frames, card_rate;
static float *rec_l, *rec_r; /* what the card played: recorded */
static size_t rec_n, rec_cap;
static atomic_int card_blocks;
static int dev_mode; /* 0 all fine, 1 "Busy" is busy, 2 only 48000 */
static int crone_delay_ms, crone_preconnect; /* crone starts late (the window and crone come a while after the bridge); something else already made the connections */

static void sleep_ms_f(double ms) {
    struct timespec ts = {(time_t)(ms / 1000), (long)(fmod(ms, 1000.0) * 1e6)};
    nanosleep(&ts, NULL);
}

static void *card_loop(void *a) {
    (void)a;
    float *buf = calloc(card_frames * 2, sizeof(float));
    double period_ms = 1000.0 * card_frames / card_rate;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long n = 0;
    while (atomic_load(&card_run)) {
        n++;
        double target = n * period_ms;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double el = (now.tv_sec - t0.tv_sec) * 1000.0 + (now.tv_nsec - t0.tv_nsec) / 1e6;
        if (target > el) sleep_ms_f(target - el);
        card_cb(buf, card_frames, NULL);
        if (rec_n + card_frames <= rec_cap) {
            for (unsigned i = 0; i < card_frames; i++) {
                rec_l[rec_n + i] = buf[2 * i];
                rec_r[rec_n + i] = buf[2 * i + 1];
            }
            rec_n += card_frames;
        }
        atomic_fetch_add(&card_blocks, 1);
    }
    free(buf);
    return NULL;
}

static int fk_list(vaud_device *o, int max) {
    (void)max;
    memset(o, 0, 2 * sizeof *o);
    strcpy(o[0].uid, "wasapi:Fake Speakers"); strcpy(o[0].name, "Fake Speakers"); o[0].is_default = 1; o[0].out_channels = 2; o[0].default_rate = 48000;
    strcpy(o[1].uid, "wasapi:Busy Headset"); strcpy(o[1].name, "Busy Headset"); o[1].out_channels = 2; o[1].default_rate = 44100;
    return 2;
}
static vaud_error fk_open(const char *uid, unsigned rate, unsigned frames, vaud_callback cb, void *u, vaud_opened *res, char *err, size_t en) {
    (void)u;
    if (uid[0] && strcmp(uid, "wasapi:Fake Speakers") != 0 && strcmp(uid, "wasapi:Busy Headset") != 0) {
        snprintf(err, en, "no output device with this name");
        return VAUD_NOT_FOUND;
    }
    if (!strcmp(uid, "wasapi:Busy Headset")) {
        snprintf(err, en, "device unavailable");
        return VAUD_BUSY;
    }
    if (dev_mode == 2 && rate != 48000) {
        snprintf(err, en, "invalid sample rate");
        res->rate = 48000;
        return VAUD_BAD_RATE;
    }
    card_cb = cb; card_frames = frames; card_rate = rate;
    strcpy(res->device_name, "Fake Speakers"); strcpy(res->host_api, "Fake shared");
    res->rate = rate; res->frames = frames; res->latency_ms = 12.5;
    return VAUD_OK;
}
static int fk_start(char *err, size_t en) {
    (void)err, (void)en;
    atomic_store(&card_run, 1);
    pthread_create(&card_thread, NULL, card_loop, NULL);
    return 0;
}
static void fk_close(void) {
    if (atomic_exchange(&card_run, 0)) pthread_join(card_thread, NULL);
}
static const vaud_backend FAKE = {"fake", fk_list, fk_open, fk_start, fk_close};

/* ---- crone stand-in: sends 0.2 to the engines, plays what comes back ---- */
static jack_client_t *crone;
static jack_port_t *c_in5, *c_in6, *c_out5, *c_out6, *c_out1, *c_out2;
static int crone_process(jack_nframes_t n, void *a) {
    (void)a;
    float *i5 = jack_port_get_buffer(c_in5, n), *i6 = jack_port_get_buffer(c_in6, n);
    float *o5 = jack_port_get_buffer(c_out5, n), *o6 = jack_port_get_buffer(c_out6, n);
    float *o1 = jack_port_get_buffer(c_out1, n), *o2 = jack_port_get_buffer(c_out2, n);
    for (jack_nframes_t i = 0; i < n; i++) {
        o5[i] = o6[i] = 0.2f;
        o1[i] = i5[i];
        o2[i] = i6[i];
    }
    return 0;
}
static void crone_start(void) {
    jack_status_t st;
    crone = jack_client_open("crone", JackNoStartServer, &st);
    c_in5 = jack_port_register(crone, "input_5", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    c_in6 = jack_port_register(crone, "input_6", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    c_out5 = jack_port_register(crone, "output_5", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    c_out6 = jack_port_register(crone, "output_6", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    c_out1 = jack_port_register(crone, "output_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    c_out2 = jack_port_register(crone, "output_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(crone, crone_process, NULL);
    jack_connect(crone, "crone:output_1", "system:playback_1");
    jack_connect(crone, "crone:output_2", "system:playback_2");
    jack_activate(crone);
}

/* ---- scsynth stand-in: the driver of the patch, in a thread: 440 Hz at 0.5 plus what crone sent ---- */
static pthread_t sc_thread;
static atomic_int sc_run;
static const char *bridge_name;
static atomic_int sc_blocks;
static int sc_ignore_close; /* the exit scenario: the stand-in goes on until the process ends (Wine takes the exit status of whichever thread ends last; Windows takes the one of TerminateProcess) */
static void *sc_loop(void *a) {
    (void)a;
    vb_t g;
    if (vb_guest_open(&g, bridge_name, 3000) != 0) {
        printf("FAIL the guest could not open the bridge\n");
        fails++;
        return NULL;
    }
    unsigned n = g.sh->frames;
    double rate = g.sh->rate, ph = 0;
    float *il = malloc(n * sizeof(float)), *ir = malloc(n * sizeof(float)), *ol = malloc(n * sizeof(float)), *or_ = malloc(n * sizeof(float));
    vb_guest_attach(&g);
    while (atomic_load(&sc_run)) {
        int r = vb_guest_wait(&g, 50, il, ir);
        if (r < 0) {
            if (sc_ignore_close) { sleep_ms_f(5); continue; }
            break;
        }
        if (r == 0) continue;
        for (unsigned i = 0; i < n; i++, ph += 440.0 / rate) {
            float s = 0.5f * sinf((float)(2 * M_PI * ph));
            ol[i] = s + il[i];
            or_[i] = s + ir[i];
        }
        vb_guest_push(&g, ol, or_);
        atomic_fetch_add(&sc_blocks, 1);
    }
    vb_guest_detach(&g);
    vb_close(&g);
    free(il); free(ir); free(ol); free(or_);
    return NULL;
}

static void analyse(const char *what, unsigned rate, double *mean_out, double *peak_out, double *freq_out) {
    size_t from = rec_n / 2; /* after the start-up */
    double sum = 0, peak = 0;
    for (size_t i = from; i < rec_n; i++) sum += rec_l[i];
    double mean = sum / (double)(rec_n - from);
    int cross = 0;
    for (size_t i = from + 1; i < rec_n; i++) {
        double a = rec_l[i - 1] - mean, b = rec_l[i] - mean;
        if (fabs(b) > peak) peak = fabs(b);
        if ((a < 0) != (b < 0)) cross++;
    }
    double secs = (double)(rec_n - from) / rate;
    *mean_out = mean; *peak_out = peak; *freq_out = cross / 2.0 / secs;
    (void)what;
}

static void run_chain(const char *scenario, int with_guest, const char *output, unsigned rate, unsigned period, int expect_mode) {
    char name[64];
    snprintf(name, sizeof name, "AudioChainTest-%d", (int)getpid());
    bridge_name = name;
    vaud_config cfg;
    memset(&cfg, 0, sizeof cfg);
    snprintf(cfg.output, sizeof cfg.output, "%s", output);
    cfg.rate = rate; cfg.period = period;
    cfg.force_null = getenv("VERDANDI_AUDIO") != NULL;
    rec_cap = 48000 * 10; rec_l = calloc(rec_cap, sizeof(float)); rec_r = calloc(rec_cap, sizeof(float));
    vaud_state st;
    vaud_start(&FAKE, &cfg, name, &st);
    CHECK((int)st.mode == expect_mode, "%s: mode %d, expected %d (note: %s)", scenario, st.mode, expect_mode, st.note);
    if (crone_delay_ms) sleep_ms_f(crone_delay_ms);
    crone_start();
    if (crone_preconnect) {
        jack_connect(crone, "crone:output_5", "SuperCollider:in_1"); jack_connect(crone, "crone:output_6", "SuperCollider:in_2");
        jack_connect(crone, "SuperCollider:out_1", "crone:input_5"); jack_connect(crone, "SuperCollider:out_2", "crone:input_6");
    }
    if (with_guest) {
        atomic_store(&sc_run, 1);
        pthread_create(&sc_thread, NULL, sc_loop, NULL);
    }
    unsigned t0 = verdandi_jack_null_ticks();
    double run_ms = 3400 + 2.0 * crone_delay_ms; /* (the connection thread looks once per second) */
    sleep_ms_f(run_ms);
    unsigned ticks = verdandi_jack_null_ticks() - t0;
    double expected = run_ms / 1000.0 * st.rate / st.frames;
    CHECK(ticks > expected * 0.8 && ticks < expected * 1.2, "%s: %u blocks in 2.2 s, expected about %.0f", scenario, ticks, expected);
    unsigned long long to_sc, from_sc, under, drops; int att;
    vaud_bridge_stats(&to_sc, &from_sc, &under, &drops, &att);
    if (expect_mode == VAUD_MODE_DEVICE) {
        CHECK(atomic_load(&card_blocks) > 0, "%s: the card callback ran", scenario);
    }
    double mean, peak, freq;
    mean = peak = freq = 0;
    if (expect_mode == VAUD_MODE_DEVICE) analyse(scenario, st.rate, &mean, &peak, &freq);
    if (with_guest && expect_mode != VAUD_MODE_DEVICE) {
        /* null audio: nothing plays, but scsynth is paced and fed exactly the same */
        CHECK(att == 1, "%s: scsynth is attached", scenario);
        CHECK(from_sc + 4 >= to_sc && to_sc > expected * 0.7, "%s: blocks to scsynth %llu / from %llu", scenario, to_sc, from_sc);
        CHECK(under <= 3 && drops <= 3, "%s: underruns %llu drops %llu", scenario, under, drops);
    } else if (with_guest) {
        CHECK(att == 1, "%s: scsynth is attached", scenario);
        CHECK(fabs(mean - 0.2) < 0.01, "%s: what crone sent to the engine (0.2) came back through scsynth to the card: mean %.3f", scenario, mean);
        CHECK(fabs(peak - 0.5) < 0.03, "%s: the engine's sine (0.5) reached the card: peak %.3f", scenario, peak);
        CHECK(fabs(freq - 440.0) < 12.0, "%s: 440 Hz: %.1f", scenario, freq);
        unsigned long long lim = st.frames <= 128 ? 25 : 3; /* small blocks on a busy machine miss a deadline now and then */
        CHECK(under <= lim, "%s: bridge underruns %llu", scenario, under);
        CHECK(drops <= lim, "%s: bridge drops %llu", scenario, drops);
        CHECK(from_sc + 4 >= to_sc && to_sc > expected * 0.7, "%s: blocks to scsynth %llu / from %llu", scenario, to_sc, from_sc);
    } else {
        CHECK(att == 0, "%s: no scsynth is attached", scenario);
        CHECK(fabs(mean) < 0.001 && peak < 0.001, "%s: without scsynth the card gets silence from the engine path (mean %.4f peak %.4f), and nothing hung", scenario, mean, peak);
        CHECK(to_sc == 0, "%s: nothing is queued for a scsynth that is not there (%llu)", scenario, to_sc);
    }
    printf("%s: mode %d rate %u frames %u note '%s' | blocks to/from scsynth %llu/%llu underruns %llu drops %llu | mean %.3f peak %.3f freq %.1f\n", scenario, st.mode, st.rate, st.frames, st.note,
           to_sc, from_sc, under, drops, mean, peak, freq);
    if (with_guest) {
        atomic_store(&sc_run, 0);
        pthread_join(sc_thread, NULL);
    }
    if (!strcmp(scenario, "busy")) {
        CHECK(strstr(st.note, "busy") != NULL && strstr(st.note, "null audio") != NULL, "busy: the note says busy and null audio: '%s'", st.note);
    } else if (!strcmp(scenario, "notfound")) {
        CHECK(strstr(st.note, "not found") != NULL && strstr(st.note, "default") != NULL, "notfound: the note says not found, default device: '%s'", st.note);
    } else if (!strcmp(scenario, "badrate")) {
        CHECK(st.rate == 48000, "badrate: follows the device's 48000 (%u)", st.rate);
    }
    vaud_stop();
}

static void scenario_config(void) {
    vaud_config c;
    memset(&c, 0, sizeof c);
    c.rate = 12345; c.period = 100;
    vaud_config_check(&c);
    CHECK(c.rate == 48000 && c.period == 512, "defaults replace bad values: %u %u", c.rate, c.period);
    CHECK(strstr(c.notes, "12345") && strstr(c.notes, "100"), "and the notes say so: %s", c.notes);
    memset(&c, 0, sizeof c);
    vaud_config_check(&c);
    CHECK(c.rate == 48000 && c.period == 512 && c.notes[0] == 0, "no values: the defaults, no note");
#ifdef _WIN32
    return; /* (the rest needs mkdtemp and setenv: the Linux run) */
#else
    char dir[] = "/tmp/vaudXXXXXX";
    if (!mkdtemp(dir)) { printf("FAIL mkdtemp\n"); fails++; return; }
    char path[200];
    snprintf(path, sizeof path, "%s/audio.conf", dir);
    FILE *f = fopen(path, "w");
    fputs("in_ports=foo\noutput=wasapi:Fake Speakers\nrate=44100\nperiod=256\n", f);
    fclose(f);
    unsetenv("VERDANDI_AUDIO"); unsetenv("VERDANDI_AUDIO_OUTPUT"); unsetenv("VERDANDI_AUDIO_RATE"); unsetenv("VERDANDI_AUDIO_PERIOD");
    vaud_config_load(&c, dir);
    CHECK(!strcmp(c.output, "wasapi:Fake Speakers") && c.rate == 44100 && c.period == 256 && !c.force_null, "audio.conf is read: %s %u %u", c.output, c.rate, c.period);
    setenv("VERDANDI_AUDIO", "null", 1);
    vaud_config_load(&c, dir);
    CHECK(c.force_null, "VERDANDI_AUDIO=null forces null audio");
    unsetenv("VERDANDI_AUDIO");
    f = fopen(path, "w"); fputs("output=default\nrate=48000\n", f); fclose(f);
    vaud_config_load(&c, dir);
    CHECK(c.output[0] == 0, "output=default is the default device (%s)", c.output);
    f = fopen(path, "w"); fputs("output=\nrate=48000\n", f); fclose(f);
    vaud_config_load(&c, dir);
    CHECK(c.output[0] == 0, "an empty output= is the default device");
    f = fopen(path, "w"); fputs("rate=48000\r\noutput=wasapi:Fake Speakers\r\n", f); fclose(f);
    vaud_config_load(&c, dir);
    CHECK(!strcmp(c.output, "wasapi:Fake Speakers"), "a file with Windows line ends is read (%s)", c.output);
    vaud_config_load(&c, "/nonexistent");
    CHECK(c.output[0] == 0 && c.rate == 48000 && c.period == 512, "no audio.conf: the defaults");
    char text[1024];
    int n = vaud_list_text(&FAKE, text, sizeof text);
    CHECK(n == 2 && strstr(text, "wasapi:Fake Speakers\tFake Speakers (default)\t0\t2\n") && strstr(text, "wasapi:Busy Headset\tBusy Headset\t0\t2\n"), "device list text: %s", text);
    unlink(path); rmdir(dir);
#endif
}

int main(int argc, char **argv) {
    const char *sc = argc > 1 ? argv[1] : "device";
    if (!strcmp(sc, "config")) scenario_config();
    else if (!strcmp(sc, "device")) run_chain(sc, 1, "wasapi:Fake Speakers", 48000, 512, VAUD_MODE_DEVICE);
    else if (!strcmp(sc, "small")) run_chain(sc, 1, "", 48000, 128, VAUD_MODE_DEVICE);
    else if (!strcmp(sc, "noguest")) run_chain(sc, 0, "", 48000, 512, VAUD_MODE_DEVICE);
    else if (!strcmp(sc, "busy")) run_chain(sc, 1, "wasapi:Busy Headset", 48000, 512, VAUD_MODE_FALLBACK);
    else if (!strcmp(sc, "notfound")) run_chain(sc, 1, "wasapi:Gone Speakers", 48000, 512, VAUD_MODE_DEVICE);
    else if (!strcmp(sc, "badrate")) { dev_mode = 2; run_chain(sc, 1, "", 44100, 512, VAUD_MODE_DEVICE); }
    else if (!strcmp(sc, "latecrone")) { crone_delay_ms = 1500; run_chain(sc, 1, "", 48000, 512, VAUD_MODE_DEVICE); }
    else if (!strcmp(sc, "preconnected")) { crone_preconnect = 1; run_chain(sc, 1, "", 48000, 512, VAUD_MODE_DEVICE); }
    else if (!strcmp(sc, "exit")) {
        /* the way norns.exe ends (restart = 42): with the card callback, crone, the bridge and scsynth running. the process must end with the code, at once, without a crash */
        char name[64];
        snprintf(name, sizeof name, "AudioChainExit-%d", (int)getpid());
        bridge_name = name;
        vaud_config cfg;
        memset(&cfg, 0, sizeof cfg);
        cfg.rate = 48000; cfg.period = 256;
        rec_cap = 48000; rec_l = calloc(rec_cap, sizeof(float)); rec_r = calloc(rec_cap, sizeof(float));
        vaud_state st;
        vaud_start(&FAKE, &cfg, name, &st);
        crone_start();
        sc_ignore_close = 1;
        atomic_store(&sc_run, 1);
        pthread_create(&sc_thread, NULL, sc_loop, NULL);
        sleep_ms_f(700 + (getpid() % 7) * 130); /* another moment of the blocks every time */
        verdandi_win_exit(42);
        return 99; /* never */
    }
    else if (!strcmp(sc, "null")) {
#ifndef _WIN32
        setenv("VERDANDI_AUDIO", "null", 1);
#endif
        vaud_config c; vaud_config_load(&c, NULL); run_chain(sc, 1, "", c.rate, c.period, VAUD_MODE_NULL); }
    else { printf("unknown scenario\n"); return 2; }
    if (!fails) printf("audio_chain_test %s: passed\n", sc);
    return fails ? 1 : 0;
}
