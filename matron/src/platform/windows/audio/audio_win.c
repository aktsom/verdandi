/* audio_win.c (M2): see audio_win.h. */
#include "audio_win.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_bridge_host.h"
#include "audio_device.h"

#ifdef _WIN32
#include <windows.h>
#endif

extern const vaud_backend vaud_backend_portaudio;
extern void vaud_backend_pa_describe(char *out, size_t n);

static vaud_config CFG;

int verdandi_audio_boot(void) {
    char desc[400];
    vaud_backend_pa_describe(desc, sizeof desc);
    fprintf(stderr, "audio: %s\n", desc);
    const char *home = getenv("HOME");
    vaud_config_load(&CFG, home);
    const char *list = getenv("VERDANDI_AUDIO_LIST");
    if (list && list[0] == '1') {
        char text[16384];
        int n = vaud_list_text(&vaud_backend_portaudio, text, sizeof text);
        printf("%d devices\n%s", n, text);
        fflush(stdout);
        return 1;
    }
#ifdef _WIN32
    /* the process that runs the sound card's callback gets a priority class above the normal one (its callback thread is also registered with MMCSS as "Pro Audio" by the backend) */
    if (SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS)) {
        fprintf(stderr, "audio: norns.exe runs at the above-normal priority class\n");
    }
#endif
    vaud_state st;
    vaud_start(&vaud_backend_portaudio, &CFG, getenv("VERDANDI_BRIDGE"), &st);
    /* audio.conf.failed: the AUDIO page says "failed: back to default" while it exists (the same file the macOS launcher leaves) */
    if (home && *home) {
        char failed[1100], conf[1100];
        snprintf(failed, sizeof failed, "%s/audio.conf.failed", home);
        snprintf(conf, sizeof conf, "%s/audio.conf", home);
        if (st.mode == VAUD_MODE_FALLBACK) {
            FILE *src = fopen(conf, "rb"), *dst = fopen(failed, "wb");
            if (dst) {
                char buf[512];
                size_t n;
                while (src && (n = fread(buf, 1, sizeof buf, src)) > 0) {
                    fwrite(buf, 1, n, dst);
                }
                fclose(dst);
            }
            if (src) {
                fclose(src);
            }
        } else {
            remove(failed);
        }
    }
    return 0;
}

void verdandi_audio_shutdown(void) { vaud_stop(); }

int verdandi_audio_devices_text(char *out, size_t n) { return vaud_list_text(&vaud_backend_portaudio, out, n); }

int verdandi_audio_input(int mic_on, int sys_on) { return vaud_input_set(mic_on, sys_on); }

void verdandi_audio_measure(void) { vaud_measure_start(); }

void verdandi_audio_selftest_start(void) { vaud_selftest_start(); }

void verdandi_audio_selftest(verdandi_selftest_t *out) {
    const vaud_selftest *t = &vaud_get_state()->selftest;
    out->state = t->state;
    out->callbacks = t->callbacks;
    out->verdict = (int)t->verdict;
    out->avg_ms = t->interval_avg_ms;
    out->max_ms = t->interval_max_ms;
    out->expect_ms = t->interval_expect_ms;
    out->engine_blocks = t->engine_blocks;
    out->late = t->late;
    out->glitches = t->glitches;
}

int verdandi_audio_apply(const char *conf_text, char *msg, size_t n) {
    vaud_config c;
    memset(&c, 0, sizeof c);
    vaud_config_parse_text(&c, conf_text);
    return vaud_apply(&c, msg, n);
}

void verdandi_audio_info(verdandi_audio_info_t *out) {
    memset(out, 0, sizeof *out);
    const vaud_state *s = vaud_get_state();
    int dev = s->mode == VAUD_MODE_DEVICE;
    out->mode = dev ? "device" : (s->mode == VAUD_MODE_FALLBACK ? "fallback" : "null");
    snprintf(out->device, sizeof out->device, "%s", dev ? s->opened.device_name : "");
    snprintf(out->in_device, sizeof out->in_device, "%s", dev ? s->opened.in_name : "");
    snprintf(out->host_api, sizeof out->host_api, "%s", dev ? s->opened.host_api : "");
    snprintf(out->host_apis, sizeof out->host_apis, "%s", s->host_apis);
    out->input = s->input == VAUD_IN_MIC ? "mic" : (s->input == VAUD_IN_SYS ? "system" : "off");
    out->rate = s->rate;
    out->frames = s->frames;
    out->out_latency_ms = dev ? s->opened.out_latency_ms : 0.0;
    out->in_latency_ms = dev ? s->opened.in_latency_ms : 0.0;
    out->block_ms = s->rate ? 1000.0 * s->frames / s->rate : 0.0;
    out->engine_ms = (verdandi_bridge_host_lag() ? verdandi_bridge_host_lag() : (s->engine_lag ? s->engine_lag : 1)) * out->block_ms + (s->rate ? 1000.0 * s->engine_prime / s->rate : 0.0); /* the bridge keeps one block between crone and scsynth; the re-blocking may add one more */
    out->total_ms = out->out_latency_ms + out->engine_ms;
    out->card_frames = s->card_frames;
    out->engine_lag = verdandi_bridge_host_lag();
    out->lag_raises = verdandi_bridge_host_raises();
    out->device_rate = dev ? s->opened.device_rate : 0.0;
    out->exclusive = dev && s->opened.exclusive;
    {
        const vaud_config *c = vaud_current_config();
        snprintf(out->config_text, sizeof out->config_text, "output=%s\ninput=%s\nrate=%u\nblock=%u\nbuffer=%u\nexclusive=%d\nout_first=%d\nin_l=%d\nin_r=%d\n", c->output, c->input, c->rate, c->period, c->buffer,
                 c->exclusive, c->out_first, c->in_l, c->in_r);
    }
    out->peak_db = s->in_peak_db;
    out->clock_rate = s->clock_rate;
    out->measured_ms = s->measured_ms;
    out->card_xruns = s->card_xruns;
    out->in_active = dev && s->opened.in_active;
    snprintf(out->note, sizeof out->note, "%s", s->note);
    snprintf(out->in_note, sizeof out->in_note, "%s", dev ? s->opened.in_note : "");
    out->sys_available = s->sys_available;
    snprintf(out->sys_reason, sizeof out->sys_reason, "%s", s->sys_reason);
    snprintf(out->sys_note, sizeof out->sys_note, "%s", s->sys_note);
    vaud_bridge_stats(&out->to_sc, &out->from_sc, &out->underruns, &out->drops, &out->scsynth_attached);
}
