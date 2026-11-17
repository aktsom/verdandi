/*
 * windows/ci/asio_stub.c: a STUB ASIO driver for the CI and the tests (not shipped). It is a real in-process COM server, as every ASIO driver is: a class factory, a class with the ASIO interface (the same
 * order of functions as Steinberg's IASIO, written out by hand here: no SDK file is used), 4 inputs and 4 outputs of 32-bit float, buffer sizes 64 to 2048 (preferred 256, powers of two), 48000 Hz, and a thread that calls
 * the host's bufferSwitch at the pace of the buffer. what it does is chosen by the environment variable VERDANDI_STUB_ASIO of the program that loads it:
 *   (not set)    works                 busy   init fails ("the device is in use by another program", as a driver that Ableton has does)       broken   the class cannot be made   slow   init takes 3 s
 *   nostart      init and open work, ASIOStart fails (a driver in a bad state, or another program took the card in between)
 *   single       one client at a time: init fails while another instance of the driver (in this process) is still loaded: a program that leaves the driver loaded finds it "in use" when it opens it again (M20)
 * more of the environment (M20): VERDANDI_STUB_RATE the card's clock when the driver is first loaded (44100 or 48000, default 48000); VERDANDI_STUB_HOLD another program has the card: "refuse" (ASIOSetSampleRate says no)
 * or "silent" (it says yes and changes nothing); VERDANDI_STUB_REAL the rate the card REALLY runs at, when it is not the one it reports (a driver that lies: for the mismatch warning); VERDANDI_STUB_LOG a file that gets one
 * line for every create / set_rate / init / release / start / stop the driver sees ("stop peak=... callbacks=... size=..." says how loud the host's output was: sound or silence); VERDANDI_STUB_BUFMAX the
 * largest buffer it offers (default 2048); VERDANDI_STUB_CTL a file that can be made and removed WHILE the program runs: if it contains "ratefail" the driver cannot say which rate the card runs at (ASIOGetSampleRate fails). its channels are called Analog 1, Analog 2, SPDIF L, SPDIF R (as an interface names them).
 * windows/ci/register_asio_stub.sh registers it (HKLM\SOFTWARE\ASIO\Verdandi Test ASIO and its CLSID), the CI removes it again.
 */
#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>

static const GUID CLSID_STUB = {0xd9b1e8e3, 0x6f1c, 0x4d6a, {0x9c, 0x57, 0x7c, 0x1a, 0x3f, 0x7b, 0x5e, 0x01}};

#define ASE_OK 0
#define ASE_NotPresent (-1000)
#define ASE_InvalidParameter (-998)
#define ASE_NoClock (-995)
#define ASE_SPNotAdvancing (-996)
#define ASIOSTFloat32LSB 19

typedef struct { long channel; long isInput; long isActive; long channelGroup; long type; char name[32]; } ChannelInfo;
typedef struct { long isInput; long channelNum; void *buffers[2]; } BufferInfo;
typedef struct { void (*bufferSwitch)(long index, long directProcess); void (*sampleRateDidChange)(double); long (*asioMessage)(long, long, void *, double *); void *(*bufferSwitchTimeInfo)(void *, long, long); } Callbacks;

typedef struct Driver Driver;
typedef struct {
    HRESULT(STDMETHODCALLTYPE *QueryInterface)(Driver *, REFIID, void **);
    ULONG(STDMETHODCALLTYPE *AddRef)(Driver *);
    ULONG(STDMETHODCALLTYPE *Release)(Driver *);
    long(STDMETHODCALLTYPE *init)(Driver *, void *);
    void(STDMETHODCALLTYPE *getDriverName)(Driver *, char *);
    long(STDMETHODCALLTYPE *getDriverVersion)(Driver *);
    void(STDMETHODCALLTYPE *getErrorMessage)(Driver *, char *);
    long(STDMETHODCALLTYPE *start)(Driver *);
    long(STDMETHODCALLTYPE *stop)(Driver *);
    long(STDMETHODCALLTYPE *getChannels)(Driver *, long *, long *);
    long(STDMETHODCALLTYPE *getLatencies)(Driver *, long *, long *);
    long(STDMETHODCALLTYPE *getBufferSize)(Driver *, long *, long *, long *, long *);
    long(STDMETHODCALLTYPE *canSampleRate)(Driver *, double);
    long(STDMETHODCALLTYPE *getSampleRate)(Driver *, double *);
    long(STDMETHODCALLTYPE *setSampleRate)(Driver *, double);
    long(STDMETHODCALLTYPE *getClockSources)(Driver *, void *, long *);
    long(STDMETHODCALLTYPE *setClockSource)(Driver *, long);
    long(STDMETHODCALLTYPE *getSamplePosition)(Driver *, void *, void *);
    long(STDMETHODCALLTYPE *getChannelInfo)(Driver *, ChannelInfo *);
    long(STDMETHODCALLTYPE *createBuffers)(Driver *, BufferInfo *, long, long, Callbacks *);
    long(STDMETHODCALLTYPE *disposeBuffers)(Driver *);
    long(STDMETHODCALLTYPE *controlPanel)(Driver *);
    long(STDMETHODCALLTYPE *future)(Driver *, long, void *);
    long(STDMETHODCALLTYPE *outputReady)(Driver *);
} Vtbl;

