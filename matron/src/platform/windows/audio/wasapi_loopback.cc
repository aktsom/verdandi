/* wasapi_loopback.cc (Windows build): SYS = what Windows plays, recorded straight from WASAPI (the PortAudio of MSYS2 lists no loopback device). The loopback of the DEFAULT output in SHARED mode: an
 * IAudioClient on the render endpoint with AUDCLNT_STREAMFLAGS_LOOPBACK, read by polling every 5 ms in a thread of its own (event callbacks are not allowed with loopback on older Windows). Packets are in the
 * mix format of that device (any rate, any channels): loopback_convert.h makes them stereo at norns's rate and vaud_push_sys() hands them to the card's callback through a ring. Nothing here touches the
 * output stream. shared mode only: it does not hear what a program plays through ASIO or in exclusive mode. a failure at any step is an error text, never a crash: every call is checked and the thread
 * releases what it made. NOT run in the sandbox (no Windows): compile-checked with mingw only; the first real test is the owner's PC. */
#include <initguid.h>
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <ksmedia.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <vector>

#include "loopback_convert.h"

extern "C" void vaud_push_sys(const float *interleaved, unsigned frames);

namespace {
pthread_t g_thread;
volatile LONG g_stop, g_state; /* state: 0 starting, 1 running, 2 failed */
bool g_started;
unsigned g_target_rate;
char g_err[240];

void fail(const char *what, HRESULT hr) { snprintf(g_err, sizeof g_err, "%s (Windows error 0x%08lx)", what, (unsigned long)hr); }

bool is_float(const WAVEFORMATEX *wf) {
    if (wf->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE && wf->cbSize >= 22) {
        const WAVEFORMATEXTENSIBLE *e = (const WAVEFORMATEXTENSIBLE *)wf;
        return IsEqualGUID(e->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) != 0;
    }
    return false;
}
bool is_pcm16(const WAVEFORMATEX *wf) {
    if (wf->wBitsPerSample != 16) return false;
    if (wf->wFormatTag == WAVE_FORMAT_PCM) return true;
    if (wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE && wf->cbSize >= 22) {
        return IsEqualGUID(((const WAVEFORMATEXTENSIBLE *)wf)->SubFormat, KSDATAFORMAT_SUBTYPE_PCM) != 0;
    }
    return false;
}

void *loop(void *) {
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    bool com = SUCCEEDED(hr);
    IMMDeviceEnumerator *en = NULL;
    IMMDevice *dev = NULL;
    IAudioClient *ac = NULL;
    IAudioCaptureClient *cap = NULL;
    WAVEFORMATEX *wf = NULL;
    bool started = false;
    do {
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, (void **)&en);
        if (FAILED(hr) || !en) { fail("the Windows device enumerator is not available", hr); break; }
        hr = en->GetDefaultAudioEndpoint(eRender, eConsole, &dev);
        if (FAILED(hr) || !dev) { fail("there is no default output device to listen to", hr); break; }
        hr = dev->Activate(IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&ac);
        if (FAILED(hr) || !ac) { fail("the default output cannot be opened for recording", hr); break; }
        hr = ac->GetMixFormat(&wf);
        if (FAILED(hr) || !wf) { fail("the format of the default output is not known", hr); break; }
        if (!(is_float(wf) || is_pcm16(wf)) || wf->nChannels < 1 || wf->nSamplesPerSec < 8000) { fail("the format of the default output is not one this build can read", E_FAIL); break; }
        hr = ac->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2000000 /* 200 ms in 100 ns units */, 0, wf, NULL);
        if (FAILED(hr)) { fail("WASAPI refused the loopback of the default output", hr); break; }
        hr = ac->GetService(IID_IAudioCaptureClient, (void **)&cap);
        if (FAILED(hr) || !cap) { fail("the loopback has no capture client", hr); break; }
        hr = ac->Start();
        if (FAILED(hr)) { fail("the loopback did not start", hr); break; }
        started = true;
        InterlockedExchange(&g_state, 1);
        vlb_state st;
        vlb_reset(&st);
        const int ch = wf->nChannels;
        const bool flt = is_float(wf);
        std::vector<float> conv, out;
        while (!g_stop) {
            Sleep(5);
            UINT32 n = 0;
            while (!g_stop && SUCCEEDED(cap->GetNextPacketSize(&n)) && n > 0) {
                BYTE *data = NULL;
                UINT32 frames = 0;
                DWORD flags = 0;
                if (FAILED(cap->GetBuffer(&data, &frames, &flags, NULL, NULL)) || frames == 0) break;
                conv.assign((size_t)frames * ch, 0.0f);
                if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
                    if (flt) {
                        memcpy(conv.data(), data, (size_t)frames * ch * sizeof(float));
                    } else {
                        const short *p = (const short *)data;
                        for (size_t i = 0; i < (size_t)frames * ch; i++) conv[i] = p[i] / 32768.0f;
                    }
                }
                cap->ReleaseBuffer(frames);
                out.resize(((size_t)frames * g_target_rate / wf->nSamplesPerSec + 8) * 2);
                size_t w = vlb_process(&st, conv.data(), frames, ch, wf->nSamplesPerSec, g_target_rate, out.data(), out.size() / 2);
                if (w) vaud_push_sys(out.data(), (unsigned)w);
            }
        }
    } while (0);
    if (!started) InterlockedExchange(&g_state, 2);
    if (ac && started) ac->Stop();
    if (cap) cap->Release();
    if (wf) CoTaskMemFree(wf);
    if (ac) ac->Release();
    if (dev) dev->Release();
    if (en) en->Release();
    if (com) CoUninitialize();
    return NULL;
}
} // namespace

extern "C" int vwl_open(unsigned target_rate, char *name, size_t namen, char *err, size_t errn) {
    if (g_started) return 0;
    g_target_rate = target_rate;
    g_err[0] = 0;
    InterlockedExchange(&g_stop, 0);
    InterlockedExchange(&g_state, 0);
    if (pthread_create(&g_thread, NULL, loop, NULL) != 0) {
        snprintf(err, errn, "the loopback thread could not be started");
        return -1;
    }
    g_started = true;
    for (int i = 0; i < 150 && g_state == 0; i++) Sleep(20); /* up to 3 s */
    if (g_state != 1) {
        InterlockedExchange(&g_stop, 1);
        pthread_join(g_thread, NULL);
        g_started = false;
        snprintf(err, errn, "%s", g_err[0] ? g_err : "the loopback did not start in time");
        return -1;
    }
    snprintf(name, namen, "default output (WASAPI loopback)");
    return 0;
}

extern "C" void vwl_close(void) {
    if (!g_started) return;
    InterlockedExchange(&g_stop, 1);
    pthread_join(g_thread, NULL);
    g_started = false;
}
