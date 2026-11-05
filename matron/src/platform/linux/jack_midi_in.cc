/*
 * jack_midi_in.cc: see jack_midi_in.h
 */

#include "jack_midi_in.h"

#include <errno.h>
#include <fcntl.h>
#include <jack/jack.h>
#include <jack/midiport.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <atomic>

#include "clocks/clock_midi.h"
#include "device_list.h"
#include "jack_client.h"
#include "midi_frame.h"
#include "../macos/product.h"
#include "readerwriterqueue.h"

#define JACK_MIDI_CLIENT MACOS_PRODUCT // "Verdandi"
#define JACK_MIDI_PORT "midi_in"
#define JACK_MIDI_PORT_OUT "midi_out"
#define JACK_MIDI_DEVICE "virtual" // the same device reads and sends (it was called "Verdandi JACK in")
#define CHUNK 64          // bytes per queue entry: longer messages (sysex) are split, the parser takes the stream
#define QUEUE_ENTRIES 4096
#define OUT_ENTRIES 2048  // messages a script sent, waiting for the next JACK cycle (a cycle is about 20 ms: a script would have to send 100 000 a second to fill it)

namespace {

struct chunk_t {
    uint32_t frame; // JACK frame time of the event (start of the cycle plus its offset)
    uint8_t len;
    uint8_t data[CHUNK];
};

// one message for the output port: the JACK frame time of the send and the whole message
struct out_msg_t {
    uint32_t frame;
    uint16_t len;
    uint8_t data[MIDI_FRAME_MAX];
};

jack_client_t *client = NULL;
jack_port_t *port = NULL;
jack_port_t *out_port = NULL;
moodycamel::ReaderWriterQueue<out_msg_t> out_queue(OUT_ENTRIES); // the capacity is made here, at start: enqueue by try_enqueue and dequeue never allocate
std::atomic_flag out_lock = ATOMIC_FLAG_INIT; // the senders (script thread, clock thread) take turns; the real-time thread never touches it
std::atomic<unsigned> out_dropped{0};
std::atomic<long long> last_report_ms{0};
std::atomic<int> out_last_error{0}; // the last error code of jack_midi_event_write that was not "full" (for the log line)
moodycamel::ReaderWriterQueue<chunk_t> queue(QUEUE_ENTRIES);
sem_t wake;
std::atomic<bool> stopping{false};
std::atomic<unsigned> dropped{0};
int pipe_rd = -1, pipe_wr = -1;
pthread_t reader;
// the device's "clock receive" switch (device_midi.cc gives the address); the clock is fed from here, with the
// event's own time, and the device parser leaves clock messages of this device alone
const bool *clock_enabled = NULL;

// real-time thread: copy, no allocation, no locks (try_enqueue never allocates; sem_post is real-time safe)
int process(jack_nframes_t nframes, void *) {
    void *buf = jack_port_get_buffer(port, nframes);
    jack_nframes_t count = jack_midi_get_event_count(buf);
    jack_nframes_t cycle_start = jack_last_frame_time(client);
    bool any = false;
    for (jack_nframes_t i = 0; i < count; i++) {
        jack_midi_event_t ev;
        if (jack_midi_event_get(&ev, buf, i) != 0) {
            continue;
        }
        for (size_t off = 0; off < ev.size; off += CHUNK) {
            chunk_t c;
            c.frame = cycle_start + ev.time;
            c.len = (uint8_t)(ev.size - off > CHUNK ? CHUNK : ev.size - off);
            memcpy(c.data, ev.buffer + off, c.len);
            if (queue.try_enqueue(c)) {
                any = true;
            } else {
                dropped.fetch_add(1, std::memory_order_relaxed);
            }
        }
    }
    if (any) {
        sem_post(&wake);
    }
    // the output: what scripts sent, one period later at the distances they were sent at (a clock tick that was sent 20 ms after the one before is written 20 ms
    // after it), never earlier than the one before in this cycle, and nothing at all when nothing was sent
    if (out_port != NULL) {
        void *obuf = jack_port_get_buffer(out_port, nframes);
        jack_midi_clear_buffer(obuf);
        size_t biggest = jack_midi_max_event_size(obuf);
        int32_t last = 0;
        size_t used = 0; // what the events of this cycle take of the budget of midi_frame.h (PipeWire's JACK layer cannot take more: a crash past it)
        int written = 0;
        for (;;) {
            out_msg_t *m = out_queue.peek();
            if (m == NULL) {
                break;
            }
            if (!midi_out_fits(used, written, m->len)) {
                break; // enough for this cycle: the rest waits in the queue for the next one
            }
            if (m->len > biggest) { // cannot ever fit: dropped, not allowed to block what comes after
                out_dropped.fetch_add(1, std::memory_order_relaxed);
                out_queue.pop();
                continue;
            }
            int32_t off = (int32_t)(m->frame + nframes - cycle_start);
            if (off >= (int32_t)nframes) {
                break; // for the next cycle
            }
            if (off < last) {
                off = last; // too old (a backlog) or out of order: now, after the one before
            }
            int r = jack_midi_event_write(obuf, (jack_nframes_t)off, m->data, m->len);
            if (r == -ENOBUFS) {
                break; // the port buffer is full: the rest waits for the next cycle
            }
            if (r != 0) {
                out_dropped.fetch_add(1, std::memory_order_relaxed);
                out_last_error.store(r, std::memory_order_relaxed);
            } else {
                last = off;
                used += midi_out_cost(m->len);
                written++;
            }
            out_queue.pop();
        }
    }
    return 0;
}

// a script thread: one whole message into the output queue (try_enqueue: no allocation, no waiting; a full queue drops it)
void out_emit(const uint8_t *msg, size_t len, void *frame) {
    out_msg_t m;
    m.frame = *(const uint32_t *)frame;
    m.len = (uint16_t)len;
    memcpy(m.data, msg, len);
    if (!out_queue.try_enqueue(m)) {
        out_dropped.fetch_add(1, std::memory_order_relaxed);
    }
}

// dropped events are counted where they happen (the real-time thread must not print) and said here, from a script's thread or the reader thread, at most every 10 seconds, with the totals since the last line
void report_drops(void) {
    if (out_dropped.load(std::memory_order_relaxed) == 0 && dropped.load(std::memory_order_relaxed) == 0) {
        return;
    }
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    long long now = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    long long last = last_report_ms.load();
    if (last != 0 && now - last < 10000) {
        return;
    }
    if (!last_report_ms.compare_exchange_strong(last, now)) {
        return;
    }
    unsigned o = out_dropped.exchange(0), i = dropped.exchange(0);
    fprintf(stderr, "jack_midi: events dropped since the last line: %u of the output (more sent than the JACK cycles could take, or one that the port refused: last error %d), %u of the input (norns was too slow to read them); said at most every 10 s\n", o,
            out_last_error.load(std::memory_order_relaxed), i);
}

void *reader_thread(void *) {
    for (;;) {
        sem_wait(&wake);
        if (stopping.load()) {
            return NULL;
        }
        chunk_t c;
        while (queue.try_dequeue(c)) {
            // clock messages: handled here, in order, with the time they happened (JACK delivers a period at once,
            // handling time would be quantised to periods: intervals of 0, tempo errors of a few percent)
            if (clock_enabled != NULL && *clock_enabled) {
                bool realtime = c.len == 1 && (c.data[0] == 0xf8 || c.data[0] == 0xfa || c.data[0] == 0xfb || c.data[0] == 0xfc);
                bool spp = c.len == 3 && c.data[0] == 0xf2;
                if (realtime || spp) {
                    // the event's time in the clock's time base: now, minus how long ago its frame was
                    uint32_t cur = (uint32_t)jack_frame_time(client);
                    double now = jack_client_get_current_time();
                    double t = now - (double)(int32_t)(cur - c.frame) / jack_get_sample_rate(client);
                    if (realtime) {
                        clock_midi_handle_message_at(c.data[0], t);
                    } else {
                        clock_midi_handle_song_position((uint16_t)(c.data[1] | (c.data[2] << 7)));
                    }
                }
            }
            // the pipe is blocking: if norns' MIDI thread is slow this thread waits, the queue (4096 entries)
            // absorbs it, and the real-time thread never waits
            ssize_t done = 0;
            while (done < c.len) {
                ssize_t n = write(pipe_wr, c.data + done, (size_t)(c.len - done));
                if (n < 0) {
                    if (errno == EINTR) {
                        continue;
                    }
                    return NULL;
                }
                done += n;
            }
        }
        report_drops();
    }
}

} // namespace

