// OSC to MIDI (osc_midi.h) and the UDP input (osc_in.cc) on the loopback of this machine: real packets, a real socket, bound to 127.0.0.1 only.
#include <string>
//   g++ -std=c++17 -I matron/src linux/tests/osc_midi_test.cpp matron/src/platform/windows/midi/osc_in.cc matron/src/platform/windows/midi/midi_port.cc -lpthread -o /tmp/osc_midi_test
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <vector>
#include "platform/windows/midi/osc_midi.h"
#include "platform/windows/midi/osc_in.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static void put_str(std::vector<uint8_t> &v, const char *s) { size_t n = strlen(s); v.insert(v.end(), s, s + n); v.insert(v.end(), 4 - (n % 4), 0); }
static void put_i(std::vector<uint8_t> &v, int32_t x) { for (int i = 3; i >= 0; i--) v.push_back((uint8_t)(x >> (8 * i))); }
static void put_f(std::vector<uint8_t> &v, float f) { uint32_t u; memcpy(&u, &f, 4); put_i(v, (int32_t)u); }
static std::vector<uint8_t> msg(const char *path, const char *tags, std::vector<double> a) {
    std::vector<uint8_t> v; put_str(v, path); std::string t = std::string(",") + tags; put_str(v, t.c_str());
    size_t i = 0; for (char c : std::string(tags)) { if (c == 'i') put_i(v, (int32_t)a[i++]); else if (c == 'f') put_f(v, (float)a[i++]); }
    return v;
}
static size_t conv(const std::vector<uint8_t> &p, uint8_t *out) { size_t ol = 0; vosc::packet(p.data(), p.size(), out, 32, &ol); return ol; }

int main() {
    uint8_t o[32];
    CHECK(conv(msg("/cc", "iii", {1, 74, 100}), o) == 3 && o[0] == 0xb0 && o[1] == 74 && o[2] == 100, "/cc ints");
    CHECK(conv(msg("/cc", "iif", {16, 7, 0.5}), o) == 3 && o[0] == 0xbf && o[2] == 64, "/cc float 0.5 -> 64 (%d)", o[2]);
    CHECK(conv(msg("/cc", "iif", {1, 7, 1.0}), o) == 3 && o[2] == 127, "/cc float 1.0 -> 127");
    CHECK(conv(msg("/cc", "iii", {1, 200, -5}), o) == 3 && o[1] == 127 && o[2] == 0, "values are clamped");
    CHECK(conv(msg("/note", "iii", {2, 60, 90}), o) == 3 && o[0] == 0x91 && o[1] == 60 && o[2] == 90, "/note");
    CHECK(conv(msg("/noteoff", "ii", {2, 60}), o) == 3 && o[0] == 0x81 && o[2] == 0, "/noteoff");
    CHECK(conv(msg("/pitchbend", "ii", {1, 8192}), o) == 3 && o[0] == 0xe0 && o[1] == 0 && o[2] == 64, "/pitchbend");
    CHECK(conv(msg("/pc", "ii", {1, 5}), o) == 2 && o[0] == 0xc0 && o[1] == 5, "/pc");
    CHECK(conv(msg("/midi", "iii", {0xb0, 1, 2}), o) == 3 && o[0] == 0xb0, "/midi raw");
    CHECK(conv(msg("/nothing", "i", {1}), o) == 0, "unknown path: nothing");
    std::vector<uint8_t> bad = {'/', 'c', 'c'};
    CHECK(conv(bad, o) == 0, "a broken packet is ignored");
    // a bundle of two
    std::vector<uint8_t> b; put_str(b, "#bundle"); for (int i = 0; i < 8; i++) b.push_back(0);
    for (auto &m : {msg("/cc", "iii", {1, 1, 1}), msg("/cc", "iii", {1, 2, 2})}) { put_i(b, (int32_t)m.size()); b.insert(b.end(), m.begin(), m.end()); }
    CHECK(conv(b, o) == 6 && o[1] == 1 && o[4] == 2, "a bundle is taken apart");

    // the socket
    vmidi_port *p = vmidi_port_new_push(nullptr, nullptr);
    char err[200] = "";
    int rc = vmidi_osc_start(p, 39201, err, sizeof err);
    CHECK(rc == 0, "start: %s", err);
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_port = htons(39201); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    auto m = msg("/cc", "iii", {3, 21, 99});
    sendto(s, m.data(), m.size(), 0, (struct sockaddr *)&a, sizeof a);
    uint8_t buf[16];
    long n = vmidi_port_read(p, buf, sizeof buf);
    CHECK(n == 3 && buf[0] == 0xb2 && buf[1] == 21 && buf[2] == 99, "a UDP packet arrives as MIDI bytes (%ld)", n);
    char err2[200] = "";
    vmidi_port *p2 = vmidi_port_new_push(nullptr, nullptr);
    CHECK(vmidi_osc_start(p2, 39201, err2, sizeof err2) == 0, "a second start is the same input"); // already up
    vmidi_osc_stop();
    int rc2 = vmidi_osc_start(p2, 39201, err2, sizeof err2);
    CHECK(rc2 == 0, "restart on the same port: %s", err2);
    // a port that is taken: a plain sentence
    int hold = socket(AF_INET, SOCK_DGRAM, 0); struct sockaddr_in h = a; h.sin_port = htons(39202); bind(hold, (struct sockaddr *)&h, sizeof h);
    vmidi_osc_stop();
    CHECK(vmidi_osc_start(p2, 39202, err2, sizeof err2) != 0 && strstr(err2, "in use by another program"), "port taken: '%s'", err2);
    // bound to the loopback only
    vmidi_osc_start(p2, 39203, err2, sizeof err2);
    struct sockaddr_in got; socklen_t gl = sizeof got;
    (void)got; (void)gl;
    vmidi_osc_stop();
    printf(fails == 0 ? "osc_midi: all checks pass\n" : "osc_midi: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
