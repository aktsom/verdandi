/*
 * audio_backend_pa.c (M2, extended in M3): the PortAudio backend of audio_device.h. Windows: the WASAPI host API in shared mode (the Windows mixer owns the device and converts the rate, other programs keep
 * their sound) and, when this PortAudio was built with it, the ASIO host API (the driver of the interface, normally used by one program at a time). Input: a duplex stream when the input is on the output's
 * device, else a separate input stream; WASAPI loopback (what Windows plays) for SYS. Channel selection: ASIO channel selectors, WASAPI the first channels. Exclusive mode is not offered. It also compiles on
 * Linux against libportaudio (the tests use it to check that an unknown device is refused with a plain error).
 */
#include <portaudio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#if defined(__has_include)
#if __has_include(<pa_win_wasapi.h>)
#include <pa_win_wasapi.h>
#define HAVE_PA_WASAPI_H 1
#endif
#if __has_include(<pa_asio.h>)
#include <pa_asio.h>
#endif
#endif
#endif
/* the ASIO host API's stream info (PortAudio's public pa_asio.h, version 1 of the struct) when the header of this PortAudio does not come with the package: the standard MSYS2 PortAudio has no ASIO, but the ASIO
 * build of PortAudio (windows/ci/build-portaudio-asio.sh) is a drop-in DLL, so one norns.exe serves both builds: a PortAudio without ASIO simply lists no ASIO host API (Pa_HostApiTypeIdToHostApiIndex) and
 * this code is never reached. no ASIO SDK header or code is used here: only this plain struct. */
#ifndef PA_ASIO_H
#define paAsioUseChannelSelectors (0x01)
typedef struct PaAsioStreamInfo {
    unsigned long size;
    PaHostApiTypeId hostApiType;
    unsigned long version;
    unsigned long flags;
    int *channelSelectors;
} PaAsioStreamInfo;
#endif
#define HAVE_PA_ASIO_H 1

#include "audio_device.h"
#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#include <objbase.h>
#include <mmsystem.h>
#include "audio_asio_probe.h"
#endif

#define MAXF 16384 /* the card's callback at most (an ASIO buffer of 4096 or 8192 frames is sound; M21) */

static PaStream *stream;     /* the main stream: output, and the input when it is on the same device */
static PaStream *in_stream;  /* a separate input stream */
static PaStream *sys_stream; /* WASAPI loopback */
static vaud_callback user_cb;
static void *user_arg;
static int pa_ready;
static int out_ch, in_ch;          /* the channels the main stream was opened with */
static int in_l_sel, in_r_sel;     /* 0 based indexes into the input frame (WASAPI: after the channels were opened; ASIO: 0 and 1, the selectors did the picking) */
static int sin_ch, sin_l, sin_r;   /* the separate input stream */
static float inmix[2 * MAXF];

/* ---- ASIO: what is installed and what each driver says (M19, audio_asio_probe.c). PortAudio drops a driver that does not answer and the whole ASIO host API when none does, without a word: this is how the log and the
 * AUDIO page can say why. the probe runs when PortAudio starts, and only when this PortAudio is the ASIO build (its DLL exports PaAsio_GetAvailableBufferSizes) */
#ifdef _WIN32
static va_driver asio_drv[VA_MAX];
static int asio_n, asio_usable, asio_flavour;
static char asio_note[480];

static void asio_log(const char *line) { fprintf(stderr, "%s\n", line); }

static void asio_scan(void) {
    /* which file is PortAudio? the module whose name says so. when none does, PortAudio is not a DLL at all: it is linked into norns.exe, and a DLL in the zip (the ASIO build's) is not what runs. the list of the
     * modules that are loaded is in the log then */
    HMODULE pa = NULL, mods[512];
    DWORD need = 0;
    if (EnumProcessModules(GetCurrentProcess(), mods, sizeof mods, &need)) {
        for (DWORD i = 0; i < need / sizeof(HMODULE) && i < 512; i++) {
            char nm[MAX_PATH];
            if (GetModuleFileNameA(mods[i], nm, sizeof nm)) {
                for (char *c = nm; *c; c++) if (*c >= 'A' && *c <= 'Z') *c = (char)(*c + 32);
                if (strstr(nm, "portaudio")) pa = mods[i];
            }
        }
    }
    if (!pa) {
        char list[900] = "";
        for (DWORD i = 0; i < need / sizeof(HMODULE) && i < 512 && strlen(list) < 800; i++) {
            char nm[MAX_PATH];
            if (GetModuleFileNameA(mods[i], nm, sizeof nm)) {
                const char *base = strrchr(nm, '\\');
                snprintf(list + strlen(list), sizeof list - strlen(list), "%s%s", list[0] ? " " : "", base ? base + 1 : nm);
            }
        }
        fprintf(stderr, "audio: no loaded file is called portaudio: PortAudio is linked into norns.exe itself, so the ASIO zip's PortAudio DLL is NOT the one that runs. loaded: %s\n", list);
    }
    char path[MAX_PATH] = "(no PortAudio DLL is loaded)";
    WIN32_FILE_ATTRIBUTE_DATA fa;
    unsigned long long size = 0;
    if (pa && GetModuleFileNameA(pa, path, sizeof path) && GetFileAttributesExA(path, GetFileExInfoStandard, &fa)) size = ((unsigned long long)fa.nFileSizeHigh << 32) | fa.nFileSizeLow;
    asio_flavour = pa && GetProcAddress(pa, "PaAsio_GetAvailableBufferSizes") != NULL;
    asio_n = asio_usable = 0;
    asio_note[0] = 0;
    fprintf(stderr, "audio: PortAudio is %s (%llu bytes); the ASIO host API is %s this file\n", path, size, asio_flavour ? "built into" : "NOT in");
    if (!asio_flavour) {
        snprintf(asio_note, sizeof asio_note, "this is the normal build: its PortAudio has no ASIO (the ASIO zip has it)");
        return;
    }
    /* the full report once; when the AUDIO page asks PortAudio to look again, the drivers are probed quietly and only a change is said */
    static int scanned;
    static char last_sum[300];
    DWORD t0 = GetTickCount();
    asio_n = va_probe(asio_drv, VA_MAX, scanned ? NULL : asio_log);
    char sum[300];
    va_summary(asio_drv, asio_n, sum, sizeof sum, &asio_usable);
    if (!scanned || strcmp(sum, last_sum)) {
        if (scanned) {
            for (int i = 0; i < asio_n; i++) fprintf(stderr, "asio: driver '%s': %s\n", asio_drv[i].name, asio_drv[i].status == VA_OK ? "usable now" : asio_drv[i].detail);
        }
        fprintf(stderr, "audio: ASIO: %s (looked at in %lu ms)\n", sum, (unsigned long)(GetTickCount() - t0));
    }
    snprintf(last_sum, sizeof last_sum, "%s", sum);
    scanned = 1;
    /* PortAudio of this build keeps an ASIO host API even when no driver started (with no devices in it): "listed" means there is a device to use */
    PaHostApiIndex ai = Pa_HostApiTypeIdToHostApiIndex(paASIO);
    int listed = ai >= 0 && Pa_GetHostApiInfo(ai) && Pa_GetHostApiInfo(ai)->deviceCount > 0;
    if (listed) {
        snprintf(asio_note, sizeof asio_note, "%s", sum);
    } else if (asio_n == 0) {
        snprintf(asio_note, sizeof asio_note, "no ASIO driver is installed on this PC: install the ASIO driver of your interface");
    } else if (asio_usable == 0) {
        snprintf(asio_note, sizeof asio_note, "%d ASIO driver%s found but none starts: %.140s", asio_n, asio_n == 1 ? "" : "s", asio_drv[0].detail);
    } else {
        snprintf(asio_note, sizeof asio_note, "ASIO driver '%.60s' starts for Verdandi, but PortAudio did not list it (see norns.log)", asio_drv[0].name);
    }
    if (!listed) fprintf(stderr, "audio: no ASIO host API: %s\n", asio_note);
}

