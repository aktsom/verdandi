/* audio_asio_probe.c: see audio_asio_probe.h. Windows only (registry, COM). The ASIO interface is written out here as a plain table of functions in the order of Steinberg's IASIO (an ASIO driver is a COM object
 * with this layout); no file of the ASIO SDK is used. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <objbase.h>

#include "audio_asio_probe.h"

#define ASIO_KEY "SOFTWARE\\ASIO"
#define PROBE_MS 10000

typedef struct IAsio IAsio;
typedef struct {
    HRESULT(STDMETHODCALLTYPE *QueryInterface)(IAsio *, REFIID, void **);
    ULONG(STDMETHODCALLTYPE *AddRef)(IAsio *);
    ULONG(STDMETHODCALLTYPE *Release)(IAsio *);
    long(STDMETHODCALLTYPE *init)(IAsio *, void *);
    void(STDMETHODCALLTYPE *getDriverName)(IAsio *, char *);
    long(STDMETHODCALLTYPE *getDriverVersion)(IAsio *);
    void(STDMETHODCALLTYPE *getErrorMessage)(IAsio *, char *);
    long(STDMETHODCALLTYPE *start)(IAsio *);
    long(STDMETHODCALLTYPE *stop)(IAsio *);
    long(STDMETHODCALLTYPE *getChannels)(IAsio *, long *, long *);
    long(STDMETHODCALLTYPE *getLatencies)(IAsio *, long *, long *);
    long(STDMETHODCALLTYPE *getBufferSize)(IAsio *, long *, long *, long *, long *);
    long(STDMETHODCALLTYPE *canSampleRate)(IAsio *, double);
    long(STDMETHODCALLTYPE *getSampleRate)(IAsio *, double *);
    long(STDMETHODCALLTYPE *setSampleRate)(IAsio *, double);
    long(STDMETHODCALLTYPE *getClockSources)(IAsio *, void *, long *);
    long(STDMETHODCALLTYPE *setClockSource)(IAsio *, long);
    long(STDMETHODCALLTYPE *getSamplePosition)(IAsio *, void *, void *);
    long(STDMETHODCALLTYPE *getChannelInfo)(IAsio *, void *);
} IAsioVtbl;
typedef struct { long channel, isInput, isActive, channelGroup, type; char name[32]; } AsioChannelInfo;
struct IAsio { const IAsioVtbl *v; };

static void say(void (*log)(const char *), const char *fmt, ...) __attribute__((format(printf, 2, 3)));
#include <stdarg.h>
static void say(void (*log)(const char *), const char *fmt, ...) {
    if (!log) return;
    char b[700];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    log(b);
}

static int reg_string(HKEY k, const char *value, char *out, size_t n) {
    DWORD type = 0, len = (DWORD)n - 1;
    out[0] = 0;
    if (RegQueryValueExA(k, value, NULL, &type, (LPBYTE)out, &len) != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) return 0;
    out[len < n ? len : n - 1] = 0;
    return out[0] != 0;
}

/* the machine type of a PE file: 0x8664 = 64-bit, 0x14c = 32-bit; 0 = not a PE file / not readable */
static unsigned pe_machine(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char dos[64];
    unsigned machine = 0;
    if (fread(dos, 1, 64, f) == 64 && dos[0] == 'M' && dos[1] == 'Z') {
        unsigned off = (unsigned)dos[0x3c] | ((unsigned)dos[0x3d] << 8) | ((unsigned)dos[0x3e] << 16) | ((unsigned)dos[0x3f] << 24);
        unsigned char pe[6];
        if (fseek(f, (long)off, SEEK_SET) == 0 && fread(pe, 1, 6, f) == 6 && pe[0] == 'P' && pe[1] == 'E') machine = (unsigned)pe[4] | ((unsigned)pe[5] << 8);
    }
    fclose(f);
    return machine;
}

typedef struct {
    va_driver *d;
    HANDLE done;
} probe_job;

