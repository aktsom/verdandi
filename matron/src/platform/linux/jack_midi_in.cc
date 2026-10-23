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

#include "device_list.h"
#include "../macos/product.h"
#include "readerwriterqueue.h"

#define JACK_MIDI_CLIENT MACOS_PRODUCT // "Verdandi"
#define JACK_MIDI_PORT "midi_in"
#define JACK_MIDI_DEVICE MACOS_PRODUCT " JACK in"
#define CHUNK 64          // bytes per queue entry: longer messages (sysex) are split, the parser takes the stream
#define QUEUE_ENTRIES 4096

namespace {

struct chunk_t {
    uint8_t len;
    uint8_t data[CHUNK];
};

jack_client_t *client = NULL;
jack_port_t *port = NULL;
moodycamel::ReaderWriterQueue<chunk_t> queue(QUEUE_ENTRIES);
sem_t wake;
std::atomic<bool> stopping{false};
std::atomic<unsigned> dropped{0};
int pipe_rd = -1, pipe_wr = -1;
pthread_t reader;

// real-time thread: copy, no allocation, no locks (try_enqueue never allocates; sem_post is real-time safe)
int process(jack_nframes_t nframes, void *) {
    void *buf = jack_port_get_buffer(port, nframes);
    jack_nframes_t count = jack_midi_get_event_count(buf);
    bool any = false;
    for (jack_nframes_t i = 0; i < count; i++) {
        jack_midi_event_t ev;
        if (jack_midi_event_get(&ev, buf, i) != 0) {
            continue;
        }
        for (size_t off = 0; off < ev.size; off += CHUNK) {
            chunk_t c;
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
    return 0;
}

void *reader_thread(void *) {
    for (;;) {
        sem_wait(&wake);
        if (stopping.load()) {
            return NULL;
        }
        chunk_t c;
        while (queue.try_dequeue(c)) {
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
        unsigned d = dropped.exchange(0);
        if (d > 0) {
            fprintf(stderr, "jack_midi_in: queue full, dropped %u events\n", d);
        }
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
    int fds[2];
    if (port == NULL || pipe(fds) != 0 || sem_init(&wake, 0, 0) != 0) {
        fprintf(stderr, "jack_midi_in: could not make the port\n");
        jack_client_close(client);
        client = NULL;
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
    fprintf(stderr, "jack_midi_in: JACK MIDI input %s:%s\n", JACK_MIDI_CLIENT, JACK_MIDI_PORT);
    // the device list takes its own lock; dev_midi_init picks the pipe up (jack_midi_in_take_pipe)
    dev_list_add(DEV_TYPE_MIDI, JACK_MIDI_PATH, strdup(JACK_MIDI_DEVICE), NULL);
    return 0;
}

int jack_midi_in_take_pipe(void) {
    int fd = pipe_rd;
    pipe_rd = -1;
    return fd;
}

const char *jack_midi_in_port_name(void) {
    return JACK_MIDI_CLIENT ":" JACK_MIDI_PORT;
}