void vaud_backend_pa_asio_status(char *note, size_t n, int *flavour, int *registered, int *usable) {
    snprintf(note, n, "%s", asio_note);
    if (flavour) *flavour = asio_flavour;
    if (registered) *registered = asio_n;
    if (usable) *usable = asio_usable;
}

/* the facts the probe found about a driver whose PortAudio name is `name` */
static const va_driver *asio_facts(const char *name) {
    for (int i = 0; i < asio_n; i++) {
        if (asio_drv[i].status == VA_OK && !_stricmp(asio_drv[i].name, name)) return &asio_drv[i];
    }
    return NULL;
}
#else
void vaud_backend_pa_asio_status(char *note, size_t n, int *flavour, int *registered, int *usable) {
    snprintf(note, n, "%s", "");
    if (flavour) *flavour = 0;
    if (registered) *registered = 0;
    if (usable) *usable = 0;
}
#endif

static int pa_up(char *err, size_t errn) {
    if (!pa_ready) {
        PaError e = Pa_Initialize();
        if (e != paNoError) {
            snprintf(err, errn, "PortAudio: %s", Pa_GetErrorText(e));
            return -1;
        }
        pa_ready = 1;
#ifdef _WIN32
        asio_scan();
#endif
    }
    return 0;
}

static int pa_up_quiet(void) {
    char err[200];
    return pa_up(err, sizeof err);
}

static int ends_with(const char *s, const char *suffix) {
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && !strcmp(s + a - b, suffix);
}

typedef struct {
    PaHostApiIndex index;
    const char *label; /* "WASAPI", "ASIO" */
} api_t;

static int apis(api_t *out) {
    int n = 0;
    PaHostApiIndex w = Pa_HostApiTypeIdToHostApiIndex(paWASAPI);
    PaHostApiIndex a = Pa_HostApiTypeIdToHostApiIndex(paASIO);
    if (w >= 0) {
        out[n].index = w, out[n].label = "WASAPI", n++;
    }
    if (a >= 0) {
        out[n].index = a, out[n].label = "ASIO", n++;
    }
    if (n == 0) { /* (the tests on Linux: the default host API stands in for WASAPI) */
        PaHostApiIndex d = Pa_GetDefaultHostApi();
        if (d >= 0) {
            out[n].index = d, out[n].label = "WASAPI", n++;
        }
    }
    return n;
}

static int pa_list_w(vaud_device *out, int max) {
    char err[200];
    if (pa_up(err, sizeof err) != 0) {
        return 0;
    }
    api_t ap[2];
    int na = apis(ap), n = 0;
    for (int k = 0; k < na; k++) {
        const PaHostApiInfo *hi = Pa_GetHostApiInfo(ap[k].index);
        if (!hi) {
            continue;
        }
        for (int i = 0; i < hi->deviceCount && n < max; i++) {
            PaDeviceIndex d = Pa_HostApiDeviceIndexToDeviceIndex(ap[k].index, i);
            const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
            if (!di || (di->maxOutputChannels < 1 && di->maxInputChannels < 1)) {
                continue;
            }
            memset(&out[n], 0, sizeof out[n]);
            int loop = !strcmp(ap[k].label, "WASAPI") && ends_with(di->name, "[Loopback]") && di->maxInputChannels > 0;
            if (loop) {
                char base[128];
                snprintf(base, sizeof base, "%s", di->name);
                base[strlen(base) - strlen("[Loopback]")] = 0;
                while (strlen(base) && base[strlen(base) - 1] == ' ') base[strlen(base) - 1] = 0;
                snprintf(out[n].name, sizeof out[n].name, "%s", base);
                snprintf(out[n].uid, sizeof out[n].uid, "loopback:%s", base);
            } else {
                snprintf(out[n].name, sizeof out[n].name, "%s", di->name);
                snprintf(out[n].uid, sizeof out[n].uid, "%s:%s", !strcmp(ap[k].label, "ASIO") ? "asio" : "wasapi", di->name);
            }
            snprintf(out[n].api, sizeof out[n].api, "%s", ap[k].label);
            out[n].loopback = loop;
            out[n].is_default = d == hi->defaultOutputDevice && !loop;
            out[n].out_channels = loop ? 0 : di->maxOutputChannels;
            out[n].in_channels = di->maxInputChannels;
            out[n].default_rate = di->defaultSampleRate;
            out[n].low_out_ms = di->defaultLowOutputLatency * 1000.0;
            out[n].low_in_ms = di->defaultLowInputLatency * 1000.0;
#ifdef _WIN32
            if (!strcmp(ap[k].label, "ASIO")) {
                const va_driver *f = asio_facts(di->name);
                if (f) {
                    if (f->rate > 0) out[n].default_rate = f->rate; /* the card's clock NOW (the driver's ASIOGetSampleRate); PortAudio's own default_rate is the first rate in 44100, 48000, ... the driver CAN run at, which says nothing about what it runs at */
                    out[n].out_names = f->n_out_names ? (const char(*)[24])f->out_names : NULL, out[n].n_out_names = f->n_out_names;
                    out[n].in_names = f->n_in_names ? (const char(*)[24])f->in_names : NULL, out[n].n_in_names = f->n_in_names;
                    out[n].buf_min = f->buf_min, out[n].buf_max = f->buf_max, out[n].buf_pref = f->buf_pref, out[n].buf_gran = f->buf_gran;
                }
            }
#endif
            n++;
        }
    }
    return n;
}

