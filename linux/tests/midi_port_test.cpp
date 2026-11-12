// the port layer of the Windows MIDI code (midi_port.cc) with a fake backend: bytes in and out, the clock and the song position at once on the backend's thread, the ring, a busy port, the
// jitter statistics, closing while a reader waits. g++ -std=c++17 -I matron/src linux/tests/midi_port_test.cpp matron/src/platform/windows/midi/midi_port.cc -lpthread -o /tmp/midi_port_test
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <vector>
#include "platform/windows/midi/midi_port.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static vmidi_rx_fn g_rx; static void *g_user;
static double g_now = 1000;
static bool busy_in = false;
static std::vector<uint8_t> sent;
static int closed_in = 0, closed_out = 0;
static int list(int input, char names[][64], int max) { (void)max; strcpy(names[0], input ? "Fake In" : "Fake Out"); return 1; }
static void *open_in(int i, vmidi_rx_fn rx, void *u, char *err, size_t en, int *busy) { (void)i; if (busy_in) { *busy = 1; snprintf(err, en, "allocated"); return NULL; } g_rx = rx; g_user = u; return (void *)1; }
static void close_in(void *) { closed_in++; g_rx = nullptr; }
static void *open_out(int, char *, size_t, int *) { return (void *)2; }
static int send_(void *, const uint8_t *d, size_t n) { sent.insert(sent.end(), d, d + n); return (int)n; }
static void close_out(void *) { closed_out++; }
static double now() { return g_now; }
static vmidi_backend BE = {"fake", list, open_in, close_in, open_out, send_, close_out, now};

static std::vector<int> clk; static std::vector<int> spp;
static void on_clock(uint8_t m) { clk.push_back(m); }
static void on_spp(uint16_t b) { spp.push_back(b); }
static volatile uint8_t enabled = 1;

static void *reader(void *a) {
    vmidi_port *p = (vmidi_port *)a;
    uint8_t buf[64];
    long n;
    long total = 0;
    while ((n = vmidi_port_read(p, buf, sizeof buf)) > 0) total += n;
    vmidi_port_unref(p);
    return (void *)total;
}

int main() {
    vmidi_hooks hk = {on_clock, on_spp};
    char note[200];
    vmidi_port *p = vmidi_port_open(&BE, 0, 0, &hk, &enabled, note, sizeof note);
    CHECK(p && vmidi_port_has_input(p) && vmidi_port_has_output(p), "opens both");
    // out
    uint8_t cc[3] = {0xb0, 7, 100};
    CHECK(vmidi_port_send(p, cc, 3) == 3 && sent.size() == 3 && sent[1] == 7, "send");
    // in: a CC, then realtime inside a message, running status is left to the reader
    uint8_t m1[] = {0xb0, 1, 64, 0xf8, 0xfa, 0xfb, 0xfc};
    g_rx(g_user, m1, sizeof m1);
    CHECK(clk.size() == 4 && clk[0] == 0xf8 && clk[1] == 0xfa && clk[2] == 0xfb && clk[3] == 0xfc, "the clock gets its four messages at once (%zu)", clk.size());
    uint8_t m2[] = {0xf2, 0x10, 0x01};
    g_rx(g_user, m2, 3);
    CHECK(spp.size() == 1 && spp[0] == (0x10 | (1 << 7)), "song position pointer: %zu", spp.size());
    uint8_t buf[64];
    long n = vmidi_port_read(p, buf, sizeof buf);
    CHECK(n == 10 && buf[0] == 0xb0 && buf[3] == 0xf8, "all bytes reach the ring, the realtime bytes too (%ld)", n);
    // the clock is off for this device
    enabled = 0; clk.clear();
    uint8_t t = 0xf8; g_rx(g_user, &t, 1);
    CHECK(clk.empty(), "clock disabled: the clock does not get it");
    n = vmidi_port_read(p, buf, sizeof buf);
    CHECK(n == 1 && buf[0] == 0xf8, "but norns' scripts still do");
    enabled = 1;
    // jitter: 24 ppq at 120 bpm: 20833 us, a few ticks late
    vmidi_stats st; vmidi_port_stats(p, &st);
    g_now = 5000; g_rx(g_user, &t, 1); vmidi_port_stats(p, &st);
    for (int i = 0; i < 100; i++) { g_now += 20833.3 + ((i % 5) - 2) * 100.0; g_rx(g_user, &t, 1); }
    vmidi_port_stats(p, &st);
    CHECK(st.ticks >= 100 && fabs(st.mean_us - 20833) < 50 && st.jitter_us > 50 && st.jitter_us < 400 && st.max_us > st.min_us, "statistics: mean %.0f jitter %.0f min %.0f max %.0f", st.mean_us, st.jitter_us, st.min_us, st.max_us);
    vmidi_port_stats(p, &st);
    CHECK(st.mean_us == 0, "the window starts again");
    // overflow
    std::vector<uint8_t> big(20000, 0x40);
    vmidi_port_push(p, big.data(), big.size());
    vmidi_port_stats(p, &st);
    CHECK(st.dropped > 10000, "a reader that is too slow loses bytes and counts them (%llu)", st.dropped);
    // close wakes a waiting reader; refs free the port
    while (vmidi_port_read(p, buf, 61) == 61) {}
    vmidi_port_ref(p);
    pthread_t th; pthread_create(&th, NULL, reader, p);
    usleep(50000);
    vmidi_port_close(p);
    void *r; pthread_join(th, &r);
    CHECK(closed_in == 1 && closed_out == 1, "both sides closed");
    vmidi_port_unref(p);
    // a reader that is cancelled while it waits (norns cancels the thread of a device that is removed): the lock is free afterwards
    p = vmidi_port_open(&BE, 0, 0, &hk, &enabled, note, sizeof note);
    pthread_t th2; pthread_create(&th2, NULL, [](void *a) -> void * { uint8_t b[8]; vmidi_port_read((vmidi_port *)a, b, 8); return NULL; }, p);
    usleep(150000);
    pthread_cancel(th2); pthread_join(th2, &r);
    uint8_t one = 1; vmidi_port_push(p, &one, 1); // would hang if the lock were left taken
    vmidi_port_close(p); vmidi_port_unref(p);
    CHECK(true, "cancel");
    // a busy input: the output still opens, the note says why
    busy_in = true;
    p = vmidi_port_open(&BE, 0, 0, &hk, &enabled, note, sizeof note);
    CHECK(p && !vmidi_port_has_input(p) && vmidi_port_has_output(p) && strstr(note, "held by another program"), "busy input: output only, plain note: '%s'", note);
    vmidi_port_close(p); vmidi_port_unref(p);
    p = vmidi_port_open(&BE, 0, -1, &hk, &enabled, note, sizeof note);
    CHECK(p == NULL && strstr(note, "held by another program"), "only a busy input: no device, plain note");
    printf(fails == 0 ? "midi_port: all checks pass\n" : "midi_port: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
