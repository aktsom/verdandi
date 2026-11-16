/*
 * windows/ci/asio_stub.c: a STUB ASIO driver for the CI and the tests (not shipped). It is a real in-process COM server, as every ASIO driver is: a class factory, a class with the ASIO interface (the same
 * order of functions as Steinberg's IASIO, written out by hand here: no SDK file is used), 4 inputs and 4 outputs of 32-bit float, buffer sizes 64 to 2048 (preferred 256, powers of two), 48000 Hz, and a thread that calls
 * the host's bufferSwitch at the pace of the buffer. what it does is chosen by the environment variable VERDANDI_STUB_ASIO of the program that loads it:
 *   (not set)    works                 busy   init fails ("the device is in use by another program", as a driver that Ableton has does)       broken   the class cannot be made   slow   init takes 3 s
 *   nostart      init and open work, ASIOStart fails (a driver in a bad state, or another program took the card in between)
 * windows/ci/register_asio_stub.sh registers it (HKLM\SOFTWARE\ASIO\Verdandi Test ASIO and its CLSID), the CI removes it again.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

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
};

static volatile LONG g_locks;
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
    d->err[0] = 0;
    return 1;
}
static void STDMETHODCALLTYPE d_name(Driver *d, char *n) { (void)d; strcpy(n, "Verdandi Test ASIO"); }
static long STDMETHODCALLTYPE d_version(Driver *d) { (void)d; return 1; }
static void STDMETHODCALLTYPE d_errmsg(Driver *d, char *s) { snprintf(s, 124, "%s", d->err[0] ? d->err : "no error"); }
static DWORD WINAPI pump(LPVOID arg) {
    Driver *d = (Driver *)arg;
    long index = 0;
    DWORD ms = (DWORD)(d->buffer_size * 1000.0 / 48000.0 + 0.5);
    if (ms < 1) ms = 1;
    while (d->running) {
        Sleep(ms);
        if (!d->running) break;
        d->position += d->buffer_size;
        d->cb->bufferSwitch(index, 1);
        index ^= 1;
    }
    return 0;
}
static long STDMETHODCALLTYPE d_start(Driver *d) {
    if (!d->cb) return ASE_NotPresent;
    if (!strcmp(mode(), "nostart")) return -999; /* ASE_HWMalfunction: opens, but will not run */
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
    }
    return ASE_OK;
}
static long STDMETHODCALLTYPE d_channels(Driver *d, long *i, long *o) { (void)d; *i = 4; *o = 4; return ASE_OK; }
static long STDMETHODCALLTYPE d_latencies(Driver *d, long *i, long *o) { (void)d; *i = 256; *o = 256; return ASE_OK; }
static long STDMETHODCALLTYPE d_bufsize(Driver *d, long *mn, long *mx, long *pref, long *gran) { (void)d; *mn = 64; *mx = 2048; *pref = 256; *gran = -1; return ASE_OK; }
static long STDMETHODCALLTYPE d_can(Driver *d, double r) { (void)d; return (r == 48000.0 || r == 44100.0) ? ASE_OK : ASE_NoClock; }
static long STDMETHODCALLTYPE d_getrate(Driver *d, double *r) { (void)d; *r = 48000.0; return ASE_OK; }
static long STDMETHODCALLTYPE d_setrate(Driver *d, double r) { return d_can(d, r); }
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
    snprintf(c->name, sizeof c->name, "%s %ld", c->isInput ? "In" : "Out", c->channel + 1);
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