struct Driver {
    const Vtbl *v;
    volatile LONG refs;
    char err[128];
    long buffer_size;
    Callbacks *cb;
    void *bufs[8][2];
    int nbufs;
    volatile LONG running;
    HANDLE thread;
    volatile LONG64 position;
    int inited;
    int isin[8];
    double peak;
    long callbacks;
};

static volatile LONG g_locks;
static volatile LONG g_inited;       /* instances that did init and were not released */
static double g_rate = 0;            /* the card's clock (0 = not read from the environment yet) */
static const char *env(const char *name) {
    static char b[8][64];
    static int k;
    char *m = b[k++ & 7];
    DWORD n = GetEnvironmentVariableA(name, m, 64);
    return n > 0 && n < 64 ? m : "";
}
static void logev(const char *fmt, ...) {
    const char *path = env("VERDANDI_STUB_LOG");
    if (!path[0]) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}
static double card_rate(void) {
    if (g_rate == 0) {
        const char *r = env("VERDANDI_STUB_RATE");
        g_rate = r[0] ? atof(r) : 48000.0;
    }
    return g_rate;
}
static const char *mode(void) {
    static char m[32];
    DWORD n = GetEnvironmentVariableA("VERDANDI_STUB_ASIO", m, sizeof m);
    return n > 0 && n < sizeof m ? m : "";
}