/* the device of a uid ("wasapi:name", "asio:name", "loopback:name"); "" = the default output of WASAPI */
static PaDeviceIndex find_device(const char *uid, int want_input, const char **api_out) {
    api_t ap[2];
    int na = apis(ap);
    const char *want_api = NULL, *name = uid;
    int loop = 0;
    if (!strncmp(uid, "asio:", 5)) want_api = "ASIO", name = uid + 5;
    else if (!strncmp(uid, "wasapi:", 7)) want_api = "WASAPI", name = uid + 7;
    else if (!strncmp(uid, "loopback:", 9)) want_api = "WASAPI", name = uid + 9, loop = 1;
    for (int k = 0; k < na; k++) {
        if (want_api && strcmp(want_api, ap[k].label)) {
            continue;
        }
        const PaHostApiInfo *hi = Pa_GetHostApiInfo(ap[k].index);
        if (!uid[0]) {
            if (strcmp(ap[k].label, "WASAPI") == 0 && hi) {
                *api_out = ap[k].label;
                return want_input ? hi->defaultInputDevice : hi->defaultOutputDevice;
            }
            continue;
        }
        for (int i = 0; hi && i < hi->deviceCount; i++) {
            PaDeviceIndex d = Pa_HostApiDeviceIndexToDeviceIndex(ap[k].index, i);
            const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
            if (!di) {
                continue;
            }
            char nm[160];
            snprintf(nm, sizeof nm, "%s", di->name);
            if (loop) {
                if (!ends_with(nm, "[Loopback]")) continue;
                nm[strlen(nm) - strlen("[Loopback]")] = 0;
                while (strlen(nm) && nm[strlen(nm) - 1] == ' ') nm[strlen(nm) - 1] = 0;
            } else if (ends_with(nm, "[Loopback]") && !want_input) {
                continue;
            }
            if (strcmp(nm, name) == 0 && (want_input ? di->maxInputChannels > 0 : di->maxOutputChannels > 0)) {
                *api_out = ap[k].label;
                return d;
            }
        }
    }
    return paNoDevice;
}

static vaud_error classify(PaError e, const char *api) {
    switch (e) {
    case paInvalidDevice: return VAUD_NOT_FOUND;
    case paDeviceUnavailable: return VAUD_BUSY;
    case paInvalidSampleRate: return VAUD_BAD_RATE;
    case paUnanticipatedHostError: /* an ASIO driver that another program has says this */
        return api && !strcmp(api, "ASIO") ? VAUD_BUSY : VAUD_FAILED;
    default: return VAUD_FAILED;
    }
}

static const char *host_error_text(PaError e, char *buf, size_t n) {
    if (e == paUnanticipatedHostError) {
        const PaHostErrorInfo *h = Pa_GetLastHostErrorInfo();
        snprintf(buf, n, "%s%s%s", Pa_GetErrorText(e), h && h->errorText ? ": " : "", h && h->errorText ? h->errorText : "");
    } else {
        snprintf(buf, n, "%s", Pa_GetErrorText(e));
    }
    return buf;
}

/* exclusive mode refused: the exact reason, once, for the log and the note: what PortAudio said, the rate the device runs at, and which of the usual rates the device takes in exclusive mode */
static void exclusive_report(const PaDeviceInfo *odi, const PaStreamParameters *outp, char *err, size_t errn) {
    static const double rates[4] = {44100, 48000, 88200, 96000};
    char ok[80] = "";
    for (int i = 0; i < 4; i++) {
        if (Pa_IsFormatSupported(NULL, outp, rates[i]) == paFormatIsSupported) {
            snprintf(ok + strlen(ok), sizeof ok - strlen(ok), "%s%.0f", ok[0] ? ", " : "", rates[i]);
        }
    }
    size_t len = strlen(err);
    snprintf(err + len, errn - len, "; the device runs at %.0f Hz, exclusive takes: %s", odi->defaultSampleRate, ok[0] ? ok : "none of 44100, 48000, 88200, 96000");
}

/* ---- the callbacks ---- */
static int main_cb(const void *in, void *out, unsigned long frames, const PaStreamCallbackTimeInfo *ti, PaStreamCallbackFlags fl, void *user) {
    (void)ti, (void)user;
    if (fl & (paOutputUnderflow | paInputOverflow)) {
        vaud_card_xrun_flags(1, fl);
    }
    if (frames > MAXF) {
        memset(out, 0, frames * (size_t)out_ch * sizeof(float));
        return paContinue;
    }
    const float *inp = NULL;
    if (in && in_ch > 0) {
        const float *x = (const float *)in;
        vaud_pick_pair(x, (unsigned)frames, in_ch, in_l_sel, in_r_sel, inmix);
        inp = inmix;
    }
    user_cb(inp, (float *)out, (unsigned)frames, user_arg); /* the output is always the stereo pair that was opened */
    return paContinue;
}

