/*
 * keys_midi.cc: see keys_midi.h
 */

#include "keys_midi.h"

#include <alsa/asoundlib.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "device_list.h"
#include "../macos/product.h"

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int pipe_rd = -1, pipe_wr = -1;
static int is_open = 0;

// B: the sequencer port, optional
static snd_seq_t *seq = NULL;
static snd_midi_event_t *encoder = NULL;
static int seq_port = -1;

static void seq_open(void) {
    if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_OUTPUT, 0) < 0) {
        seq = NULL;
        fprintf(stderr, "keys_midi: no ALSA sequencer here, \"norns keys\" is visible to norns only\n");
        return;
    }
    snd_seq_set_client_name(seq, MACOS_PRODUCT);
    seq_port = snd_seq_create_simple_port(seq, "norns keys", SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ,
                                          SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
    if (seq_port < 0 || snd_midi_event_new(32, &encoder) < 0) {
        fprintf(stderr, "keys_midi: could not make the ALSA sequencer port\n");
        if (encoder != NULL) {
            snd_midi_event_free(encoder);
            encoder = NULL;
        }
        snd_seq_close(seq);
        seq = NULL;
        seq_port = -1;
        return;
    }
    snd_midi_event_no_status(encoder, 1);
    fprintf(stderr, "keys_midi: ALSA sequencer port %d:%d (%s \"norns keys\")\n", snd_seq_client_id(seq), seq_port,
            MACOS_PRODUCT);
}

static void seq_close(void) {
    if (encoder != NULL) {
        snd_midi_event_free(encoder);
        encoder = NULL;
    }
    if (seq != NULL) {
        snd_seq_close(seq);
        seq = NULL;
    }
    seq_port = -1;
}

int keys_midi_open(void) {
    pthread_mutex_lock(&lock);
    if (is_open) {
        pthread_mutex_unlock(&lock);
        return 0;
    }
    int fds[2];
    if (pipe(fds) != 0) {
        pthread_mutex_unlock(&lock);
        perror("keys_midi: pipe");
        return -1;
    }
    // never block the window: if norns stalls, bytes are dropped
    fcntl(fds[1], F_SETFL, O_NONBLOCK);
    pipe_rd = fds[0];
    pipe_wr = fds[1];
    is_open = 1;
    seq_open();
    pthread_mutex_unlock(&lock);
    // the device list takes its own lock; dev_midi_init picks the pipe up (keys_midi_take_pipe)
    dev_list_add(DEV_TYPE_MIDI, KEYS_MIDI_PATH, strdup(MACOS_PRODUCT " keys"), NULL);
    return 0;
}

void keys_midi_close(void) {
    pthread_mutex_lock(&lock);
    if (!is_open) {
        pthread_mutex_unlock(&lock);
        return;
    }
    pthread_mutex_unlock(&lock);
    // the device closes its end (dev_midi_deinit), then ours
    dev_list_remove(DEV_TYPE_MIDI, KEYS_MIDI_PATH);
    pthread_mutex_lock(&lock);
    if (pipe_rd >= 0) {
        // the device never started (could not be added): nobody took the read end
        close(pipe_rd);
    }
    if (pipe_wr >= 0) {
        close(pipe_wr);
    }
    pipe_rd = pipe_wr = -1;
    seq_close();
    is_open = 0;
    pthread_mutex_unlock(&lock);
}

int keys_midi_is_open(void) {
    return is_open;
}

int keys_midi_seq_up(void) {
    return seq != NULL;
}

int keys_midi_take_pipe(void) {
    pthread_mutex_lock(&lock);
    int fd = pipe_rd;
    pipe_rd = -1;
    pthread_mutex_unlock(&lock);
    return fd;
}

void keys_midi_send(uint8_t status, uint8_t d1, uint8_t d2) {
    const uint8_t msg[3] = {status, d1, d2};
    pthread_mutex_lock(&lock);
    if (!is_open) {
        pthread_mutex_unlock(&lock);
        return;
    }
    if (pipe_wr >= 0 && write(pipe_wr, msg, 3) < 0 && errno == EAGAIN) {
        fprintf(stderr, "keys_midi: norns is not reading, dropped a message\n");
    }
    if (seq != NULL) {
        snd_seq_event_t ev;
        snd_seq_ev_clear(&ev);
        if (snd_midi_event_encode(encoder, msg, 3, &ev) > 0) {
            snd_seq_ev_set_source(&ev, seq_port);
            snd_seq_ev_set_subs(&ev);
            snd_seq_ev_set_direct(&ev);
            snd_seq_event_output_direct(seq, &ev);
        }
        snd_midi_event_reset_encode(encoder);
    }
    pthread_mutex_unlock(&lock);
}
