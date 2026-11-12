// midi_winmm.c: MIDI input and output through WinMM (midiIn*, midiOut*), the API every Windows version has and every driver supports; no administrator rights, no extra install. docs/port/phase-m4.md.
// what it does for the timing: the input callback runs on a thread of the system whose priority is raised once through MMCSS ("Pro Audio"); it hands the bytes to midi_port.cc at once.
// what it cannot do: WinMM ports have ONE client each (with most drivers): a port that another program has open answers MMSYSERR_ALLOCATED. that is reported as "busy" so the DEVICES page can say so.
#include <windows.h>
#include <mmsystem.h>
/* dbt.h is not used: its far pointers do not compile next to the macros of compat_win.h; these are its values */
#define DBT_DEVNODES_CHANGED 0x0007
#define DBT_DEVICEARRIVAL 0x8000
#define DBT_DEVICEREMOVECOMPLETE 0x8004
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "midi_winmm.h"

#define SYSEX_BUFS 4
#define SYSEX_SIZE 4096

static void utf8(const wchar_t *w, char *out, size_t n) {
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)n, NULL, NULL) <= 0) {
        out[0] = 0;
    }
}

static int wm_list(int input, char names[][64], int max) {
    UINT n = input ? midiInGetNumDevs() : midiOutGetNumDevs();
    int k = 0;
    for (UINT i = 0; i < n && k < max; i++) {
        if (input) {
            MIDIINCAPSW c;
            if (midiInGetDevCapsW(i, &c, sizeof c) != MMSYSERR_NOERROR) {
                names[k][0] = 0;
            } else {
                utf8(c.szPname, names[k], 64);
            }
        } else {
            MIDIOUTCAPSW c;
            if (midiOutGetDevCapsW(i, &c, sizeof c) != MMSYSERR_NOERROR) {
                names[k][0] = 0;
            } else {
                utf8(c.szPname, names[k], 64);
            }
        }
        k++;
    }
    return k;
}

static double wm_now_us(void) {
    static LARGE_INTEGER f;
    LARGE_INTEGER c;
    if (f.QuadPart == 0) {
        QueryPerformanceFrequency(&f);
    }
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1e6 / (double)f.QuadPart;
}

/* ---------------------------------------------------------------- input */
typedef struct {
    HMIDIIN h;
    vmidi_rx_fn rx;
    void *user;
    MIDIHDR hdr[SYSEX_BUFS];
    char *buf[SYSEX_BUFS];
    volatile LONG closing;
} win_in;

static __declspec(thread) int mmcss_done;

/* the calling thread joins MMCSS as "Pro Audio" (the scheduler class for audio and MIDI timing threads). avrt.dll is loaded when needed, as the audio code does. 1 = registered */
int vmidi_mmcss_enter(void) {
    typedef HANDLE(WINAPI * SetFn)(LPCSTR, LPDWORD);
    static SetFn set;
    static int tried;
    if (!tried) {
        tried = 1;
        HMODULE av = LoadLibraryA("avrt.dll");
        set = av ? (SetFn)GetProcAddress(av, "AvSetMmThreadCharacteristicsA") : NULL;
    }
    DWORD task = 0;
    return set && set("Pro Audio", &task) != NULL;
}

static void raise_callback_thread(void) {
    if (!mmcss_done) {
        mmcss_done = 1;
        vmidi_mmcss_enter();
    }
}

static int short_len(uint8_t status) {
    if (status >= 0xf8) return 1;
    switch (status & 0xf0) {
    case 0x80: case 0x90: case 0xa0: case 0xb0: case 0xe0: return 3;
    case 0xc0: case 0xd0: return 2;
    }
    switch (status) {
    case 0xf1: case 0xf3: return 2;
    case 0xf2: return 3;
    case 0xf6: return 1;
    }
    return 1;
}

static void CALLBACK in_proc(HMIDIIN h, UINT msg, DWORD_PTR inst, DWORD_PTR p1, DWORD_PTR p2) {
    win_in *w = (win_in *)inst;
    (void)p2;
    if (!w) return;
    if (msg == MIM_DATA || msg == MIM_MOREDATA) {
        raise_callback_thread();
        uint8_t d[3] = {(uint8_t)(p1 & 0xff), (uint8_t)((p1 >> 8) & 0xff), (uint8_t)((p1 >> 16) & 0xff)};
        w->rx(w->user, d, (size_t)short_len(d[0]));
    } else if (msg == MIM_LONGDATA) {
        MIDIHDR *hdr = (MIDIHDR *)p1;
        if (hdr->dwBytesRecorded > 0) {
            w->rx(w->user, (const uint8_t *)hdr->lpData, hdr->dwBytesRecorded);
        }
        if (!InterlockedCompareExchange(&w->closing, 0, 0) && hdr->dwBytesRecorded > 0) {
            midiInAddBuffer(h, hdr, sizeof *hdr); /* as RtMidi does */
        }
    }
}

static void *wm_open_in(int index, vmidi_rx_fn rx, void *user, char *err, size_t en, int *busy) {
    win_in *w = (win_in *)calloc(1, sizeof *w);
    if (!w) return NULL;
    w->rx = rx;
    w->user = user;
    MMRESULT r = midiInOpen(&w->h, (UINT)index, (DWORD_PTR)in_proc, (DWORD_PTR)w, CALLBACK_FUNCTION);
    if (r != MMSYSERR_NOERROR) {
        if (r == MMSYSERR_ALLOCATED) {
            *busy = 1;
        }
        char t[MAXERRORLENGTH] = "";
        midiInGetErrorTextA(r, t, sizeof t);
        snprintf(err, en, "%s", t);
        free(w);
        return NULL;
    }
    for (int i = 0; i < SYSEX_BUFS; i++) {
        w->buf[i] = (char *)calloc(1, SYSEX_SIZE);
        w->hdr[i].lpData = w->buf[i];
        w->hdr[i].dwBufferLength = SYSEX_SIZE;
        midiInPrepareHeader(w->h, &w->hdr[i], sizeof w->hdr[i]);
        midiInAddBuffer(w->h, &w->hdr[i], sizeof w->hdr[i]);
    }
    midiInStart(w->h);
    return w;
}