static HRESULT STDMETHODCALLTYPE d_qi(Driver *d, REFIID riid, void **out) {
    if (IsEqualGUID(riid, &CLSID_STUB) || IsEqualGUID(riid, &IID_IUnknown)) {
        *out = d;
        InterlockedIncrement(&d->refs);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE d_addref(Driver *d) { return (ULONG)InterlockedIncrement(&d->refs); }
static ULONG STDMETHODCALLTYPE d_release(Driver *d) {
    LONG r = InterlockedDecrement(&d->refs);
    if (r == 0) {
        d->v->stop(d);
        d->v->disposeBuffers(d);
        if (d->inited) InterlockedDecrement(&g_inited);
        logev("release");
        InterlockedDecrement(&g_locks);
        HeapFree(GetProcessHeap(), 0, d);
    }
    return (ULONG)r;
}
static long STDMETHODCALLTYPE d_init(Driver *d, void *sys) {
    (void)sys;
    if (!strcmp(mode(), "busy")) {
        snprintf(d->err, sizeof d->err, "Verdandi Test ASIO: the device is in use by another program");
        return 0;
    }
    if (!strcmp(mode(), "slow")) {
        Sleep(3000);
    }
    if (!strcmp(mode(), "single") && g_inited > 0) {
        snprintf(d->err, sizeof d->err, "Verdandi Test ASIO: the driver is already in use (by this program: it was not released)");
        logev("init refused: in use");
        return 0;
    }
    InterlockedIncrement(&g_inited);
    d->inited = 1;
    logev("init");
    d->err[0] = 0;
    return 1;
}
static void STDMETHODCALLTYPE d_name(Driver *d, char *n) { (void)d; strcpy(n, "Verdandi Test ASIO"); }
static long STDMETHODCALLTYPE d_version(Driver *d) { (void)d; return 1; }
static void STDMETHODCALLTYPE d_errmsg(Driver *d, char *s) { snprintf(s, 124, "%s", d->err[0] ? d->err : "no error"); }
static DWORD WINAPI pump(LPVOID arg) {
    /* the card's clock: buffer after buffer, each at its time by the PC's clock (not Sleep(n) after Sleep(n): that drifts by whole milliseconds), at the rate the card REALLY runs at */
    Driver *d = (Driver *)arg;
    long index = 0;
    const char *real = env("VERDANDI_STUB_REAL");
    double rate = real[0] ? atof(real) : card_rate();
    LARGE_INTEGER f, t0, now;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t0);
    double n = 0;
    while (d->running) {
        n += 1;
        double due = n * d->buffer_size / rate; /* seconds since the start */
        for (;;) {
            QueryPerformanceCounter(&now);
            double t = (double)(now.QuadPart - t0.QuadPart) / (double)f.QuadPart;
            if (t >= due || !d->running) break;
            DWORD ms = (DWORD)((due - t) * 1000.0);
            Sleep(ms > 1 ? ms - 1 : 0);
        }
        if (!d->running) break;
        d->position += d->buffer_size;
        d->cb->bufferSwitch(index, 1);
        /* what the host put in the first output buffer it was given: the loudest sample, for the test that asks "sound or silence" */
        for (int c = 0; c < d->nbufs; c++) {
            if (!d->isin[c] && d->bufs[c][index]) {
                const float *o = (const float *)d->bufs[c][index];
                for (long k = 0; k < d->buffer_size; k++) {
                    double a = o[k] < 0 ? -o[k] : o[k];
                    if (a > d->peak) d->peak = a;
                }
                break;
            }
        }
        d->callbacks++;
        index ^= 1;
    }
    return 0;
}
static long STDMETHODCALLTYPE d_start(Driver *d) {
    if (!d->cb) return ASE_NotPresent;
    if (!strcmp(mode(), "nostart")) return -999; /* ASE_HWMalfunction: opens, but will not run */
    logev("start");
    timeBeginPeriod(1);
    d->running = 1;
    d->thread = CreateThread(NULL, 0, pump, d, 0, NULL);
    return d->thread ? ASE_OK : ASE_NotPresent;
}
static long STDMETHODCALLTYPE d_stop(Driver *d) {
    if (d->running) {
        d->running = 0;
        WaitForSingleObject(d->thread, 2000);
        CloseHandle(d->thread);
        d->thread = NULL;
        timeEndPeriod(1);
        logev("stop peak=%.4f callbacks=%ld size=%ld", d->peak, d->callbacks, d->buffer_size);
        d->peak = 0;
        d->callbacks = 0;
    }
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_channels(Driver *d, long *i, long *o) { (void)d; *i = 4; *o = 4; return ASE_OK; }
static long STDMETHODCALLTYPE d_latencies(Driver *d, long *i, long *o) { (void)d; *i = 256; *o = 256; return ASE_OK; }
static long STDMETHODCALLTYPE d_bufsize(Driver *d, long *mn, long *mx, long *pref, long *gran) { (void)d; *mn = 64; *mx = env("VERDANDI_STUB_BUFMAX")[0] ? atol(env("VERDANDI_STUB_BUFMAX")) : 2048; *pref = 256; *gran = -1; return ASE_OK; }
static long STDMETHODCALLTYPE d_can(Driver *d, double r) { (void)d; return (r == 48000.0 || r == 44100.0) ? ASE_OK : ASE_NoClock; }
static int ctl_has(const char *word) {
    const char *path = env("VERDANDI_STUB_CTL");
    if (!path[0]) return 0;
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    char b[64] = "";
    size_t n = fread(b, 1, sizeof b - 1, f);
    b[n] = 0;
    fclose(f);
    return strstr(b, word) != NULL;
}
static long STDMETHODCALLTYPE d_getrate(Driver *d, double *r) {
    (void)d;
    logev("getrate");
    if (ctl_has("ratefail")) return ASE_NotPresent; /* the driver cannot say which rate the card runs at */
    *r = card_rate();
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_setrate(Driver *d, double r) {
    logev("set_rate %.0f", r);
    if (r == card_rate()) return ASE_OK;
    if (d_can(d, r) != ASE_OK) return ASE_NoClock;
    const char *h = env("VERDANDI_STUB_HOLD");
    if (!strcmp(h, "refuse")) return ASE_NoClock; /* another program has the card at its rate: the driver says no */
    if (!strcmp(h, "silent")) return ASE_OK;      /* ... or says yes and changes nothing */
    g_rate = r;
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_clocksrc(Driver *d, void *c, long *n) {
    (void)d;
    if (c) {
        struct { long index, channel, group; long current; char name[32]; } *cs = c;
        cs[0].index = 0; cs[0].channel = -1; cs[0].group = -1; cs[0].current = 1; strcpy(cs[0].name, "Internal");
    }
    *n = 1;
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_setclock(Driver *d, long r) { (void)d; return r == 0 ? ASE_OK : ASE_InvalidParameter; }
static long STDMETHODCALLTYPE d_pos(Driver *d, void *sp, void *ts) {
    struct { unsigned long hi, lo; } *s = sp, *t = ts;
    LONG64 p = d->position;
    s->hi = (unsigned long)(p >> 32); s->lo = (unsigned long)(p & 0xffffffff);
    LONG64 ns = (LONG64)GetTickCount64() * 1000000LL;
    t->hi = (unsigned long)(ns >> 32); t->lo = (unsigned long)(ns & 0xffffffff);
    return d->running ? ASE_OK : ASE_SPNotAdvancing;
}
static long STDMETHODCALLTYPE d_chinfo(Driver *d, ChannelInfo *c) {
    (void)d;
    if (c->channel < 0 || c->channel > 3) return ASE_InvalidParameter;
    c->isActive = 0; c->channelGroup = 0; c->type = ASIOSTFloat32LSB;
    static const char *const nm[4] = {"Analog 1", "Analog 2", "SPDIF L", "SPDIF R"};
    snprintf(c->name, sizeof c->name, "%s", nm[c->channel]);
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_create(Driver *d, BufferInfo *b, long n, long size, Callbacks *cb) {
    if (n > 8) return ASE_InvalidParameter;
    d->v->disposeBuffers(d);
    for (long i = 0; i < n; i++) {
        for (int k = 0; k < 2; k++) {
            d->bufs[i][k] = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (SIZE_T)size * 4);
            b[i].buffers[k] = d->bufs[i][k];
        }
        d->isin[i] = (int)b[i].isInput;
    }
    d->nbufs = (int)n;
    d->buffer_size = size;
    d->cb = cb;
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_dispose(Driver *d) {
    for (int i = 0; i < d->nbufs; i++) for (int k = 0; k < 2; k++) if (d->bufs[i][k]) { HeapFree(GetProcessHeap(), 0, d->bufs[i][k]); d->bufs[i][k] = NULL; }
    d->nbufs = 0;
    d->cb = NULL;
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_panel(Driver *d) { (void)d; return ASE_OK; }
static long STDMETHODCALLTYPE d_future(Driver *d, long s, void *o) { (void)d, (void)s, (void)o; return ASE_NotPresent; }
static long STDMETHODCALLTYPE d_outready(Driver *d) { (void)d; return ASE_NotPresent; }

static const Vtbl VT = {d_qi, d_addref, d_release, d_init, d_name, d_version, d_errmsg, d_start, d_stop, d_channels, d_latencies, d_bufsize, d_can, d_getrate, d_setrate, d_clocksrc, d_setclock, d_pos, d_chinfo, d_create, d_dispose, d_panel, d_future, d_outready};

/* ---- the class factory ---- */
typedef struct { const IClassFactoryVtbl *v; } Factory;
static HRESULT STDMETHODCALLTYPE f_qi(IClassFactory *f, REFIID r, void **o) {
    if (IsEqualGUID(r, &IID_IUnknown) || IsEqualGUID(r, &IID_IClassFactory)) { *o = f; return S_OK; }
    *o = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE f_addref(IClassFactory *f) { (void)f; return 2; }
static ULONG STDMETHODCALLTYPE f_release(IClassFactory *f) { (void)f; return 1; }
static HRESULT STDMETHODCALLTYPE f_create(IClassFactory *f, IUnknown *outer, REFIID riid, void **out) {
    (void)f;
    *out = NULL;
    if (outer) return CLASS_E_NOAGGREGATION;
    if (!strcmp(mode(), "broken")) return E_FAIL;
    Driver *d = (Driver *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof *d);
    if (!d) return E_OUTOFMEMORY;
    logev("create");
    d->v = &VT;
    d->refs = 1;
    InterlockedIncrement(&g_locks);
    HRESULT hr = d->v->QueryInterface(d, riid, out);
    d->v->Release(d);
    return hr;
}
static HRESULT STDMETHODCALLTYPE f_lock(IClassFactory *f, BOOL l) { (void)f; if (l) InterlockedIncrement(&g_locks); else InterlockedDecrement(&g_locks); return S_OK; }
static const IClassFactoryVtbl FV = {f_qi, f_addref, f_release, f_create, f_lock};
static Factory FACTORY = {&FV};

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **out) {
    if (!IsEqualGUID(clsid, &CLSID_STUB)) { *out = NULL; return CLASS_E_CLASSNOTAVAILABLE; }
    return f_qi((IClassFactory *)&FACTORY, riid, out);
}
STDAPI DllCanUnloadNow(void) { return g_locks == 0 ? S_OK : S_FALSE; }
