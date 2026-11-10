/* audio_win.c (M2): see audio_win.h. */
#include "audio_win.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_device.h"

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
    out->engine_ms = out->block_ms; /* the bridge keeps one block between crone and scsynth */
    out->peak_db = s->in_peak_db;
    out->measured_ms = s->measured_ms;
    out->in_active = dev && s->opened.in_active;
    snprintf(out->note, sizeof out->note, "%s", s->note);
    snprintf(out->in_note, sizeof out->in_note, "%s", dev ? s->opened.in_note : "");
    snprintf(out->sys_note, sizeof out->sys_note, "%s", s->sys_note);
    vaud_bridge_stats(&out->to_sc, &out->from_sc, &out->underruns, &out->drops, &out->scsynth_attached);
}
