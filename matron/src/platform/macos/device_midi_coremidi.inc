// -*- c++ -*-
// device_midi_coremidi.inc
//
// CoreMIDI backend for device_midi.cc on macOS. included in place of the ALSA functions
// so the byte parser above (running status, sysex chunks, midi clock) stays shared.
//
// device paths are "coremidi:<unique id>" of a CoreMIDI entity (ports = its sources /
// destinations) or of a lone endpoint (another app's virtual source or destination).
// input: the CoreMIDI read callback writes raw bytes into a pipe; dev_midi_start reads the
// pipe on the device thread exactly like snd_rawmidi_read on linux.

#include <CoreMIDI/CoreMIDI.h>
#include <fcntl.h>
#include <unistd.h>

#include "platform/macos/device_runloop.h"

// the byte-stream API (MIDIPacketList) is deprecated since macOS 11 in favour of UMP,
// but it is still supported and maps 1:1 onto the rawmidi byte stream norns expects.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// stable ids so other apps remember the norns virtual port across launches
#define NORNS_VIRTUAL_SRC_UID 0x6e726e73 // 'nrns'
#define NORNS_VIRTUAL_DST_UID 0x6e726e64 // 'nrnd'

static MIDIPortRef midi_out_port = 0;
static pthread_mutex_t midi_out_port_lock = PTHREAD_MUTEX_INITIALIZER;

static MIDIObjectRef coremidi_lookup(const char *path, MIDIObjectType *type) {
    MIDIUniqueID uid;
    MIDIObjectRef obj = 0;
    if (path == NULL || sscanf(path, "coremidi:%d", &uid) != 1) {
        return 0;
    }
    if (MIDIObjectFindByUniqueID(uid, &obj, type) != noErr) {
        return 0;
    }
    return obj;
}

static int midi_pipe_open(struct dev_midi *midi) {
    int fds[2];
    if (pipe(fds) < 0) {
        perror("dev_midi: pipe");
        return -1;
    }
    // never block the CoreMIDI thread; if matron stalls the bytes are dropped (like an xrun)
    fcntl(fds[1], F_SETFL, O_NONBLOCK);
    midi->pipe_rd = fds[0];
    midi->pipe_wr = fds[1];
    return 0;
}

static void midi_pipe_write(int fd, const MIDIPacketList *pl) {
    const MIDIPacket *p = &pl->packet[0];
    for (UInt32 i = 0; i < pl->numPackets; i++) {
        if (write(fd, p->data, p->length) < 0 && errno == EAGAIN) {
            fprintf(stderr, "dev_midi: input overrun, dropped %u bytes\n", (unsigned)p->length);
        }
        p = MIDIPacketNext(p);
    }
}

unsigned int dev_midi_port_count(const char *path) {
    MIDIObjectType type;
    MIDIObjectRef obj = coremidi_lookup(path, &type);
    if (obj == 0) {
        return 0;
    }
    switch (type) {
    case kMIDIObjectType_Entity: {
        ItemCount s = MIDIEntityGetNumberOfSources(obj);
        ItemCount d = MIDIEntityGetNumberOfDestinations(obj);
        return (unsigned int)(s > d ? s : d);
    }
    case kMIDIObjectType_Source:
    case kMIDIObjectType_Destination:
        return 1;
    default:
        return 0;
    }
}

int dev_midi_init(void *self, unsigned int port_index, bool multiport_device) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;

    midi->src = midi->dst = midi->in_port = midi->vsrc = midi->vdst = 0;
    midi->pipe_rd = midi->pipe_wr = -1;

    MIDIClientRef client = coremidi_client();
    if (client == 0) {
        return -1;
    }

    MIDIObjectType type;
    MIDIObjectRef obj = coremidi_lookup(base->path, &type);
    if (obj == 0) {
        fprintf(stderr, "dev_midi: no CoreMIDI object for %s\n", base->path);
        return -1;
    }
    if (type == kMIDIObjectType_Entity) {
        if (port_index < MIDIEntityGetNumberOfSources(obj)) {
            midi->src = MIDIEntityGetSource(obj, port_index);
        }
        if (port_index < MIDIEntityGetNumberOfDestinations(obj)) {
            midi->dst = MIDIEntityGetDestination(obj, port_index);
        }
    } else if (type == kMIDIObjectType_Source) {
        midi->src = obj;
    } else if (type == kMIDIObjectType_Destination) {
        midi->dst = obj;
    }
    if (midi->src == 0 && midi->dst == 0) {
        return -1;
    }

    if (midi->src != 0) {
        if (midi_pipe_open(midi) < 0) {
            return -1;
        }
        MIDIPortRef port;
        int fd = midi->pipe_wr;
        OSStatus err = MIDIInputPortCreateWithBlock(client, CFSTR("norns in"), &port,
                                                    ^(const MIDIPacketList *pl, void *refcon) {
                                                      (void)refcon;
                                                      midi_pipe_write(fd, pl);
                                                    });
        if (err != noErr || MIDIPortConnectSource(port, midi->src, NULL) != noErr) {
            fprintf(stderr, "dev_midi: failed to open input for %s (%d)\n", base->path, (int)err);
            close(midi->pipe_rd);
            close(midi->pipe_wr);
            midi->pipe_rd = midi->pipe_wr = -1;
            midi->src = 0;
        } else {
            midi->in_port = port;
        }
    }

    if (midi->dst != 0) {
        pthread_mutex_lock(&midi_out_port_lock);
        if (midi_out_port == 0 && MIDIOutputPortCreate(client, CFSTR("norns out"), &midi_out_port) != noErr) {
            midi_out_port = 0;
        }
        pthread_mutex_unlock(&midi_out_port_lock);
        if (midi_out_port == 0) {
            midi->dst = 0;
        }
    }

    if (midi->src == 0 && midi->dst == 0) {
        return -1;
    }
    if (midi->src == 0) {
        fprintf(stderr, "device opened OK, only output ports\n");
    } else if (midi->dst == 0) {
        fprintf(stderr, "device opened OK, only input ports\n");
    } else {
        fprintf(stderr, "device opened (bidirectional)\n");
    }

    if (multiport_device) {
        char *name_with_port_index;
        if (asprintf(&name_with_port_index, "%s %u", base->name, port_index + 1) < 0) {
            return -1;
        }
        base->name = name_with_port_index;
    }

    base->start = midi->src != 0 ? &dev_midi_start : NULL;
    base->deinit = &dev_midi_deinit;
    midi->clock_enabled = true;
    return 0;
}

