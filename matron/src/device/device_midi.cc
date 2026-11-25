#ifndef __APPLE__
#include <alsa/asoundlib.h>
#endif
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "../events.h"

#include "../clocks/clock_midi.h"
#include "../clock.h"

#include "device.h"
#include "device_midi.h"
#ifdef NORNS_LINUX_DESKTOP
#include <errno.h>
#include <time.h>
#include <unistd.h>

#include "device_monitor.h"
#include "platform/linux/aseq_out.h"
#include "platform/linux/jack_midi_in.h"
#include "platform/linux/keys_midi.h"
#endif

#define DEV_MIDI_INPUT_BUFFER_SIZE 128

#if defined(NORNS_LINUX_DESKTOP) && !defined(NORNS_WINDOWS) && !defined(__APPLE__)
// M37 (docs/port/phase-m37.md): the raw port is opened WITHOUT waiting. a blocking snd_rawmidi_open on a port that another program holds does not answer "busy": the kernel puts the caller to
// sleep until the other program lets go, and the caller was the start-up (or the thread that looks at the cards). why the last open failed is kept per thread for the device list, which says it once
static __thread int last_open_busy;
static __thread char last_open_why[160];

extern "C" int dev_midi_open_failure(char *why, size_t n) {
    if (why != NULL && n > 0) {
        snprintf(why, n, "%s", last_open_why);
    }
    return last_open_busy;
}

static void open_failed(int busy, const char *what, int err) {
    last_open_busy = busy;
    if (busy) {
        snprintf(last_open_why, sizeof last_open_why, "busy: another program has it open%s%s", what != NULL && what[0] ? " (its " : "", what != NULL && what[0] ? what : "");
        if (what != NULL && what[0]) {
            size_t l = strlen(last_open_why);
            snprintf(last_open_why + l, sizeof last_open_why - l, ")");
        }
    } else {
        snprintf(last_open_why, sizeof last_open_why, "could not be opened: %s", snd_strerror(err));
    }
}

static double midi_now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

static bool open_is_busy(int err) {
    return err == -EBUSY || err == -EAGAIN;
}

// the input and the output are opened one after the other, both non-blocking. 0: at least one is open (the other may be missing: a device with no input or no output, as before)
// -1: busy or not openable (what was opened is closed again, last_open_* says why)
static int rawmidi_open_pair(snd_rawmidi_t **in, snd_rawmidi_t **out, const char *name) {
    *in = NULL;
    *out = NULL;
    last_open_busy = 0;
    last_open_why[0] = '\0';
    int ein = snd_rawmidi_open(in, NULL, name, SND_RAWMIDI_NONBLOCK);
    if (ein < 0) {
        *in = NULL;
    }
    int eout = snd_rawmidi_open(NULL, out, name, SND_RAWMIDI_NONBLOCK);
    if (eout < 0) {
        *out = NULL;
    }
    if (open_is_busy(ein) || open_is_busy(eout)) {
        if (*in != NULL) {
            snd_rawmidi_close(*in);
            *in = NULL;
        }
        if (*out != NULL) {
            snd_rawmidi_close(*out);
            *out = NULL;
        }
        open_failed(1, open_is_busy(ein) ? "input" : "output", 0);
        return -1;
    }
    if (ein < 0 && eout < 0) {
        open_failed(0, NULL, ein);
        return -1;
    }
    if (*in != NULL) {
        // the reader thread waits in snd_rawmidi_read: that handle is blocking again (it has a file of its own: the output stays non-blocking)
        snd_rawmidi_nonblock(*in, 0);
    }
    return 0;
}
#endif

