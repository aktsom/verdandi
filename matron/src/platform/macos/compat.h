/*
 * compat.h
 *
 * force-included (-include) into every matron/crone/sidecar translation unit on macOS.
 * fills the gaps between linux and darwin POSIX so upstream sources build unchanged.
 */

#pragma once

#ifdef __APPLE__

#include <dispatch/dispatch.h>
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdint.h>
#include <time.h>

//--- pthread_setname_np: darwin can only name the calling thread
static inline int norns_pthread_setname_np(pthread_t t, const char *name) {
    if (pthread_equal(t, pthread_self())) {
        return pthread_setname_np(name);
    }
    return 0;
}
#define pthread_setname_np(t, name) norns_pthread_setname_np((t), (name))

//--- clock_nanosleep: missing on darwin
#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1
#endif

static inline int norns_clock_nanosleep(clockid_t clk, int flags, const struct timespec *req,
                                        struct timespec *rem) {
    struct timespec ts = *req;
    if (flags & TIMER_ABSTIME) {
        for (;;) {
            struct timespec now;
            clock_gettime(clk, &now);
            int64_t d = (int64_t)(req->tv_sec - now.tv_sec) * 1000000000LL + (req->tv_nsec - now.tv_nsec);
            if (d <= 0) {
                return 0;
            }
            ts.tv_sec = (time_t)(d / 1000000000LL);
            ts.tv_nsec = (long)(d % 1000000000LL);
            if (nanosleep(&ts, NULL) != 0 && errno != EINTR) {
                return errno;
            }
        }
    }
    if (nanosleep(&ts, rem) != 0) {
        return errno;
    }
    return 0;
}
#define clock_nanosleep norns_clock_nanosleep

//--- unnamed semaphores: sem_init is unsupported on darwin, use libdispatch
typedef struct {
    dispatch_semaphore_t sem;
} norns_sem_t;

static inline int norns_sem_init(norns_sem_t *s, int pshared, unsigned int value) {
    (void)pshared;
    s->sem = dispatch_semaphore_create((long)value);
    return s->sem ? 0 : -1;
}
static inline int norns_sem_wait(norns_sem_t *s) {
    dispatch_semaphore_wait(s->sem, DISPATCH_TIME_FOREVER);
    return 0;
}
static inline int norns_sem_post(norns_sem_t *s) {
    dispatch_semaphore_signal(s->sem);
    return 0;
}
static inline int norns_sem_destroy(norns_sem_t *s) {
    dispatch_release(s->sem);
    return 0;
}
#define sem_t norns_sem_t
#define sem_init norns_sem_init
#define sem_wait norns_sem_wait
#define sem_post norns_sem_post
#define sem_destroy norns_sem_destroy

//--- lua: matron's C++ sources include the lua headers without extern "C" (on norns they
// link against a C++-built lua). the macOS port uses C lua, which C modules from scripts
// (cjson.so &c, rebuilt for macOS) also need, so give every declaration C linkage here;
// the include guards make the later #include <lua.h> in matron a no-op.
#ifdef __cplusplus
extern "C" {
#endif
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef __cplusplus
}
#endif

#endif // __APPLE__
