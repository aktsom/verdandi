/* loopback_convert.h (Windows build): what the WASAPI loopback of the default output delivers (the mix format of that device: any rate, any number of channels, interleaved floats) becomes what norns needs:
 * stereo at norns's rate. a linear resampler that keeps its position between packets, the first two channels (one channel on both sides). header only, no Windows calls: linux/tests/loopback_convert_test.cc. */
#ifndef VERDANDI_LOOPBACK_CONVERT_H
#define VERDANDI_LOOPBACK_CONVERT_H
#include <stddef.h>

typedef struct {
    double pos;        /* position of the next output frame in input frames, relative to the start of the next packet (can be a little negative: between the last frame of the last packet and the first of this one) */
    float last_l, last_r; /* the last frame of the previous packet */
    int have_last;
} vlb_state;

static inline void vlb_reset(vlb_state *s) {
    s->pos = 0;
    s->last_l = s->last_r = 0;
    s->have_last = 0;
}

/* in: `n_in` frames of `channels` interleaved floats at `rate_in`; out: stereo interleaved at `rate_out`, at most `cap` frames. returns the frames written. a silent packet (NULL) is n_in frames of zeros */
static inline size_t vlb_process(vlb_state *s, const float *in, size_t n_in, int channels, unsigned rate_in, unsigned rate_out, float *out, size_t cap) {
    if (channels < 1 || rate_in == 0 || rate_out == 0 || n_in == 0) return 0;
    double step = (double)rate_in / (double)rate_out;
    size_t w = 0;
    /* frame k of this packet is at position k; the frame before the packet (index -1) is last_l/last_r */
    while (w < cap) {
        double p = s->pos;
        if (p > (double)n_in - 1.0) break; /* needs frame floor(p)+1, which is in the next packet */
        long i0 = (long)(p < 0 ? -1 : (long)p);
        if (p < 0) i0 = -1;
        double frac = p - (double)i0;
        float a_l, a_r, b_l, b_r;
        if (i0 < 0) {
            a_l = s->have_last ? s->last_l : in[0];
            a_r = s->have_last ? s->last_r : (channels > 1 ? in[1] : in[0]);
        } else {
            a_l = in[(size_t)i0 * channels];
            a_r = channels > 1 ? in[(size_t)i0 * channels + 1] : a_l;
        }
        long i1 = i0 + 1;
        b_l = in[(size_t)i1 * channels];
        b_r = channels > 1 ? in[(size_t)i1 * channels + 1] : b_l;
        out[2 * w] = (float)(a_l + (b_l - a_l) * frac);
        out[2 * w + 1] = (float)(a_r + (b_r - a_r) * frac);
        w++;
        s->pos += step;
    }
    /* the packet is used up: the next one starts where this one ended */
    s->last_l = in[(n_in - 1) * channels];
    s->last_r = channels > 1 ? in[(n_in - 1) * channels + 1] : s->last_l;
    s->have_last = 1;
    s->pos -= (double)n_in;
    return w;
}
#endif