#if !defined(__APPLE__) && !defined(NORNS_WINDOWS)
unsigned int dev_midi_port_count(const char *path) {
    int card;
    int alsa_dev;

#ifdef NORNS_LINUX_DESKTOP
    if (strcmp(path, KEYS_MIDI_PATH) == 0 || strcmp(path, JACK_MIDI_PATH) == 0) {
        return 1;
    }
#endif

    if (sscanf(path, "/dev/snd/midiC%dD%d", &card, &alsa_dev) < 0) {
        // TODO: Insert error message here
        return 0;
    }

    // mostly from amidi.c
    snd_ctl_t *ctl;
    char name[32];

    snd_rawmidi_info_t *info;
    int subs = 0;
    int subs_in = 0;
    int subs_out = 0;

    sprintf(name, "hw:%d", card);
    if (snd_ctl_open(&ctl, name, 0) < 0) {
        // TODO: Insert error message here
        return 0;
    }

    snd_rawmidi_info_alloca(&info);
    snd_rawmidi_info_set_device(info, alsa_dev);

    snd_rawmidi_info_set_stream(info, SND_RAWMIDI_STREAM_INPUT);
    if (snd_ctl_rawmidi_info(ctl, info) >= 0) {
        subs_in = snd_rawmidi_info_get_subdevices_count(info);
    }

    snd_rawmidi_info_set_stream(info, SND_RAWMIDI_STREAM_OUTPUT);
    if (snd_ctl_rawmidi_info(ctl, info) >= 0) {
        subs_out = snd_rawmidi_info_get_subdevices_count(info);
    }
    snd_ctl_close(ctl);

    subs = subs_in > subs_out ? subs_in : subs_out;
    return subs;
}

int dev_midi_init(void *self, unsigned int port_index, bool multiport_device) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;

    unsigned int alsa_card;
    unsigned int alsa_dev;
    char *alsa_name;

#ifdef NORNS_LINUX_DESKTOP
    if (strcmp(base->path, KEYS_MIDI_PATH) == 0 || strcmp(base->path, JACK_MIDI_PATH) == 0) {
        // the virtual keyboard window and the JACK MIDI input: input only, from the pipe they write
        midi->pipe_rd = strcmp(base->path, KEYS_MIDI_PATH) == 0 ? keys_midi_take_pipe() : jack_midi_in_take_pipe();
        if (midi->pipe_rd < 0) {
            return -1;
        }
        midi->from_pipe = true;
        if (strcmp(base->path, JACK_MIDI_PATH) == 0) {
            midi->jack_out = true;
            midi->clock_timed = true;
            jack_midi_in_set_clock_flag(&midi->clock_enabled);
        }
        midi->handle_in = NULL;
        midi->handle_out = NULL;
        base->start = &dev_midi_start;
        base->deinit = &dev_midi_deinit;
        midi->clock_enabled = true;
        return 0;
    }
#endif

    sscanf(base->path, "/dev/snd/midiC%uD%u", &alsa_card, &alsa_dev);
#ifdef NORNS_LINUX_DESKTOP
    midi->port_index = port_index;
    midi->gone = 0;
#endif

    if (asprintf(&alsa_name, "hw:%u,%u,%u", alsa_card, alsa_dev, port_index) < 0) {
        fprintf(stderr, "failed to create alsa device name for card %d,%d\n", alsa_card, alsa_dev);
        return -1;
    }

#ifdef NORNS_LINUX_DESKTOP
    if (rawmidi_open_pair(&midi->handle_in, &midi->handle_out, alsa_name) < 0) {
        free(alsa_name);
        return -1;
    }
    if (midi->handle_in != NULL && midi->handle_out != NULL) {
        fprintf(stderr, "device opened (bidirectional)\n");
    } else if (midi->handle_in != NULL) {
        fprintf(stderr, "device opened OK, only input ports\n");
    } else {
        fprintf(stderr, "device opened OK, only output ports\n");
    }
    free(alsa_name);
#else
    if (snd_rawmidi_open(&midi->handle_in, &midi->handle_out, alsa_name, 0) < 0) {
        if (snd_rawmidi_open(NULL, &midi->handle_out, alsa_name, 0) < 0) {
            if (snd_rawmidi_open(&midi->handle_in, NULL, alsa_name, 0) < 0) {
                return -1;
            } else {
                fprintf(stderr, "device opened OK, only input ports\n");
                midi->handle_out = NULL;
            }
        } else {
            fprintf(stderr, "device opened OK, only output ports\n");
            midi->handle_in = NULL;
        }
    } else {
        fprintf(stderr, "device opened (bidirectional)\n");
    }
