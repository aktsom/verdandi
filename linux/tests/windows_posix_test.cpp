// the Windows build's POSIX stand-ins (matron/src/platform/windows: posix_compat.c, sidecar_shell_win.cpp), cross-built with mingw-w64 and run under Wine by
// linux/tests/windows_wine_test.sh. fnmatch is also run natively on Linux (it is portable C).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>
#include <time.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#endif

extern "C" {
#include <fnmatch.h>
#include <glob.h>
}
#include "norns/sidecar_shell.h"

static int fails;
#define CHECK(c, ...)                                                                                                                                          \
    do {                                                                                                                                                       \
        if (!(c)) {                                                                                                                                            \
            fails++;                                                                                                                                           \
            printf("FAIL line %d: ", __LINE__);                                                                                                                \
            printf(__VA_ARGS__);                                                                                                                               \
            printf("\n");                                                                                                                                      \
        }                                                                                                                                                      \
    } while (0)

struct Out {
    std::string text;
    size_t chunks = 0;
};
static bool on_output(void *ctx, const char *buf, size_t len) {
    Out *o = (Out *)ctx;
    o->text.append(buf, len);
    o->chunks++;
    return true;
}
static bool on_watch(void *) { return false; }

static sidecar_shell_result_t run(const char *cmd, Out *o, uint32_t silence_ms = 0, size_t cap = 0) {
    sidecar_shell_opts_t opts;
    memset(&opts, 0, sizeof opts);
    opts.silence_timeout_ms = silence_ms;
    opts.max_output_bytes = cap;
    opts.term_grace_ms = 200;
    opts.watch_fd = -1;
    opts.ctx = o;
    opts.on_output = on_output;
    opts.on_watch = on_watch;
    sidecar_shell_result_t r;
    sidecar_shell_run(cmd, &opts, &r);
    return r;
}

#ifdef _WIN32
extern "C" int norns_win_listdir(const char *dir, void (*cb)(const char *name, int isdir, void *ud), void *ud);
extern "C" void norns_win_sleep_until_ns(int64_t target);
#endif

