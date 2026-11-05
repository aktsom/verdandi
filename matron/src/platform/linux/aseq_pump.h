/*
 * aseq_pump.h: the logic of the ALSA sequencer output of the virtual MIDI device, without libasound's connection to a kernel (so it can be tested where there is none): a script's bytes are cut into whole messages
 * (midi_frame.h), put into a bounded lock-free queue by the sender (never waiting, never allocating: a full queue drops and counts), and a worker thread turns them into sequencer events, in order, and hands
 * them to a "sink" (aseq_out.cc: snd_seq_event_output_direct; the tests: a fake). a destination that is full (-EAGAIN) is waited for a little and tried again a few times, then the event is dropped and counted; another error
 * drops and counts it. dropped events are said in the log at most every 10 seconds, with the totals since the last line, from a sender's thread or the worker, never in the middle of a delivery.
 */

#pragma once

#include <alsa/asoundlib.h>
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include <atomic>

#include "midi_frame.h"
#include "readerwriterqueue.h"

namespace aseq {

struct Item {
    uint16_t len;
    uint8_t data[MIDI_FRAME_MAX];
};

struct Sink {
    // deliver one event to the subscribers: >= 0 taken (also when nobody is subscribed), -EAGAIN the destination is full, another negative number: it failed
    int (*output)(void *ctx, const snd_seq_event_t *ev);
    // wait up to `ms` for room again: true = try again, false = do not wait
    bool (*wait_room)(void *ctx, int ms);
    void *ctx;
};

struct Stats {
    unsigned long sent, dropped_full, dropped_error;
};

//--- one whole MIDI message (status byte first; sysex F0 ... F7) as a sequencer event for the subscribers, delivered directly (no queue). false: nothing to send (an undefined byte)
inline bool to_event(const uint8_t *m, size_t len, snd_seq_event_t *ev) {
    if (len == 0) {
        return false;
    }
    snd_seq_ev_clear(ev);
    snd_seq_ev_set_subs(ev);
    snd_seq_ev_set_direct(ev);
    uint8_t st = m[0];
    if (st < 0x80) {
        // the rest of a long sysex (midi_frame.h cuts it into pieces of at most MIDI_FRAME_MAX bytes): the bytes follow the first piece as they are
        snd_seq_ev_set_sysex(ev, len, (void *)m);
        return true;
    }
    int ch = st & 0x0f;
    if (st >= 0x80 && st < 0xf0) {
        switch (st & 0xf0) {
        case 0x80: if (len < 3) return false; snd_seq_ev_set_noteoff(ev, ch, m[1], m[2]); return true;
        case 0x90: if (len < 3) return false; snd_seq_ev_set_noteon(ev, ch, m[1], m[2]); return true;
        case 0xa0: if (len < 3) return false; snd_seq_ev_set_keypress(ev, ch, m[1], m[2]); return true;
        case 0xb0: if (len < 3) return false; snd_seq_ev_set_controller(ev, ch, m[1], m[2]); return true;
        case 0xc0: if (len < 2) return false; snd_seq_ev_set_pgmchange(ev, ch, m[1]); return true;
        case 0xd0: if (len < 2) return false; snd_seq_ev_set_chanpress(ev, ch, m[1]); return true;
        case 0xe0: if (len < 3) return false; snd_seq_ev_set_pitchbend(ev, ch, (int)(m[1] | (m[2] << 7)) - 8192); return true;
        }
        return false;
    }
    switch (st) {
    case 0xf0:
        snd_seq_ev_set_sysex(ev, len, (void *)m);
        return true;
    case 0xf1: if (len < 2) return false; ev->type = SND_SEQ_EVENT_QFRAME; snd_seq_ev_set_fixed(ev); ev->data.control.value = m[1]; return true;
    case 0xf2: if (len < 3) return false; ev->type = SND_SEQ_EVENT_SONGPOS; snd_seq_ev_set_fixed(ev); ev->data.control.value = m[1] | (m[2] << 7); return true;
    case 0xf3: if (len < 2) return false; ev->type = SND_SEQ_EVENT_SONGSEL; snd_seq_ev_set_fixed(ev); ev->data.control.value = m[1]; return true;
    case 0xf6: ev->type = SND_SEQ_EVENT_TUNE_REQUEST; snd_seq_ev_set_fixed(ev); return true;
    case 0xf8: ev->type = SND_SEQ_EVENT_CLOCK; snd_seq_ev_set_fixed(ev); return true;
    case 0xfa: ev->type = SND_SEQ_EVENT_START; snd_seq_ev_set_fixed(ev); return true;
    case 0xfb: ev->type = SND_SEQ_EVENT_CONTINUE; snd_seq_ev_set_fixed(ev); return true;
    case 0xfc: ev->type = SND_SEQ_EVENT_STOP; snd_seq_ev_set_fixed(ev); return true;
    case 0xfe: ev->type = SND_SEQ_EVENT_SENSING; snd_seq_ev_set_fixed(ev); return true;
    case 0xff: ev->type = SND_SEQ_EVENT_RESET; snd_seq_ev_set_fixed(ev); return true;
    }
    return false; // F4 F5 F7 F9 FD: nothing a sequencer port carries
}

class Pump {
  public:
    Pump(const Sink &sink, size_t capacity = 2048) : sink_(sink), q_(capacity) { sem_init(&wake_, 0, 0); }
    ~Pump() {
        stop();
        sem_destroy(&wake_);
    }
    Pump(const Pump &) = delete;
    Pump &operator=(const Pump &) = delete;
    void set_clock(double (*now)(void *), void *ctx) { clock_ = now; clock_ctx_ = ctx; }
    void set_logger(void (*fn)(const char *, void *), void *ctx) { log_ = fn; log_ctx_ = ctx; }

