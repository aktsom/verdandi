/*
 * bridge_protocol.h
 *
 * UDP on 127.0.0.1 between the norns AUv3 (in the DAW) and auv3_bridge (a jack client next
 * to norns). the AU sends fixed blocks of the DAW's input; the bridge answers each block
 * with as many frames of norns' output (resampled from the norns clock to the DAW's).
 * MIDI from the DAW travels as raw bytes. one machine, so native byte order.
 */

#pragma once

#include <stdint.h>

#define NB_MAGIC 0x4e524e53u // 'NRNS'
#define NB_PORT 10200        // bridge port on 127.0.0.1 (env NORNS_AUV3_PORT)
#define NB_BLOCK 128         // frames per audio packet
#define NB_CHANNELS 2
#define NB_MAX_MIDI 1024

enum {
    NB_AUDIO = 1, // AU -> bridge: DAW input; bridge -> AU: norns output (same seq, same frames)
    NB_MIDI = 2,  // AU -> bridge: raw MIDI bytes (count in frames)
    NB_BYE = 3,   // AU -> bridge: stopped rendering
};

typedef struct {
    uint32_t magic;
    uint16_t type;
    uint16_t frames;      // audio frames, or MIDI byte count
    uint32_t seq;
    uint32_t sample_rate; // DAW sample rate (audio packets)
} nb_header_t;

// audio payload: NB_CHANNELS planar float blocks of `frames` samples
#define NB_AUDIO_BYTES(frames) ((frames) * NB_CHANNELS * (int)sizeof(float))
#define NB_MAX_PACKET ((int)sizeof(nb_header_t) + NB_AUDIO_BYTES(NB_BLOCK) + NB_MAX_MIDI)