static int sep_in_cb(const void *in, void *out, unsigned long frames, const PaStreamCallbackTimeInfo *ti, PaStreamCallbackFlags fl, void *user) {
    (void)out, (void)ti, (void)fl, (void)user;
    static float mix[2 * MAXF];
    if (!in || frames > MAXF) {
        return paContinue;
    }
    const float *x = (const float *)in;
    vaud_pick_pair(x, (unsigned)frames, sin_ch, sin_l, sin_r, mix);
    vaud_push_mic(mix, (unsigned)frames);
    return paContinue;
}

static int sys_cb(const void *in, void *out, unsigned long frames, const PaStreamCallbackTimeInfo *ti, PaStreamCallbackFlags fl, void *user) {
    (void)out, (void)ti, (void)fl, (void)user;
    static float mix[2 * MAXF];
    if (!in || frames > MAXF) {
        return paContinue;
    }
    const float *x = (const float *)in;
    int ch = (int)(intptr_t)user;
    for (unsigned long i = 0; i < frames; i++) {
        mix[2 * i] = x[i * (size_t)ch];
        mix[2 * i + 1] = ch > 1 ? x[i * (size_t)ch + 1] : x[i * (size_t)ch];
    }
    vaud_push_sys(mix, (unsigned)frames);
    return paContinue;
}

/* stream parameters for a device: `channels` opened, ASIO channel selectors when the first channel is not 1 (or the input channels are picked) */
typedef struct {
    PaStreamParameters p;
#ifdef HAVE_PA_ASIO_H
    PaAsioStreamInfo asio;
    int selectors[2];
#endif
#ifdef HAVE_PA_WASAPI_H
    PaWasapiStreamInfo wasapi;
#endif
} sp_t;

static void fill_params(sp_t *sp, PaDeviceIndex dev, const char *api, int channels, int is_input, double rate, double frames /* 0 = the device's own period */, const int *sel /* 2 selectors, 0 based, or NULL */, int exclusive) {
    memset(sp, 0, sizeof *sp);
    const PaDeviceInfo *di = Pa_GetDeviceInfo(dev);
    sp->p.device = dev;
    sp->p.channelCount = channels;
    sp->p.sampleFormat = paFloat32;
    double want_lat = frames > 0 ? frames / rate : 0.0, low = is_input ? di->defaultLowInputLatency : di->defaultLowOutputLatency;
    sp->p.suggestedLatency = low > want_lat ? low : want_lat;
#ifdef HAVE_PA_ASIO_H
    if (!strcmp(api, "ASIO") && sel) {
        sp->asio.size = sizeof sp->asio;
        sp->asio.hostApiType = paASIO;
        sp->asio.version = 1;
        sp->asio.flags = paAsioUseChannelSelectors;
        sp->selectors[0] = sel[0];
        sp->selectors[1] = sel[1];
        sp->asio.channelSelectors = sp->selectors;
        sp->p.hostApiSpecificStreamInfo = &sp->asio;
    }
#endif
#ifdef HAVE_PA_WASAPI_H
    if (!strcmp(api, "WASAPI")) {
        sp->wasapi.size = sizeof sp->wasapi;
        sp->wasapi.hostApiType = paWASAPI;
        sp->wasapi.version = 1;
#ifdef paWinWasapiAutoConvert
        if (!exclusive) {
            sp->wasapi.flags = paWinWasapiAutoConvert; /* shared mode: the Windows mixer converts the rate when the device runs at another one */
        }
#endif
#ifdef paWinWasapiExclusive
        if (exclusive) {
            sp->wasapi.flags |= paWinWasapiExclusive; /* the device is ours alone: a block as small as the driver takes, and nothing else (Ableton, Windows sounds) can use it meanwhile */
        }
#endif
#ifdef paWinWasapiThreadPriority
        /* the callback thread is registered with MMCSS as "Pro Audio" (the scheduler class for audio threads): without it a callback that must finish in 3 to 10 ms is a normal thread among all the others */
        sp->wasapi.flags |= paWinWasapiThreadPriority;
        sp->wasapi.threadPriority = eThreadPriorityProAudio;
#endif
        sp->p.hostApiSpecificStreamInfo = &sp->wasapi;
    }
#endif
    (void)api, (void)sel, (void)exclusive;
}

static void close_all(void) {
    if (stream) {
        Pa_StopStream(stream);
        Pa_CloseStream(stream);
        stream = NULL;
    }
    if (in_stream) {
        Pa_StopStream(in_stream);
        Pa_CloseStream(in_stream);
        in_stream = NULL;
    }
}

