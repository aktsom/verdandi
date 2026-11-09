/*
 * compat_win.h: force-included (-include) into every matron/crone/sidecar translation unit of the Windows build (as matron/src/platform/macos/compat.h is on macOS).
 * fills the gaps between Linux POSIX and MinGW-w64 so that the shared sources build unchanged. nothing here is used by the Linux or macOS builds.
 */
#pragma once

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <windows.h>

#include <mmsystem.h> /* uses "far" in a struct: it must be included before the macros below are removed (timeBeginPeriod; link winmm) */
/* windows.h defines macros that are ordinary words in the shared sources (a variable called "near"). IN, OUT, OPTIONAL and interface stay: the Windows headers included later need them: take them away right here, before anything else is included */
#undef near
#undef far
#undef small
#include <direct.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef R_OK
#define R_OK 4
#define W_OK 2
#define X_OK 0 /* Windows has no execute bit: access(path, X_OK) only checks that the file exists */
#define F_OK 0
#endif

#ifndef PTHREAD_STACK_MIN
#define PTHREAD_STACK_MIN 16384
#endif

/* mkdir(path, mode): Windows has mkdir(path) only */
#ifdef __cplusplus
extern "C" {
#endif
static inline int norns_win_mkdir(const char *path, int mode) {
    (void)mode;
    return _mkdir(path);
}
#ifdef __cplusplus
}
#endif
#define mkdir(p, m) norns_win_mkdir((p), (m))

#include <stdlib.h>
#include <string.h>
#include <limits.h>
#ifdef __cplusplus
extern "C" {
#endif
/* realpath: the absolute form of an existing path (forward slashes kept as given by the caller's convention) */
static inline char *realpath(const char *path, char *resolved) {
    if (_access(path, 0) != 0) {
        errno = ENOENT;
        return NULL;
    }
    return _fullpath(resolved, path, resolved ? 4096 : 0);
}
static inline char *strndup(const char *s, size_t n) {
    size_t l = 0;
    while (l < n && s[l]) {
        l++;
    }
    char *p = (char *)malloc(l + 1);
    if (p) {
        memcpy(p, s, l);
        p[l] = 0;
    }
    return p;
}
#ifdef __cplusplus
}
#endif

#ifndef localtime_r
#define localtime_r(t, tm) (localtime_s((tm), (t)) == 0 ? (tm) : NULL)
#define gmtime_r(t, tm) (gmtime_s((tm), (t)) == 0 ? (tm) : NULL)
#endif

#ifndef SIGHUP
#define SIGHUP 1
#endif
typedef unsigned long sigset_t;
#define sigemptyset(s) (*(s) = 0)
#define sigaddset(s, n) (*(s) |= (1UL << (n)))

/* pthread_timedjoin_np: the device layer joins a reader thread with a timeout. winpthreads has no such call; the Windows build has no device threads in M1,
 * so the plain join (which could block for ever) is never reached. */
static inline int pthread_timedjoin_np(pthread_t t, void **ret, const struct timespec *abstime) {
    (void)abstime;
    return pthread_join(t, ret);
}

/* pipe(fds): _pipe with a buffer and binary mode */
#define pipe(fds) _pipe((fds), 4096, _O_BINARY)

/* insque / remque (BSD queue.h uses them for the circular lists of the device layer): posix_compat.c */
#ifdef __cplusplus
extern "C" {
#endif
void insque(void *elem, void *prev);
void remque(void *elem);
#ifdef __cplusplus
}
#endif

/* clock_nanosleep, nanosleep, clock_gettime and pthread_setname_np come with winpthreads (MSYS2 and the mingw-w64 posix threads variant) */

#endif /* _WIN32 */
