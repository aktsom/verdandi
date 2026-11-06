/*
 * aseq_out.cc: see aseq_out.h
 */

#include "aseq_out.h"

#include <alsa/asoundlib.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <atomic>
#include <new>
#include <type_traits>
#include <mutex>

#include <condition_variable>
#include <thread>
#include <unistd.h>

#include "../macos/product.h"
#include "aseq_link.h"
#include "aseq_pump.h"

#define ASEQ_CLIENT MACOS_PRODUCT          // "Verdandi"
#define ASEQ_PORT MACOS_PRODUCT " out"     // "Verdandi out"

namespace {

std::mutex lifecycle;               // start and stop (never taken by a sender)
snd_seq_t *seq = NULL;
int port = -1;
int client_id = -1;
std::atomic<aseq::Pump *> pump{NULL}; // read by the senders; set once after the client exists, cleared before it is closed
// the pump lives here (its queue is over-aligned, which plain new of C++14 does not honour)
std::aligned_storage<sizeof(aseq::Pump), alignof(aseq::Pump)>::type pump_storage;
bool said_off = false, said_fail = false;

std::mutex seq_mtx; // the handle is used by the worker (output) and by the linking thread (queries, subscriptions)

int sink_output(void *, const snd_seq_event_t *ev) {
    snd_seq_event_t e = *ev; // the sequencer wants a non-const event; the sysex data pointer stays
    snd_seq_ev_set_source(&e, (unsigned char)port);
    std::lock_guard<std::mutex> l(seq_mtx);
    return snd_seq_event_output_direct(seq, &e);
}

// the sequencer as aseq_link.h asks about it
struct RealSeq : aseq::LinkSeq {
    bool list(std::vector<aseq::PortInfo> &out) override {
        std::lock_guard<std::mutex> l(seq_mtx);
        if (seq == NULL) {
            return false;
        }
        snd_seq_client_info_t *ci;
        snd_seq_port_info_t *pi;
        snd_seq_client_info_alloca(&ci);
        snd_seq_port_info_alloca(&pi);
        snd_seq_client_info_set_client(ci, -1);
        while (snd_seq_query_next_client(seq, ci) >= 0) {
            int c = snd_seq_client_info_get_client(ci);
            snd_seq_port_info_set_client(pi, c);
            snd_seq_port_info_set_port(pi, -1);
            while (snd_seq_query_next_port(seq, pi) >= 0) {
                unsigned int caps = snd_seq_port_info_get_capability(pi);
                aseq::PortInfo p;
                p.client = c;
                p.port = snd_seq_port_info_get_port(pi);
                p.client_name = snd_seq_client_info_get_name(ci);
                p.port_name = snd_seq_port_info_get_name(pi);
                p.writable = (caps & SND_SEQ_PORT_CAP_WRITE) && (caps & SND_SEQ_PORT_CAP_SUBS_WRITE);
                p.pid = snd_seq_client_info_get_pid(ci);
                out.push_back(p);
            }
        }
        return true;
    }
    bool connected(int c, int p) override {
        std::lock_guard<std::mutex> l(seq_mtx);
        snd_seq_port_subscribe_t *sub;
        snd_seq_port_subscribe_alloca(&sub);
        snd_seq_addr_t from, to;
        from.client = (unsigned char)client_id;
        from.port = (unsigned char)port;
        to.client = (unsigned char)c;
        to.port = (unsigned char)p;
        snd_seq_port_subscribe_set_sender(sub, &from);
        snd_seq_port_subscribe_set_dest(sub, &to);
        return snd_seq_get_port_subscription(seq, sub) == 0;
    }
    int connect(int c, int p) override {
        std::lock_guard<std::mutex> l(seq_mtx);
        return snd_seq_connect_to(seq, port, c, p);
    }
};

RealSeq real_seq;
aseq::Linker *linker = NULL;
std::thread link_thread;
std::mutex link_mtx;
std::condition_variable link_cv;
bool link_stop = false;

bool own_thread(int pid) { // a client made by a thread of this process
    char path[64];
    snprintf(path, sizeof path, "/proc/self/task/%d", pid);
    return access(path, F_OK) == 0;
}

void link_loop() {
    std::unique_lock<std::mutex> l(link_mtx);
    while (!link_stop) {
        l.unlock();
        linker->check();
        l.lock();
        link_cv.wait_for(l, std::chrono::seconds(3), [] { return link_stop; });
    }
}

bool sink_wait_room(void *, int ms) {
    int n = snd_seq_poll_descriptors_count(seq, POLLOUT);
    if (n <= 0 || n > 8) {
        return false;
    }
    struct pollfd pfd[8];
    snd_seq_poll_descriptors(seq, pfd, (unsigned)n, POLLOUT);
    return poll(pfd, (nfds_t)n, ms) > 0;
}

} // namespace