static DWORD WINAPI probe_thread(LPVOID arg) {
    probe_job *j = (probe_job *)arg;
    va_driver *d = j->d;
    /* an ASIO driver is an apartment-threaded COM object: the thread that makes it is a single-threaded apartment */
    HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    wchar_t wc[64];
    CLSID clsid;
    MultiByteToWideChar(CP_ACP, 0, d->clsid, -1, wc, 64);
    if (FAILED(CLSIDFromString(wc, &clsid))) {
        d->status = VA_REGISTRY;
        snprintf(d->detail, sizeof d->detail, "the registry entry has no usable class id ('%s')", d->clsid);
    } else {
        IAsio *drv = NULL;
        HRESULT hr = CoCreateInstance(&clsid, NULL, CLSCTX_INPROC_SERVER, &clsid, (void **)&drv);
        if (FAILED(hr) || !drv) {
            if (hr == REGDB_E_CLASSNOTREG) {
                d->status = VA_NO_CLASS;
                snprintf(d->detail, sizeof d->detail, "its class is not registered for a %d-bit program%s", (int)(sizeof(void *) * 8), d->view == 32 ? " (it is a 32-bit driver: only 32-bit programs can use it)" : "");
            } else {
                d->status = VA_CREATE;
                snprintf(d->detail, sizeof d->detail, "Windows could not make the driver (error 0x%08lx): the driver file would not load or its class refused", (unsigned long)hr);
            }
        } else {
            long ok = drv->v->init(drv, GetDesktopWindow());
            if (!ok) {
                char msg[128] = "";
                drv->v->getErrorMessage(drv, msg);
                msg[sizeof msg - 1] = 0;
                d->status = VA_INIT;
                snprintf(d->detail, sizeof d->detail, "the driver refused to start: \"%.120s\" (usually another program has the card: close its audio, or switch the driver's multi-client mode on)", msg[0] ? msg : "no message");
            } else {
                d->status = VA_OK;
                drv->v->getDriverName(drv, d->driver_name);
                d->driver_name[sizeof d->driver_name - 1] = 0;
                d->version = drv->v->getDriverVersion(drv);
                long in = 0, out = 0;
                if (drv->v->getChannels(drv, &in, &out) == 0) d->in_ch = (int)in, d->out_ch = (int)out;
                drv->v->getBufferSize(drv, &d->buf_min, &d->buf_max, &d->buf_pref, &d->buf_gran);
                double r = 0;
                if (drv->v->getSampleRate(drv, &r) == 0) d->rate = r;
                static const double rates[4] = {44100, 48000, 88200, 96000};
                for (int i = 0; i < 4; i++) {
                    if (drv->v->canSampleRate(drv, rates[i]) == 0) d->can_rates |= 1u << i;
                }
                /* the channels' own names (the driver's: "Analog 1", "SPDIF L"), so that a pair can be recognised */
                for (int dir = 1; dir >= 0; dir--) {
                    int count = dir ? d->in_ch : d->out_ch;
                    for (int c = 0; c < count && c < VA_CH; c++) {
                        AsioChannelInfo ci;
                        memset(&ci, 0, sizeof ci);
                        ci.channel = c;
                        ci.isInput = dir;
                        char *to = dir ? d->in_names[c] : d->out_names[c];
                        if (drv->v->getChannelInfo(drv, &ci) == 0) {
                            ci.name[sizeof ci.name - 1] = 0;
                            snprintf(to, 24, "%.23s", ci.name);
                        }
                        if (dir) d->n_in_names = c + 1; else d->n_out_names = c + 1;
                    }
                }
            }
            drv->v->Release(drv);
        }
    }
    if (SUCCEEDED(co)) CoUninitialize();
    SetEvent(j->done);
    return 0;
}

static void already(va_driver *out, int n, const char *name, int *seen_at) {
    *seen_at = -1;
    for (int i = 0; i < n; i++) {
        if (!_stricmp(out[i].name, name)) *seen_at = i;
    }
}

