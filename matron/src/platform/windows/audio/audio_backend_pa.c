/*
 * audio_backend_pa.c (M2): the PortAudio backend of audio_device.h. Windows: the WASAPI host API, shared mode (the Windows mixer owns the device and converts the rate when it must, so other programs keep
 * their sound); exclusive mode and ASIO are not here (ASIO is M3). It also compiles on Linux against libportaudio (the tests use it to check that an unknown device is refused with a plain error).
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
#endif
#endif

#include "audio_device.h"

static PaStream *stream;
static vaud_callback user_cb;
static void *user_arg;
static int pa_ready;

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

/* the host API of the list: WASAPI on Windows; elsewhere (tests) the default one */
static PaHostApiIndex host_api(void) {
    PaHostApiIndex i = Pa_HostApiTypeIdToHostApiIndex(paWASAPI);
    if (i >= 0) {
        return i;
    }
    return Pa_GetDefaultHostApi();
}

static int pa_list(vaud_device *out, int max) {
    char err[200];
    if (pa_up(err, sizeof err) != 0) {
        return 0;
    }
    PaHostApiIndex h = host_api();
    const PaHostApiInfo *hi = h >= 0 ? Pa_GetHostApiInfo(h) : NULL;
    if (!hi) {
        return 0;
    }
    int n = 0;
    for (int i = 0; i < hi->deviceCount && n < max; i++) {
        PaDeviceIndex d = Pa_HostApiDeviceIndexToDeviceIndex(h, i);
        const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
        if (!di || di->maxOutputChannels < 2) {
            continue;
        }
        memset(&out[n], 0, sizeof out[n]);
        snprintf(out[n].name, sizeof out[n].name, "%s", di->name);
        snprintf(out[n].uid, sizeof out[n].uid, "wasapi:%s", di->name);
        out[n].is_default = d == hi->defaultOutputDevice;
        out[n].out_channels = di->maxOutputChannels;
        out[n].default_rate = di->defaultSampleRate;
        n++;
    }
    return n;
}

static int stream_cb(const void *in, void *out, unsigned long frames, const PaStreamCallbackTimeInfo *ti, PaStreamCallbackFlags fl, void *user) {
    (void)in, (void)ti, (void)fl, (void)user;
    user_cb((float *)out, (unsigned)frames, user_arg);
    return paContinue;
}

static vaud_error classify(PaError e) {
    switch (e) {
    case paInvalidDevice: return VAUD_NOT_FOUND;
    case paDeviceUnavailable: return VAUD_BUSY;
    case paInvalidSampleRate: return VAUD_BAD_RATE;
    default: return VAUD_FAILED;
    }
}

static vaud_error pa_open(const char *uid, unsigned rate, unsigned frames, vaud_callback cb, void *user, vaud_opened *res, char *err, size_t errn) {
    if (pa_up(err, errn) != 0) {
        return VAUD_FAILED;
    }
    PaHostApiIndex h = host_api();
    const PaHostApiInfo *hi = h >= 0 ? Pa_GetHostApiInfo(h) : NULL;
    if (!hi) {
        snprintf(err, errn, "no audio host API");
        return VAUD_FAILED;
    }
    PaDeviceIndex dev = paNoDevice;
    if (uid && *uid) {
        const char *want = strncmp(uid, "wasapi:", 7) == 0 ? uid + 7 : uid;
        for (int i = 0; i < hi->deviceCount; i++) {
            PaDeviceIndex d = Pa_HostApiDeviceIndexToDeviceIndex(h, i);
            const PaDeviceInfo *di = Pa_GetDeviceInfo(d);
            if (di && di->maxOutputChannels >= 2 && strcmp(di->name, want) == 0) {
                dev = d;
                break;
            }
        }
        if (dev == paNoDevice) {
            snprintf(err, errn, "no output device with this name");
            return VAUD_NOT_FOUND;
        }
    } else {
        dev = hi->defaultOutputDevice;
        if (dev == paNoDevice) {
            snprintf(err, errn, "Windows has no default output device (no sound card, or all are disabled)");
            return VAUD_NOT_FOUND;
        }
    }
    const PaDeviceInfo *di = Pa_GetDeviceInfo(dev);
    PaStreamParameters p;
    memset(&p, 0, sizeof p);
    p.device = dev;
    p.channelCount = 2;
    p.sampleFormat = paFloat32;
    double want_lat = (double)frames / (double)rate;
    p.suggestedLatency = di->defaultLowOutputLatency > want_lat ? di->defaultLowOutputLatency : want_lat;
#ifdef HAVE_PA_WASAPI_H
    PaWasapiStreamInfo wi;
    memset(&wi, 0, sizeof wi);
    wi.size = sizeof wi;
    wi.hostApiType = paWASAPI;
    wi.version = 1;
#ifdef paWinWasapiAutoConvert
    wi.flags = paWinWasapiAutoConvert; /* shared mode: the Windows mixer converts the rate when the device runs at another one */
#endif
    p.hostApiSpecificStreamInfo = &wi;
#endif
    user_cb = cb;
    user_arg = user;
    PaError e = Pa_IsFormatSupported(NULL, &p, (double)rate);
    if (e != paFormatIsSupported) {
        snprintf(err, errn, "%s", Pa_GetErrorText(e));
        res->rate = (unsigned)di->defaultSampleRate;
        return classify(e) == VAUD_FAILED ? VAUD_BAD_RATE : classify(e);
    }
    e = Pa_OpenStream(&stream, NULL, &p, (double)rate, frames, paClipOff | paDitherOff, stream_cb, NULL);
    if (e != paNoError) {
        snprintf(err, errn, "%s", Pa_GetErrorText(e));
        stream = NULL;
        return classify(e);
    }
    const PaStreamInfo *si = Pa_GetStreamInfo(stream);
    snprintf(res->device_name, sizeof res->device_name, "%s", di->name);
    snprintf(res->host_api, sizeof res->host_api, "%s%s", hi->name, hi->type == paWASAPI ? " shared" : "");
    res->rate = si ? (unsigned)(si->sampleRate + 0.5) : rate;
    res->frames = frames;
    res->latency_ms = si ? si->outputLatency * 1000.0 : 0.0;
    return VAUD_OK;
}

static int pa_start(char *err, size_t errn) {
    PaError e = Pa_StartStream(stream);
    if (e != paNoError) {
        snprintf(err, errn, "%s", Pa_GetErrorText(e));
        return -1;
    }
    return 0;
}

static void pa_close(void) {
    if (stream) {
        Pa_StopStream(stream);
        Pa_CloseStream(stream);
        stream = NULL;
    }
}

const vaud_backend vaud_backend_portaudio = {"PortAudio", pa_list, pa_open, pa_start, pa_close};

/* what the log shows at start: the host APIs this PortAudio has (WASAPI missing is the first thing to look for when there is no sound) */
void vaud_backend_pa_describe(char *out, size_t n) {
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
}
