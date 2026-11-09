/*
 * sidecar_shell_win.cpp: sidecar_shell_run() for Windows (norns/sidecar_shell.h). the Linux version forks /bin/sh; here a command runs through
 *   busybox sh -c    when busybox.exe is next to norns.exe (or named in VERDANDI_BUSYBOX): the POSIX tools that scripts use (ls, cp, mkdir -p, grep, ...)
 *   cmd.exe /d /s /c otherwise (plain Windows commands only)
 * stdin is NUL, stdout (and stderr when NORNS_CAPTURE_STDERR=1) is a pipe read by polling, the whole process tree is in a job object so that "kill" ends all of it.
 * limits and outcomes are those of the Linux version: silence timeout, output cap, refused output, an abandoned caller.
 */
#ifdef _WIN32

#include <winsock2.h>
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>

#include "../../../../norns/sidecar_shell.h"

static std::string exe_dir() {
    char path[MAX_PATH * 2];
    DWORD n = GetModuleFileNameA(NULL, path, sizeof path);
    std::string p(path, n);
    size_t slash = p.find_last_of("\\/");
    return slash == std::string::npos ? std::string(".") : p.substr(0, slash);
}

static std::string command_line(const char *cmd) {
    const char *bb = getenv("VERDANDI_BUSYBOX");
    std::string busybox = (bb && *bb) ? bb : exe_dir() + "\\busybox.exe";
    DWORD attr = GetFileAttributesA(busybox.c_str());
    if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
        std::string q;
        for (const char *c = cmd; *c; c++) { // the command is one argument: quote it for CommandLineToArgvW rules
            if (*c == '"' || *c == '\\') {
                q += '\\';
            }
            q += *c;
        }
        return "\"" + busybox + "\" sh -c \"" + q + "\"";
    }
    return std::string("cmd.exe /d /s /c \"") + cmd + "\"";
}

static uint64_t now_ms() { return (uint64_t)GetTickCount64(); }

static void fail(sidecar_shell_result_t *r, const char *err, int errnum) {
    r->outcome = SIDECAR_SHELL_FAILED;
    r->code = 0;
    r->err = err;
    r->errnum = errnum;
}

static bool watch_readable(int watch_fd) {
    if (watch_fd < 0) {
        return false;
    }
    WSAPOLLFD p;
    p.fd = (SOCKET)watch_fd;
    p.events = POLLRDNORM;
    p.revents = 0;
    return WSAPoll(&p, 1, 0) > 0;
}

// "mkdir -p <path>" is how norns's Lua makes folders (util.make_dir, every script's data folder). cmd.exe's mkdir would make a folder called "-p"; until busybox is bundled (M5) this one command
// is done here, natively: every level of the path, forward or back slashes, an existing folder is not an error. returns true when cmd was exactly that command
static bool builtin_mkdir_p(const char *cmd, int *code) {
    const char *p = cmd;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (strncmp(p, "mkdir", 5) != 0 || (p[5] != ' ' && p[5] != '\t')) {
        return false;
    }
    p += 5;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (strncmp(p, "-p", 2) != 0 || (p[2] != ' ' && p[2] != '\t')) {
        return false;
    }
    p += 2;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    std::string path(p);
    while (!path.empty() && (path.back() == ' ' || path.back() == '\t' || path.back() == '\r' || path.back() == '\n')) {
        path.pop_back();
    }
    if (path.size() >= 2 && ((path.front() == '"' && path.back() == '"') || (path.front() == '\'' && path.back() == '\''))) {
        path = path.substr(1, path.size() - 2);
    }
    // a shell operator: not ours. a path with spaces is one path (norns's Lua does not quote it: "mkdir -p /home/we/dust/data/my script/", and the user folder may have spaces too)
    if (path.empty() || path.find_first_of("&|<>;") != std::string::npos) {
        return false;
    }
    for (char &c : path) {
        if (c == '/') {
            c = '\\';
        }
    }
    *code = 0;
    for (size_t i = (path.size() > 2 && path[1] == ':') ? 3 : 1; i <= path.size(); i++) {
        if (i == path.size() || path[i] == '\\') {
            std::string part = path.substr(0, i);
            if (!part.empty() && !CreateDirectoryA(part.c_str(), NULL) && GetLastError() != ERROR_ALREADY_EXISTS) {
                *code = 1;
                break;
            }
        }
    }
    return true;
}

