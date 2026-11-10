/* exit_win.c (M2): see exit_win.h. */
#include "exit_win.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#endif

extern void vaud_stop(void);

static int exit_code;
/* crash_report_win.cc defines the real one (a crash report is being written); a program without it (the tests) gets this */
__attribute__((weak)) int verdandi_crash_in_progress(void) { return 0; }

#ifdef _WIN32
static DWORD WINAPI watchdog(LPVOID arg) {
    (void)arg;
    Sleep(3000);
    for (int i = 0; i < 300 && verdandi_crash_in_progress(); i++) {
        Sleep(50); /* a crash report is being written: not under it (up to 15 s more) */
    }
    TerminateProcess(GetCurrentProcess(), (UINT)exit_code);
    return 0;
}
static void kill_self(int code) {
    for (int i = 0; i < 300 && verdandi_crash_in_progress(); i++) {
        Sleep(50);
    }
    TerminateProcess(GetCurrentProcess(), (UINT)code);
}
static void start_watchdog(void) { CreateThread(NULL, 0, watchdog, NULL, 0, NULL); }
static int first_caller(void) {
    static volatile LONG once;
    return InterlockedExchange(&once, 1) == 0;
}
static void wait_forever(void) { Sleep(INFINITE); }
#else
static void *watchdog(void *arg) {
    (void)arg;
    struct timespec ts = {3, 0};
    nanosleep(&ts, NULL);
    _exit(exit_code);
    return NULL;
}
static void kill_self(int code) { _exit(code); }
static void start_watchdog(void) {
    pthread_t t;
    pthread_create(&t, NULL, watchdog, NULL);
}
static int first_caller(void) {
    static int once;
    return __sync_lock_test_and_set(&once, 1) == 0;
}
static void wait_forever(void) {
    for (;;) pause();
}
#endif

void verdandi_win_exit(int code) {
    if (!first_caller()) {
        wait_forever(); /* another thread is ending the process */
    }
    exit_code = code;
    start_watchdog();
    fprintf(stderr, "norns.exe ends with exit code %d (card stopped first, no atexit handlers)\n", code);
    fflush(NULL);
    vaud_stop();
    fflush(NULL);
    kill_self(code);
}
