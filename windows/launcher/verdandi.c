/*
 * Verdandi.exe: the Windows launcher (milestone M1). double-click it. plain Win32 C, no dependencies, no admin rights.
 * what it does, in order:
 *   1. one copy at a time (a named mutex); a second start brings the window of the first to the front instead.
 *   2. the user's folder: %USERPROFILE%\Verdandi (VERDANDI_HOME or --home= name another): dust, logs, logs\crash, cache, .config\SuperCollider. the program folder is linked into it as
 *      "norns" (a directory junction, which needs no rights), because norns reads $HOME/norns/lua and $HOME/norns/resources.
 *   3. checks that the pieces are there and says in plain words what is missing (a dialog, and the same text in logs\launcher.log).
 *   4. writes sclang's configuration, starts norns.exe, then sclang.exe (the sound engines) in the background, both with their output in logs\ (the previous logs are kept as .1 .2 .3).
 *      sclang gets only RELATIVE ASCII arguments and its own folder as the working directory: it reads its command line in the ANSI code page (M0 finding).
 *      no sound device is used in M1: scsynth runs on Verdandi's null audio driver (VERDANDI_NULL_AUDIO=1).
 *   5. waits for norns.exe; when it ends, everything it started ends (a job object). a crash is reported with the place of the crash report.
 * options: --headless (no windows: SDL dummy video driver, messages only in the log; for tests), --no-sclang, --no-norns (prepare and stop), --home=DIR, --exit-after=SECONDS, --version.
 */
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

#define VERDANDI_LAUNCHER_VERSION "0.1 (M1)"

static wchar_t g_app[MAX_PATH * 2];  /* program folder, no trailing backslash */
static wchar_t g_home[MAX_PATH * 2]; /* user's folder */
static int g_headless;
static HANDLE g_job;
static FILE *g_log;

/* ---------- helpers ---------- */

static void utf8(const wchar_t *w, char *out, size_t n) {
    int r = WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)n, NULL, NULL);
    if (r <= 0) {
        out[0] = 0;
    }
}

static void say(const wchar_t *fmt, ...) {
    wchar_t msg[2048];
    va_list ap;
    va_start(ap, fmt);
    _vsnwprintf(msg, 2047, fmt, ap);
    va_end(ap);
    msg[2047] = 0;
    char u[4096];
    utf8(msg, u, sizeof u);
    SYSTEMTIME t;
    GetLocalTime(&t);
    if (g_log) {
        fprintf(g_log, "%04d-%02d-%02d %02d:%02d:%02d launcher: %s\n", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, u);
        fflush(g_log);
    }
    fprintf(stderr, "launcher: %s\n", u);
}

/* a message for the person: a dialog (the same words go to the log). headless: log only */
static void tell_user(const wchar_t *title, UINT icon, const wchar_t *fmt, ...) {
    wchar_t msg[2048];
    va_list ap;
    va_start(ap, fmt);
    _vsnwprintf(msg, 2047, fmt, ap);
    va_end(ap);
    msg[2047] = 0;
    say(L"%ls: %ls", title, msg);
    if (!g_headless) {
        MessageBoxW(NULL, msg, title, MB_OK | icon | MB_SETFOREGROUND);
    }
}

static int exists(const wchar_t *p) { return GetFileAttributesW(p) != INVALID_FILE_ATTRIBUTES; }
static int is_dir(const wchar_t *p) {
    DWORD a = GetFileAttributesW(p);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}

static void join(wchar_t *out, size_t n, const wchar_t *a, const wchar_t *b) { _snwprintf(out, n, L"%ls\\%ls", a, b); out[n - 1] = 0; }

static int make_dirs(const wchar_t *path) {
    wchar_t p[MAX_PATH * 2];
    wcsncpy(p, path, MAX_PATH * 2 - 1);
    p[MAX_PATH * 2 - 1] = 0;
    for (wchar_t *c = p + 3; *c; c++) {
        if (*c == L'\\') {
            *c = 0;
            CreateDirectoryW(p, NULL);
            *c = L'\\';
        }
    }
    CreateDirectoryW(p, NULL);
    return is_dir(p);
}

/* C:\Users\me\Verdandi -> C:/Users/me/Verdandi (what norns and Lua expect in HOME) */
static void fwd(const wchar_t *in, wchar_t *out, size_t n) {
    wcsncpy(out, in, n - 1);
    out[n - 1] = 0;
    for (wchar_t *c = out; *c; c++) {
        if (*c == L'\\') {
            *c = L'/';
        }
    }
}