int main() {
    // fnmatch: the patterns scripts use
    CHECK(fnmatch("*.lua", "init.lua", 0) == 0, "star");
    CHECK(fnmatch("*.lua", "init.luax", 0) != 0, "star end");
    CHECK(fnmatch("a?c", "abc", 0) == 0, "question");
    CHECK(fnmatch("a?c", "ac", 0) != 0, "question needs a char");
    CHECK(fnmatch("[a-c]x", "bx", 0) == 0, "range");
    CHECK(fnmatch("[!a-c]x", "bx", 0) != 0, "negated range");
    CHECK(fnmatch("[!a-c]x", "dx", 0) == 0, "negated range, other");
    CHECK(fnmatch("*", "", 0) == 0, "star matches nothing");
    CHECK(fnmatch("*a*b*", "xxaxxbxx", 0) == 0, "two stars");
    CHECK(fnmatch("*a*b*", "xxbxxaxx", 0) != 0, "order matters");
#ifdef _WIN32
    // glob: a folder with three files
    CreateDirectoryA("globtest", NULL);
    for (const char *f : {"globtest/b.wav", "globtest/a.wav", "globtest/c.txt"}) {
        FILE *fp = fopen(f, "w");
        if (fp) {
            fputs("x", fp);
            fclose(fp);
        }
    }
    glob_t g;
    CHECK(glob("globtest/*.wav", 0, NULL, &g) == 0, "glob finds files");
    CHECK(g.gl_pathc == 2, "two wavs, got %zu", g.gl_pathc);
    if (g.gl_pathc == 2) {
        CHECK(strcmp(g.gl_pathv[0], "globtest/a.wav") == 0, "sorted, with the folder: %s", g.gl_pathv[0]);
        CHECK(strcmp(g.gl_pathv[1], "globtest/b.wav") == 0, "second: %s", g.gl_pathv[1]);
    }
    globfree(&g);
    CHECK(glob("globtest/*.xyz", 0, NULL, &g) == GLOB_NOMATCH, "no match");

    // listdir (_norns.listdir): folders first, "/" after them, hidden names and . .. left out
    {
        CreateDirectoryA("lsdir", NULL);
        CreateDirectoryA("lsdir/sub", NULL);
        CreateDirectoryA("lsdir/.hid", NULL);
        for (const char *f : {"lsdir/b.lua", "lsdir/a.lua", "lsdir/.dot"}) {
            FILE *fp = fopen(f, "w");
            if (fp) {
                fputs("x", fp);
                fclose(fp);
            }
        }
        std::vector<std::string> names;
        int rc = norns_win_listdir("lsdir/", [](const char *n, int isdir, void *ud) { ((std::vector<std::string> *)ud)->push_back(std::string(n) + (isdir ? "/" : "")); }, &names);
        CHECK(rc == 0 && names.size() == 3, "listdir: three visible names, got %zu", names.size());
        CHECK(norns_win_listdir("no_such_folder", [](const char *, int, void *) {}, NULL) == -1, "listdir of a missing folder");
    }
    // the metro sleep: an absolute time on the monotonic clock, ticks 10 ms apart must not drift or run early
    {
        struct timespec t0;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        int64_t t = (int64_t)t0.tv_sec * 1000000000LL + t0.tv_nsec;
        int64_t worst_late = 0;
        int early = 0;
        for (int i = 0; i < 100; i++) {
            t += 10000000LL;
            norns_win_sleep_until_ns(t);
            struct timespec n;
            clock_gettime(CLOCK_MONOTONIC, &n);
            int64_t now = (int64_t)n.tv_sec * 1000000000LL + n.tv_nsec;
            if (now < t - 100000) early++;
            if (now - t > worst_late) worst_late = now - t;
        }
        CHECK(early == 0, "metro sleep: %d ticks came early", early);
        CHECK(worst_late < 50000000LL, "metro sleep: worst lateness %lld us", (long long)(worst_late / 1000));
        printf("metro sleep: 100 ticks of 10 ms, worst lateness %lld us\n", (long long)(worst_late / 1000));
    }
    // mkdir -p is done natively (cmd.exe would make a folder called "-p")
    Out om;
    sidecar_shell_result_t rm = run("mkdir -p mk_test/a/b/c", &om);
    CHECK(rm.outcome == SIDECAR_SHELL_EXITED && rm.code == 0, "mkdir -p exits 0");
    CHECK(GetFileAttributesA("mk_test\\a\\b\\c") != INVALID_FILE_ATTRIBUTES, "every level was made");
    CHECK(GetFileAttributesA("-p") == INVALID_FILE_ATTRIBUTES, "no folder called -p");
    rm = run("mkdir -p mk_test/a/b/c", &om);
    CHECK(rm.outcome == SIDECAR_SHELL_EXITED && rm.code == 0, "an existing folder is not an error");
    rm = run("mkdir -p \"mk test/with space\"", &om);
    CHECK(rm.code == 0 && GetFileAttributesA("mk test\\with space") != INVALID_FILE_ATTRIBUTES, "a quoted path with a space");
    rm = run("mkdir -p mk test2/unquoted path/x", &om);
    CHECK(rm.code == 0 && GetFileAttributesA("mk test2\\unquoted path\\x") != INVALID_FILE_ATTRIBUTES, "an unquoted path with spaces is one path");
    // the shell runner
    Out o;
    sidecar_shell_result_t r = run("echo hello from the sidecar", &o);
    CHECK(r.outcome == SIDECAR_SHELL_EXITED && r.code == 0, "echo exits 0 (outcome %d code %d)", r.outcome, r.code);
    CHECK(o.text.find("hello from the sidecar") != std::string::npos, "echo output: '%s'", o.text.c_str());
    Out o2;
    r = run("exit 7", &o2);
    CHECK(r.outcome == SIDECAR_SHELL_EXITED && r.code == 7, "exit code 7 (outcome %d code %d)", r.outcome, r.code);
    Out o3;
    r = run("echo a& echo b& echo c", &o3);
    CHECK(o3.text.find('a') != std::string::npos && o3.text.find('c') != std::string::npos, "several lines: '%s'", o3.text.c_str());
    Out o4;
    r = run("ping -n 30 127.0.0.1 > nul", &o4, 1000);
    CHECK(r.outcome == SIDECAR_SHELL_QUIET, "a silent command is stopped (outcome %d)", r.outcome);
    Out o5;
    r = run("for /l %i in (1,1,2000) do @echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", &o5, 0, 2000);
    CHECK(r.outcome == SIDECAR_SHELL_CAPPED, "output over the cap is stopped (outcome %d)", r.outcome);
#endif
    printf(fails ? "windows_posix: %d FAILED\n" : "windows_posix: all checks passed\n", fails);
    return fails ? 1 : 0;
}