static vaud_error pa_open_w(const vaud_open_req *rq, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn) {
    if (pa_up(err, errn) != 0) {
        return VAUD_FAILED;
    }
    close_all();
    const char *oapi = "", *iapi = "";
    PaDeviceIndex od = find_device(rq->out_uid, 0, &oapi);
    if (od == paNoDevice) {
        snprintf(err, errn, rq->out_uid[0] ? "no output device with this name" : "Windows has no default output device (no sound card, or all are disabled)");
        return VAUD_NOT_FOUND;
    }
    const PaDeviceInfo *odi = Pa_GetDeviceInfo(od);
    int is_asio = !strcmp(oapi, "ASIO");
    unsigned asio_frames = 0; /* the size of the ASIO callbacks (the asked buffer, or the driver's preferred one) */
    memset(res->in_name, 0, sizeof res->in_name);
#ifdef _WIN32
    if (is_asio) {
        /* the card's clock is another program's business too (the DAW that has the card at 48000): opening at another rate would make the driver change it, under the other program. so: ask the driver which rate the
         * card runs at NOW, and open only at that; any other rate is refused here and the caller (the start-up) follows the card, a live change keeps the engine's rate and says so */
        va_driver f;
        if (va_probe_one(odi->name, &f) != 0 || f.rate <= 0) {
            /* the rate could not be read (the driver refused, did not answer, or has no current rate): PortAudio would then ask the driver to set the rate it is opened at, which is a change of the card's clock.
             * Verdandi never takes that risk: no open. the caller's retry and fallback (WASAPI on the same hardware) take over */
            snprintf(err, errn, "the card's rate could not be read (ASIO driver '%.50s'%s%.120s), so Verdandi will not risk changing it", odi->name, f.detail[0] ? ": " : "", f.detail);
            return f.status == VA_INIT || f.status == VA_TIMEOUT ? VAUD_BUSY : VAUD_FAILED;
        }
        res->device_rate = f.rate;
        unsigned cur = (unsigned)(f.rate + 0.5);
        if (cur != rq->rate) {
            int ok = cur == 44100 || cur == 48000 || cur == 88200 || cur == 96000;
            res->rate = ok ? cur : 0;
            snprintf(err, errn, "the card (ASIO driver '%.50s') runs at %u Hz and the engine at %u Hz. Verdandi does not change a card's clock, another program may be using it%s", odi->name, cur, rq->rate,
                     ok ? ": set the card to the engine's rate, or restart Verdandi so that it follows the card" : " (and norns can run at 44100, 48000, 88200 or 96000 Hz only)");
            return VAUD_BAD_RATE;
        }
        asio_frames = rq->frames ? (unsigned)rq->frames : (unsigned)(f.buf_pref > 0 ? f.buf_pref : 0);
        if (rq->frames > MAXF || (rq->frames == 0 && f.buf_pref > MAXF)) {
            /* a buffer the engine cannot take in one callback: said, not tried (a card that opens and never answers would be reopened for ever) */
            snprintf(err, errn, "the card's buffer of %ld frames is more than Verdandi can take (at most %d): choose a smaller BUFFER", rq->frames ? (long)rq->frames : f.buf_pref, MAXF);
            return VAUD_FAILED;
        }
    }
#endif
    res->in_active = res->in_separate = 0;
    res->in_note[0] = 0;
    PaDeviceIndex id = paNoDevice;
    if (rq->in_uid[0]) {
        id = find_device(rq->in_uid, 1, &iapi);
        if (id == paNoDevice) {
            snprintf(res->in_note, sizeof res->in_note, "input '%.60s' was not found: output only", rq->in_uid);
        }
    }
    int out_first = is_asio ? (rq->out_first > 0 ? rq->out_first : 1) : 1;
    if (!is_asio && rq->out_first > 1) {
        snprintf(res->in_note + strlen(res->in_note), sizeof res->in_note - strlen(res->in_note), "%soutput channels other than 1 and 2 are ASIO only", res->in_note[0] ? ". " : "");
    }
    if (out_first + 1 > odi->maxOutputChannels && odi->maxOutputChannels >= 2) {
        out_first = 1;
    }
    int osel[2] = {out_first - 1, out_first};
    int duplex = id != paNoDevice && id == od;
    const PaDeviceInfo *idi = id != paNoDevice ? Pa_GetDeviceInfo(id) : NULL;
    if (id != paNoDevice && !duplex && is_asio) {
        /* an ASIO driver is one device: the input has to be on it */
        snprintf(res->in_note, sizeof res->in_note, "ASIO uses one device: the input '%.60s' is not on it, output only", rq->in_uid);
        id = paNoDevice;
        idi = NULL;
    }
    user_cb = cb;
    user_arg = user;
    sp_t outp, inp;
    fill_params(&outp, od, oapi, 2, 0, rq->rate, rq->frames, is_asio ? osel : NULL, rq->exclusive && !is_asio);
    const unsigned long fpb = rq->frames ? rq->frames : paFramesPerBufferUnspecified; /* 0: the host API's own period, no re-blocking by PortAudio (the engine re-blocks itself) */
    PaError e;
    int try_input = duplex; /* one stream with both directions only on one device; another device gets its own input stream below */
    int isel[2] = {rq->in_l - 1, rq->in_r - 1};
    if (try_input) {
        int maxc = rq->in_l > rq->in_r ? rq->in_l : rq->in_r;
        if (maxc > idi->maxInputChannels) {
            snprintf(res->in_note + strlen(res->in_note), sizeof res->in_note - strlen(res->in_note), "%sinput channels %d/%d are not on this device (it has %d)", res->in_note[0] ? ". " : "", rq->in_l,
                     rq->in_r, idi->maxInputChannels);
            isel[0] = 0;
            isel[1] = idi->maxInputChannels > 1 ? 1 : 0;
            maxc = idi->maxInputChannels > 1 ? 2 : 1;
        }
        in_ch = is_asio ? 2 : maxc; /* ASIO: two channels, picked by the selectors; WASAPI: the first `maxc` channels, picked by the callback */
        in_l_sel = is_asio ? 0 : isel[0];
        in_r_sel = is_asio ? 1 : isel[1];
        fill_params(&inp, id, iapi, in_ch, 1, rq->rate, rq->frames, is_asio ? isel : NULL, rq->exclusive && !is_asio);
    }
    out_ch = 2;
    e = Pa_IsFormatSupported(try_input ? &inp.p : NULL, &outp.p, (double)rq->rate);
    if (e != paFormatIsSupported && try_input) {
        /* the input is what the device does not take: the output alone */
        char t[120];
        snprintf(res->in_note + strlen(res->in_note), sizeof res->in_note - strlen(res->in_note), "%sinput '%.50s' cannot be opened with this output (%s): output only", res->in_note[0] ? ". " : "",
                 rq->in_uid, host_error_text(e, t, sizeof t));
        try_input = 0;
        e = Pa_IsFormatSupported(NULL, &outp.p, (double)rq->rate);
    }
    if (e != paFormatIsSupported) {
        host_error_text(e, err, errn);
        if (rq->exclusive && !is_asio) {
            exclusive_report(odi, &outp.p, err, errn);
        }
        res->rate = (unsigned)odi->defaultSampleRate;
        vaud_error c = classify(e, oapi);
        return c == VAUD_FAILED && e == paInvalidSampleRate ? VAUD_BAD_RATE : (c == VAUD_FAILED && e != paUnanticipatedHostError ? VAUD_BAD_RATE : c);
    }
    e = Pa_OpenStream(&stream, try_input ? &inp.p : NULL, &outp.p, (double)rq->rate, fpb, paClipOff | paDitherOff, main_cb, NULL);
    if (e != paNoError && try_input) {
        char t[120];
        snprintf(res->in_note + strlen(res->in_note), sizeof res->in_note - strlen(res->in_note), "%sinput '%.50s' could not be opened (%s): output only", res->in_note[0] ? ". " : "", rq->in_uid,
                 host_error_text(e, t, sizeof t));
        try_input = 0;
        stream = NULL;
        e = Pa_OpenStream(&stream, NULL, &outp.p, (double)rq->rate, fpb, paClipOff | paDitherOff, main_cb, NULL);
    }
    if (e != paNoError) {
        host_error_text(e, err, errn);
        if (rq->exclusive && !is_asio) {
            exclusive_report(odi, &outp.p, err, errn);
        }
        stream = NULL;
        return classify(e, oapi);
    }
    if (!try_input) {
        in_ch = 0;
    }
    /* a separate input stream: another device (WASAPI) */
    if (id != paNoDevice && !duplex) {
        int maxc = rq->in_l > rq->in_r ? rq->in_l : rq->in_r;
        if (maxc > idi->maxInputChannels) {
            maxc = idi->maxInputChannels > 1 ? 2 : 1;
            sin_l = 0;
            sin_r = maxc > 1 ? 1 : 0;
        } else {
            sin_l = rq->in_l - 1;
            sin_r = rq->in_r - 1;
        }
        sin_ch = maxc;
        sp_t sip;
        fill_params(&sip, id, iapi, sin_ch, 1, rq->rate, rq->frames, NULL, 0);
        PaError e2 = Pa_OpenStream(&in_stream, &sip.p, NULL, (double)rq->rate, fpb, paClipOff | paDitherOff, sep_in_cb, NULL);
        if (e2 == paNoError) {
            res->in_active = 1;
            res->in_separate = 1;
        } else {
            char t[120];
            snprintf(res->in_note + strlen(res->in_note), sizeof res->in_note - strlen(res->in_note), "%sinput '%.50s' could not be opened (%s): output only", res->in_note[0] ? ". " : "", rq->in_uid,
                     host_error_text(e2, t, sizeof t));
            in_stream = NULL;
        }
        if (idi) {
            snprintf(res->in_name, sizeof res->in_name, "%s", idi->name);
        }
    } else if (try_input) {
        res->in_active = 1;
        snprintf(res->in_name, sizeof res->in_name, "%s", idi->name);
    } else if (id != paNoDevice && idi) {
        snprintf(res->in_name, sizeof res->in_name, "%s", idi->name);
    }
    const PaHostApiInfo *hi = Pa_GetHostApiInfo(odi->hostApi);
    const PaStreamInfo *si = Pa_GetStreamInfo(stream);
    snprintf(res->device_name, sizeof res->device_name, "%s", odi->name);
    snprintf(res->host_api, sizeof res->host_api, "%s%s", hi ? hi->name : "?", hi && hi->type == paWASAPI ? " shared" : "");
    res->rate = si ? (unsigned)(si->sampleRate + 0.5) : rq->rate;
    res->frames = rq->frames ? rq->frames : asio_frames;
    res->exclusive = rq->exclusive && !is_asio;
    if (!is_asio || res->device_rate <= 0) res->device_rate = odi->defaultSampleRate;
#if defined(HAVE_PA_WASAPI_H) && defined(_WIN32)
    if (!is_asio && !rq->frames) {
        /* the period Windows gave (480 frames at 48000 Hz in shared mode): that is the size of the card's callbacks */
        UINT32 hin = 0, hout = 0;
        if (PaWasapi_GetFramesPerHostBuffer(stream, &hin, &hout) == paNoError && hout > 0) {
            res->frames = hout;
            res->host_frames = hout;
        }
    }
#endif
    res->out_latency_ms = si ? si->outputLatency * 1000.0 : 0.0;
    res->in_latency_ms = si && res->in_active && !res->in_separate ? si->inputLatency * 1000.0 : (res->in_active ? idi->defaultLowInputLatency * 1000.0 : 0.0);
    return VAUD_OK;
}