static void set_env(const wchar_t *k, const wchar_t *v) { SetEnvironmentVariableW(k, v); }

/* keep the last logs: name.log -> name.1.log -> name.2.log -> name.3.log */
static void rotate(const wchar_t *dir, const wchar_t *name) {
    wchar_t a[MAX_PATH * 2], b[MAX_PATH * 2];
    for (int i = 3; i >= 1; i--) {
        if (i == 3) {
            _snwprintf(a, MAX_PATH * 2, L"%ls\\%ls.%d.log", dir, name, i);
            DeleteFileW(a);
        }
        if (i == 1) {
            _snwprintf(a, MAX_PATH * 2, L"%ls\\%ls.log", dir, name);
        } else {
            _snwprintf(a, MAX_PATH * 2, L"%ls\\%ls.%d.log", dir, name, i - 1);
        }
        _snwprintf(b, MAX_PATH * 2, L"%ls\\%ls.%d.log", dir, name, i);
        if (i < 3) {
            DeleteFileW(b);
        }
        MoveFileW(a, b);
    }
}

static int run_hidden(const wchar_t *cmdline, DWORD *code) {
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    wchar_t buf[2048];
    wcsncpy(buf, cmdline, 2047);
    buf[2047] = 0;
    if (!CreateProcessW(NULL, buf, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        return 0;
    }
    WaitForSingleObject(pi.hProcess, 15000);
    if (code) {
        GetExitCodeProcess(pi.hProcess, code);
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return 1;
}

/* ---------- the pieces ---------- */

/* <home>\norns must lead to the program folder: a junction (no rights needed). 1 = ok */
static int link_program_folder(void) {
    if (GetEnvironmentVariableW(L"VERDANDI_NO_LINK", NULL, 0) > 0) { /* tests under Wine, which cannot make junctions */
        say(L"VERDANDI_NO_LINK is set: the program folder is not linked into the user folder");
        return 1;
    }
    wchar_t link[MAX_PATH * 2];
    join(link, MAX_PATH * 2, g_home, L"norns");
    DWORD a = GetFileAttributesW(link);
    if (a != INVALID_FILE_ATTRIBUTES) {
        if (a & FILE_ATTRIBUTE_REPARSE_POINT) {
            RemoveDirectoryW(link); /* removes the link only; made again below, in case the program folder moved */
        } else {
            tell_user(L"Verdandi", MB_ICONERROR, L"The folder %ls already exists and is not a link to the Verdandi program folder.\n\nRename or move it (it may hold files of yours), then start Verdandi again.", link);
            return 0;
        }
    }
    wchar_t cmd[MAX_PATH * 5];
    _snwprintf(cmd, MAX_PATH * 5, L"cmd.exe /d /c mklink /J \"%ls\" \"%ls\"", link, g_app);
    DWORD code = 1;
    if (!run_hidden(cmd, &code) || code != 0 || !exists(link)) {
        tell_user(L"Verdandi", MB_ICONERROR, L"Verdandi could not link its program folder into %ls (mklink /J failed).\n\nIs the folder on a drive that does not allow links (a network drive, FAT)? Unpack Verdandi on a normal local drive.", g_home);
        return 0;
    }
    return 1;
}

static void write_sclang_conf(const wchar_t *dir) {
    wchar_t path[MAX_PATH * 2], app[MAX_PATH * 2], home[MAX_PATH * 2];
    join(path, MAX_PATH * 2, dir, L"sclang_conf.yaml");
    fwd(g_app, app, MAX_PATH * 2);
    fwd(g_home, home, MAX_PATH * 2);
    FILE *f = _wfopen(path, L"wb");
    if (!f) {
        say(L"cannot write %ls", path);
        return;
    }
    char a[MAX_PATH * 4], h[MAX_PATH * 4];
    utf8(app, a, sizeof a);
    utf8(home, h, sizeof h);
    fprintf(f, "includePaths:\n    - \"%s/sc/core\"\n    - \"%s/sc/engines\"\n", a, a);
    fprintf(f, "    - \"%s/sc/linux\"\n    - \"%s/sc/linux-compat\"\n    - \"%s/dust\"\n", a, a, h);
    fprintf(f, "excludePaths:\n    []\npostInlineWarnings: false\n");
    fclose(f);
}

/* the output of a program goes through a pipe to a thread of the launcher that writes the log: a line that repeats (a message every few milliseconds when something is wrong)
 * is written once with a note "(repeated N more times)", so the log stays readable and small. what comes after a crash is still written (the pipe is read to its end). */
typedef struct {
    HANDLE read;
    HANDLE file;
    HANDLE thread;
} pump_t;
static pump_t g_pumps[4];
static int g_npumps;

static void pump_write(HANDLE file, const char *text, size_t n) {
    DWORD done;
    WriteFile(file, text, (DWORD)n, &done, NULL);
}

static void pump_flush_repeat(HANDLE file, unsigned long repeats) {
    if (repeats > 0) {
        char note[96];
        int n = snprintf(note, sizeof note, "   (the line above repeated %lu more times)\n", repeats);
        pump_write(file, note, (size_t)n);
    }
}

static DWORD WINAPI pump_thread(LPVOID arg) {
    pump_t *pt = (pump_t *)arg;
    char buf[4096];
    char line[2048], last[2048];
    size_t len = 0, lastlen = 0;
    unsigned long repeats = 0;
    DWORD got;
    last[0] = 0;
    for (;;) {
        BOOL ok = ReadFile(pt->read, buf, sizeof buf, &got, NULL);
        if (!ok || got == 0) {
            break;
        }
        for (DWORD i = 0; i < got; i++) {
            char c = buf[i];
            if (c != '\n' && len < sizeof line - 2) {
                line[len++] = c;
            }
            if (c == '\n') {
                line[len++] = '\n';
                if (len == lastlen && memcmp(line, last, len) == 0) {
                    repeats++;
                } else {
                    pump_flush_repeat(pt->file, repeats);
                    repeats = 0;
                    pump_write(pt->file, line, len);
                    memcpy(last, line, len);
                    lastlen = len;
                }
                len = 0;
            }
        }
    }
    pump_flush_repeat(pt->file, repeats);
    if (len > 0) {
        pump_write(pt->file, line, len); /* the last line without a newline */
    }
    CloseHandle(pt->read);
    CloseHandle(pt->file);
    return 0;
}

/* the write end of a pipe for a child (inheritable); the read end goes to a pump thread that writes name.log */
static HANDLE open_log_for_child(const wchar_t *dir, const wchar_t *name) {
    wchar_t p[MAX_PATH * 2];
    _snwprintf(p, MAX_PATH * 2, L"%ls\\%ls.log", dir, name);
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE file = CreateFileW(p, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE rd = NULL, wr = NULL;
    if (file == INVALID_HANDLE_VALUE || g_npumps >= 4 || !CreatePipe(&rd, &wr, &sa, 0)) {
        if (file != INVALID_HANDLE_VALUE) {
            /* no pipe: the child writes the file itself, as before */
            HANDLE dup = INVALID_HANDLE_VALUE;
            DuplicateHandle(GetCurrentProcess(), file, GetCurrentProcess(), &dup, 0, TRUE, DUPLICATE_SAME_ACCESS);
            CloseHandle(file);
            return dup;
        }
        return INVALID_HANDLE_VALUE;
    }
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
    pump_t *pt = &g_pumps[g_npumps];
    pt->read = rd;
    pt->file = file;
    pt->thread = CreateThread(NULL, 0, pump_thread, pt, 0, NULL);
    if (!pt->thread) {
        CloseHandle(rd);
        CloseHandle(file);
        CloseHandle(wr);
        return INVALID_HANDLE_VALUE;
    }
    g_npumps++;
    return wr;
}

/* after the children are gone: the pumps have read their pipes to the end; waits a moment for the last lines to be written */
static void pumps_finish(void) {
    for (int i = 0; i < g_npumps; i++) {
        WaitForSingleObject(g_pumps[i].thread, 3000);
        CloseHandle(g_pumps[i].thread);
    }
    g_npumps = 0;
}

/* starts a program in the job object with its output in a log. cwd is the working folder; cmdline uses relative names when the program is sclang */
static HANDLE start_child(const wchar_t *exe, const wchar_t *args, const wchar_t *cwd, const wchar_t *logdir, const wchar_t *logname, DWORD *err) {
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE out = open_log_for_child(logdir, logname);
    HANDLE nul = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    STARTUPINFOW si;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = nul;
    si.hStdOutput = out;
    si.hStdError = out;
    wchar_t cmd[MAX_PATH * 5];
    _snwprintf(cmd, MAX_PATH * 5, L"\"%ls\" %ls", exe, args);
    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof pi);
    DWORD flags = CREATE_NO_WINDOW | CREATE_SUSPENDED;
    BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, TRUE, flags, NULL, cwd, &si, &pi);
    *err = ok ? 0 : GetLastError();
    if (out != INVALID_HANDLE_VALUE) {
        CloseHandle(out);
    }
    if (nul != INVALID_HANDLE_VALUE) {
        CloseHandle(nul);
    }
    if (!ok) {
        return NULL;
    }
    if (g_job) {
        AssignProcessToJobObject(g_job, pi.hProcess);
    }
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);
    return pi.hProcess;
}

