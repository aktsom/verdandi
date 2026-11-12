/*
 * verdandi_bridge.h (M2): the audio bridge between norns.exe and scsynth.exe, one header, plain C, no dependencies. It is included by norns.exe (the "host") and, copied into the
 * SuperCollider source tree by windows/ci/build-sc.sh, by the Verdandi audio driver of scsynth (the "guest", windows/patches/scsynth-null-audio.patch).
 *
 * Why: crone (mixer, softcut, tape) and the engines of SuperCollider are two programs. On Linux JACK joins them; on Windows norns.exe owns the sound card (one clock, one callback:
 * WASAPI through PortAudio) and runs crone's blocks inside that callback; scsynth does not open a device at all, it computes one block each time norns.exe has handed it one:
 *
 *      sound card callback (norns.exe) -> crone block -> push 2 channels to scsynth (the signal crone sends to engines: ADC, as crone:output_5/6 on Linux)
 *                                                      <- pull the block scsynth made for the previous callback (the engine output, crone:input_5/6)
 *      scsynth: wait for a block -> run the engine for it -> push the result
 *
 * Latency added by the bridge: one block (the engine's output reaches the mixer in the next callback). A ring of VB_RING blocks in a named shared memory, a named event wakes scsynth.
 * Nothing blocks the card's callback: when scsynth is late the host takes silence and counts an underrun; when scsynth is gone the host never waits.
 */
#ifndef VERDANDI_BRIDGE_H
#define VERDANDI_BRIDGE_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define VB_MAGIC 0x42444E56u /* "VNDB" */
#define VB_VERSION 2u
#define VB_RING 16u
#define VB_MAXFRAMES 2048u
#define VB_LATE_LIMIT 2u /* the host never lets more than this many blocks of scsynth wait for it: older ones are dropped (a bound on the latency) */

typedef struct {
    uint32_t magic, version;
    uint32_t rate, frames;
    uint32_t ring, reserved;
    volatile uint64_t to_w, to_r;     /* norns -> scsynth, in blocks */
    volatile uint64_t from_w, from_r; /* scsynth -> norns */
    volatile uint64_t host_underruns; /* the host wanted a block of scsynth's and there was none (only counted once scsynth has produced one) */
    volatile uint64_t host_drops;     /* blocks dropped: scsynth too slow (ring full) or late blocks discarded */
    volatile uint64_t guest_attached; /* 1 while a scsynth driver runs */
    volatile uint64_t guest_blocks;   /* blocks scsynth made */
    volatile uint64_t host_closed;    /* 1 when norns.exe ends: scsynth stops waiting */
    float to_sc[VB_RING][2 * VB_MAXFRAMES];
    float from_sc[VB_RING][2 * VB_MAXFRAMES];
} vb_shared;

typedef struct {
    vb_shared *sh;
    int host;
    volatile unsigned lag;   /* host only: how many blocks of scsynth's answers are held back (>= the number of engine blocks that run in one callback of the card, so that a burst of blocks finds its answers) */
    int primed;              /* host only: the held-back blocks are there */
    uint64_t calls, last_underrun_call; /* host only: exchanges so far, and the call of the last underrun (a second underrun soon after raises the hold-back by itself) */
    unsigned lag_base;       /* host only: the hold-back the card's way of calling asks for; a grown hold-back goes back down to it after a quiet time */
    unsigned grace_calls, decay_calls; /* host only: blocks after scsynth's first answer during which underruns do not make the hold-back grow (0: 15 s), and quiet blocks before it goes down by one (0: 60 s) */
    uint64_t first_guest_call, last_decay_call; /* host only */
    volatile unsigned raises; /* host only: how often the hold-back grew by itself */
#ifdef _WIN32
    HANDLE map, event;
#else
    char name[96];
#endif
} vb_t;

