/*
 * posix_compat.c: the few POSIX functions the shared sources call that Windows does not have, in the simplest form that serves norns:
 *   glob / globfree   a pattern with wildcards in the LAST path component (FindFirstFileA); forward or back slashes
 *   fnmatch           * ? and [..] (no flags)
 *   statvfs           free and total space of the disk that holds a path (GetDiskFreeSpaceExA)
 *   DNSService*       Bonjour announcement: not available, one log line (see dns_sd.h)
 * built into norns.exe only. unit-tested on Linux in linux/tests/posix_compat_test.c with the portable parts (fnmatch, the pattern splitting).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dns_sd.h>
#include <fnmatch.h>
#include <glob.h>
#include <sys/statvfs.h>

#ifdef _WIN32
#include <windows.h>
#endif

/* insque / remque: the doubly linked list primitives of <search.h> (an element starts with next and prev pointers) */
struct qelem {
    struct qelem *q_forw, *q_back;
};
void insque(void *elem, void *prev) {
    struct qelem *e = elem, *p = prev;
    if (!p) {
        e->q_forw = e->q_back = NULL;
        return;
    }
    e->q_forw = p->q_forw;
    e->q_back = p;
    if (p->q_forw) {
        p->q_forw->q_back = e;
    }
    p->q_forw = e;
}
void remque(void *elem) {
    struct qelem *e = elem;
    if (e->q_back) {
        e->q_back->q_forw = e->q_forw;
    }
    if (e->q_forw) {
        e->q_forw->q_back = e->q_back;
    }
}

int fnmatch(const char *pattern, const char *s, int flags) {
    (void)flags;
    const char *star = NULL, *mark = NULL;
    while (*s) {
        if (*pattern == '[') {
            const char *p = pattern + 1;
            int neg = (*p == '!' || *p == '^');
            if (neg) {
                p++;
            }
            int hit = 0;
            const char *q = p;
            if (*q == ']') {
                if (*s == ']') {
                    hit = 1;
                }
                q++;
            }
            while (*q && *q != ']') {
                if (q[1] == '-' && q[2] && q[2] != ']') {
                    if ((unsigned char)*s >= (unsigned char)q[0] && (unsigned char)*s <= (unsigned char)q[2]) {
                        hit = 1;
                    }
                    q += 3;
                } else {
                    if (*q == *s) {
                        hit = 1;
                    }
                    q++;
                }
            }
            if (*q == ']' && hit != neg) {
                pattern = q + 1;
                s++;
                continue;
            }
            if (*q != ']') { /* no closing bracket: '[' is a plain character */
                if (*s == '[') {
                    pattern++;
                    s++;
                    continue;
                }
            }
        } else if (*pattern == '?' || *pattern == *s) {
            pattern++;
            s++;
            continue;
        } else if (*pattern == '*') {
            star = pattern++;
            mark = s;
            continue;
        }
        if (star) {
            pattern = star + 1;
            s = ++mark;
            continue;
        }
        return FNM_NOMATCH;
    }
    while (*pattern == '*') {
        pattern++;
    }
    return *pattern ? FNM_NOMATCH : 0;
}

#ifdef _WIN32

#include <time.h>

/* list a folder for lua (_norns.listdir): calls back with each UTF-8 name, isdir set for a folder; hidden names and "." ".." are left out, as `ls -p` does.
 * returns 0, or -1 when the folder cannot be opened. */