static int pa_start_w(char *err, size_t errn) {
    PaError e = Pa_StartStream(stream);
    if (e != paNoError) {
        snprintf(err, errn, "%s", Pa_GetErrorText(e));
        return -1;
    }
    if (in_stream) {
        Pa_StartStream(in_stream);
    }
    return 0;
}

static void pa_close_w(void) { close_all(); }

#ifdef _WIN32
/* direct WASAPI loopback (wasapi_loopback.cc): used when this PortAudio lists no loopback device */
extern int vwl_open(unsigned target_rate, char *name, size_t namen, char *err, size_t errn);
extern void vwl_close(void);
static int direct_sys_on;
#endif

static int pa_open_sys_w(unsigned rate, unsigned frames, char *name, size_t namen, char *err, size_t errn) {
    if (pa_up(err, errn) != 0) {
        return -1;
    }
    /* the loopback of the Windows default output: what the other programs play */
    api_t ap[2];
    int na = apis(ap);
    PaDeviceIndex dev = paNoDevice;
    PaHostApiIndex wi = Pa_HostApiTypeIdToHostApiIndex(paWASAPI);
    if (wi < 0 || na == 0) {
        snprintf(err, errn, "no WASAPI here: the system's sound cannot be recorded");
        return -1;
    }
    const PaHostApiInfo *hi = Pa_GetHostApiInfo(wi);
    const PaDeviceInfo *defd = hi->defaultOutputDevice != paNoDevice ? Pa_GetDeviceInfo(hi->defaultOutputDevice) : NULL;
    for (int i = 0; i < hi->deviceCount; i++) {
        PaDeviceIndex d = Pa_HostApiDeviceIndexToDeviceIndex(wi, i);
        const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
        if (di && ends_with(di->name, "[Loopback]") && di->maxInputChannels > 0) {
            if (dev == paNoDevice) dev = d;
            if (defd && !strncmp(di->name, defd->name, strlen(defd->name))) {
                dev = d;
                break;
            }
        }
    }
    if (dev == paNoDevice) {
#ifdef _WIN32
        /* this PortAudio lists no loopback device (the MSYS2 build): record the default output straight from WASAPI */
        if (vwl_open(rate, name, namen, err, errn) == 0) {
            direct_sys_on = 1;
            return 0;
        }
        return -1;
#else
        snprintf(err, errn, "this PortAudio has no WASAPI loopback device: the system's sound cannot be recorded");
        return -1;
#endif
    }
    const PaDeviceInfo *di = Pa_GetDeviceInfo(dev);
    int ch = di->maxInputChannels > 1 ? 2 : 1;
    sp_t sp;
    fill_params(&sp, dev, "WASAPI", ch, 1, rate, frames, NULL, 0);
    PaError e = Pa_OpenStream(&sys_stream, &sp.p, NULL, (double)rate, frames, paClipOff | paDitherOff, sys_cb, (void *)(intptr_t)ch);
    if (e != paNoError) {
        host_error_text(e, err, errn);
        sys_stream = NULL;
        return -1;
    }
    if (Pa_StartStream(sys_stream) != paNoError) {
        Pa_CloseStream(sys_stream);
        sys_stream = NULL;
        snprintf(err, errn, "the loopback stream did not start");
        return -1;
    }
    snprintf(name, namen, "%s", di->name);
    return 0;
}