/* ---- counters with the barriers a one reader / one writer ring needs ---- */
#ifdef _WIN32
static inline uint64_t vb_load(volatile uint64_t *p) { return (uint64_t)InterlockedCompareExchange64((volatile LONG64 *)p, 0, 0); }
static inline void vb_store(volatile uint64_t *p, uint64_t v) { InterlockedExchange64((volatile LONG64 *)p, (LONG64)v); }
static inline uint64_t vb_add(volatile uint64_t *p, uint64_t v) { return (uint64_t)InterlockedExchangeAdd64((volatile LONG64 *)p, (LONG64)v) + v; }
#else
static inline uint64_t vb_load(volatile uint64_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void vb_store(volatile uint64_t *p, uint64_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }
static inline uint64_t vb_add(volatile uint64_t *p, uint64_t v) { return __atomic_add_fetch(p, v, __ATOMIC_ACQ_REL); }
#endif

/* ---- the operating system part: a named shared memory and a named event (Windows); a POSIX shared memory with polling (everything else: the tests on Linux) ---- */
#ifdef _WIN32
static inline void vb_names(const char *name, char *map, char *ev, size_t n) {
    snprintf(map, n, "Local\\%s", name);
    snprintf(ev, n, "Local\\%s.ev", name);
}
static inline int vb_os_open(vb_t *b, const char *name, int create) {
    char map[160], ev[160];
    vb_names(name, map, ev, sizeof map);
    if (create) {
        b->map = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, (DWORD)sizeof(vb_shared), map);
        b->event = CreateEventA(NULL, FALSE, FALSE, ev);
    } else {
        b->map = OpenFileMappingA(FILE_MAP_ALL_ACCESS, FALSE, map);
        b->event = OpenEventA(SYNCHRONIZE | EVENT_MODIFY_STATE, FALSE, ev);
    }
    if (!b->map || !b->event) {
        return -1;
    }
    b->sh = (vb_shared *)MapViewOfFile(b->map, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(vb_shared));
    return b->sh ? 0 : -1;
}
static inline void vb_os_close(vb_t *b) {
    if (b->sh) UnmapViewOfFile(b->sh);
    if (b->map) CloseHandle(b->map);
    if (b->event) CloseHandle(b->event);
    b->sh = NULL, b->map = b->event = NULL;
}
static inline void vb_os_signal(vb_t *b) { SetEvent(b->event); }
static inline void vb_os_wait(vb_t *b, unsigned ms) { WaitForSingleObject(b->event, ms); }
#else
static inline int vb_os_open(vb_t *b, const char *name, int create) {
    snprintf(b->name, sizeof b->name, "/%s", name);
    int fd = shm_open(b->name, create ? (O_RDWR | O_CREAT | O_TRUNC) : O_RDWR, 0600);
    if (fd < 0) return -1;
    if (create && ftruncate(fd, (off_t)sizeof(vb_shared)) != 0) {
        close(fd);
        return -1;
    }
    void *m = mmap(NULL, sizeof(vb_shared), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (m == MAP_FAILED) return -1;
    b->sh = (vb_shared *)m;
    return 0;
}
static inline void vb_os_close(vb_t *b) {
    if (b->sh) munmap((void *)b->sh, sizeof(vb_shared));
    if (b->host && b->name[0]) shm_unlink(b->name);
    b->sh = NULL;
}
static inline void vb_os_signal(vb_t *b) { (void)b; }
static inline void vb_os_wait(vb_t *b, unsigned ms) {
    (void)b;
    struct timespec ts = {0, (ms > 1 ? 1 : ms) * 500000L};
    nanosleep(&ts, NULL);
}
#endif

/* ---- the host (norns.exe) ---- */
/* creates the shared memory. false (-1) when the name is in use by a live bridge */
static inline int vb_host_create(vb_t *b, const char *name, unsigned rate, unsigned frames) {
    memset(b, 0, sizeof *b);
    if (frames == 0 || frames > VB_MAXFRAMES || frames % 64 != 0) return -2;
    b->host = 1;
    if (vb_os_open(b, name, 1) != 0) {
        return -1;
    }
    memset((void *)b->sh, 0, sizeof(vb_shared)); /* a fresh mapping is zero; a mapping of a crashed earlier run is not */
    b->sh->version = VB_VERSION;
    b->sh->rate = rate;
    b->sh->frames = frames;
    b->sh->ring = VB_RING;
    b->sh->magic = VB_MAGIC; /* last: the guest accepts the memory only with the magic */
    return 0;
}

/* called once per block of the sound card, by its callback: hand crone's engine feed to scsynth, take scsynth's last block. never waits. */
static inline void vb_host_exchange(vb_t *b, const float *to_l, const float *to_r, float *from_l, float *from_r) {
    vb_shared *s = b->sh;
    unsigned n = s->frames;
    uint64_t w = vb_load(&s->to_w), r = vb_load(&s->to_r);
    if (vb_load(&s->guest_attached)) {
        if (w - r < VB_RING) {
            float *d = s->to_sc[w % VB_RING];
            if (to_l) memcpy(d, to_l, n * sizeof(float)); else memset(d, 0, n * sizeof(float));
            if (to_r) memcpy(d + n, to_r, n * sizeof(float)); else memset(d + n, 0, n * sizeof(float));
            vb_store(&s->to_w, w + 1);
        } else {
            vb_add(&s->host_drops, 1);
        }
        vb_os_signal(b);
    }
    /* scsynth's answer: the oldest block that is not too old. `lag` blocks are held back: scsynth is another program and answers a moment after it was handed a block, so when the card's callback runs
     * several engine blocks in a row (a callback of 480 or 1024 frames with a 128 or 256 block) the answers of the earlier ones must already be there. after an underrun the lag is built up again */
    b->calls++;
    if (!b->first_guest_call && vb_load(&s->guest_blocks) > 0) {
        b->first_guest_call = b->calls; /* scsynth answered for the first time: its start-up (it loads synthdefs, the machine is busy) is not the way it will run */
    }
    unsigned lag = b->lag ? b->lag : 1;
    {
        /* a hold-back that grew goes down again, one block after each quiet minute (a transient must not cost delay for the rest of the session) */
        uint64_t quiet = b->decay_calls ? b->decay_calls : 22500u;
        uint64_t since = b->calls - (b->last_underrun_call > b->last_decay_call ? b->last_underrun_call : b->last_decay_call);
        if (lag > b->lag_base && b->lag_base > 0 && since >= quiet) {
            lag--;
            b->lag = lag;
            b->last_decay_call = b->calls;
        }
    }
    uint64_t fw = vb_load(&s->from_w), fr = vb_load(&s->from_r);
    while (fw - fr > lag + VB_LATE_LIMIT - 1) {
        fr++;
        vb_add(&s->host_drops, 1);
    }
    if (!b->primed && fw - fr >= lag) {
        b->primed = 1;
    }
    if (b->primed && fw > fr) {
        const float *src = s->from_sc[fr % VB_RING];
        if (from_l) memcpy(from_l, src, n * sizeof(float));
        if (from_r) memcpy(from_r, src + n, n * sizeof(float));
        vb_store(&s->from_r, fr + 1);
    } else {
        if (from_l) memset(from_l, 0, n * sizeof(float));
        if (from_r) memset(from_r, 0, n * sizeof(float));
        if (b->primed && vb_load(&s->guest_attached) && vb_load(&s->guest_blocks) > 0) {
            vb_add(&s->host_underruns, 1);
            b->primed = 0;
            /* two underruns within about half a second (4000 blocks of 128 frames): the hold-back is too small for the way this card calls back (bursts nobody announced, a scsynth that wakes late).
             * one more block is held back, up to 6 (the ring holds 8). it stays: a smaller hold-back would only bring the clicks back */
            uint64_t grace = b->grace_calls ? b->grace_calls : 5600u;
            int past_grace = b->first_guest_call && b->calls - b->first_guest_call >= grace;
            if (past_grace && b->last_underrun_call && b->calls - b->last_underrun_call < 4000 && lag < VB_RING - 2) {
                b->lag = lag + 1;
                b->raises++;
            }
            b->last_underrun_call = b->calls;
        }
    }
}

/* ---- the guest (the scsynth driver) ---- */
/* opens an existing bridge; waits up to timeout_ms for norns.exe to create it. 0 = ok, -1 = not there */
static inline int vb_guest_open(vb_t *b, const char *name, unsigned timeout_ms) {
    memset(b, 0, sizeof *b);
    unsigned waited = 0;
    for (;;) {
        if (vb_os_open(b, name, 0) == 0 && b->sh->magic == VB_MAGIC && b->sh->version == VB_VERSION) {
            return 0;
        }
        vb_os_close(b);
        if (waited >= timeout_ms) {
            return -1;
        }
#ifdef _WIN32
        Sleep(50);
#else
        struct timespec ts = {0, 50000000L};
        nanosleep(&ts, NULL);
#endif
        waited += 50;
    }
}

static inline void vb_guest_attach(vb_t *b) {
    /* a block queued for a driver that has just started would be old: begin at the host's position */
    vb_store(&b->sh->to_r, vb_load(&b->sh->to_w));
    vb_store(&b->sh->from_r, vb_load(&b->sh->from_w));
    vb_store(&b->sh->guest_attached, 1);
}

static inline void vb_guest_detach(vb_t *b) {
    if (b->sh) vb_store(&b->sh->guest_attached, 0);
}

/* waits for the next block of the host: 1 = got it (copied to in_l / in_r), 0 = nothing within timeout_ms, -1 = the host has closed */
static inline int vb_guest_wait(vb_t *b, unsigned timeout_ms, float *in_l, float *in_r) {
    vb_shared *s = b->sh;
    unsigned n = s->frames;
    for (;;) {
        if (vb_load(&s->host_closed)) return -1;
        uint64_t r = vb_load(&s->to_r), w = vb_load(&s->to_w);
        if (r < w) {
            const float *src = s->to_sc[r % VB_RING];
            memcpy(in_l, src, n * sizeof(float));
            memcpy(in_r, src + n, n * sizeof(float));
            vb_store(&s->to_r, r + 1);
            return 1;
        }
        if (timeout_ms == 0) return 0;
        vb_os_wait(b, timeout_ms);
        timeout_ms = 0; /* one wait, then look once more */
    }
}

static inline void vb_guest_push(vb_t *b, const float *out_l, const float *out_r) {
    vb_shared *s = b->sh;
    unsigned n = s->frames;
    uint64_t w = vb_load(&s->from_w), r = vb_load(&s->from_r);
    if (w - r >= VB_RING) {
        vb_store(&s->from_r, r + 1); /* nobody reads: drop the oldest */
    }
    float *d = s->from_sc[w % VB_RING];
    memcpy(d, out_l, n * sizeof(float));
    memcpy(d + n, out_r, n * sizeof(float));
    vb_store(&s->from_w, w + 1);
    vb_add(&s->guest_blocks, 1);
}

static inline void vb_close(vb_t *b) {
    if (b->sh && b->host) {
        vb_store(&b->sh->host_closed, 1);
        vb_os_signal(b);
    }
    vb_os_close(b);
}

#ifdef __cplusplus
}
#endif
#endif