    // a script's bytes: never waits (a lock only between senders, held for the cutting), never allocates
    long send(const uint8_t *data, size_t n) {
        if (data == NULL || n == 0) {
            return 0;
        }
        while (lock_.test_and_set(std::memory_order_acquire)) {
        }
        midi_frame_split(data, n, &Pump::emit_thunk, this);
        lock_.clear(std::memory_order_release);
        sem_post(&wake_);
        report();
        return (long)n;
    }

    // deliver everything that is queued now, in order (the worker's body; the tests call it themselves). one caller at a time
    void run_once() {
        Item it;
        while (q_.try_dequeue(it)) {
            deliver(it);
        }
        report();
    }

    void start() {
        if (started_) {
            return;
        }
        stopping_ = false;
        if (pthread_create(&thread_, NULL, &Pump::worker_thunk, this) == 0) {
            started_ = true;
            pthread_setname_np(thread_, "aseq_out");
        }
    }

    void stop() {
        if (!started_) {
            return;
        }
        stopping_ = true;
        sem_post(&wake_);
        pthread_join(thread_, NULL);
        started_ = false;
    }

    Stats stats() const {
        return Stats{sent_.load(), dropped_full_.load(), dropped_error_.load()};
    }

  private:
    static void emit_thunk(const uint8_t *msg, size_t len, void *self) { ((Pump *)self)->enqueue(msg, len); }
    static void *worker_thunk(void *self) {
        ((Pump *)self)->worker();
        return NULL;
    }

    void enqueue(const uint8_t *msg, size_t len) {
        Item it;
        it.len = (uint16_t)len;
        memcpy(it.data, msg, len);
        if (!q_.try_enqueue(it)) {
            dropped_full_.fetch_add(1, std::memory_order_relaxed);
        }
    }

    void worker() {
        for (;;) {
            sem_wait(&wake_);
            if (stopping_.load()) {
                return;
            }
            run_once();
        }
    }

    void deliver(const Item &it) {
        snd_seq_event_t ev;
        if (!to_event(it.data, it.len, &ev)) {
            return; // an undefined byte: not an error
        }
        int r = 0;
        for (int attempt = 0; attempt < 4; attempt++) {
            r = sink_.output(sink_.ctx, &ev);
            if (r != -EAGAIN) {
                break;
            }
            if (!sink_.wait_room(sink_.ctx, 2)) {
                break;
            }
        }
        if (r >= 0) {
            sent_.fetch_add(1, std::memory_order_relaxed);
        } else {
            dropped_error_.fetch_add(1, std::memory_order_relaxed);
            last_error_.store(r, std::memory_order_relaxed);
        }
    }

    static double real_now(void *) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (double)ts.tv_sec + ts.tv_nsec / 1e9;
    }

    // dropped events are said at most every 10 seconds, with the totals since the last line (the counters are read here, never in a delivery)
    void report() {
        unsigned long f = dropped_full_.load(std::memory_order_relaxed), e = dropped_error_.load(std::memory_order_relaxed);
        if (f == said_full_.load(std::memory_order_relaxed) && e == said_error_.load(std::memory_order_relaxed)) {
            return;
        }
        long long now = (long long)((clock_ ? clock_(clock_ctx_) : real_now(NULL)) * 1000.0);
        long long last = last_ms_.load();
        if (last >= 0 && now - last < 10000) {
            return;
        }
        if (!last_ms_.compare_exchange_strong(last, now)) {
            return; // another thread says it
        }
        unsigned long pf = said_full_.exchange(f), pe = said_error_.exchange(e);
        char line[256];
        snprintf(line, sizeof line, "aseq_out: %lu message(s) dropped since the last line (%lu: the queue was full, %lu: the sequencer refused them, last error %d); said at most every 10 s", (f - pf) + (e - pe), f - pf, e - pe,
                 last_error_.load(std::memory_order_relaxed));
        if (log_) {
            log_(line, log_ctx_);
        } else {
            fprintf(stderr, "%s\n", line);
        }
    }

    Sink sink_;
    moodycamel::ReaderWriterQueue<Item> q_;
    std::atomic_flag lock_ = ATOMIC_FLAG_INIT;
    sem_t wake_;
    pthread_t thread_;
    bool started_ = false;
    std::atomic<bool> stopping_{false};
    std::atomic<unsigned long> sent_{0}, dropped_full_{0}, dropped_error_{0};
    std::atomic<unsigned long> said_full_{0}, said_error_{0};
    std::atomic<int> last_error_{0};
    std::atomic<long long> last_ms_{-1};
    double (*clock_)(void *) = NULL;
    void *clock_ctx_ = NULL;
    void (*log_)(const char *, void *) = NULL;
    void *log_ctx_ = NULL;
};

} // namespace aseq
