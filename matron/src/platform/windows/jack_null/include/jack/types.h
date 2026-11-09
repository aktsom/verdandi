/*
 * jack/types.h of the JACK-compatible NULL backend (matron/src/platform/windows/jack_null). only what norns uses. the names and values are those of
 * the JACK API (so that crone and matron compile unchanged); the implementation is jack_null.c: an in-process audio graph driven by a timer, no audio device.
 * the API is an interface, not code from JACK.
 */
#ifndef VERDANDI_JACK_NULL_TYPES_H
#define VERDANDI_JACK_NULL_TYPES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t jack_nframes_t;
typedef uint64_t jack_time_t;
typedef uint32_t jack_port_id_t;
typedef float jack_default_audio_sample_t;

typedef struct _jack_client jack_client_t;
typedef struct _jack_port jack_port_t;

typedef enum {
    JackNullOption = 0x00,
    JackNoStartServer = 0x01,
    JackUseExactName = 0x02,
    JackServerName = 0x04
} jack_options_t;

typedef enum {
    JackFailure = 0x01,
    JackInvalidOption = 0x02,
    JackNameNotUnique = 0x04,
    JackServerStarted = 0x08,
    JackServerFailed = 0x10,
    JackServerError = 0x20,
    JackNoSuchClient = 0x40,
    JackLoadFailure = 0x80,
    JackInitFailure = 0x100,
    JackShmFailure = 0x200,
    JackVersionError = 0x400,
    JackBackendError = 0x800,
    JackClientZombie = 0x1000
} jack_status_t;

enum JackPortFlags {
    JackPortIsInput = 0x1,
    JackPortIsOutput = 0x2,
    JackPortIsPhysical = 0x4,
    JackPortCanMonitor = 0x8,
    JackPortIsTerminal = 0x10
};

#define JACK_MAX_FRAMES (4294967295U)
#define JACK_DEFAULT_AUDIO_TYPE "32 bit float mono audio"
#define JACK_DEFAULT_MIDI_TYPE "8 bit raw midi"

typedef int (*JackProcessCallback)(jack_nframes_t nframes, void *arg);
typedef void (*JackShutdownCallback)(void *arg);
typedef int (*JackXRunCallback)(void *arg);
typedef void (*JackPortRegistrationCallback)(jack_port_id_t port, int registered, void *arg);
typedef void (*JackClientRegistrationCallback)(const char *name, int registered, void *arg);

#ifdef __cplusplus
}
#endif

#endif
