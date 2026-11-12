// linux/tests/loopback_convert_test.cc: matron/src/platform/windows/audio/loopback_convert.h: the loopback of the default output (any rate, any channels) becomes stereo at norns's rate.
#include <math.h>
#include <stdio.h>
#include <vector>
#include "../../matron/src/platform/windows/audio/loopback_convert.h"
static int fails;
#define CK(c, ...) do { if (!(c)) { fails++; printf("FAIL "); printf(__VA_ARGS__); printf("\n"); } } while (0)
// a sine of `hz` at `rate_in`, `channels` wide (channel 0 the sine, the others 0.25), delivered in packets of `packet` frames, converted to rate_out
static std::vector<float> run(double hz, unsigned rate_in, unsigned rate_out, int channels, size_t packet, size_t total_in) {
    vlb_state st; vlb_reset(&st);
    std::vector<float> in(total_in * channels), out;
    for (size_t i = 0; i < total_in; i++) {
        for (int c = 0; c < channels; c++) in[i * channels + c] = c == 0 ? (float)sin(2 * M_PI * hz * i / rate_in) : 0.25f;
    }
    std::vector<float> buf(packet * 4 + 64);
    for (size_t at = 0; at < total_in; at += packet) {
        size_t n = at + packet <= total_in ? packet : total_in - at;
        size_t w = vlb_process(&st, &in[at * channels], n, channels, rate_in, rate_out, buf.data(), buf.size() / 2);
        out.insert(out.end(), buf.begin(), buf.begin() + 2 * w);
    }
    return out;
}
static double freq_of(const std::vector<float> &o, unsigned rate) { // zero crossings of the left channel
    int cross = 0; size_t n = o.size() / 2;
    for (size_t i = 1; i < n; i++) if ((o[2 * (i - 1)] < 0) != (o[2 * i] < 0)) cross++;
    return cross / 2.0 / ((double)n / rate);
}
int main() {
    // 44100 -> 48000, stereo, packets of 441 frames (10 ms)
    auto o = run(1000, 44100, 48000, 2, 441, 44100 * 2);
    size_t frames = o.size() / 2;
    CK(frames > 95900 && frames < 96100, "44100 -> 48000: two seconds in, %zu frames out (96000 expected)", frames);
    CK(fabs(freq_of(o, 48000) - 1000) < 10, "the 1000 Hz sine stays 1000 Hz: %.1f", freq_of(o, 48000));
    // no jumps at the packet borders: the largest step between two frames of a 1 kHz sine at 48 kHz is 0.13
    double maxstep = 0; for (size_t i = 1; i < frames; i++) maxstep = fmax(maxstep, fabs(o[2 * i] - o[2 * (i - 1)]));
    CK(maxstep < 0.14, "no clicks at the packet borders (largest step %.3f)", maxstep);
    // 48000 -> 48000 passes through (a different packet size)
    o = run(440, 48000, 48000, 2, 480, 48000);
    CK(o.size() / 2 >= 47990 && o.size() / 2 <= 48000, "48000 -> 48000: %zu frames", o.size() / 2);
    // 96000 -> 48000 and 6 channels: the first two channels, the rest ignored
    o = run(1000, 96000, 48000, 6, 960, 96000);
    CK(fabs(freq_of(o, 48000) - 1000) < 10, "96000 -> 48000, 6 channels: 1000 Hz (%.1f)", freq_of(o, 48000));
    CK(fabs(o[2 * 5000 + 1] - 0.25) < 0.01, "channel 2 is the right side (0.25): %.3f", o[2 * 5000 + 1]);
    // mono: both sides
    o = run(1000, 48000, 48000, 1, 480, 48000);
    CK(fabs(o[2 * 3000] - o[2 * 3000 + 1]) < 1e-6, "mono: left = right");
    // odd packet sizes
    o = run(1000, 44100, 48000, 2, 333, 44100);
    CK(fabs(freq_of(o, 48000) - 1000) < 10, "odd packet sizes: 1000 Hz (%.1f)", freq_of(o, 48000));
    printf(fails ? "loopback_convert_test: %d failures\n" : "loopback_convert_test: passed\n", fails);
    return fails != 0;
}