int norns_win_listdir(const char *dir_utf8, void (*cb)(const char *name, int isdir, void *ud), void *ud) {
    wchar_t wdir[MAX_PATH * 2];
    if (MultiByteToWideChar(CP_UTF8, 0, dir_utf8, -1, wdir, MAX_PATH * 2 - 3) <= 0) {
        return -1;
    }
    size_t n = wcslen(wdir);
    while (n > 0 && (wdir[n - 1] == L'/' || wdir[n - 1] == L'\\')) {
        wdir[--n] = 0;
    }
    wcscat(wdir, L"\\*");
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(wdir, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return -1;
    }
    do {
        if (fd.cFileName[0] == L'.' || (fd.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN)) {
            continue;
        }
        char name[MAX_PATH * 4];
        if (WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, name, (int)sizeof name, NULL, NULL) > 0) {
            cb(name, (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0, ud);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return 0;
}

/* sleep until an absolute CLOCK_MONOTONIC time (nanoseconds), on a high resolution waitable timer (Windows 10 1803 and later; otherwise a 1 ms timer resolution and a normal timer).
 * used by the metros: matron/src/metro.cc. one timer per thread. */
void norns_win_sleep_until_ns(int64_t target) {
    static __thread HANDLE timer;
    static __thread int tried;
    struct timespec ts;
    if (!tried) {
        tried = 1;
        timer = CreateWaitableTimerExW(NULL, NULL, 0x2 /* CREATE_WAITABLE_TIMER_HIGH_RESOLUTION */, TIMER_ALL_ACCESS);
        if (!timer) {
            timer = CreateWaitableTimerW(NULL, FALSE, NULL);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t d = target - ((int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec);
    if (d <= 0) {
        return;
    }
    if (timer) {
        LARGE_INTEGER due;
        due.QuadPart = -(d / 100);
        if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
            WaitForSingleObject(timer, INFINITE);
            return;
        }
    }
    Sleep((DWORD)(d / 1000000));
}

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *pglob) {
    (void)flags;
    (void)errfunc;
    pglob->gl_pathc = 0;
    pglob->gl_pathv = NULL;
    pglob->gl_offs = 0;
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return GLOB_NOMATCH;
    }
    /* the directory part of the pattern, as written (kept so the results are full paths like glob() gives) */
    char dir[MAX_PATH * 2];
    snprintf(dir, sizeof dir, "%s", pattern);
    char *slash = strrchr(dir, '/');
    char *bslash = strrchr(dir, '\\');
    if (bslash && (!slash || bslash > slash)) {
        slash = bslash;
    }
    if (slash) {
        slash[1] = 0;
    } else {
        dir[0] = 0;
    }
    size_t cap = 16, n = 0;
    char **v = malloc(cap * sizeof *v);
    do {
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) {
            continue;
        }
        if (n + 1 >= cap) {
            cap *= 2;
            v = realloc(v, cap * sizeof *v);
        }
        size_t l = strlen(dir) + strlen(fd.cFileName) + 1;
        v[n] = malloc(l);
        snprintf(v[n], l, "%s%s", dir, fd.cFileName);
        n++;
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    if (n == 0) {
        free(v);
        return GLOB_NOMATCH;
    }
    qsort(v, n, sizeof *v, cmp_str);
    v[n] = NULL;
    pglob->gl_pathc = n;
    pglob->gl_pathv = v;
    return 0;
}

void globfree(glob_t *pglob) {
    for (size_t i = 0; i < pglob->gl_pathc; i++) {
        free(pglob->gl_pathv[i]);
    }
    free(pglob->gl_pathv);
    pglob->gl_pathv = NULL;
    pglob->gl_pathc = 0;
}

int statvfs(const char *path, struct statvfs *buf) {
    ULARGE_INTEGER avail, total, freeb;
    if (!GetDiskFreeSpaceExA(path, &avail, &total, &freeb)) {
        return -1;
    }
    buf->f_bsize = buf->f_frsize = 4096;
    buf->f_blocks = total.QuadPart / 4096;
    buf->f_bfree = freeb.QuadPart / 4096;
    buf->f_bavail = avail.QuadPart / 4096;
    return 0;
}

#endif /* _WIN32 */

/* Bonjour: not part of Windows. the OSC service is not announced; maiden and scripts reach norns by localhost */
DNSServiceErrorType DNSServiceRegister(DNSServiceRef *sdRef, DNSServiceFlags flags, uint32_t interfaceIndex, const char *name, const char *regtype, const char *domain,
                                       const char *host, uint16_t port, uint16_t txtLen, const void *txtRecord, DNSServiceRegisterReply callBack, void *context) {
    (void)flags, (void)interfaceIndex, (void)name, (void)regtype, (void)domain, (void)host, (void)port, (void)txtLen, (void)txtRecord, (void)callBack, (void)context;
    if (sdRef) {
        *sdRef = NULL;
    }
    fprintf(stderr, "dns_sd: the OSC service is not announced on Windows (no Bonjour); use localhost\n");
    return kDNSServiceErr_Unsupported;
}
void DNSServiceRefDeallocate(DNSServiceRef sdRef) { (void)sdRef; }
int DNSServiceRefSockFD(DNSServiceRef sdRef) {
    (void)sdRef;
    return -1;
}
DNSServiceErrorType DNSServiceProcessResult(DNSServiceRef sdRef) {
    (void)sdRef;
    return kDNSServiceErr_Unsupported;
}