static void pa_close_sys_w(void) {
#ifdef _WIN32
    if (direct_sys_on) {
        vwl_close();
        direct_sys_on = 0;
    }
#endif
    if (sys_stream) {
        Pa_StopStream(sys_stream);
        Pa_CloseStream(sys_stream);
        sys_stream = NULL;
    }
}

static void pa_describe_w(char *out, size_t n) {
    char err[200];
    out[0] = 0;
    if (pa_up(err, sizeof err) != 0) {
        snprintf(out, n, "%s", err);
        return;
    }
    size_t len = (size_t)snprintf(out, n, "PortAudio %s; host APIs:", Pa_GetVersionText());
    for (int i = 0; i < Pa_GetHostApiCount() && len + 40 < n; i++) {
        len += (size_t)snprintf(out + len, n - len, " %s(%d)", Pa_GetHostApiInfo(i)->name, Pa_GetHostApiInfo(i)->deviceCount);
    }
    if (Pa_HostApiTypeIdToHostApiIndex(paASIO) < 0 && len + 40 < n) {
#ifdef _WIN32
        snprintf(out + len, n - len, " [no ASIO host API: %s]", asio_note[0] ? asio_note : "not known");
#else
        snprintf(out + len, n - len, " [no ASIO host API: this PortAudio has none, or no ASIO driver is installed]");
#endif
    }
}

#ifdef _WIN32
#define HAS_DIRECT_SYS 1
#else
#define HAS_DIRECT_SYS 0
#endif
/* the clock of a card that another program (an ASIO driver that is running) has set: the device takes, in its own format (exclusive mode), only the rate it runs at; a free card takes several. exactly one rate
 * taken = that is the clock. 0: not WASAPI, not known, or free */
static double pa_card_clock_w(const char *uid) {
#ifdef _WIN32
    if (uid && !strncmp(uid, "asio:", 5)) {
        /* an ASIO driver: ask THIS driver for the card's clock, once (it is loaded for a moment and let go): no restart of PortAudio, no other driver is looked at */
        va_driver f;
        return va_probe_one(uid + 5, &f) == 0 && f.rate > 0 ? f.rate : 0;
    }
#endif
#ifdef HAVE_PA_WASAPI_H
    static const double rates[4] = {44100, 48000, 88200, 96000};
    if (!uid || !strncmp(uid, "asio:", 5) || pa_up_quiet() != 0) {
        return 0;
    }
    const char *api = NULL;
    PaDeviceIndex d = uid[0] ? find_device(uid, 0, &api) : Pa_GetDefaultOutputDevice();
    if (d == paNoDevice || d < 0) {
        return 0;
    }
    const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
    if (!di || di->maxOutputChannels < 2) {
        return 0;
    }
    double found = 0;
    int count = 0;
    for (int i = 0; i < 4; i++) {
        sp_t outp;
        fill_params(&outp, d, "WASAPI", 2, 0, rates[i], 0, NULL, 1);
        if (Pa_IsFormatSupported(NULL, &outp.p, rates[i]) == paFormatIsSupported) {
            count++;
            found = rates[i];
        }
    }
    return count == 1 ? found : 0;
#else
    (void)uid;
    return 0;
#endif
}

/* look at the devices again: the list PortAudio made at its start does not know that a card's state changed. only when no stream is open (Pa_Terminate would end it) */
/* is the chosen output device there now? without a restart of PortAudio and without touching a stream that plays */
static int pa_present_w(const char *uid) {
#ifdef _WIN32
    if (!uid || !uid[0]) {
        return 1; /* the Windows default device: whatever Windows has */
    }
    if (!strncmp(uid, "asio:", 5)) {
        va_driver f;
        return va_probe_one(uid + 5, &f) == 0 ? 1 : 0;
    }
    if (!strncmp(uid, "wasapi:", 7)) {
        /* the names of the Windows devices as winmm lists them (cut at 31 characters): only the devices that are plugged in and enabled */
        const char *name = uid + 7;
        UINT n = waveOutGetNumDevs();
        for (UINT i = 0; i < n; i++) {
            WAVEOUTCAPSA c;
            if (waveOutGetDevCapsA(i, &c, sizeof c) != MMSYSERR_NOERROR) continue;
            size_t k = strlen(c.szPname);
            if (!strncmp(name, c.szPname, k) && (k >= 31 || strlen(name) == k)) return 1;
        }
        return 0;
    }
#else
    (void)uid;
#endif
    return -1;
}

static void pa_refresh_w(void) {
    if (!pa_ready || stream || in_stream || sys_stream) {
        return;
    }
    Pa_Terminate();
    pa_ready = 0;
    char err[200];
    pa_up(err, sizeof err);
}


/* ---- one thread for all of PortAudio (M20). an ASIO driver is an in-process COM object that has to be made, used and released on a thread with a COM apartment of its own kind (single-threaded: what the drivers say in the
 * registry, "ThreadingModel Apartment"). Pa_Initialize makes the apartment of the thread it runs on; an open from ANOTHER thread (the AUDIO page's apply runs on the Lua thread, the watchdog on its own) found no apartment
 * and PortAudio said "Failed to load ASIO driver". reproduced with the stub driver (linux/tests/asio_reopen_test.sh): same thread, again and again, works; a thread without COM, or with a multi-threaded apartment, fails.
 * so every call into PortAudio is done by this worker thread, whoever asks: the callers wait for the answer (the calls take what they took before). it also pumps its message queue while it waits, as a single-threaded
 * apartment should (a driver that posts a window message to its own thread is heard) ---- */
