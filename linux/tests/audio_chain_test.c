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

static vaud_open_req last_req;
static int fake_sep;           /* the input arrives in its own stream: the card thread pushes it */
static int fake_in_ch, fake_in_l, fake_in_r; /* 0 based */
static int fake_duplex, loop_back; /* loop_back: the input is the output delayed (a cable from the output to the input) */
static int fake_sys_open;
#define LOOPN 65536
static float loop_buf[LOOPN * 2];
static unsigned long loop_pos;
static unsigned loop_delay = 1024; /* frames: the fake cable's delay */
static void *card_loop(void *a) {
    (void)a;
    float *buf = calloc(card_frames * 2, sizeof(float));
    float *inbuf = calloc((size_t)card_frames * 8, sizeof(float)), *pair = calloc(card_frames * 2, sizeof(float)), *sysb = calloc(card_frames * 2, sizeof(float));
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
        /* the input: channel c carries 0.1 * c, or the output of loop_delay frames ago (a cable) */
        const float *in = NULL;
        if (fake_duplex || fake_sep) {
            for (unsigned i = 0; i < card_frames; i++) {
                for (int c = 0; c < fake_in_ch; c++) {
                    inbuf[(size_t)i * fake_in_ch + c] = 0.1f * (c + 1);
                }
                if (loop_back) {
                    unsigned long p = (loop_pos + LOOPN - loop_delay + i) % LOOPN;
                    for (int c = 0; c < fake_in_ch; c++) {
                        inbuf[(size_t)i * fake_in_ch + c] = loop_buf[2 * p + (c & 1)];
                    }
                }
            }
            vaud_pick_pair(inbuf, card_frames, fake_in_ch, fake_in_l, fake_in_r, pair); /* the same code as the PortAudio backend's mapping */
            if (fake_duplex) in = pair; else vaud_push_mic(pair, card_frames);
        }
        if (fake_sys_open) {
            for (unsigned i = 0; i < card_frames; i++) { sysb[2 * i] = 0.6f; sysb[2 * i + 1] = 0.7f; }
            vaud_push_sys(sysb, card_frames);
        }
        card_cb(in, buf, card_frames, NULL);
        if (rec_n + card_frames <= rec_cap) {
            for (unsigned i = 0; i < card_frames; i++) {
                rec_l[rec_n + i] = buf[2 * i];
                rec_r[rec_n + i] = buf[2 * i + 1];
            }
            rec_n += card_frames;
        }
        for (unsigned i = 0; i < card_frames; i++) {
            loop_buf[2 * ((loop_pos + i) % LOOPN)] = buf[2 * i];
            loop_buf[2 * ((loop_pos + i) % LOOPN) + 1] = buf[2 * i + 1];
        }
        loop_pos = (loop_pos + card_frames) % LOOPN;
        atomic_fetch_add(&card_blocks, 1);
    }
    free(buf); free(inbuf); free(pair); free(sysb);
    return NULL;
}