static int probe_impl(va_driver *out, int max, void (*log)(const char *line), const char *only) {
    int n = 0;
    int views[2] = {64, 32};
    for (int vi = 0; vi < 2; vi++) {
        REGSAM wow = views[vi] == 64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
        HKEY root;
        LONG r = RegOpenKeyExA(HKEY_LOCAL_MACHINE, ASIO_KEY, 0, KEY_READ | KEY_ENUMERATE_SUB_KEYS | wow, &root);
        if (r != ERROR_SUCCESS) {
            say(log, "asio: the %d-bit registry has no ASIO drivers (HKLM\\%s: %s)", views[vi], ASIO_KEY, r == ERROR_FILE_NOT_FOUND ? "no such key" : "cannot be read");
            continue;
        }
        char name[128];
        int count = 0;
        for (DWORD i = 0;; i++) {
            DWORD nl = sizeof name;
            if (RegEnumKeyExA(root, i, name, &nl, NULL, NULL, NULL, NULL) != ERROR_SUCCESS) break;
            count++;
            int at;
            already(out, n, name, &at);
            if (at >= 0) {
                say(log, "asio: '%s' is in the %d-bit registry too (the %d-bit entry is used)", name, views[vi], out[at].view);
                continue;
            }
            if (n >= max) continue;
            va_driver *d = &out[n];
            memset(d, 0, sizeof *d);
            snprintf(d->name, sizeof d->name, "%s", name);
            d->view = views[vi];
            HKEY k;
            if (RegOpenKeyExA(root, name, 0, KEY_READ | wow, &k) == ERROR_SUCCESS) {
                reg_string(k, "CLSID", d->clsid, sizeof d->clsid);
                RegCloseKey(k);
            }
            n++;
        }
        say(log, "asio: %d driver(s) in the %d-bit registry (HKLM\\%s)", count, views[vi], ASIO_KEY);
        RegCloseKey(root);
    }
    for (int i = 0; i < n; i++) {
        va_driver *d = &out[i];
        d->status = VA_REGISTRY;
        if (!d->clsid[0]) {
            snprintf(d->detail, sizeof d->detail, "the registry entry has no CLSID value");
            say(log, "asio: driver '%s' (%d-bit registry): %s", d->name, d->view, d->detail);
            continue;
        }
        /* the driver file from the class registration of the same registry view */
        REGSAM wow = d->view == 64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
        char path[200];
        snprintf(path, sizeof path, "SOFTWARE\\Classes\\CLSID\\%s\\InprocServer32", d->clsid);
        HKEY k;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, path, 0, KEY_READ | wow, &k) != ERROR_SUCCESS) {
            snprintf(path, sizeof path, "SOFTWARE\\CLSID\\%s\\InprocServer32", d->clsid);
            if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, path, 0, KEY_READ | wow, &k) != ERROR_SUCCESS) k = NULL;
        }
        char raw[300] = "";
        if (k) {
            reg_string(k, NULL, raw, sizeof raw);
            RegCloseKey(k);
        }
        if (raw[0]) ExpandEnvironmentStringsA(raw, d->file, sizeof d->file);
        if (d->file[0]) {
            if (GetFileAttributesA(d->file) == INVALID_FILE_ATTRIBUTES) {
                d->status = VA_NO_FILE;
                snprintf(d->detail, sizeof d->detail, "the driver file is not there: %s", d->file);
                say(log, "asio: driver '%s' (%d-bit registry): %s", d->name, d->view, d->detail);
                continue;
            }
            unsigned m = pe_machine(d->file);
            if (m == 0x14c && sizeof(void *) == 8) {
                d->status = VA_WRONG_BITS;
                snprintf(d->detail, sizeof d->detail, "the driver file %s is a 32-bit file: a 64-bit program cannot load it (the interface's 64-bit driver is the one to have installed)", d->file);
                say(log, "asio: driver '%s' (%d-bit registry): %s", d->name, d->view, d->detail);
                continue;
            }
        } else {
            say(log, "asio: driver '%s' (%d-bit registry): its class %s has no driver file registered under this view", d->name, d->view, d->clsid);
        }
        if (only && _stricmp(only, d->name) != 0) {
            continue; /* (looking at one driver only: the others are not loaded) */
        }
        /* load it and ask, on a thread of its own with a time limit: a driver that hangs must not hang the program. the thread works on its own copy (heap memory that a stuck thread keeps for good) */
        probe_job *job = (probe_job *)calloc(1, sizeof *job);
        va_driver *copy = (va_driver *)calloc(1, sizeof *copy);
        if (!job || !copy) {
            free(job);
            free(copy);
            continue;
        }
        *copy = *d;
        job->d = copy;
        job->done = CreateEventA(NULL, TRUE, FALSE, NULL);
        HANDLE th = CreateThread(NULL, 0, probe_thread, job, 0, NULL);
        if (!th || WaitForSingleObject(job->done, PROBE_MS) != WAIT_OBJECT_0) {
            d->status = VA_TIMEOUT;
            snprintf(d->detail, sizeof d->detail, "the driver did not answer within %d s", PROBE_MS / 1000);
            if (th) CloseHandle(th); /* (the thread is left: it may be stuck in the driver; its memory is never freed) */
            say(log, "asio: driver '%s' (%d-bit registry, %s): %s", d->name, d->view, d->file[0] ? d->file : "no file", d->detail);
            continue;
        }
        CloseHandle(th);
        CloseHandle(job->done);
        *d = *copy;
        free(copy);
        free(job);
        if (d->status == VA_OK) {
            say(log, "asio: driver '%s' (%d-bit registry, %s): loads and starts; it calls itself '%s' version %ld, %d inputs, %d outputs, buffer %ld to %ld frames (preferred %ld, %s), %.0f Hz", d->name, d->view, d->file[0] ? d->file : "file not named", d->driver_name, d->version, d->in_ch, d->out_ch, d->buf_min, d->buf_max, d->buf_pref,
                d->buf_gran == -1 ? "powers of two" : (d->buf_gran == 0 ? "only that size" : "steps"), d->rate);
        } else {
            say(log, "asio: driver '%s' (%d-bit registry, %s): NOT usable: %s", d->name, d->view, d->file[0] ? d->file : "no file", d->detail);
        }
    }
    if (n == 0) say(log, "asio: no ASIO driver is registered on this PC (neither the 64-bit nor the 32-bit view): install the interface's ASIO driver");
    return n;
}