static void wm_close_in(void *h) {
    win_in *w = (win_in *)h;
    if (!w) return;
    InterlockedExchange(&w->closing, 1);
    midiInStop(w->h);
    midiInReset(w->h);
    for (int i = 0; i < SYSEX_BUFS; i++) {
        midiInUnprepareHeader(w->h, &w->hdr[i], sizeof w->hdr[i]);
        free(w->buf[i]);
    }
    midiInClose(w->h);
    free(w);
}

/* ---------------------------------------------------------------- output */
typedef struct {
    HMIDIOUT h;
    CRITICAL_SECTION cs;
} win_out;

static void *wm_open_out(int index, char *err, size_t en, int *busy) {
    win_out *w = (win_out *)calloc(1, sizeof *w);
    if (!w) return NULL;
    MMRESULT r = midiOutOpen(&w->h, (UINT)index, 0, 0, CALLBACK_NULL);
    if (r != MMSYSERR_NOERROR) {
        if (r == MMSYSERR_ALLOCATED) {
            *busy = 1;
        }
        char t[MAXERRORLENGTH] = "";
        midiOutGetErrorTextA(r, t, sizeof t);
        snprintf(err, en, "%s", t);
        free(w);
        return NULL;
    }
    InitializeCriticalSection(&w->cs);
    return w;
}

static int wm_send(void *h, const uint8_t *d, size_t n) {
    win_out *w = (win_out *)h;
    size_t i = 0;
    EnterCriticalSection(&w->cs);
    while (i < n) {
        uint8_t st = d[i];
        if (st < 0x80) { /* data without a status: nothing to run on */
            i++;
            continue;
        }
        if (st == 0xf0) {
            size_t e = i + 1;
            while (e < n && d[e] != 0xf7) e++;
            size_t len = (e < n ? e + 1 : n) - i;
            MIDIHDR hdr;
            memset(&hdr, 0, sizeof hdr);
            hdr.lpData = (LPSTR)(d + i);
            hdr.dwBufferLength = (DWORD)len;
            if (midiOutPrepareHeader(w->h, &hdr, sizeof hdr) == MMSYSERR_NOERROR) {
                if (midiOutLongMsg(w->h, &hdr, sizeof hdr) == MMSYSERR_NOERROR) {
                    for (int t = 0; t < 500 && !(hdr.dwFlags & MHDR_DONE); t++) Sleep(1);
                }
                midiOutUnprepareHeader(w->h, &hdr, sizeof hdr);
            }
            i += len;
            continue;
        }
        int len = short_len(st);
        if (i + (size_t)len > n) len = (int)(n - i);
        DWORD msg = st;
        if (len > 1) msg |= (DWORD)d[i + 1] << 8;
        if (len > 2) msg |= (DWORD)d[i + 2] << 16;
        midiOutShortMsg(w->h, msg);
        i += (size_t)len;
    }
    LeaveCriticalSection(&w->cs);
    return (int)n;
}

static void wm_close_out(void *h) {
    win_out *w = (win_out *)h;
    if (!w) return;
    midiOutReset(w->h);
    midiOutClose(w->h);
    DeleteCriticalSection(&w->cs);
    free(w);
}

const vmidi_backend vmidi_winmm_backend = {"WinMM", wm_list, wm_open_in, wm_close_in, wm_open_out, wm_send, wm_close_out, wm_now_us};

/* ---------------------------------------------------------------- hot-plug notification */
static HWND watch_hwnd;
static HANDLE watch_thread;
static void (*watch_poke)(void);

static LRESULT CALLBACK watch_proc(HWND h, UINT m, WPARAM wp, LPARAM lp) {
    if (m == WM_DEVICECHANGE && (wp == DBT_DEVNODES_CHANGED || wp == DBT_DEVICEARRIVAL || wp == DBT_DEVICEREMOVECOMPLETE)) {
        if (watch_poke) watch_poke();
        return TRUE;
    }
    if (m == WM_DESTROY) {
        PostQuitMessage(0);
    }
    return DefWindowProcW(h, m, wp, lp);
}

static DWORD WINAPI watch_run(LPVOID ready) {
    WNDCLASSW wc;
    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = watch_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"VerdandiMidiWatch";
    RegisterClassW(&wc);
    /* a hidden top-level window (message-only windows do not get WM_DEVICECHANGE) */
    watch_hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"", WS_POPUP, 0, 0, 0, 0, NULL, NULL, wc.hInstance, NULL);
    SetEvent((HANDLE)ready);
    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}

int vmidi_winmm_watch(void (*poke)(void)) {
    if (watch_thread) return 0;
    watch_poke = poke;
    HANDLE ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    watch_thread = CreateThread(NULL, 0, watch_run, ready, 0, NULL);
    if (!watch_thread) {
        CloseHandle(ready);
        return -1;
    }
    WaitForSingleObject(ready, 2000);
    CloseHandle(ready);
    return watch_hwnd ? 0 : -1;
}

void vmidi_winmm_watch_stop(void) {
    if (watch_hwnd) PostMessageW(watch_hwnd, WM_CLOSE, 0, 0);
    watch_hwnd = NULL;
}
