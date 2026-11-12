// the route measurement (midi_measure.cc): a fake cable (the output of a port comes back as its input after 1.5 ms), a cable that is not closed, a bad device, and UDP on the real loopback of this machine.
//   g++ -std=c++17 -I matron/src linux/tests/midi_measure_test.cpp matron/src/platform/windows/midi/midi_measure.cc matron/src/platform/windows/midi/midi_port.cc -lpthread -o /tmp/midi_measure_test
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "platform/windows/midi/midi_measure.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static vmidi_rx_fn g_rx; static void *g_user; static bool closed_cable = true; static int delay_us = 1500;
static double now() { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec * 1e6 + ts.tv_nsec / 1e3; }
struct Echo { uint8_t d[3]; };
static void *echo(void *a) { Echo *e = (Echo *)a; usleep(delay_us); if (g_rx) g_rx(g_user, e->d, 3); delete e; return NULL; }
static int list(int, char n[][64], int) { strcpy(n[0], "Cable"); return 1; }
static void *open_in(int, vmidi_rx_fn rx, void *u, char *, size_t, int *) { g_rx = rx; g_user = u; return (void *)1; }
static void close_in(void *) { g_rx = nullptr; }
static void *open_out(int, char *, size_t, int *) { return (void *)2; }
static int send_(void *, const uint8_t *d, size_t n) {
    if (closed_cable && n == 3) { Echo *e = new Echo; memcpy(e->d, d, 3); pthread_t t; pthread_create(&t, NULL, echo, e); pthread_detach(t); }
    return (int)n;
}
static void close_out(void *) {}
static vmidi_backend BE = {"fake", list, open_in, close_in, open_out, send_, close_out, now};

int main() {
    char note[100], err[200];
    vmidi_port *p = vmidi_port_open(&BE, 0, 0, nullptr, nullptr, note, sizeof note);
    vmidi_route_result r;
    CHECK(vmidi_measure_port(p, 50, 3, &r, err, sizeof err) == 0, "measure: %s", err);
    CHECK(r.got == 50 && r.mean_ms > 1.4 && r.mean_ms < 4.0 && r.jitter_ms < 1.5 && r.max_ms >= r.mean_ms, "a 1.5 ms cable: mean %.2f max %.2f jitter %.2f got %d", r.mean_ms, r.max_ms, r.jitter_ms, r.got);
    char line[200]; vmidi_route_format(&r, "Cable", line, sizeof line);
    CHECK(strstr(line, "Cable:") && strstr(line, "50 of 50"), "the line: %s", line);
    uint8_t buf[8];
    // the test's own messages did not reach the ring
    vmidi_port_push(p, (const uint8_t *)"\x90\x3c\x40", 3);
    CHECK(vmidi_port_read(p, buf, 8) == 3 && buf[0] == 0x90, "the test messages are swallowed, others pass");
    closed_cable = false;
    CHECK(vmidi_measure_port(p, 3, 2, &r, err, sizeof err) != 0 && strstr(err, "nothing came back"), "an open cable: '%s'", err);
    vmidi_port_close(p); vmidi_port_unref(p);
    vmidi_port *q = vmidi_port_open(&BE, 0, -1, nullptr, nullptr, note, sizeof note);
    CHECK(vmidi_measure_port(q, 3, 2, &r, err, sizeof err) != 0 && strstr(err, "input and an output"), "no output: '%s'", err);
    vmidi_port_close(q); vmidi_port_unref(q);
    CHECK(vmidi_measure_udp(100, 2, &r, err, sizeof err) == 0 && r.got == 100 && r.mean_ms < 5, "udp on the loopback: %s mean %.3f max %.3f jitter %.3f", err, r.mean_ms, r.max_ms, r.jitter_ms);
    printf("udp loopback: mean %.3f ms, worst %.3f, jitter %.3f\n", r.mean_ms, r.max_ms, r.jitter_ms);
    printf(fails == 0 ? "midi_measure: all checks pass\n" : "midi_measure: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