#endif
    // fprintf(stderr, "input handle  : %p\n", midi->handle_in);
    // fprintf(stderr, "output handle : %p\n", midi->handle_out);

    char *name_with_port_index;
    if (multiport_device) {
        if (asprintf(&name_with_port_index, "%s %u", base->name, port_index + 1) < 0) {
            fprintf(stderr, "failed to create human-readable device name for card %d,%d,%d\n", alsa_card, alsa_dev,
                    port_index);
            return -1;
        } else {
            fprintf(stderr, "assigned device name with port: %s\n", name_with_port_index);
        }
        base->name = name_with_port_index;
    }

    if (midi->handle_in != NULL) {
        base->start = &dev_midi_start;
    } else {
        base->start = NULL;
    }
    base->deinit = &dev_midi_deinit;

    midi->clock_enabled = true;

    return 0;
}

int dev_midi_virtual_init(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;

    if (snd_rawmidi_open(&midi->handle_in, &midi->handle_out, "virtual", 0) < 0) {
        fprintf(stderr, "failed to open alsa virtual device.\n");
        return -1;
    }

    // trigger reading
    snd_rawmidi_read(midi->handle_in, NULL, 0);

    base->start = &dev_midi_start;
    base->deinit = &dev_midi_deinit;

    return 0;
}

void dev_midi_deinit(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    // struct dev_common *base = (struct dev_common *)self;
    // fprintf(stderr, "midi_deinit   : %s\n", base->name);
    // fprintf(stderr, "input handle  : %p\n", midi->handle_in);
    // fprintf(stderr, "output handle : %p\n", midi->handle_out);

#ifdef NORNS_LINUX_DESKTOP
    if (midi->from_pipe) {
        close(midi->pipe_rd);
        return;
    }
#endif
    if (midi->handle_in != NULL) {
        snd_rawmidi_close(midi->handle_in);
    }
    if (midi->handle_out != NULL) {
        snd_rawmidi_close(midi->handle_out);
    }
}

#endif // !__APPLE__ && !NORNS_WINDOWS

static inline bool is_status_byte(uint8_t byte) {
    return (byte & 0xf0) >> 7;
}

static inline bool is_status_real_time(uint8_t byte) {
    return byte >= 0xf8;
}

static inline uint8_t midi_msg_len(uint8_t status) {
    uint8_t upper = status & 0xf0;

    // channel voice messages
    switch (upper) {
    case 0x80: // note off
    case 0x90: // note on
    case 0xa0: // polyphonic key pressure
    case 0xb0: // control change
    case 0xe0: // pitch bend
        return 3;
    case 0xc0: // program change
    case 0xd0: // channel pressure
        return 2;
    }

    // system real-time messages
    switch (status) {
    case 0xf8: // timing clock
    case 0xfa: // start sequence
    case 0xfb: // continue sequence
    case 0xfc: // stop sequence
    case 0xfe: // active sensing
    case 0xff: // system reset
        return 1;
    }

    // system common messages
    switch (status) {
    case 0xf1: // midi timing code
    case 0xf3: // song select
        return 2;
    case 0xf2: // song position pointer
        return 3;
    case 0xf6: // tune request
        return 1;
    }

    // system exclusive messages (variable length)
    switch (status) {
    case 0xf0:    // sysex start
        return 3; // special case, deliver sysex to lua in 3 byte chunks
    case 0xf7:    // sysex stop
        return 1; // special case, allow single sysex stop as isolated event
    }

    // channel mode messages
    return 2;
}

typedef struct {
    uint8_t buffer[DEV_MIDI_INPUT_BUFFER_SIZE];

    uint8_t prior_status;
    uint8_t prior_len;

    uint8_t msg_buf[3];
    uint8_t msg_pos;
    uint8_t msg_len;
    bool msg_started;
    bool msg_sysex;
} midi_input_state_t;

