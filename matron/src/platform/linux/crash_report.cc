/*
 * crash_report.cc: see crash_report.h
 * only async-signal-safe calls in the handler (write, prctl, syscall, backtrace_symbols_fd after one priming call at install time)
 */

#include "crash_report.h"

#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

// where a report goes: <dir>/crash-<unix seconds>-<pid>.txt, made at the crash and only then (no empty file at every start)
static char crash_dir[400];
static size_t crash_dir_len;

static void put(int fd, const char *s) {
    if (fd >= 0) {
        ssize_t r = write(fd, s, strlen(s));
        (void)r;
    }
}

static void put_num(int fd, long v, int base) {
    char buf[32];
    int i = sizeof buf;
    buf[--i] = 0;
    int neg = v < 0;
    unsigned long u = neg ? -(unsigned long)v : (unsigned long)v;
    do {
        buf[--i] = "0123456789abcdef"[u % base];
        u /= base;
    } while (u && i > 1);
    if (base == 16) {
        buf[--i] = 'x';
        buf[--i] = '0';
    }
    if (neg) {
        buf[--i] = '-';
    }
    put(fd, buf + i);
}

static const char *sig_name(int sig) {
    switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGABRT: return "SIGABRT";
    case SIGBUS: return "SIGBUS";
    case SIGFPE: return "SIGFPE";
    case SIGILL: return "SIGILL";
    }
    return "signal";
}

static void report_to(int fd, int sig, siginfo_t *si, void **frames, int n) {
    char name[32] = "?";
    prctl(PR_GET_NAME, (unsigned long)name, 0, 0, 0);
    put(fd, "\n==== norns crashed: ");
    put(fd, sig_name(sig));
    put(fd, " (signal ");
    put_num(fd, sig, 10);
    put(fd, ") in thread \"");
    put(fd, name);
    put(fd, "\" (tid ");
    put_num(fd, syscall(SYS_gettid), 10);
    put(fd, ", pid ");
    put_num(fd, getpid(), 10);
    put(fd, ")");
    if (si != NULL && (sig == SIGSEGV || sig == SIGBUS || sig == SIGFPE || sig == SIGILL)) {
        put(fd, ", address ");
        put_num(fd, (long)(intptr_t)si->si_addr, 16);
    }
    put(fd, " ====\n");
    if (fd >= 0) {
        backtrace_symbols_fd(frames, n, fd);
    }
    put(fd, "==== end of the crash report (names shown are the exported ones; for the others use the offset with `nm -n` or "
            "`addr2line -f -e <the norns binary>`; the core dump is kept) ====\n");
}

static void on_crash(int sig, siginfo_t *si, void *ctx) {
    (void)ctx;
    void *frames[64];
    int n = backtrace(frames, 64);
    report_to(2, sig, si, frames, n);
    if (crash_dir_len > 0) {
        // the file name is built by hand: nothing here may allocate or take a lock
        char path[480];
        size_t k = 0;
        for (size_t i = 0; i < crash_dir_len && k < sizeof path - 64; i++) {
            path[k++] = crash_dir[i];
        }
        static const char pre[] = "/crash-";
        for (size_t i = 0; pre[i] != 0; i++) {
            path[k++] = pre[i];
        }
        char num[24];
        int ni = 0;
        for (long v = (long)time(NULL); v > 0 && ni < 20; v /= 10) {
            num[ni++] = (char)('0' + v % 10);
        }
        while (ni > 0) {
            path[k++] = num[--ni];
        }
        path[k++] = '-';
        ni = 0;
        for (long v = (long)getpid(); v > 0 && ni < 20; v /= 10) {
            num[ni++] = (char)('0' + v % 10);
        }
        while (ni > 0) {
            path[k++] = num[--ni];
        }
        static const char suf[] = ".txt";
        for (size_t i = 0; suf[i] != 0; i++) {
            path[k++] = suf[i];
        }
        path[k] = 0;
        int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
        if (fd >= 0) {
            report_to(fd, sig, si, frames, n);
            close(fd);
        }
    }
    // the default action (SA_RESETHAND) with the same signal: the core dump is made as without this handler
    raise(sig);
}

extern "C" void crash_report_install(const char *dir) {
    // backtrace() loads libgcc the first time: do that now, not in the handler
    void *prime[4];
    backtrace(prime, 4);
    if (dir != NULL && strlen(dir) < sizeof crash_dir) {
        strcpy(crash_dir, dir);
        crash_dir_len = strlen(dir);
        mkdir(dir, 0755); // the launcher made it already; a plain call so that the handler never has to
    }
    // a stack of its own, for a crash from a stack overflow (of the thread that installs this)
    static char altstack[64 * 1024];
    stack_t ss;
    ss.ss_sp = altstack;
    ss.ss_size = sizeof altstack;
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_crash;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_NODEFER | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    static const int sigs[] = {SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL};
    for (unsigned i = 0; i < sizeof sigs / sizeof sigs[0]; i++) {
        sigaction(sigs[i], &sa, NULL);
    }
}