/* the fake devices: a plain output, a WASAPI interface with 4 inputs (duplex), a microphone (an input on another device: its own stream), an ASIO driver with 8 in / 8 out and its WASAPI twin, a loopback */
static int asio_busy, no_loopback, no_mic_open; /* scenario switches */
static int fk_list(vaud_device *o, int max) {
    (void)max;
    memset(o, 0, 8 * sizeof *o);
    int n = 0;
#define DEV(u, nm, api_, def, ins, outs, lo, li, lb) do { strcpy(o[n].uid, u); strcpy(o[n].name, nm); strcpy(o[n].api, api_); o[n].is_default = def; o[n].in_channels = ins; o[n].out_channels = outs; \
    o[n].low_out_ms = lo; o[n].low_in_ms = li; o[n].loopback = lb; o[n].default_rate = 48000; n++; } while (0)
    DEV("wasapi:Fake Speakers", "Fake Speakers", "WASAPI", 1, 0, 2, 21, 0, 0);
    DEV("wasapi:Busy Headset", "Busy Headset", "WASAPI", 0, 0, 2, 21, 0, 0);
    DEV("wasapi:Fake Interface", "Fake Interface", "WASAPI", 0, 4, 2, 21, 12, 0);
    DEV("wasapi:Fake Mic", "Fake Mic", "WASAPI", 0, 2, 0, 0, 12, 0);
    DEV("wasapi:Fake ASIO", "Fake ASIO", "WASAPI", 0, 2, 2, 21, 12, 0);
    DEV("wasapi:Fake Speakers [Loopback]", "Fake Speakers [Loopback]", "WASAPI", 0, 2, 0, 0, 12, 1);
    DEV("asio:Fake ASIO", "Fake ASIO", "ASIO", 0, 8, 8, 6, 6, 0);
    return n;
}
/* what each input channel of the fake devices carries: channel c (1 based) is the constant 0.1 * c, so the mapping can be read from the numbers in crone */
static int dev_in_channels(const char *uid) {
    if (!strcmp(uid, "wasapi:Fake Interface")) return 4;
    if (!strcmp(uid, "asio:Fake ASIO")) return 8;
    return 2;
}
static vaud_error fk_open(const vaud_open_req *rq, vaud_callback cb, void *u, vaud_opened *res, char *err, size_t en) {
    (void)u;
    last_req = *rq;
    const char *uid = rq->out_uid;
    if (uid[0] && strcmp(uid, "wasapi:Fake Speakers") && strcmp(uid, "wasapi:Busy Headset") && strcmp(uid, "wasapi:Fake Interface") && strcmp(uid, "wasapi:Fake ASIO") && strcmp(uid, "asio:Fake ASIO")) {
        snprintf(err, en, "no output device with this name");
        return VAUD_NOT_FOUND;
    }
    if (!strcmp(uid, "wasapi:Busy Headset")) {
        snprintf(err, en, "device unavailable");
        return VAUD_BUSY;
    }
    if (!strcmp(uid, "asio:Fake ASIO") && asio_busy) {
        snprintf(err, en, "ASIO driver could not be started (another program has it)");
        return VAUD_BUSY;
    }
    if (dev_mode == 2 && rq->rate != 48000) {
        snprintf(err, en, "invalid sample rate");
        res->rate = 48000;
        return VAUD_BAD_RATE;
    }
    card_cb = cb; card_frames = rq->frames; card_rate = rq->rate;
    int is_asio = !strncmp(uid, "asio:", 5);
    strcpy(res->device_name, uid[0] ? uid + (is_asio ? 5 : 7) : "Fake Speakers");
    strcpy(res->host_api, is_asio ? "Fake ASIO" : "Fake shared");
    res->rate = rq->rate; res->frames = rq->frames; res->out_latency_ms = is_asio ? 6.5 : 12.5;
    fake_duplex = fake_sep = 0;
    if (rq->in_uid[0] && !no_mic_open) {
        int dup = !strcmp(rq->in_uid, uid) || (!uid[0] && !strcmp(rq->in_uid, "wasapi:Fake Speakers"));
        if (!dup && is_asio) {
            snprintf(res->in_note, sizeof res->in_note, "ASIO uses one device: the input is not on it, output only");
        } else {
            fake_in_ch = dev_in_channels(rq->in_uid);
            fake_in_l = rq->in_l - 1; fake_in_r = rq->in_r - 1;
            res->in_active = 1;
            res->in_latency_ms = 7.5;
            snprintf(res->in_name, sizeof res->in_name, "%s", rq->in_uid + (!strncmp(rq->in_uid, "asio:", 5) ? 5 : 7));
            if (dup) fake_duplex = 1; else { fake_sep = 1; res->in_separate = 1; }
        }
    }
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
static int fk_open_sys(unsigned rate, unsigned frames, char *name, size_t nn, char *err, size_t en) {
    (void)rate, (void)frames;
    if (no_loopback) {
        snprintf(err, en, "this Windows has no loopback device");
        return 1;
    }
    snprintf(name, nn, "Fake Speakers [Loopback]");
    fake_sys_open = 1;
    return 0;
}
static void fk_close_sys(void) { fake_sys_open = 0; }
static void fk_describe(char *o, size_t n) { snprintf(o, n, "Fake PortAudio; host APIs: Fake WASAPI, Fake ASIO"); }
static const vaud_backend FAKE = {"fake", fk_list, fk_open, fk_start, fk_close, fk_open_sys, fk_close_sys, fk_describe};

/* ---- crone stand-in: sends 0.2 to the engines, plays what comes back ---- */
static jack_client_t *crone;
static jack_port_t *c_in5, *c_in6, *c_out5, *c_out6, *c_out1, *c_out2, *c_adc1, *c_adc2;
static volatile double adc_sum_l, adc_sum_r; /* what arrives at crone's input_1/2 (the sound card's input, as the real crone's ADC) */
static volatile unsigned long adc_n;
static int crone_process(jack_nframes_t n, void *a) {
    (void)a;
    {
        float *a1 = jack_port_get_buffer(c_adc1, n), *a2 = jack_port_get_buffer(c_adc2, n);
        double sl = 0, sr = 0;
        for (jack_nframes_t i = 0; i < n; i++) { sl += a1[i]; sr += a2[i]; }
        adc_sum_l += sl; adc_sum_r += sr; adc_n += n;
    }
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
    c_adc1 = jack_port_register(crone, "input_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    c_adc2 = jack_port_register(crone, "input_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    jack_set_process_callback(crone, crone_process, NULL);
    jack_connect(crone, "crone:output_1", "system:playback_1");
    jack_connect(crone, "crone:output_2", "system:playback_2");
    jack_connect(crone, "system:capture_1", "crone:input_1");
    jack_connect(crone, "system:capture_2", "crone:input_2");
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
    CHECK(n == 7 && strstr(text, "wasapi:Fake Speakers\tFake Speakers (default)\t0\t2\tWASAPI\t21.0\t0.0\t0\n") && strstr(text, "asio:Fake ASIO\tFake ASIO\t8\t8\tASIO\t6.0\t6.0\t0\n") &&
              strstr(text, "wasapi:Fake Speakers [Loopback]\tFake Speakers [Loopback]\t2\t0\tWASAPI\t0.0\t12.0\t1\n"), "device list text (8 fields, host API, latencies, loopback): %s", text);
    f = fopen(path, "w");
    fputs("output=asio:Fake ASIO\ninput=asio:Fake ASIO\nrate=44100\nperiod=128\nout_first=3\nin_l=5\nin_r=6\n", f);
    fclose(f);
    vaud_config_load(&c, dir);
    CHECK(!strcmp(c.input, "asio:Fake ASIO") && c.out_first == 3 && c.in_l == 5 && c.in_r == 6 && c.period == 128, "the M3 keys are read: input out_first in_l in_r: %s %d %d %d", c.input, c.out_first, c.in_l, c.in_r);
    f = fopen(path, "w");
    fputs("out_first=0\nin_l=99\nin_r=-3\n", f);
    fclose(f);
    vaud_config_load(&c, dir);
    CHECK(c.out_first == 1 && c.in_l == 1 && c.in_r == 2 && c.notes[0], "bad channel numbers are replaced (1, 1, 2) with a note: %d %d %d '%s'", c.out_first, c.in_l, c.in_r, c.notes);
    memset(&c, 0, sizeof c);
    vaud_config_check(&c);
    CHECK(c.out_first == 1 && c.in_l == 1 && c.in_r == 2 && c.input[0] == 0, "defaults: outputs 1+2, inputs 1 and 2, no input device");
    /* the shared channel mapping */
    float x[3 * 4] = {1, 2, 3, 10, 20, 30, 100, 200, 300, 0, 0, 0}, d[6];
    vaud_pick_pair(x, 3, 4, 2, 3, d);
    CHECK(d[0] == 3 && d[1] == 10 && d[2] == 100 && d[3] == 200, "pick_pair picks channels 3 and 4 of 4 (%g %g %g %g)", d[0], d[1], d[2], d[3]);
    vaud_pick_pair(x, 3, 4, 1, 1, d);
    CHECK(d[0] == 2 && d[1] == 2 && d[2] == 30 && d[3] == 30, "pick_pair: a mono source (l == r) is on both sides");
    vaud_pick_pair(x, 3, 2, 0, 7, d);
    CHECK(d[1] == 0, "pick_pair: a channel that is not there is silence");
    unlink(path); rmdir(dir);
#endif
}

/* ---- M3: input, host APIs, fallbacks, measurement ---- */
static void adc_reset(void) { adc_sum_l = adc_sum_r = 0; adc_n = 0; }
static void adc_means(double *l, double *r) {
    sleep_ms_f(700);
    adc_reset();
    sleep_ms_f(900);
    unsigned long n = adc_n ? adc_n : 1;
    *l = adc_sum_l / n;
    *r = adc_sum_r / n;
}
static vaud_state start_card(const char *out, const char *in, int in_l, int in_r, int out_first, unsigned period) {
    vaud_config cfg;
    memset(&cfg, 0, sizeof cfg);
    snprintf(cfg.output, sizeof cfg.output, "%s", out);
    snprintf(cfg.input, sizeof cfg.input, "%s", in);
    cfg.rate = 48000; cfg.period = period; cfg.in_l = in_l; cfg.in_r = in_r; cfg.out_first = out_first;
    rec_cap = 48000 * 12; rec_l = calloc(rec_cap, sizeof(float)); rec_r = calloc(rec_cap, sizeof(float));
    vaud_state st;
    vaud_start(&FAKE, &cfg, NULL, &st);
    crone_start();
    return st;
}
#define NEAR(a, b) (fabs((a) - (b)) < 0.02)

static void scenario_input(const char *sc) {
    vaud_state st;
    double l, r;
    if (!strcmp(sc, "in_duplex") || !strcmp(sc, "in_mono") || !strcmp(sc, "in_separate") || !strcmp(sc, "in_asio")) {
        const char *out = "wasapi:Fake Interface", *in = out;
        int il = 3, ir = 4;
        if (!strcmp(sc, "in_mono")) { il = ir = 2; }
        if (!strcmp(sc, "in_separate")) { out = ""; in = "wasapi:Fake Mic"; il = 1; ir = 2; }
        if (!strcmp(sc, "in_asio")) { out = in = "asio:Fake ASIO"; il = 5; ir = 8; }
        st = start_card(out, in, il, ir, !strcmp(sc, "in_asio") ? 3 : 1, 512);
        CHECK(st.mode == VAUD_MODE_DEVICE && st.opened.in_active, "%s: the card and the input run (%s)", sc, st.note);
        CHECK(st.opened.in_separate == !strcmp(sc, "in_separate"), "%s: separate input stream: %d", sc, st.opened.in_separate);
        CHECK(last_req.in_l == il && last_req.in_r == ir, "%s: the backend was asked for input channels %d and %d (%d/%d)", sc, il, ir, last_req.in_l, last_req.in_r);
        CHECK(last_req.out_first == (!strcmp(sc, "in_asio") ? 3 : 1), "%s: the output pair starts at %d", sc, last_req.out_first);
        CHECK(st.input == VAUD_IN_OFF, "%s: the input is OFF at the start (no feedback)", sc);
        adc_means(&l, &r);
        CHECK(fabs(l) < 1e-4 && fabs(r) < 1e-4, "%s: OFF is silent: %.4f %.4f", sc, l, r);
        CHECK(vaud_get_state()->in_peak_db <= -100, "%s: no level while OFF (%.1f dB)", sc, vaud_get_state()->in_peak_db);
        CHECK(vaud_input_set(1, 0) == 0 && vaud_get_state()->input == VAUD_IN_MIC, "%s: MIC works", sc);
        adc_means(&l, &r);
        CHECK(NEAR(l, 0.1 * il) && NEAR(r, 0.1 * ir), "%s: MIC: channel %d is left (%.3f), channel %d is right (%.3f)", sc, il, l, ir, r);
        double pk = vaud_get_state()->in_peak_db, want = 20 * log10(0.1 * (il > ir ? il : ir));
        CHECK(fabs(pk - want) < 1.5, "%s: the input level is the peak: %.1f dB, expected %.1f", sc, pk, want);
        CHECK(vaud_input_set(0, 0) == 0 && vaud_get_state()->input == VAUD_IN_OFF, "%s: OFF again", sc);
        adc_means(&l, &r);
        CHECK(fabs(l) < 1e-4 && fabs(r) < 1e-4, "%s: OFF is silent again", sc);
        CHECK(vaud_get_state()->in_peak_db < pk - 10, "%s: the level falls when the input is off (%.1f dB)", sc, vaud_get_state()->in_peak_db);
        printf("%s: l %.3f r %.3f peak %.1f dB\n", sc, l, r, pk);
    } else if (!strcmp(sc, "in_missing")) {
        no_mic_open = 1;
        st = start_card("", "wasapi:Gone Mic", 1, 2, 1, 512);
        CHECK(st.mode == VAUD_MODE_DEVICE && !st.opened.in_active, "in_missing: the output runs, the input does not");
        CHECK(vaud_input_set(1, 0) == 1 && vaud_get_state()->input == VAUD_IN_OFF, "in_missing: MIC cannot be switched on, it stays OFF");
        CHECK(strstr(vaud_get_state()->sys_note, "MIC") && strstr(vaud_get_state()->sys_note, "INPUT"), "in_missing: the note says what to do: '%s'", vaud_get_state()->sys_note);
    } else if (!strcmp(sc, "in_asio_other")) {
        st = start_card("asio:Fake ASIO", "wasapi:Fake Mic", 1, 2, 1, 512);
        CHECK(st.mode == VAUD_MODE_DEVICE && !st.opened.in_active, "in_asio_other: ASIO output runs, an input on another device does not");
        CHECK(strstr(st.note, "ASIO uses one device"), "in_asio_other: the note says why: '%s'", st.note);
    } else if (!strcmp(sc, "sys") || !strcmp(sc, "sys_none")) {
        no_loopback = !strcmp(sc, "sys_none");
        st = start_card("", "", 1, 2, 1, 512);
        int rc = vaud_input_set(1, 1); /* SYS has priority over MIC */
        if (no_loopback) {
            CHECK(rc == 1 && vaud_get_state()->input == VAUD_IN_OFF, "sys_none: SYS without a loopback stays OFF");
            CHECK(strstr(vaud_get_state()->sys_note, "loopback"), "sys_none: the note says why: '%s'", vaud_get_state()->sys_note);
        } else {
            CHECK(rc == 0 && vaud_get_state()->input == VAUD_IN_SYS && fake_sys_open, "sys: SYS opens the loopback");
            adc_means(&l, &r);
            CHECK(NEAR(l, 0.6) && NEAR(r, 0.7), "sys: what the system plays reaches crone's input: %.3f %.3f", l, r);
            vaud_input_set(0, 0);
            CHECK(!fake_sys_open && vaud_get_state()->input == VAUD_IN_OFF, "sys: OFF closes the loopback");
            adc_means(&l, &r);
            CHECK(fabs(l) < 1e-4 && fabs(r) < 1e-4, "sys: OFF is silent again");
        }
    } else if (!strcmp(sc, "measure") || !strcmp(sc, "measure_none")) {
        loop_back = !strcmp(sc, "measure");
        /* the fake interface's inputs 1 and 2 carry 0.1 and 0.2 (below the click threshold) unless the cable is on */
        st = start_card("wasapi:Fake Interface", "wasapi:Fake Interface", 1, 2, 1, 512);
        sleep_ms_f(500);
        vaud_measure_start();
        sleep_ms_f(loop_back ? 1200 : 2800);
        double m = vaud_get_state()->measured_ms;
        if (loop_back) {
            CHECK(m > 20.0 && m < 23.0, "measure: a cable with a delay of 1024 frames (21.3 ms) is measured as %.1f ms", m);
        } else {
            CHECK(m == -2, "measure_none: no click heard: -2 (%.1f)", m);
        }
        printf("%s: measured %.2f ms\n", sc, m);
    } else if (!strcmp(sc, "asio_ok") || !strcmp(sc, "asio_busy")) {
        asio_busy = !strcmp(sc, "asio_busy");
        st = start_card("asio:Fake ASIO", "", 1, 2, 3, 128);
        CHECK(st.mode == VAUD_MODE_DEVICE, "%s: a card runs (%s)", sc, st.note);
        sleep_ms_f(800);
        if (asio_busy) {
            CHECK(!strcmp(st.opened.host_api, "Fake shared") && !strcmp(st.opened.device_name, "Fake ASIO"), "asio_busy: the same hardware through WASAPI: %s / %s", st.opened.host_api, st.opened.device_name);
            CHECK(strstr(st.note, "busy") && strstr(st.note, "WASAPI") && strstr(st.note, "multi-client"), "asio_busy: the plain words (busy, WASAPI, multi-client): '%s'", st.note);
            CHECK(last_req.out_first == 1 && !strncmp(last_req.out_uid, "wasapi:", 7), "asio_busy: the reopened request is WASAPI, outputs 1+2 (%s %d)", last_req.out_uid, last_req.out_first);
        } else {
            CHECK(!strcmp(st.opened.host_api, "Fake ASIO") && st.note[0] == 0, "asio_ok: ASIO runs, no note (%s '%s')", st.opened.host_api, st.note);
            CHECK(st.frames == 128 && fabs(st.opened.out_latency_ms - 6.5) < 0.01, "asio_ok: block %u, reported output latency %.1f", st.frames, st.opened.out_latency_ms);
        }
        CHECK(card_blocks > 10, "%s: the card runs", sc);
        vaud_card_xrun(2);
        CHECK(vaud_get_state()->card_xruns == 2, "%s: the card's glitches are counted (%llu)", sc, vaud_get_state()->card_xruns);
    } else if (!strcmp(sc, "asio_gone")) {
        st = start_card("asio:Gone Driver", "", 1, 2, 1, 512);
        CHECK(st.mode == VAUD_MODE_DEVICE && strstr(st.note, "not found") && strstr(st.note, "default"), "asio_gone: a driver that is gone: the default device with a note: '%s'", st.note);
    } else {
        printf("unknown input scenario\n");
        fails++;
    }
    vaud_stop();
}

int main(int argc, char **argv) {
    const char *sc = argc > 1 ? argv[1] : "device";
    if (!strcmp(sc, "config")) scenario_config();
    else if (!strncmp(sc, "in_", 3) || !strncmp(sc, "sys", 3) || !strncmp(sc, "measure", 7) || !strncmp(sc, "asio_", 5)) scenario_input(sc);
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