static inline void midi_input_msg_post(midi_input_state_t *state, struct dev_midi *midi) {
    union event_data *ev = event_data_new(EVENT_MIDI_EVENT);
    ev->midi_event.id = midi->dev.id;
    ev->midi_event.nbytes = state->msg_len;
    for (uint8_t n = 0; n < state->msg_len; n++) {
        ev->midi_event.data[n] = state->msg_buf[n];
    }
    event_post(ev);
}

static inline void midi_input_msg_start(midi_input_state_t *state, uint8_t status) {
    state->msg_pos = 0;
    state->msg_len = midi_msg_len(status);
    state->msg_started = true;
    state->msg_buf[state->msg_pos++] = status;
    state->msg_sysex = status == 0xf0;

    // save for running status
    if (!is_status_real_time(status)) {
        state->prior_status = status;
        state->prior_len = state->msg_len;
    }
}

static inline void midi_input_msg_end(midi_input_state_t *state) {
    state->msg_started = false;
    state->msg_pos = 0;
}

static inline void midi_input_msg_acc(midi_input_state_t *state, uint8_t byte) {
    if (!state->msg_started) {
        if (state->msg_sysex) {
            // continue to pass sysex through in 3 byte chunks
            state->msg_started = true;
            state->msg_pos = 0;
            state->msg_len = 3;
        } else {
            // running status, start a new message
            state->msg_started = true;
            state->msg_pos = 0;
            state->msg_len = state->prior_len;
            state->msg_buf[state->msg_pos++] = state->prior_status;
        }
    }

    state->msg_buf[state->msg_pos++] = byte;

    // terminate sysex
    if (byte == 0xf7) {
        state->msg_sysex = false;
        state->msg_len = state->msg_pos;
    }
}

static inline bool midi_input_msg_is_complete(midi_input_state_t *state) {
    return state->msg_started && (state->msg_len == state->msg_pos);
}

