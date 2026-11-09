/*
 * crash_report_win.cc: crash_report.h for Windows. a crash of norns.exe leaves
 *   <dir>\crash-<time>-<pid>.txt   exception code and address, the thread, the modules loaded (name, base address) and the stack addresses, readable without symbols
 *   <dir>\crash-<time>-<pid>.dmp   a minidump (DbgHelp MiniDumpWriteDump) that the developer can open
 * and one line in the log (stderr). made at the crash and only then. the folder is the one the launcher names (<Verdandi folder>\logs\crash). dir NULL: no files, the log line only.
 */
#ifdef _WIN32

#include <windows.h>

#include <dbghelp.h>
#include <psapi.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "../linux/crash_report.h"

static char g_dir[MAX_PATH * 2];
static void (*g_hook)(void);
static LONG volatile g_in_crash;

extern "C" void crash_report_set_hook(void (*fn)(void)) { g_hook = fn; }

static const char *exception_name(DWORD code) {
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: return "access violation";
    case EXCEPTION_STACK_OVERFLOW: return "stack overflow";
    case EXCEPTION_ILLEGAL_INSTRUCTION: return "illegal instruction";
    case EXCEPTION_INT_DIVIDE_BY_ZERO: return "integer divide by zero";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "float divide by zero";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "array bounds exceeded";
    case EXCEPTION_IN_PAGE_ERROR: return "in page error";
    default: return "exception";
    }
}

static LONG WINAPI on_crash(EXCEPTION_POINTERS *ep) {
    if (InterlockedExchange(&g_in_crash, 1)) {
        return EXCEPTION_CONTINUE_SEARCH; // a second crash while reporting the first
    }
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    fprintf(stderr, "\nnorns CRASHED: %s (0x%08lx) at %p\n", exception_name(code), (unsigned long)code, ep->ExceptionRecord->ExceptionAddress);
    if (g_dir[0]) {
        time_t t = time(NULL);
        struct tm tmv;
        localtime_s(&tmv, &t);
        char stamp[64];
        strftime(stamp, sizeof stamp, "%Y%m%d-%H%M%S", &tmv);
        char base[MAX_PATH * 2 + 80];
        snprintf(base, sizeof base, "%s\\crash-%s-%lu", g_dir, stamp, (unsigned long)GetCurrentProcessId());

        char txt[sizeof base + 8];
        snprintf(txt, sizeof txt, "%s.txt", base);
        FILE *f = fopen(txt, "w");
        if (f) {
            fprintf(f, "norns.exe crashed: %s (0x%08lx) at %p\nthread %lu\n", exception_name(code), (unsigned long)code, ep->ExceptionRecord->ExceptionAddress,
                    (unsigned long)GetCurrentThreadId());
            fprintf(f, "\nmodules:\n");
            HMODULE mods[512];
            DWORD need = 0;
            if (EnumProcessModules(GetCurrentProcess(), mods, sizeof mods, &need)) {
                for (DWORD i = 0; i < need / sizeof(HMODULE) && i < 512; i++) {
                    char name[MAX_PATH];
                    if (GetModuleFileNameA(mods[i], name, sizeof name)) {
                        fprintf(f, "  %p %s\n", (void *)mods[i], name);
                    }
                }
            }
            fprintf(f, "\nstack (addresses, newest first):\n");
            void *frames[64];
            USHORT n = CaptureStackBackTrace(0, 64, frames, NULL);
            for (USHORT i = 0; i < n; i++) {
                fprintf(f, "  %p\n", frames[i]);
            }
            fclose(f);
            fprintf(stderr, "crash report: %s\n", txt);
        }

        char dmp[sizeof base + 8];
        snprintf(dmp, sizeof dmp, "%s.dmp", base);
        HANDLE h = CreateFileA(dmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            MINIDUMP_EXCEPTION_INFORMATION mei;
            mei.ThreadId = GetCurrentThreadId();
            mei.ExceptionPointers = ep;
            mei.ClientPointers = FALSE;
            MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), h, MiniDumpNormal, &mei, NULL, NULL);
            CloseHandle(h);
            fprintf(stderr, "minidump: %s\n", dmp);
        }
    }
    fflush(stderr);
    if (g_hook) {
        g_hook(); // best effort: the LEDs of grids off (no grids in M1)
    }
    return EXCEPTION_CONTINUE_SEARCH; // the system's own handling (and an error dialog) follows
}

extern "C" void crash_report_install(const char *dir) {
    g_dir[0] = 0;
    if (dir && *dir) {
        snprintf(g_dir, sizeof g_dir, "%s", dir);
        for (char *c = g_dir; *c; c++) {
            if (*c == '/') {
                *c = '\\';
            }
        }
        // the folder may not exist yet: create each level (the launcher normally has)
        for (char *c = g_dir + 3; *c; c++) {
            if (*c == '\\') {
                *c = 0;
                CreateDirectoryA(g_dir, NULL);
                *c = '\\';
            }
        }
        CreateDirectoryA(g_dir, NULL);
    }
    SetUnhandledExceptionFilter(on_crash);
}

#endif