void sidecar_shell_run(const char *cmd, const sidecar_shell_opts_t *opts, sidecar_shell_result_t *result) {
    result->code = 0;
    result->err = NULL;
    result->errnum = 0;

    int builtin_code = 0;
    if (builtin_mkdir_p(cmd, &builtin_code)) {
        result->outcome = SIDECAR_SHELL_EXITED;
        result->code = builtin_code;
        return;
    }

    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE rd = NULL, wr = NULL;
    if (!CreatePipe(&rd, &wr, &sa, 0)) {
        fail(result, "could not start command", (int)GetLastError());
        return;
    }
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
    HANDLE nul = CreateFileA("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    const char *e = getenv("NORNS_CAPTURE_STDERR");
    bool merge_err = e && *e && strcmp(e, "0") != 0;

    STARTUPINFOA si;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = nul;
    si.hStdOutput = wr;
    si.hStdError = merge_err ? wr : GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof pi);

    std::string line = command_line(cmd);
    std::string mutable_line = line;
    HANDLE job = CreateJobObjectA(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
        memset(&info, 0, sizeof info);
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof info);
    }
    BOOL ok = CreateProcessA(NULL, &mutable_line[0], NULL, NULL, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, NULL, NULL, &si, &pi);
    CloseHandle(wr);
    if (nul != INVALID_HANDLE_VALUE) {
        CloseHandle(nul);
    }
    if (!ok) {
        int err = (int)GetLastError();
        CloseHandle(rd);
        if (job) {
            CloseHandle(job);
        }
        fail(result, "could not start command", err);
        return;
    }
    if (job) {
        AssignProcessToJobObject(job, pi.hProcess);
    }
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);

    uint64_t last_output = now_ms();
    size_t total = 0;
    bool aborted = false, exited = false;
    sidecar_shell_outcome_t why = SIDECAR_SHELL_FAILED;
    char buf[4096];

    for (;;) {
        DWORD avail = 0;
        BOOL peek = PeekNamedPipe(rd, NULL, 0, NULL, &avail, NULL);
        if (peek && avail > 0) {
            DWORD got = 0;
            if (!ReadFile(rd, buf, sizeof buf, &got, NULL) || got == 0) {
                break;
            }
            total += got;
            if (opts->max_output_bytes != 0 && total > opts->max_output_bytes) {
                aborted = true;
                why = SIDECAR_SHELL_CAPPED;
                break;
            }
            last_output = now_ms();
            if (!opts->on_output(opts->ctx, buf, got)) {
                aborted = true;
                why = SIDECAR_SHELL_REFUSED;
                break;
            }
            continue;
        }
        if (!peek) { // the write end is closed (the process and its children are gone): everything is read
            break;
        }
        if (WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) {
            exited = true;
            // read what is left, then stop
            if (!(PeekNamedPipe(rd, NULL, 0, NULL, &avail, NULL) && avail > 0)) {
                break;
            }
            continue;
        }
        if (opts->silence_timeout_ms != 0 && now_ms() - last_output >= opts->silence_timeout_ms) {
            aborted = true;
            why = SIDECAR_SHELL_QUIET;
            break;
        }
        if (opts->on_watch && watch_readable(opts->watch_fd) && opts->on_watch(opts->ctx)) {
            aborted = true;
            why = SIDECAR_SHELL_ABANDONED;
            break;
        }
        Sleep(5);
    }
    (void)exited;

    if (aborted) {
        if (job) {
            TerminateJobObject(job, 1);
        } else {
            TerminateProcess(pi.hProcess, 1);
        }
        WaitForSingleObject(pi.hProcess, 2000);
        CloseHandle(rd);
        CloseHandle(pi.hProcess);
        if (job) {
            CloseHandle(job);
        }
        result->outcome = why;
        return;
    }

    // the output ended: wait for the exit (with the same silence budget)
    for (;;) {
        if (WaitForSingleObject(pi.hProcess, 50) == WAIT_OBJECT_0) {
            break;
        }
        if (opts->silence_timeout_ms != 0 && now_ms() - last_output >= opts->silence_timeout_ms) {
            if (job) {
                TerminateJobObject(job, 1);
            }
            TerminateProcess(pi.hProcess, 1);
            CloseHandle(rd);
            CloseHandle(pi.hProcess);
            if (job) {
                CloseHandle(job);
            }
            result->outcome = SIDECAR_SHELL_QUIET;
            return;
        }
    }
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(rd);
    CloseHandle(pi.hProcess);
    if (job) {
        CloseHandle(job);
    }
    result->outcome = SIDECAR_SHELL_EXITED;
    result->code = (int)(code & 0xff);
}

#endif /* _WIN32 */
