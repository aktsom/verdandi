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

#include "../macos/product.h"
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

int sink_output(void *, const snd_seq_event_t *ev) {
    snd_seq_event_t e = *ev; // the sequencer wants a non-const event; the sysex data pointer stays
    snd_seq_ev_set_source(&e, (unsigned char)port);
    return snd_seq_event_output_direct(seq, &e);
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
    fprintf(stderr, "aseq_out: ALSA sequencer port %d:%d (\"%s\" \"%s\")\n", client_id, port, ASEQ_CLIENT, ASEQ_PORT);
    return 0;
}

void aseq_out_stop(void) {
    std::lock_guard<std::mutex> l(lifecycle);
    aseq::Pump *p = pump.exchange(NULL);
    if (p == NULL) {
        return;
    }
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

int aseq_out_client_id(void) {
    return pump.load() != NULL ? client_id : -1;
}
