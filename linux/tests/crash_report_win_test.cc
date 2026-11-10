// the crash report of the Windows build (matron/src/platform/windows/crash_report_win.cc) under Wine: a crash in a nested call, and a crash while another thread holds the C library's stdio locks (a nearly dead
// process). the report must be complete: the exception, the address touched, the thread, the stack of the FAULTING context with function names, the modules. run:  crash_report_win_test DIR MODE   (MODE: null, locked)
#include <windows.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../matron/src/platform/linux/crash_report.h"

extern "C" __attribute__((noinline)) void vd_test_inner_crash(volatile int *p) {
    *p = 42; // the write to address 0
}
extern "C" __attribute__((noinline)) void vd_test_crash_target(volatile int *p) {
    vd_test_inner_crash(p);
    asm volatile("" ::: "memory");
}

static void *hold_locks(void *) {
    _lock_file(stderr);
    _lock_file(stdout);
    Sleep(60000);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    crash_report_install(argv[1]);
    if (!strcmp(argv[2], "locked")) {
        pthread_t t;
        pthread_create(&t, NULL, hold_locks, NULL);
        Sleep(300);
    }
    vd_test_crash_target((volatile int *)0);
    return 0;
}
