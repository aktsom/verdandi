/*
 * bridge_host_tool.c: the norns.exe side of the audio bridge as a small program (Linux and Wine): creates the bridge, then feeds it blocks paced like a sound card (default 512 frames at 48000 Hz) for a
 * number of seconds, sending a constant 0.2 to scsynth, and reports what came back: the mean (0.2 = scsynth passed the input through its input bus), the peak and the frequency of the sine the
 * test SynthDef plays. Used by linux/tests/scsynth_bridge_test.sh against a PATCHED scsynth.
 *   bridge_host_tool NAME SECONDS [FRAMES]
 */
#define _GNU_SOURCE 1
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "audio/verdandi_bridge.h"

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    unsigned frames = argc > 3 ? (unsigned)atoi(argv[3]) : 512, rate = 48000;
    vb_t b;
    if (vb_host_create(&b, argv[1], rate, frames) != 0) {
        printf("FAIL cannot create the bridge\n");
        return 1;
    }
    double secs = atof(argv[2]);
    long blocks = (long)(secs * rate / frames);
    float *in = malloc(frames * sizeof(float)), *ol = malloc(frames * sizeof(float)), *orr = malloc(frames * sizeof(float));
    float *rec = malloc((size_t)blocks * frames * sizeof(float));
    for (unsigned i = 0; i < frames; i++) in[i] = 0.2f;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    double period_ms = 1000.0 * frames / rate;
    int attached_at = -1;
    for (long n = 1; n <= blocks; n++) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double el = (now.tv_sec - t0.tv_sec) * 1000.0 + (now.tv_nsec - t0.tv_nsec) / 1e6, target = n * period_ms;
        if (target > el) {
            struct timespec ts = {(time_t)((target - el) / 1000), (long)(fmod(target - el, 1000.0) * 1e6)};
            nanosleep(&ts, NULL);
        }
        vb_host_exchange(&b, in, in, ol, orr);
        for (unsigned i = 0; i < frames; i++) rec[(n - 1) * frames + i] = ol[i];
        if (attached_at < 0 && vb_load(&b.sh->guest_attached)) attached_at = (int)n;
    }
    size_t from = (size_t)blocks * frames / 2, total = (size_t)blocks * frames;
    double sum = 0, peak = 0;
    for (size_t i = from; i < total; i++) sum += rec[i];
    double mean = sum / (double)(total - from);
    int cross = 0;
    for (size_t i = from + 1; i < total; i++) {
        double a = rec[i - 1] - mean, c = rec[i] - mean;
        if (fabs(c) > peak) peak = fabs(c);
        if ((a < 0) != (c < 0)) cross++;
    }
    double freq = cross / 2.0 / ((double)(total - from) / rate);
    printf("attached_at_block %d guest_blocks %llu underruns %llu drops %llu mean %.3f peak %.3f freq %.1f\n", attached_at, (unsigned long long)vb_load(&b.sh->guest_blocks),
           (unsigned long long)vb_load(&b.sh->host_underruns), (unsigned long long)vb_load(&b.sh->host_drops), mean, peak, freq);
    vb_close(&b);
    return 0;
}