#ifdef _WIN32
typedef struct {
    void (*fn)(void *);
    void *arg;
} pa_job;
static HANDLE pa_job_ev, pa_done_ev;
static pa_job pa_cur;
static DWORD pa_worker_id;
static INIT_ONCE pa_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION pa_call_lock;

static DWORD WINAPI pa_worker(LPVOID unused) {
    (void)unused;
    (void)CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    pa_worker_id = GetCurrentThreadId();
    SetEvent(pa_done_ev); /* "up" */
    for (;;) {
        DWORD w = MsgWaitForMultipleObjects(1, &pa_job_ev, FALSE, INFINITE, QS_ALLINPUT);
        if (w == WAIT_OBJECT_0) {
            pa_cur.fn(pa_cur.arg);
            SetEvent(pa_done_ev);
        } else {
            MSG m;
            while (PeekMessageA(&m, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&m);
                DispatchMessageA(&m);
            }
        }
    }
    return 0;
}

static BOOL CALLBACK pa_once_init(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o, (void)p, (void)c;
    InitializeCriticalSection(&pa_call_lock);
    pa_job_ev = CreateEventA(NULL, FALSE, FALSE, NULL);
    pa_done_ev = CreateEventA(NULL, FALSE, FALSE, NULL);
    HANDLE t = CreateThread(NULL, 0, pa_worker, NULL, 0, NULL);
    if (t) {
        CloseHandle(t);
        WaitForSingleObject(pa_done_ev, 10000);
    }
    return TRUE;
}

static void on_worker(void (*fn)(void *), void *arg) {
    InitOnceExecuteOnce(&pa_once, pa_once_init, NULL, NULL);
    if (!pa_worker_id || GetCurrentThreadId() == pa_worker_id) { /* (no worker could be made, or called from it: run here) */
        fn(arg);
        return;
    }
    EnterCriticalSection(&pa_call_lock);
    pa_cur.fn = fn;
    pa_cur.arg = arg;
    SetEvent(pa_job_ev);
    WaitForSingleObject(pa_done_ev, INFINITE);
    LeaveCriticalSection(&pa_call_lock);
}
#else
static void on_worker(void (*fn)(void *), void *arg) { fn(arg); }
#endif

typedef struct {
    vaud_device *out;
    int max, ret;
} job_list;
static void do_list(void *a) { job_list *j = a; j->ret = pa_list_w(j->out, j->max); }
static int pa_list(vaud_device *out, int max) {
    job_list j = {out, max, 0};
    on_worker(do_list, &j);
    return j.ret;
}
typedef struct {
    const vaud_open_req *rq;
    vaud_callback cb;
    void *user;
    vaud_opened *res;
    char *err;
    size_t errn;
    vaud_error ret;
} job_open;
static void do_open(void *a) { job_open *j = a; j->ret = pa_open_w(j->rq, j->cb, j->user, j->res, j->err, j->errn); }
static vaud_error pa_open(const vaud_open_req *rq, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn) {
    job_open j = {rq, cb, user, res, err, errn, VAUD_FAILED};
    on_worker(do_open, &j);
    return j.ret;
}
typedef struct {
    char *err;
    size_t errn;
    int ret;
} job_start;
static void do_start(void *a) { job_start *j = a; j->ret = pa_start_w(j->err, j->errn); }
static int pa_start(char *err, size_t errn) {
    job_start j = {err, errn, -1};
    on_worker(do_start, &j);
    return j.ret;
}
static void do_close(void *a) { (void)a; pa_close_w(); }
static void pa_close(void) { on_worker(do_close, NULL); }
typedef struct {
    unsigned rate, frames;
    char *name;
    size_t namen;
    char *err;
    size_t errn;
    int ret;
} job_sys;
static void do_open_sys(void *a) { job_sys *j = a; j->ret = pa_open_sys_w(j->rate, j->frames, j->name, j->namen, j->err, j->errn); }
static int pa_open_sys(unsigned rate, unsigned frames, char *name, size_t namen, char *err, size_t errn) {
    job_sys j = {rate, frames, name, namen, err, errn, -1};
    on_worker(do_open_sys, &j);
    return j.ret;
}
static void do_close_sys(void *a) { (void)a; pa_close_sys_w(); }
static void pa_close_sys(void) { on_worker(do_close_sys, NULL); }
typedef struct {
    char *out;
    size_t n;
} job_desc;
static void do_describe(void *a) { job_desc *j = a; pa_describe_w(j->out, j->n); }
static void pa_describe(char *out, size_t n) {
    job_desc j = {out, n};
    on_worker(do_describe, &j);
}
typedef struct {
    const char *uid;
    double ret;
} job_clock;
static void do_card_clock(void *a) { job_clock *j = a; j->ret = pa_card_clock_w(j->uid); }
static double pa_card_clock(const char *uid) {
    job_clock j = {uid, 0};
    on_worker(do_card_clock, &j);
    return j.ret;
}
static void do_refresh(void *a) { (void)a; pa_refresh_w(); }
typedef struct {
    const char *uid;
    int ret;
} job_present;
static void do_present(void *a) { job_present *j = a; j->ret = pa_present_w(j->uid); }
static int pa_present(const char *uid) {
    job_present j = {uid, -1};
    on_worker(do_present, &j);
    return j.ret;
}
static void pa_refresh(void) { on_worker(do_refresh, NULL); }

const vaud_backend vaud_backend_portaudio = {"PortAudio", pa_list, pa_open, pa_start, pa_close, pa_open_sys, pa_close_sys, pa_describe, HAS_DIRECT_SYS, pa_card_clock, pa_refresh, pa_present};

/* what the log shows at start: the host APIs this PortAudio has (WASAPI missing is the first thing to look for when there is no sound) */
void vaud_backend_pa_describe(char *out, size_t n) { pa_describe(out, n); }