int aseq_out_start(void) {
    std::lock_guard<std::mutex> l(lifecycle);
    if (pump.load() != NULL) {
        return 0;
    }
    const char *off = getenv("NORNS_ALSA_MIDI");
    if (off != NULL && strcmp(off, "0") == 0) {
        if (!said_off) {
            said_off = true;
            fprintf(stderr, "aseq_out: off (NORNS_ALSA_MIDI=0, or alsa_midi=0 in audio.conf)\n");
        }
        return -1;
    }
    int rc = snd_seq_open(&seq, "default", SND_SEQ_OPEN_OUTPUT, SND_SEQ_NONBLOCK);
    if (rc < 0) {
        seq = NULL;
        if (!said_fail) {
            said_fail = true;
            fprintf(stderr, "aseq_out: no ALSA sequencer here (%s): the virtual MIDI device has no ALSA port\n", snd_strerror(rc));
        }
        return -1;
    }
    snd_seq_set_client_name(seq, ASEQ_CLIENT);
    port = snd_seq_create_simple_port(seq, ASEQ_PORT, SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ, SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
    if (port < 0) {
        if (!said_fail) {
            said_fail = true;
            fprintf(stderr, "aseq_out: could not make the port (%s)\n", snd_strerror(port));
        }
        snd_seq_close(seq);
        seq = NULL;
        port = -1;
        return -1;
    }
    client_id = snd_seq_client_id(seq);
    aseq::Pump *p = new (&pump_storage) aseq::Pump(aseq::Sink{sink_output, sink_wait_room, NULL}, 2048);
    p->start();
    pump.store(p);
    // the optional auto-connect to ALSA ports (alsa_midi_out_to=): looked at once and then every few seconds, so a port that appears later and one that was cut are found
    const char *to = getenv("NORNS_ALSA_MIDI_OUT_TO");
    if (to != NULL && to[0] != '\0') {
        linker = new aseq::Linker(real_seq, to, client_id);
        linker->set_own_pid_test(own_thread);
        if (linker->enabled()) {
            link_stop = false;
            link_thread = std::thread(link_loop);
            fprintf(stderr, "aseq_out: auto-connect of Verdandi out to ALSA ports named \"%s\" (alsa_midi_out_to)\n", to);
        }
    }
    fprintf(stderr, "aseq_out: ALSA sequencer port %d:%d (\"%s\" \"%s\")\n", client_id, port, ASEQ_CLIENT, ASEQ_PORT);
    return 0;
}

void aseq_out_stop(void) {
    std::lock_guard<std::mutex> l(lifecycle);
    aseq::Pump *p = pump.exchange(NULL);
    if (p == NULL) {
        return;
    }
    if (link_thread.joinable()) {
        {
            std::lock_guard<std::mutex> ll(link_mtx);
            link_stop = true;
        }
        link_cv.notify_all();
        link_thread.join();
    }
    delete linker;
    linker = NULL;
    p->stop();
    p->~Pump();
    if (seq != NULL) {
        snd_seq_close(seq);
        seq = NULL;
    }
    port = -1;
    client_id = -1;
}

long aseq_out_send(const uint8_t *data, size_t n) {
    aseq::Pump *p = pump.load();
    if (p == NULL || data == NULL || n == 0) {
        return -1;
    }
    return p->send(data, n);
}

int aseq_out_link_status(char *names, size_t n) {
    if (names != NULL && n > 0) {
        names[0] = '\0';
    }
    aseq::Linker *l = linker;
    if (l == NULL || pump.load() == NULL) {
        return 0;
    }
    if (names != NULL && n > 0) {
        snprintf(names, n, "%s", l->names().c_str());
    }
    return l->count();
}

int aseq_out_client_id(void) {
    return pump.load() != NULL ? client_id : -1;
}
