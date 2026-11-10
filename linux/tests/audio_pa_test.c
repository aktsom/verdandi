/*
 * audio_pa_test.c (M2): the PortAudio backend of the Windows build (audio_backend_pa.c) against libportaudio on Linux. There may be no sound card here; what must hold either way: the list works, a device that
 * does not exist is refused with VAUD_NOT_FOUND and a plain error (no hang, no crash), and vaud_start() with this backend always ends with a running chain (a card, or null audio with a note).
 */
#include <stdio.h>
#include <string.h>

#include "audio/audio_device.h"

extern const vaud_backend vaud_backend_portaudio;
extern void vaud_backend_pa_describe(char *out, size_t n);

/* stand-ins for the null backend and the bridge: linking the real jack_null.c would put "jack_*" functions into the program that libportaudio's own JACK host API then calls by mistake */
void verdandi_jack_null_configure(unsigned rate, unsigned frames) { (void)rate, (void)frames; }
void verdandi_jack_null_external_clock(int on) { (void)on; }
int verdandi_jack_null_process(unsigned n, const float *a, const float *b, float *c, float *d) { (void)n, (void)a, (void)b, (void)c, (void)d; return 0; }
int verdandi_bridge_host_start(const char *name, unsigned rate, unsigned frames) { (void)name, (void)rate, (void)frames; return -1; }
void verdandi_bridge_host_stop(void) {}
void verdandi_bridge_host_stats(unsigned long long *a, unsigned long long *b, unsigned long long *c, unsigned long long *d, int *e) { (void)a, (void)b, (void)c, (void)d, (void)e; }

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    char desc[400];
    vaud_backend_pa_describe(desc, sizeof desc);
    printf("%s\n", desc);
    vaud_device dev[64];
    int n = vaud_backend_portaudio.list(dev, 64);
    CHECK(n >= 0, "list");
    printf("%d output devices\n", n);
    char text[8192];
    int m = vaud_list_text(&vaud_backend_portaudio, text, sizeof text);
    CHECK(m == n, "list text count");
    vaud_opened res;
    char err[256] = "";
    memset(&res, 0, sizeof res);
    vaud_error e = vaud_backend_portaudio.open("wasapi:No Such Speakers 12345", 48000, 512, NULL, NULL, &res, err, sizeof err);
    CHECK(e == VAUD_NOT_FOUND && err[0], "an unknown device is refused as not found (%d '%s')", e, err);
    vaud_config cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.output[0] = 0;
    cfg.rate = 48000;
    cfg.period = 512;
    vaud_state st;
    vaud_start(&vaud_backend_portaudio, &cfg, NULL, &st);
    CHECK(st.mode == VAUD_MODE_DEVICE || st.mode == VAUD_MODE_FALLBACK, "mode %d", st.mode);
    CHECK(st.mode == VAUD_MODE_DEVICE || st.note[0], "a fallback has a note");
    printf("mode %d note '%s'\n", st.mode, st.note);
    vaud_stop();
    if (!fails) printf("audio_pa_test: passed\n");
    return fails ? 1 : 0;
}