/* copy a folder tree (the seeded scripts); existing files are left alone */
static void copy_tree(const wchar_t *from, const wchar_t *to) {
    wchar_t pat[MAX_PATH * 2];
    join(pat, MAX_PATH * 2, from, L"*");
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return;
    }
    make_dirs(to);
    do {
        if (!wcscmp(fd.cFileName, L".") || !wcscmp(fd.cFileName, L"..")) {
            continue;
        }
        wchar_t a[MAX_PATH * 2], b[MAX_PATH * 2];
        join(a, MAX_PATH * 2, from, fd.cFileName);
        join(b, MAX_PATH * 2, to, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            copy_tree(a, b);
        } else {
            CopyFileW(a, b, TRUE);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

/* first start: dust\code is empty and the program folder has dust-seed\code, so SELECT has something to show. a folder with anything in it is never touched */
static void seed_scripts(const wchar_t *dust) {
    wchar_t seed[MAX_PATH * 2], code[MAX_PATH * 2], pat[MAX_PATH * 2];
    join(seed, MAX_PATH * 2, g_app, L"dust-seed\\code");
    join(code, MAX_PATH * 2, dust, L"code");
    if (!exists(seed)) {
        return;
    }
    join(pat, MAX_PATH * 2, code, L"*");
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(pat, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        int any = 0;
        do {
            if (wcscmp(fd.cFileName, L".") && wcscmp(fd.cFileName, L"..")) {
                any = 1;
            }
        } while (!any && FindNextFileW(h, &fd));
        FindClose(h);
        if (any) {
            return;
        }
    }
    copy_tree(seed, code);
    say(L"first start: the scripts of dust-seed were copied to %ls", code);
}

static void bring_running_copy_forward(void) {
    HWND w = FindWindowW(NULL, L"Verdandi Windows");
    if (w) {
        if (IsIconic(w)) {
            ShowWindow(w, SW_RESTORE);
        }
        SetForegroundWindow(w);
        say(L"Verdandi is already running: its window was brought to the front");
    } else {
        tell_user(L"Verdandi", MB_ICONINFORMATION, L"Verdandi is already running (it may still be starting). Only one copy can run at a time.");
    }
}

static const wchar_t *crash_hint(DWORD code) {
    switch (code) {
    case 0xC0000135: return L"Windows could not load a file that Verdandi needs (a DLL next to norns.exe is missing). Unpack the whole zip again into a new folder and start Verdandi from there.";
    case 0xC000007B: return L"Windows could not load a file that Verdandi needs (it is the wrong kind: 32 bit instead of 64 bit). Unpack the whole zip again into a new folder.";
    case 0xC0000005: return L"Verdandi crashed (access violation).";
    case 0xC00000FD: return L"Verdandi crashed (stack overflow).";
    default: return L"Verdandi ended with an error.";
    }
}

int wmain(int argc, wchar_t **argv) {
    int no_sclang = 0, no_norns = 0, exit_after = 0;
    wchar_t home_arg[MAX_PATH * 2] = L"";
    for (int i = 1; i < argc; i++) {
        if (!wcscmp(argv[i], L"--headless")) {
            g_headless = 1;
        } else if (!wcscmp(argv[i], L"--no-sclang")) {
            no_sclang = 1;
        } else if (!wcscmp(argv[i], L"--no-norns")) {
            no_norns = 1;
        } else if (!wcsncmp(argv[i], L"--home=", 7)) {
            wcsncpy(home_arg, argv[i] + 7, MAX_PATH * 2 - 1);
        } else if (!wcsncmp(argv[i], L"--exit-after=", 13)) {
            exit_after = _wtoi(argv[i] + 13);
        } else if (!wcscmp(argv[i], L"--version")) {
            printf("Verdandi launcher %s\n", VERDANDI_LAUNCHER_VERSION);
            return 0;
        }
    }
    if (GetEnvironmentVariableW(L"VERDANDI_HEADLESS", NULL, 0) > 0) {
        g_headless = 1;
    }

    /* program folder */
    GetModuleFileNameW(NULL, g_app, MAX_PATH * 2);
    wchar_t *slash = wcsrchr(g_app, L'\\');
    if (slash) {
        *slash = 0;
    }

    /* user's folder */
    if (home_arg[0]) {
        wcsncpy(g_home, home_arg, MAX_PATH * 2 - 1);
    } else if (GetEnvironmentVariableW(L"VERDANDI_HOME", g_home, MAX_PATH * 2) == 0) {
        wchar_t prof[MAX_PATH * 2];
        if (GetEnvironmentVariableW(L"USERPROFILE", prof, MAX_PATH * 2) == 0) {
            tell_user(L"Verdandi", MB_ICONERROR, L"Windows did not tell Verdandi where your user folder is (USERPROFILE). Set VERDANDI_HOME to a folder for Verdandi's files and start again.");
            return 2;
        }
        join(g_home, MAX_PATH * 2, prof, L"Verdandi");
    }
    if (!make_dirs(g_home)) {
        tell_user(L"Verdandi", MB_ICONERROR, L"Verdandi cannot create its folder %ls.\n\nIs the drive full or write-protected? Set VERDANDI_HOME to another folder.", g_home);
        return 2;
    }
    wchar_t logs[MAX_PATH * 2], crash[MAX_PATH * 2], dust[MAX_PATH * 2], cache[MAX_PATH * 2], scconf[MAX_PATH * 2];
    join(logs, MAX_PATH * 2, g_home, L"logs");
    join(crash, MAX_PATH * 2, logs, L"crash");
    join(dust, MAX_PATH * 2, g_home, L"dust");
    join(cache, MAX_PATH * 2, g_home, L"cache");
    join(scconf, MAX_PATH * 2, g_home, L".config\\SuperCollider");
    make_dirs(logs);
    make_dirs(crash);
    make_dirs(dust);
    {
        wchar_t sub[MAX_PATH * 2];
        join(sub, MAX_PATH * 2, dust, L"code");
        make_dirs(sub);
        join(sub, MAX_PATH * 2, dust, L"audio");
        make_dirs(sub);
        join(sub, MAX_PATH * 2, dust, L"data");
        make_dirs(sub);
        /* version.txt in the home (lua/core/norns.lua reads $HOME/version.txt) */
        wchar_t from[MAX_PATH * 2], to[MAX_PATH * 2];
        join(from, MAX_PATH * 2, g_app, L"update\\version.txt");
        join(to, MAX_PATH * 2, g_home, L"version.txt");
        if (exists(from)) {
            CopyFileW(from, to, FALSE);
        }
    }
    seed_scripts(dust);
    make_dirs(cache);
    make_dirs(scconf);

    rotate(logs, L"launcher");
    wchar_t lp[MAX_PATH * 2];
    join(lp, MAX_PATH * 2, logs, L"launcher.log");
    g_log = _wfopen(lp, L"ab");
    say(L"Verdandi launcher %hs, program folder %ls, user folder %ls%ls", VERDANDI_LAUNCHER_VERSION, g_app, g_home, g_headless ? L", headless" : L"");

    /* one copy */
    HANDLE mutex = CreateMutexW(NULL, TRUE, L"Local\\VerdandiLauncher");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        bring_running_copy_forward();
        return 3;
    }

    /* the pieces */
    wchar_t norns[MAX_PATH * 2], sclang[MAX_PATH * 2], lua[MAX_PATH * 2];
    join(norns, MAX_PATH * 2, g_app, L"norns.exe");
    join(sclang, MAX_PATH * 2, g_app, L"supercollider\\sclang.exe");
    join(lua, MAX_PATH * 2, g_app, L"lua\\core\\config.lua");
    if (!exists(norns) || !exists(lua)) {
        tell_user(L"Verdandi", MB_ICONERROR,
             L"Verdandi cannot start: a part of the program is missing (%ls).\n\nUnpack the whole zip file into a folder of its own (do not start Verdandi.exe from inside the zip), then start it again.",
             !exists(norns) ? norns : lua);
        return 4;
    }
    int have_sclang = exists(sclang) && !no_sclang;
    if (!exists(sclang) && !no_sclang) {
        tell_user(L"Verdandi", MB_ICONWARNING,
             L"The sound engine part of Verdandi (SuperCollider) is missing: %ls.\n\nVerdandi starts without engines. Scripts that need an engine will say so. Unpack the whole zip again to get it back.",
             sclang);
    }

    if (!link_program_folder()) {
        return 5;
    }

    /* environment of norns and sclang */
    wchar_t home_f[MAX_PATH * 2], path[32768], oldpath[32000];
    fwd(g_home, home_f, MAX_PATH * 2);
    set_env(L"HOME", home_f);
    set_env(L"NORNS_HOME", home_f);
    set_env(L"NORNS_PLATFORM", L"windows");
    set_env(L"NORNS_HARDWARE_KEYS", L"1");
    set_env(L"NORNS_DISPLAY_NAME", L"Verdandi Windows");
    set_env(L"SDL_NO_SIGNAL_HANDLERS", L"1");
    set_env(L"VERDANDI_NULL_AUDIO", L"1"); /* M1: no sound device; scsynth uses its null audio driver */
    if (g_headless) {
        set_env(L"SDL_VIDEODRIVER", L"dummy");
    }
    GetEnvironmentVariableW(L"PATH", oldpath, 32000);
    _snwprintf(path, 32767, L"%ls;%ls\\supercollider;%ls", g_app, g_app, oldpath);
    set_env(L"PATH", path);

    write_sclang_conf(scconf);

    if (no_norns) {
        say(L"--no-norns: prepared, stopping here");
        return 0;
    }

    g_job = CreateJobObjectW(NULL, NULL);
    if (g_job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
        memset(&info, 0, sizeof info);
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(g_job, JobObjectExtendedLimitInformation, &info, sizeof info);
    }

    rotate(logs, L"norns");
    rotate(logs, L"sclang");

    /* norns.exe first (matron, crone, softcut) */
    DWORD err = 0;
    HANDLE pn = start_child(norns, L"", g_app, logs, L"norns", &err);
    if (!pn) {
        tell_user(L"Verdandi", MB_ICONERROR, L"Windows could not start norns.exe (error %lu).\n\nAn antivirus program may have blocked it: allow the Verdandi folder and start again.", (unsigned long)err);
        return 6;
    }
    say(L"norns.exe started");

    /* then sclang, from inside its own folder with relative ASCII arguments. norns.exe has had a moment to start crone */
    HANDLE ps = NULL;
    if (have_sclang) {
        for (int i = 0; i < 30 && WaitForSingleObject(pn, 100) == WAIT_TIMEOUT; i++) {
        }
        if (WaitForSingleObject(pn, 0) == WAIT_TIMEOUT) {
            ps = start_child(sclang, L"-D -l sclang_conf.yaml", scconf, logs, L"sclang", &err);
            /* the working folder is the SuperCollider config folder, so the configuration file is named by a plain relative name */
            if (!ps) {
                tell_user(L"Verdandi", MB_ICONWARNING, L"Windows could not start sclang.exe (error %lu). Verdandi goes on without engines.", (unsigned long)err);
            } else {
                say(L"sclang.exe started");
            }
        }
    }

    /* wait for norns */
    DWORD wait = exit_after > 0 ? (DWORD)exit_after * 1000 : INFINITE;
    DWORD w = WaitForSingleObject(pn, wait);
    if (w == WAIT_TIMEOUT) {
        say(L"--exit-after=%d: stopping norns.exe", exit_after);
        TerminateProcess(pn, 0);
        WaitForSingleObject(pn, 5000);
    }
    DWORD code = 0;
    GetExitCodeProcess(pn, &code);
    say(L"norns.exe ended with exit code 0x%08lx", (unsigned long)code);
    if (g_job) {
        TerminateJobObject(g_job, 0); /* sclang, scsynth and anything else started from here */
    }
    if (ps) {
        CloseHandle(ps);
    }
    CloseHandle(pn);
    pumps_finish();

    int ret = 0;
    if (code != 0 && w != WAIT_TIMEOUT) {
        tell_user(L"Verdandi", MB_ICONERROR, L"%ls\n\nThe log is %ls\\norns.log. A crash report, if one was made, is in %ls.", crash_hint(code), logs, crash);
        ret = 7;
    }
    CloseHandle(mutex);
    if (g_log) {
        fclose(g_log);
    }
    return ret;
}