int dev_midi_virtual_init(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;

    midi->src = midi->dst = midi->in_port = midi->vsrc = midi->vdst = 0;
    midi->pipe_rd = midi->pipe_wr = -1;

    MIDIClientRef client = coremidi_client();
    if (client == 0 || midi_pipe_open(midi) < 0) {
        fprintf(stderr, "failed to open CoreMIDI virtual device.\n");
        return -1;
    }
    int fd = midi->pipe_wr;
    if (MIDISourceCreate(client, CFSTR("norns"), &midi->vsrc) != noErr ||
        MIDIDestinationCreateWithBlock(client, CFSTR("norns"), &midi->vdst, ^(const MIDIPacketList *pl, void *refcon) {
          (void)refcon;
          midi_pipe_write(fd, pl);
        }) != noErr) {
        fprintf(stderr, "failed to open CoreMIDI virtual device.\n");
        return -1;
    }
    // a collision just leaves the random id CoreMIDI assigned
    MIDIObjectSetIntegerProperty(midi->vsrc, kMIDIPropertyUniqueID, NORNS_VIRTUAL_SRC_UID);
    MIDIObjectSetIntegerProperty(midi->vdst, kMIDIPropertyUniqueID, NORNS_VIRTUAL_DST_UID);

    base->start = &dev_midi_start;
    base->deinit = &dev_midi_deinit;
    midi->clock_enabled = true;
    return 0;
}

void dev_midi_deinit(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    if (midi->in_port != 0) {
        MIDIPortDisconnectSource(midi->in_port, midi->src);
        MIDIPortDispose(midi->in_port);
    }
    if (midi->vsrc != 0) {
        MIDIEndpointDispose(midi->vsrc);
    }
    if (midi->vdst != 0) {
        MIDIEndpointDispose(midi->vdst);
    }
    if (midi->pipe_wr >= 0) {
        close(midi->pipe_wr);
    }
    if (midi->pipe_rd >= 0) {
        close(midi->pipe_rd);
    }
}

void *dev_midi_start(void *self) {
    struct dev_midi *midi = (struct dev_midi *)self;
    struct dev_common *base = (struct dev_common *)self;
    midi_input_state_t state = {};
    ssize_t n;

    if (midi->pipe_rd < 0) {
        fprintf(stderr, "starting a reader thread for a non-input MIDI device; shouldn't get here!\n");
        return NULL;
    }
    while ((n = read(midi->pipe_rd, state.buffer, DEV_MIDI_INPUT_BUFFER_SIZE)) > 0) {
        if (dev_midi_consume_buffer(&state, n, midi) != n) {
            fprintf(stderr, "midi inconsistency for device: %s\n", base->name);
        }
    }
    return NULL;
}

ssize_t dev_midi_send(void *self, uint8_t *data, size_t n) {
    struct dev_midi *midi = (struct dev_midi *)self;
    if (n == 0 || n > 0xffff || (midi->vsrc == 0 && midi->dst == 0)) {
        return -1;
    }
    size_t list_size = n + 256;
    MIDIPacketList *list = (MIDIPacketList *)malloc(list_size);
    if (list == NULL) {
        return -1;
    }
    MIDIPacket *pkt = MIDIPacketListInit(list);
    pkt = MIDIPacketListAdd(list, list_size, pkt, 0, n, data);
    OSStatus err = -1;
    if (pkt != NULL) {
        err = midi->vsrc != 0 ? MIDIReceived(midi->vsrc, list) : MIDISend(midi_out_port, midi->dst, list);
    }
    free(list);
    return err == noErr ? (ssize_t)n : -1;
}

#pragma clang diagnostic pop
