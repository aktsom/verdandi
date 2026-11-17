// linux/tests/tape_finalize_test.cc (M21 fix 2): a tape recording that is running when the program ends is left as a file of length zero (libsndfile writes the WAV header when the file is closed). the real Tape::Writer of
// crone (crone/src/Tape.h) is fed by a fake audio thread. every case is a child process that ends with _exit() the way norns.exe does (TerminateProcess): without finalize() the file has no valid header, with it it has.
//   argv: none
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <atomic>
#include <thread>
#include <vector>
#include "Tape.h"

using Writer = crone::Tape<2>::Writer;
static int fails;
#define CHECK(c, ...) do { if (c) printf("ok   "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); printf("\n"); } while (0)

// the data of a WAV file as its header says it, and as the file is: 1 = consistent and long enough
static long wav_frames(const char *path, long *header_frames) {
    *header_frames = -1;
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    unsigned char h[64];
    size_t n = fread(h, 1, sizeof h, f);
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fclose(f);
    if (n < 44 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4)) return -1;
    // find "data": 24-bit stereo = 6 bytes a frame
    for (size_t i = 12; i + 8 <= n;) {
        unsigned long len = h[i + 4] | (h[i + 5] << 8) | (h[i + 6] << 16) | ((unsigned long)h[i + 7] << 24);
        if (!memcmp(h + i, "data", 4)) {
            *header_frames = (long)(len / 6);
            return (size - (long)(i + 8)) / 6;
        }
        i += 8 + len;
    }
    return -1;
}

// the child: records for `secs` seconds from a fake audio thread, then ends the way the test says
static void child(const char *path, double secs, int finalize, int audio_runs_at_end) {
    static Writer w;
    w.open(path);
    w.start();
    std::atomic<bool> run{true}, feed{true};
    std::thread audio([&] {
        std::vector<float> l(128, 0.25f), r(128, -0.25f);
        const float *src[2] = {l.data(), r.data()};
        while (run) {
            if (feed) w.process(src, 128);
            usleep(2666); // 128 frames at 48000 Hz
        }
    });
    usleep((useconds_t)(secs * 1e6));
    if (!audio_runs_at_end) feed = false; // no audio callback any more: the stop cannot be played, finalize() must close the file by itself
    int ok = 1;
    if (finalize && !getenv("TAPE_NO_FINALIZE")) ok = w.finalize(1500); // (TAPE_NO_FINALIZE=1: the test with the fix taken out: it must fail)
    fprintf(stderr, "finalize %d\n", ok);
    _exit(ok ? 0 : 3);
}

static void case_run(const char *name, int finalize, int audio_runs_at_end, int want_valid) {
    char path[80];
    snprintf(path, sizeof path, "/tmp/tape-fin-%d-%s.wav", (int)getpid(), name);
    unlink(path);
    fflush(stdout);
    pid_t p = fork();
    if (p == 0) {
        freopen("/dev/null", "w", stdout);
        child(path, 1.2, finalize, audio_runs_at_end);
    }
    int st = 0;
    waitpid(p, &st, 0);
    long hdr = 0;
    long frames = wav_frames(path, &hdr);
    bool valid = frames > 0 && hdr == frames && hdr > 40000; // 1.2 s at 48000 Hz is about 57600 frames
    CHECK(valid == (want_valid != 0), "%s: the process ended with _exit; the file %s (frames in the file %ld, frames its header says %ld)", name, valid ? "is a valid WAV file of the right length" : "has no valid header (length zero)", frames, hdr);
    unlink(path);
}

int main() {
    case_run("not_finalized", 0, 1, 0);        // what happened on every way of ending except SLEEP
    case_run("finalized", 1, 1, 1);            // the fix: stop, play the fade-out, close
    case_run("finalized_no_audio", 1, 0, 1);   // the audio callback is gone: the disk thread is told to stop and closes the file
    // nothing recording: finalize returns at once
    {
        static Writer w;
        auto t0 = std::chrono::steady_clock::now();
        int ok = w.finalize(1500);
        double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        CHECK(ok == 1 && ms < 50, "nothing recording: finalize answers at once (%d, %.1f ms)", ok, ms);
    }
    printf(fails ? "tape_finalize_test: %d FAILED\n" : "tape_finalize_test: ok\n", fails);
    return fails ? 1 : 0;
}
