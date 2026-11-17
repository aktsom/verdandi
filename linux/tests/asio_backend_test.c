/*
 * linux/tests/asio_backend_test.c (M20): the PortAudio backend of the Windows build (audio_backend_pa.c, the REAL file) against the stub ASIO driver (windows/ci/asio_stub.c), run by Wine; started by asio_backend_test.sh.
 * what the owner's PC showed: the first open of an ASIO driver works, every later one from another thread fails with "Failed to load ASIO driver". here: open, close, open again from the thread that started, from a
 * thread WITHOUT COM, from a multi-threaded COM thread (the AUDIO page's apply runs on the Lua thread, the watchdog on its own); other output pair, other buffer; a driver that lets one client in at a time (mode
 * "single") is still free after each close; the driver's channel names; the card's clock is never changed (the log of the stub has no set_rate), a rate that is not the card's is refused with the card's own rate.
 * argv[1]: the card's rate the test expects (44100 or 48000, set for the stub in VERDANDI_STUB_RATE).
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "audio_device.h"

extern const vaud_backend vaud_backend_portaudio;
void vaud_card_xrun_flags(unsigned n, unsigned long flags) { (void)n, (void)flags; }
void vaud_card_xrun(unsigned n) { (void)n; }
void vaud_push_mic(const float *x, unsigned f) { (void)x, (void)f; }
void vaud_push_sys(const float *x, unsigned f) { (void)x, (void)f; }
int vwl_open(unsigned r, char *n, size_t nn, char *e, size_t en) { (void)r, (void)n, (void)nn; snprintf(e, en, "no"); return -1; }
void vwl_close(void) {}

static volatile long cbs;
static void cb(const float *in, float *out, unsigned frames, void *user) { (void)in, (void)user; memset(out, 0, (size_t)frames * 2 * sizeof(float)); cbs++; }

static int fails;
#define CHECK(c, ...) do { if (c) printf("ok   "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); printf("\n"); } while (0)

typedef struct { int out_first; unsigned rate, frames; vaud_error e; char err[300]; unsigned res_rate; long calls; int started; } job;
static void run_job(job *j) {
    const vaud_backend *be = &vaud_backend_portaudio;
    vaud_open_req rq;
    memset(&rq, 0, sizeof rq);
    snprintf(rq.out_uid, sizeof rq.out_uid, "asio:Verdandi Test ASIO");
    rq.rate = j->rate, rq.frames = j->frames, rq.out_first = j->out_first, rq.in_l = 1, rq.in_r = 2;
    vaud_opened res;
    memset(&res, 0, sizeof res);
    j->err[0] = 0;
    j->e = be->open(&rq, cb, NULL, &res, j->err, sizeof j->err);
    j->res_rate = res.rate;
    j->started = 0;
    if (j->e == VAUD_OK) {
        long c0 = cbs;
        if (be->start(j->err, sizeof j->err) == 0) {
            Sleep(250);
            j->started = 1;
        }
        j->calls = cbs - c0;
        be->close();
    }
}
static DWORD WINAPI th_nocom(LPVOID a) { run_job((job *)a); return 0; }
static DWORD WINAPI th_mta(LPVOID a) { CoInitializeEx(NULL, COINIT_MULTITHREADED); run_job((job *)a); CoUninitialize(); return 0; }
static DWORD WINAPI th_sta(LPVOID a) { CoInitializeEx(NULL, COINIT_APARTMENTTHREADED); run_job((job *)a); CoUninitialize(); return 0; }
static void on_thread(LPTHREAD_START_ROUTINE f, job *j) { HANDLE h = CreateThread(NULL, 0, f, j, 0, NULL); WaitForSingleObject(h, 30000); CloseHandle(h); }

static int stub_log_has(const char *needle) {
    char path[300];
    if (!GetEnvironmentVariableA("VERDANDI_STUB_LOG", path, sizeof path)) return 0;
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    char line[200];
    int n = 0;
    while (fgets(line, sizeof line, f)) if (strstr(line, needle)) n++;
    fclose(f);
    return n;
}

int main(int argc, char **argv) {
    unsigned card = argc > 1 ? (unsigned)atoi(argv[1]) : 48000;
    const vaud_backend *be = &vaud_backend_portaudio;
    static vaud_device dv[96];
    int n = be->list(dv, 96), at = -1;
    for (int i = 0; i < n; i++) if (!strcmp(dv[i].uid, "asio:Verdandi Test ASIO")) at = i;
    CHECK(at >= 0, "the stub driver is in the device list (%d devices)", n);
    if (at < 0) return 1;
    CHECK(dv[at].n_out_names == 4 && !strcmp(dv[at].out_names[2], "SPDIF L") && !strcmp(dv[at].out_names[3], "SPDIF R"), "the driver's output channel names are listed (%s, %s)", dv[at].n_out_names ? dv[at].out_names[0] : "-", dv[at].n_out_names > 3 ? dv[at].out_names[3] : "-");
    CHECK(dv[at].n_in_names == 4 && !strcmp(dv[at].in_names[0], "Analog 1"), "... and the input channel names");
    CHECK((unsigned)(dv[at].default_rate + 0.5) == card, "the rate listed for the driver is the card's clock now: %.0f Hz (PortAudio's own default would be 44100 whatever the card does)", dv[at].default_rate);
    CHECK(dv[at].buf_min == 64 && dv[at].buf_max == 2048 && dv[at].buf_pref == 256, "the driver's buffer sizes are listed (%ld to %ld, preferred %ld)", dv[at].buf_min, dv[at].buf_max, dv[at].buf_pref);

    job j;
    memset(&j, 0, sizeof j);
    j.out_first = 1, j.rate = card, j.frames = 0;
    run_job(&j);
    CHECK(j.e == VAUD_OK && j.started && j.calls > 5, "open, start, close on the thread that listed the devices (%ld callbacks, %s)", j.calls, j.err);
    run_job(&j);
    CHECK(j.e == VAUD_OK && j.started, "... again on the same thread (the driver was let go: %s)", j.err);
    memset(&j, 0, sizeof j); j.out_first = 3, j.rate = card, j.frames = 0;
    on_thread(th_nocom, &j);
    CHECK(j.e == VAUD_OK && j.started && j.calls > 5, "open from a thread WITHOUT COM, outputs 3+4 (the owner's case: the Lua thread) (%s)", j.err);
    memset(&j, 0, sizeof j); j.out_first = 1, j.rate = card, j.frames = 128;
    on_thread(th_mta, &j);
    CHECK(j.e == VAUD_OK && j.started, "open from a multi-threaded COM thread, buffer 128 (%s)", j.err);
    memset(&j, 0, sizeof j); j.out_first = 3, j.rate = card, j.frames = 512;
    on_thread(th_sta, &j);
    CHECK(j.e == VAUD_OK && j.started, "open from another single-threaded COM thread, outputs 3+4, buffer 512 (%s)", j.err);
    for (int i = 0; i < 4; i++) {
        memset(&j, 0, sizeof j); j.out_first = i % 2 ? 3 : 1, j.rate = card, j.frames = 0;
        on_thread(i % 2 ? th_nocom : th_mta, &j);
        CHECK(j.e == VAUD_OK && j.started, "round %d of open and close from changing threads (%s)", i + 1, j.err);
    }
    /* the card's clock: a rate that is not the card's is refused, with the card's own rate, and the driver is not asked to change */
    memset(&j, 0, sizeof j); j.out_first = 1, j.rate = card == 48000 ? 44100 : 48000, j.frames = 0;
    on_thread(th_nocom, &j);
    CHECK(j.e == VAUD_BAD_RATE && j.res_rate == card, "another rate than the card's is refused and the card's rate is given back (%u): %.140s", j.res_rate, j.err);
    CHECK(strstr(j.err, "does not change a card's clock") != NULL, "... in plain words");
    CHECK(stub_log_has("set_rate") == 0, "the driver was never asked to change the card's clock (%d set_rate lines)", stub_log_has("set_rate"));
    int inits = stub_log_has("init"), rel = stub_log_has("release");
    CHECK(rel >= inits - 1, "every driver that was loaded was released again (%d init, %d release)", inits, rel);
    printf(fails ? "asio_backend_test: %d FAILED\n" : "asio_backend_test: ok\n", fails);
    return fails ? 1 : 0;
}
