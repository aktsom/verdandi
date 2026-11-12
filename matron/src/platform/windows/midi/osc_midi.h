// osc_midi.h: OSC messages (UDP) to MIDI bytes. a generic control input for ANY program that can send OSC (a Max for Live device, TouchOSC, VCV Rack, Reaper, a script); it is the same kind of device as a MIDI port in
// norns (midi.connect(), MIDI MAP by name). pure, no system calls: linux/tests/osc_midi_test.cpp. docs/port/phase-m4.md.
//   /cc ch num val        control change: ch 1..16, num 0..127, val 0..127 (integer) or 0.0..1.0 (float, scaled to 0..127)
//   /note ch note vel     note on         /noteoff ch note [vel]    note off
//   /pitchbend ch val     0..16383 (integer) or 0.0..1.0 (float)      /pc ch program      /touch ch val  channel pressure
//   /midi b0 [b1 [b2]]    raw bytes (integers)
// a bundle is taken apart. anything else is ignored (counted by the caller).
#pragma once

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace vosc {

struct Arg {
    bool is_float = false;
    double v = 0;
};

static inline uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

static inline size_t padded(size_t n) { return (n + 4) & ~(size_t)3; } // a string and its 0, to 4 bytes

// one message at d (len bytes): the path and its arguments. false if it is not a well formed message
static inline bool message(const uint8_t *d, size_t len, char *path, size_t pathn, Arg *args, int *nargs, int maxargs) {
    size_t pl = strnlen((const char *)d, len);
    if (pl >= len || d[0] != '/' || pl + 1 > pathn) return false;
    memcpy(path, d, pl + 1);
    size_t pos = padded(pl);
    *nargs = 0;
    if (pos >= len || d[pos] != ',') return true; // no type tags: no arguments
    size_t tl = strnlen((const char *)d + pos, len - pos);
    if (pos + tl >= len) return false;
    const char *tags = (const char *)d + pos + 1;
    size_t tagn = tl - 1;
    pos += padded(tl);
    for (size_t i = 0; i < tagn && *nargs < maxargs; i++) {
        Arg a;
        switch (tags[i]) {
        case 'i': if (pos + 4 > len) return false; a.v = (int32_t)be32(d + pos); pos += 4; break;
        case 'f': { if (pos + 4 > len) return false; uint32_t u = be32(d + pos); float f; memcpy(&f, &u, 4); a.is_float = true; a.v = f; pos += 4; break; }
        case 'h': { if (pos + 8 > len) return false; uint64_t u = ((uint64_t)be32(d + pos) << 32) | be32(d + pos + 4); a.v = (double)(int64_t)u; pos += 8; break; }
        case 'd': { if (pos + 8 > len) return false; uint64_t u = ((uint64_t)be32(d + pos) << 32) | be32(d + pos + 4); double f; memcpy(&f, &u, 8); a.is_float = true; a.v = f; pos += 8; break; }
        case 'T': a.v = 1; break;
        case 'F': a.v = 0; break;
        default: return false; // a string or a blob: not a control value
        }
        args[(*nargs)++] = a;
    }
    return true;
}

static inline int clampi(double v, int lo, int hi) { int i = (int)lround(v); return i < lo ? lo : (i > hi ? hi : i); }
static inline int seven(const Arg &a) { return a.is_float ? clampi(a.v * 127.0, 0, 127) : clampi(a.v, 0, 127); }
static inline int chan(const Arg &a) { return clampi(a.v, 1, 16) - 1; }

// bytes for one message; returns how many (0 = nothing)
static inline size_t to_midi(const char *path, const Arg *a, int n, uint8_t out[3]) {
    if (!strcmp(path, "/cc") && n >= 3) { out[0] = 0xb0 | chan(a[0]); out[1] = clampi(a[1].v, 0, 127); out[2] = seven(a[2]); return 3; }
    if (!strcmp(path, "/note") && n >= 3) { out[0] = 0x90 | chan(a[0]); out[1] = clampi(a[1].v, 0, 127); out[2] = seven(a[2]); return 3; }
    if (!strcmp(path, "/noteoff") && n >= 2) { out[0] = 0x80 | chan(a[0]); out[1] = clampi(a[1].v, 0, 127); out[2] = n >= 3 ? seven(a[2]) : 0; return 3; }
    if (!strcmp(path, "/pitchbend") && n >= 2) { int v = a[1].is_float ? clampi(a[1].v * 16383.0, 0, 16383) : clampi(a[1].v, 0, 16383); out[0] = 0xe0 | chan(a[0]); out[1] = v & 0x7f; out[2] = v >> 7; return 3; }
    if (!strcmp(path, "/pc") && n >= 2) { out[0] = 0xc0 | chan(a[0]); out[1] = clampi(a[1].v, 0, 127); return 2; }
    if (!strcmp(path, "/touch") && n >= 2) { out[0] = 0xd0 | chan(a[0]); out[1] = seven(a[1]); return 2; }
    if (!strcmp(path, "/midi") && n >= 1) {
        int st = clampi(a[0].v, 0x80, 0xff);
        out[0] = st;
        size_t len = (st >= 0xf8 || st == 0xf6) ? 1 : ((st & 0xf0) == 0xc0 || (st & 0xf0) == 0xd0 || st == 0xf1 || st == 0xf3) ? 2 : 3;
        for (size_t i = 1; i < len; i++) out[i] = (int)i < n ? clampi(a[i].v, 0, 127) : 0;
        return len;
    }
    return 0;
}

// a whole packet (message or bundle) to MIDI bytes appended to out (max outn). returns the number of messages that made MIDI
static inline int packet(const uint8_t *d, size_t len, uint8_t *out, size_t outn, size_t *outlen, int depth = 0) {
    int made = 0;
    if (len >= 16 && !memcmp(d, "#bundle", 8) && depth < 4) {
        size_t pos = 16;
        while (pos + 4 <= len) {
            uint32_t sz = be32(d + pos);
            pos += 4;
            if (sz == 0 || pos + sz > len) break;
            made += packet(d + pos, sz, out, outn, outlen, depth + 1);
            pos += sz;
        }
        return made;
    }
    char path[64];
    Arg args[8];
    int n = 0;
    if (!message(d, len, path, sizeof path, args, &n, 8)) return 0;
    uint8_t m[3];
    size_t k = to_midi(path, args, n, m);
    if (k && *outlen + k <= outn) { memcpy(out + *outlen, m, k); *outlen += k; made = 1; }
    return made;
}

} // namespace vosc