int va_probe(va_driver *out, int max, void (*log)(const char *line)) { return probe_impl(out, max, log, NULL); }

int va_probe_one(const char *name, va_driver *out) {
    static va_driver all[VA_MAX]; /* (static: it is big; the caller is the one thread of audio_backend_pa.c) */
    memset(out, 0, sizeof *out);
    int n = probe_impl(all, VA_MAX, NULL, name);
    for (int i = 0; i < n; i++) {
        if (!_stricmp(all[i].name, name)) {
            *out = all[i];
            return all[i].status == VA_OK ? 0 : -1;
        }
    }
    out->status = VA_NO_CLASS;
    snprintf(out->detail, sizeof out->detail, "no ASIO driver of this name is registered");
    return -1;
}

void va_summary(const va_driver *d, int n, char *out, size_t outn, int *usable) {
    int ok = 0;
    for (int i = 0; i < n; i++) ok += d[i].status == VA_OK;
    if (usable) *usable = ok;
    if (n == 0) {
        snprintf(out, outn, "no ASIO driver is installed on this PC");
    } else if (ok == 0) {
        snprintf(out, outn, "%d ASIO driver%s found, none can be used: %s: %.140s", n, n == 1 ? "" : "s", d[0].name, d[0].detail);
    } else {
        snprintf(out, outn, "%d ASIO driver%s usable", ok, ok == 1 ? "" : "s");
    }
}