int jack_midi_in_start(void) {
    const char *off = getenv("NORNS_JACK_MIDI");
    if (off != NULL && strcmp(off, "0") == 0) {
        fprintf(stderr, "jack_midi_in: off (NORNS_JACK_MIDI=0)\n");
        return -1;
    }
    if (client != NULL) {
        return 0;
    }
    jack_status_t status;
    client = jack_client_open(JACK_MIDI_CLIENT, JackNoStartServer, &status);
    if (client == NULL) {
        fprintf(stderr, "jack_midi_in: no JACK client (%s): no JACK MIDI input\n", "is a JACK server running?");
        return -1;
    }
    port = jack_port_register(client, JACK_MIDI_PORT, JACK_DEFAULT_MIDI_TYPE, JackPortIsInput, 0);
    out_port = jack_port_register(client, JACK_MIDI_PORT_OUT, JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    int fds[2];
    if (port == NULL || out_port == NULL || pipe(fds) != 0 || sem_init(&wake, 0, 0) != 0) {
        fprintf(stderr, "jack_midi_in: could not make the port\n");
        jack_client_close(client);
        client = NULL;
        out_port = NULL;
        return -1;
    }
    pipe_rd = fds[0];
    pipe_wr = fds[1];
    jack_set_process_callback(client, process, NULL);
    if (pthread_create(&reader, NULL, reader_thread, NULL) != 0 || jack_activate(client) != 0) {
        fprintf(stderr, "jack_midi_in: could not start\n");
        jack_client_close(client);
        client = NULL;
        return -1;
    }
    pthread_setname_np(reader, "jack_midi_in");
    fprintf(stderr, "jack_midi_in: JACK MIDI input %s:%s, output %s:%s (the device \"%s\")\n", JACK_MIDI_CLIENT, JACK_MIDI_PORT, JACK_MIDI_CLIENT, JACK_MIDI_PORT_OUT, JACK_MIDI_DEVICE);
    // the device list takes its own lock; dev_midi_init picks the pipe up (jack_midi_in_take_pipe)
    dev_list_add(DEV_TYPE_MIDI, JACK_MIDI_PATH, strdup(JACK_MIDI_DEVICE), NULL);
    return 0;
}

void jack_midi_in_set_clock_flag(const bool *flag) {
    clock_enabled = flag;
}

int jack_midi_in_take_pipe(void) {
    int fd = pipe_rd;
    pipe_rd = -1;
    return fd;
}

const char *jack_midi_in_port_name(void) {
    return JACK_MIDI_CLIENT ":" JACK_MIDI_PORT;
}

const char *jack_midi_out_port_name(void) {
    return JACK_MIDI_CLIENT ":" JACK_MIDI_PORT_OUT;
}

long jack_midi_out_send(const uint8_t *data, size_t n) {
    if (client == NULL || out_port == NULL) {
        return -1;
    }
    // the time of the send in JACK frames (jack_frame_time may be called from any thread); the process callback keeps the distances
    uint32_t frame = (uint32_t)jack_frame_time(client);
    while (out_lock.test_and_set(std::memory_order_acquire)) {
        // another sender is cutting its bytes (microseconds): this is not the real-time thread
    }
    midi_frame_split(data, n, out_emit, &frame);
    out_lock.clear(std::memory_order_release);
    report_drops();
    return (long)n;
}