static inline ssize_t dev_midi_consume_buffer(midi_input_state_t *state, ssize_t size, struct dev_midi *midi) {
    uint8_t i = 0;
    uint8_t byte = 0;

    for (i = 0; i < size; i++) {
        byte = state->buffer[i];

        if (byte >= 0xf8) {
#ifdef NORNS_LINUX_DESKTOP
            if (midi->clock_enabled && !midi->clock_timed) {
#else
            if (midi->clock_enabled) {
#endif
                clock_midi_handle_message(byte);
            }
        }

        if (is_status_byte(byte) && (byte != 0xf7)) {
            midi_input_msg_start(state, byte);
        } else {
            midi_input_msg_acc(state, byte);
        }

        if (midi_input_msg_is_complete(state)) {
            // song position pointer: 0xf2, then 7 bits LSB and 7 bits MSB (midi beats)
#ifdef NORNS_LINUX_DESKTOP
            if (state->msg_len == 3 && state->msg_buf[0] == 0xf2 && midi->clock_enabled && !midi->clock_timed) {
#else
            if (state->msg_len == 3 && state->msg_buf[0] == 0xf2 && midi->clock_enabled) {
#endif
                clock_midi_handle_song_position((uint16_t)(state->msg_buf[1] | (state->msg_buf[2] << 7)));
            }
            midi_input_msg_post(state, midi);
            midi_input_msg_end(state);
        }
    }

    return i;
}

#ifdef __APPLE__
#include "platform/macos/device_midi_coremidi.inc"
#elif defined(NORNS_WINDOWS)
#include "platform/windows/midi/device_midi_win.inc"
#else
void *dev_midi_start(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;

    snd_rawmidi_status_t *status = NULL;

    midi_input_state_t state;
    ssize_t read = 0;
    ssize_t xruns;

#ifdef NORNS_LINUX_DESKTOP
    if (midi->from_pipe) {
        // the virtual keyboard window: the same parser, bytes from a pipe
        memset(&state, 0, sizeof state);
        do {
            read = ::read(midi->pipe_rd, state.buffer, DEV_MIDI_INPUT_BUFFER_SIZE);
            if (read > 0 && dev_midi_consume_buffer(&state, read, midi) != read) {
                fprintf(stderr, "midi inconsistency for device: %s\n", base->name);
            }
        } while (read > 0 || (read < 0 && errno == EINTR));
        return NULL;
    }
#endif

    if (midi->handle_in == NULL) {
        fprintf(stderr, "starting a reader thread for a non-input MIDI device; shouldn't get here!\n");
        return NULL;
    }

    // fprintf(stderr, "starting input thread for midi device: %s (%p)\n", base->name, midi->handle_in);

    if (snd_rawmidi_status_malloc(&status) != 0) {
        fprintf(stderr, "failed allocating rawmidi status, stopping device: %s\n", base->name);
        return NULL;
    }

    do {
        read = snd_rawmidi_read(midi->handle_in, state.buffer, DEV_MIDI_INPUT_BUFFER_SIZE);
#ifdef NORNS_LINUX_DESKTOP
        if (read < 0) {
            // the device is gone (unplugged, powered off): not an inconsistency of the data. the list is told: the entry goes without waiting for a udev event that may never come, and
            // a device of the same node that comes back takes its place (docs/port/KNOWN-ISSUES.md 36)
            fprintf(stderr, "midi: %s vanished (read error %d); it leaves the list\n", base->name, (int)read);
            midi->gone = 1;
            dev_monitor_poke();
            break;
        }
#endif
        if (dev_midi_consume_buffer(&state, read, midi) != read) {
            fprintf(stderr, "midi inconsistency for device: %s\n", base->name);
        }

        if (snd_rawmidi_status(midi->handle_in, status) == 0) {
            xruns = snd_rawmidi_status_get_xruns(status);
            if (xruns > 0) {
                fprintf(stderr, "xruns (%d) for midi device: %s\n", (int)xruns, base->name);
                snd_rawmidi_drop(midi->handle_in);
            }
        }

    } while (read > 0);

    if (status) {
        snd_rawmidi_status_free(status);
    }

    return NULL;
}

ssize_t dev_midi_send(void *self, uint8_t *data, size_t n) {
    struct dev_midi *midi = (struct dev_midi *)self;
#ifdef NORNS_LINUX_DESKTOP
    if (midi->from_pipe) {
        // the JACK device ("virtual"): the JACK port Verdandi:midi_out and the ALSA sequencer port "Verdandi out" (either may be missing); the keys window has no output
        if (!midi->jack_out) {
            return -1;
        }
        long j = jack_midi_out_send(data, n);
        long a = aseq_out_send(data, n);
        return (j >= 0 || a >= 0) ? (ssize_t)n : -1;
    }
#endif
    if (midi->handle_out == NULL) {
        return -1;
    }
#ifdef NORNS_LINUX_DESKTOP
    // the output handle is non-blocking (M37): a device that takes nothing (its buffer is full: not draining, a driver that stalled) answers -EAGAIN, and this function runs on the thread of the
    // script. it waits for a device that is slow but takes data (a long sysex to a DIN port), and gives up on one that takes nothing for 250 ms (5 s at most in all): the rest is dropped, said once
    size_t done = 0;
    double begin = midi_now_s(), last_progress = begin;
    while (done < n) {
        ssize_t r = snd_rawmidi_write(midi->handle_out, data + done, n - done);
        if (r > 0) {
            done += (size_t)r;
            last_progress = midi_now_s();
            continue;
        }
        if (r != -EAGAIN) {
            return done > 0 ? (ssize_t)done : r;
        }
        double now = midi_now_s();
        if (now - last_progress > 0.25 || now - begin > 5.0) {
            if (now - midi->last_drop_say > 5.0) {
                midi->last_drop_say = now;
                fprintf(stderr, "midi: %s does not take data (its output is full): %u of %u bytes dropped\n", ((struct dev_common *)self)->name != NULL ? ((struct dev_common *)self)->name : "?",
                        (unsigned)(n - done), (unsigned)n);
            }
            return done > 0 ? (ssize_t)done : -EAGAIN;
        }
        usleep(1000);
    }
    return (ssize_t)done;
#else
    return snd_rawmidi_write(midi->handle_out, data, n);
#endif
}
#endif // __APPLE__ / NORNS_WINDOWS / ALSA
