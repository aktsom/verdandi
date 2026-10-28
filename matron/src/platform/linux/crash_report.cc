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
#include <sys/syscall.h>
#include <unistd.h>

static int report_fd = -1;

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
    if (report_fd >= 0) {
        report_to(report_fd, sig, si, frames, n);
    }
    // the default action (SA_RESETHAND) with the same signal: the core dump is made as without this handler
    raise(sig);
}

extern "C" void crash_report_install(const char *file) {
    // backtrace() loads libgcc the first time: do that now, not in the handler
    void *prime[4];
    backtrace(prime, 4);
    if (file != NULL) {
        report_fd = open(file, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
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
