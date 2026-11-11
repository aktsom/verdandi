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

#define MAXF 2048

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

static int pa_up(char *err, size_t errn) {
    if (!pa_ready) {
        PaError e = Pa_Initialize();
        if (e != paNoError) {
            snprintf(err, errn, "PortAudio: %s", Pa_GetErrorText(e));
            return -1;
        }
        pa_ready = 1;
    }
    return 0;
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

static int pa_list(vaud_device *out, int max) {
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

/* ---- the callbacks ---- */
static int main_cb(const void *in, void *out, unsigned long frames, const PaStreamCallbackTimeInfo *ti, PaStreamCallbackFlags fl, void *user) {
    (void)ti, (void)user;
    if (fl & (paOutputUnderflow | paInputOverflow)) {
        vaud_card_xrun(1);
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

static vaud_error pa_open(const vaud_open_req *rq, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn) {
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
    memset(res->in_name, 0, sizeof res->in_name);
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
    res->frames = rq->frames;
    res->exclusive = rq->exclusive && !is_asio;
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

static int pa_start(char *err, size_t errn) {
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

static void pa_close(void) { close_all(); }

static int pa_open_sys(unsigned rate, unsigned frames, char *name, size_t namen, char *err, size_t errn) {
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
        snprintf(err, errn, "this PortAudio has no WASAPI loopback device (it needs PortAudio 19.7 or newer): the system's sound cannot be recorded");
        return -1;
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

static void pa_close_sys(void) {
    if (sys_stream) {
        Pa_StopStream(sys_stream);
        Pa_CloseStream(sys_stream);
        sys_stream = NULL;
    }
}

static void pa_describe(char *out, size_t n) {
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
        snprintf(out + len, n - len, " [no ASIO host API: this PortAudio has none, or no ASIO driver is installed]");
    }
}

const vaud_backend vaud_backend_portaudio = {"PortAudio", pa_list, pa_open, pa_start, pa_close, pa_open_sys, pa_close_sys, pa_describe};

/* what the log shows at start: the host APIs this PortAudio has (WASAPI missing is the first thing to look for when there is no sound) */
void vaud_backend_pa_describe(char *out, size_t n) { pa_describe(out, n); }
