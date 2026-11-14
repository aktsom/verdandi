/*
 * stat_win.cc: hardware/stat.cc for the Windows build (docs/port/phase-m11.md). the first page of the menu (HOME, K2) shows the numbers of the stat thread: free disk, temperature and the load of the processor
 * and of its first four cores. without them lua/core/menu/home.lua stopped at `norns.cpu[i]` ("attempt to index a nil value (field 'cpu')") on every redraw. every two seconds an EVENT_STAT, as on the other systems:
 *   disk   MB free on the drive of the user's folder (the same scale as the Linux df: bytes / 1024000)
 *   cpu    the load of the whole processor in the last interval, in per cent (GetSystemTimes); cpu1..cpu4: the first four logical processors (NtQuerySystemInformation, SystemProcessorPerformanceInformation,
 *          the same numbers the Task Manager shows); fewer than four: the total
 *   temp   0: Windows gives no processor temperature without a driver, the page leaves it out when it is 0
 */
#ifdef _WIN32
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" {
#include "events.h"
#include "hardware/stat.h"
}

#define STAT_INTERVAL_MS 2000
#define MAX_CPUS 64

struct perf_info { // SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION
    LARGE_INTEGER idle, kernel, user, dpc, interrupt;
    ULONG interrupt_count;
};
typedef LONG(WINAPI *nt_query_fn)(ULONG cls, PVOID buf, ULONG len, PULONG ret);

static HANDLE g_thread;
static volatile LONG g_stop;

static int percent(unsigned long long busy, unsigned long long total) {
    if (total == 0) return 0;
    unsigned long long p = busy * 100 / total;
    return p > 100 ? 100 : (int)p;
}

static unsigned long long ft(const FILETIME &f) { return ((unsigned long long)f.dwHighDateTime << 32) | f.dwLowDateTime; }

static DWORD WINAPI stat_thread(LPVOID) {
    nt_query_fn nt = (nt_query_fn)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQuerySystemInformation");
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    int ncpu = (int)si.dwNumberOfProcessors;
    if (ncpu > MAX_CPUS) ncpu = MAX_CPUS;
    static perf_info prev[MAX_CPUS], cur[MAX_CPUS];
    bool have_prev = false;
    unsigned long long pidle = 0, pkern = 0, puser = 0;
    wchar_t home[MAX_PATH * 2];
    DWORD hn = GetEnvironmentVariableW(L"NORNS_HOME", home, MAX_PATH * 2);
    if (hn == 0 || hn >= MAX_PATH * 2) home[0] = 0;
    while (!g_stop) {
        int cpu = 0, c[4] = {0, 0, 0, 0};
        FILETIME fi, fk, fu;
        if (GetSystemTimes(&fi, &fk, &fu)) {
            unsigned long long i = ft(fi), k = ft(fk), u = ft(fu); // kernel includes idle
            if (have_prev) {
                unsigned long long di = i - pidle, dk = k - pkern, du = u - puser, total = dk + du;
                cpu = percent(total > di ? total - di : 0, total);
            }
            pidle = i, pkern = k, puser = u;
        }
        if (nt && ncpu > 0 && nt(8, cur, (ULONG)(sizeof(perf_info) * ncpu), NULL) == 0) {
            for (int n = 0; n < 4; n++) {
                if (n < ncpu && have_prev) {
                    unsigned long long di = (unsigned long long)(cur[n].idle.QuadPart - prev[n].idle.QuadPart);
                    unsigned long long dt = (unsigned long long)((cur[n].kernel.QuadPart - prev[n].kernel.QuadPart) + (cur[n].user.QuadPart - prev[n].user.QuadPart));
                    c[n] = percent(dt > di ? dt - di : 0, dt);
                } else {
                    c[n] = cpu;
                }
            }
            memcpy(prev, cur, sizeof(perf_info) * ncpu);
        } else {
            for (int n = 0; n < 4; n++) c[n] = cpu;
        }
        have_prev = true;
        int disk = 0;
        ULARGE_INTEGER freeb;
        if (GetDiskFreeSpaceExW(home[0] ? home : NULL, &freeb, NULL, NULL)) {
            disk = (int)(freeb.QuadPart / 1024000ULL);
        }
        union event_data *ev = event_data_new(EVENT_STAT);
        ev->stat.disk = (uint32_t)disk;
        ev->stat.temp = 0;
        ev->stat.cpu = (uint8_t)cpu;
        ev->stat.cpu1 = (uint8_t)c[0];
        ev->stat.cpu2 = (uint8_t)c[1];
        ev->stat.cpu3 = (uint8_t)c[2];
        ev->stat.cpu4 = (uint8_t)c[3];
        event_post(ev);
        for (int waited = 0; waited < STAT_INTERVAL_MS && !g_stop; waited += 100) Sleep(100);
    }
    return 0;
}

extern "C" void stat_init(void) {
    g_stop = 0;
    g_thread = CreateThread(NULL, 0, stat_thread, NULL, 0, NULL);
    if (!g_thread) fprintf(stderr, "windows: stat thread could not be started (error %lu)\n", (unsigned long)GetLastError());
}

extern "C" void stat_deinit(void) {
    g_stop = 1;
    if (g_thread) {
        WaitForSingleObject(g_thread, 1000);
        CloseHandle(g_thread);
        g_thread = NULL;
    }
}
#endif
