/* shim_win.c: nice.exe, sudo.exe and systemctl.exe for the Windows build (docs/port/phase-m9.md). one source, three programs (the behaviour is chosen by the program's own name), found through the PATH of the program folder
 * like git and the other tools. scripts written for a norns call them (the installer of the script twins: `nice -n 19 git fetch`, `sudo systemctl restart norns-...`); the bundled busybox has no `nice` and Windows has no sudo or systemd.
 *   nice [-n N | -N | --adjustment=N] cmd args ...   runs the rest of the command line (the priority is not changed: a script's `nice` only asks to be polite). the exit code of the command is the exit code
 *   sudo [options] [VAR=value ...] cmd args ...      runs the rest: there is no other user to become. systemctl in the rest is this program's systemctl
 *   systemctl restart|try-restart|reload-or-restart norns-*   leaves <home>\.norns-request-restart (norns takes the request itself, as on Linux: lua/core/menu.lua) and returns 0 at once; start/reload/enable: nothing to do, 0;
 *                                                          stop/disable/kill of a norns unit: 1 with a plain line; any other unit: 1 ("no systemd on Windows")
 * a command that is not a program (a busybox applet such as ls) is run through busybox.exe next to this program. the child is in a job object that ends with this program: `timeout 20 nice git fetch` that kills the nice kills the git.
 * the arguments are passed on with the quoting rules of the C runtime, so that spaces and quotes survive. this file has no dependency on anything else of the program (windows/shims/shim_logic.h is the same logic, tested on Linux). */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "shim_logic.h"

static void err_line(const char *s) {
    HANDLE h = GetStdHandle(STD_ERROR_HANDLE);
    DWORD w;
    if (h && h != INVALID_HANDLE_VALUE) {
        WriteFile(h, s, (DWORD)strlen(s), &w, NULL);
        WriteFile(h, "\n", 1, &w, NULL);
    }
}

/* one argument, quoted by the rules of CommandLineToArgvW / the C runtime */
static void quote_arg(const wchar_t *a, wchar_t *out, size_t cap, size_t *len) {
    size_t n = *len;
    int need = (*a == 0) || wcspbrk(a, L" \t\n\v\"") != NULL;
#define PUT(c) do { if (n + 2 < cap) out[n++] = (c); } while (0)
    if (n) PUT(L' ');
    if (!need) {
        while (*a) PUT(*a++);
    } else {
        PUT(L'"');
        for (;;) {
            size_t bs = 0;
            while (*a == L'\\') { a++; bs++; }
            if (*a == 0) { for (size_t i = 0; i < bs * 2; i++) PUT(L'\\'); break; }
            if (*a == L'"') { for (size_t i = 0; i < bs * 2 + 1; i++) PUT(L'\\'); PUT(L'"'); }
            else { for (size_t i = 0; i < bs; i++) PUT(L'\\'); PUT(*a); }
            a++;
        }
        PUT(L'"');
    }
    out[n] = 0;
    *len = n;
}

static int run_command(int argc, wchar_t **argv, const wchar_t *self_dir) {
    static wchar_t cmdline[32768];
    size_t len = 0;
    cmdline[0] = 0;
    for (int i = 0; i < argc; i++) quote_arg(argv[i], cmdline, 32768, &len);
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION li;
        memset(&li, 0, sizeof li);
        li.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &li, sizeof li);
    }
    BOOL ok = CreateProcessW(NULL, cmdline, NULL, NULL, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, NULL, NULL, &si, &pi);
    if (!ok && GetLastError() == ERROR_FILE_NOT_FOUND) {
        /* not a program: a busybox applet (ls, cp, ...) */
        static wchar_t bb[32768];
        size_t bl = 0;
        bb[0] = 0;
        wchar_t path[MAX_PATH * 2];
        _snwprintf(path, MAX_PATH * 2, L"%ls\\busybox.exe", self_dir);
        quote_arg(path, bb, 32768, &bl);
        for (int i = 0; i < argc; i++) quote_arg(argv[i], bb, 32768, &bl);
        ok = CreateProcessW(NULL, bb, NULL, NULL, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, NULL, NULL, &si, &pi);
    }
    if (!ok) {
        char b[200];
        snprintf(b, sizeof b, "%ls: could not run '%ls' (error %lu)", L"shim", argv[0], (unsigned long)GetLastError());
        err_line(b);
        if (job) CloseHandle(job);
        return 127;
    }
    if (job) AssignProcessToJobObject(job, pi.hProcess); /* best effort (a job inside a job needs Windows 8 or later) */
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    if (job) CloseHandle(job);
    return (int)code;
}

static void narrow(const wchar_t *w, char *out, size_t n) {
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)n, NULL, NULL) <= 0) out[0] = 0;
}

/* <home>\.norns-request-restart: NORNS_HOME, else HOME, else the folder Verdandi in the user's folder */
static int request_restart(void) {
    wchar_t home[MAX_PATH * 2], file[MAX_PATH * 2 + 40];
    DWORD n = GetEnvironmentVariableW(L"NORNS_HOME", home, MAX_PATH * 2);
    if (n == 0 || n >= MAX_PATH * 2) n = GetEnvironmentVariableW(L"HOME", home, MAX_PATH * 2);
    if (n == 0 || n >= MAX_PATH * 2) {
        wchar_t up[MAX_PATH * 2];
        if (GetEnvironmentVariableW(L"USERPROFILE", up, MAX_PATH * 2) == 0) return -1;
        _snwprintf(home, MAX_PATH * 2, L"%ls\\Verdandi", up);
    }
    _snwprintf(file, MAX_PATH * 2 + 40, L"%ls\\.norns-request-restart", home);
    HANDLE h = CreateFileW(file, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return -1;
    CloseHandle(h);
    return 0;
}

int WINAPI wWinMain(HINSTANCE hi, HINSTANCE hp, LPWSTR cl, int sw) {
    (void)hi, (void)hp, (void)cl, (void)sw;
    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv || argc < 1) return 2;
    wchar_t self[MAX_PATH * 2];
    GetModuleFileNameW(NULL, self, MAX_PATH * 2);
    wchar_t *slash = wcsrchr(self, L'\\');
    wchar_t self_dir[MAX_PATH * 2];
    wcscpy(self_dir, self);
    if (slash) self_dir[slash - self] = 0;
    char name[64], **a8 = (char **)calloc((size_t)argc + 1, sizeof(char *));
    char base[MAX_PATH];
    narrow(slash ? slash + 1 : self, base, sizeof base);
    shim_basename(base, name, sizeof name);
    for (int i = 0; i < argc; i++) {
        a8[i] = (char *)malloc(4096);
        narrow(argv[i], a8[i], 4096);
    }
    shim_plan plan;
    shim_decide(name, argc, (const char *const *)a8, &plan);
    switch (plan.action) {
    case SHIM_RUN: {
        /* VAR=value words of sudo go to the environment */
        for (int i = 1; i < plan.first; i++) {
            wchar_t *eq = wcschr(argv[i], L'=');
            if (eq && argv[i][0] != L'-') { *eq = 0; SetEnvironmentVariableW(argv[i], eq + 1); *eq = L'='; }
        }
        if (plan.first >= argc) {
            err_line(plan.text);
            return plan.code;
        }
        return run_command(argc - plan.first, argv + plan.first, self_dir);
    }
    case SHIM_RESTART:
        if (request_restart() != 0) { err_line("norns: could not write the restart request"); return 1; }
        err_line(plan.text);
        return 0;
    case SHIM_SAY:
    default:
        if (plan.text[0]) err_line(plan.text);
        return plan.code;
    }
}
