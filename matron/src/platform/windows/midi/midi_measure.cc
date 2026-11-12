// midi_measure.cc: see midi_measure.h
#include "midi_measure.h"

#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <vector>

#include "osc_midi.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

static void sleep_ms(double ms) {
    struct timespec ts;
    ts.tv_sec = (time_t)(ms / 1000);
    ts.tv_nsec = (long)((ms - ts.tv_sec * 1000.0) * 1e6);
    nanosleep(&ts, NULL);
}

static void finish(std::vector<double> &rt_us, int sent, vmidi_route_result *o) {
    memset(o, 0, sizeof *o);
    o->sent = sent;
    o->got = (int)rt_us.size();
    if (rt_us.empty()) return;
    std::sort(rt_us.begin(), rt_us.end());
    double sum = 0;
    for (double v : rt_us) sum += v;
    double mean = sum / rt_us.size(), m2 = 0;
    for (double v : rt_us) m2 += (v - mean) * (v - mean);
    o->min_ms = rt_us.front() / 1000;
    o->max_ms = rt_us.back() / 1000;
    o->mean_ms = mean / 1000;
    o->p50_ms = rt_us[rt_us.size() / 2] / 1000;
    o->p99_ms = rt_us[std::min(rt_us.size() - 1, (size_t)ceil(rt_us.size() * 0.99) - 1)] / 1000;
    o->jitter_ms = rt_us.size() > 1 ? sqrt(m2 / (rt_us.size() - 1)) / 1000 : 0;
}

struct Probe {
    pthread_mutex_t lk = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
    int want = -1;       // the sequence number we wait for
    double t_arrive = 0;
    bool got = false;
};

static int probe_fn(void *user, const uint8_t *d, size_t n, double t_us) {
    Probe *pr = (Probe *)user;
    // the messages of the test: control change 119 on channel 16 with the sequence number (0..127) as value
    int swallowed = 0;
    for (size_t i = 0; i + 3 <= n; i += 3) {
        if (d[i] == 0xbf && d[i + 1] == 119) {
            swallowed = 1;
            pthread_mutex_lock(&pr->lk);
            if (d[i + 2] == pr->want && !pr->got) {
                pr->got = true;
                pr->t_arrive = t_us;
                pthread_cond_signal(&pr->cv);
            }
            pthread_mutex_unlock(&pr->lk);
        }
    }
    return swallowed;
}

int vmidi_measure_port(vmidi_port *p, int count, int interval_ms, vmidi_route_result *out, char *err, size_t errn) {
    if (!vmidi_port_has_input(p) || !vmidi_port_has_output(p)) {
        snprintf(err, errn, "the device needs an input and an output joined by a cable");
        return -1;
    }
    Probe pr;
    vmidi_port_set_probe(p, probe_fn, &pr);
    std::vector<double> rt;
    for (int i = 0; i < count; i++) {
        uint8_t m[3] = {0xbf, 119, (uint8_t)(i & 0x7f)};
        pthread_mutex_lock(&pr.lk);
        pr.want = m[2];
        pr.got = false;
        pthread_mutex_unlock(&pr.lk);
        double t0 = vmidi_port_now_us(p);
        vmidi_port_send(p, m, 3);
        pthread_mutex_lock(&pr.lk);
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_nsec += 200 * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        while (!pr.got) {
            if (pthread_cond_timedwait(&pr.cv, &pr.lk, &ts) != 0) break;
        }
        bool ok = pr.got;
        double t1 = pr.t_arrive;
        pthread_mutex_unlock(&pr.lk);
        if (ok) rt.push_back(t1 - t0);
        sleep_ms(interval_ms + (i * 7) % 5); // a little irregular: no lock to the period of a buffer
    }
    vmidi_port_set_probe(p, NULL, NULL);
    finish(rt, count, out);
    if (rt.empty()) {
        snprintf(err, errn, "nothing came back: is the cable closed (input and output of the same port)?");
        return -1;
    }
    return 0;
}

int vmidi_measure_udp(int count, int interval_ms, vmidi_route_result *out, char *err, size_t errn) {
#ifdef _WIN32
    WSADATA wd;
    WSAStartup(MAKEWORD(2, 2), &wd);
#endif
    int rx = (int)socket(AF_INET, SOCK_DGRAM, 0), tx = (int)socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    if (bind(rx, (struct sockaddr *)&a, sizeof a) != 0) {
        snprintf(err, errn, "no socket");
        return -1;
    }
    socklen_t al = sizeof a;
    getsockname(rx, (struct sockaddr *)&a, &al);
#ifdef _WIN32
    DWORD to = 200;
    setsockopt(rx, SOL_SOCKET, SO_RCVTIMEO, (const char *)&to, sizeof to);
#else
    struct timeval to = {0, 200000};
    setsockopt(rx, SOL_SOCKET, SO_RCVTIMEO, &to, sizeof to);
#endif
    std::vector<double> rt;
    for (int i = 0; i < count; i++) {
        // "/cc 16 119 i"
        uint8_t pk[32];
        memset(pk, 0, sizeof pk);
        memcpy(pk, "/cc\0,iii\0\0\0\0", 12);
        auto put = [&](int off, int v) { pk[off] = 0; pk[off + 1] = 0; pk[off + 2] = 0; pk[off + 3] = (uint8_t)v; };
        put(12, 16); put(16, 119); put(20, i & 0x7f);
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        sendto(tx, (const char *)pk, 24, 0, (struct sockaddr *)&a, sizeof a);
        uint8_t in[64];
        int n = (int)recv(rx, (char *)in, sizeof in, 0);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        uint8_t mid[16];
        size_t ml = 0;
        if (n > 0 && vosc::packet(in, (size_t)n, mid, sizeof mid, &ml) == 1 && ml == 3 && mid[0] == 0xbf) {
            rt.push_back((t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3);
        }
        sleep_ms(interval_ms + (i * 7) % 5);
    }
#ifdef _WIN32
    closesocket(rx); closesocket(tx);
#else
    close(rx); close(tx);
#endif
    finish(rt, count, out);
    if (rt.empty()) {
        snprintf(err, errn, "nothing came back on the loopback of this machine (a firewall?)");
        return -1;
    }
    return 0;
}

void vmidi_route_format(const vmidi_route_result *r, const char *label, char *buf, size_t n) {
    snprintf(buf, n, "%s: %.2f ms round trip (mean), %.2f worst, jitter %.2f, %d of %d", label, r->mean_ms, r->max_ms, r->jitter_ms, r->got, r->sent);
}
