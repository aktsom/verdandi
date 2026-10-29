// norns/sidecar_shell.cpp: what happens to a command's stderr (docs/port/KNOWN-ISSUES.md item 22). the sidecar merges it into the output the script reads (the upstream design, tested in
// tests/norns/sidecar_shell). scripts written for the device read ONLY the output of a command (an older norns used the plain popen): mx.samples counts the files that
// "ls /home/we/dust/audio/mx.samples/<pack>/*.wav" prints and finds ".wav" in ls's own error message for a missing folder. so on the Linux desktop build (NORNS_LINUX_DESKTOP) stderr goes
// to the program's own stderr (the log) and the output is stdout only; NORNS_CAPTURE_STDERR=1 brings the merge back. built twice by sidecar_stderr_test.sh: with the define (desktop) and without
// (what the device and macOS compile: unchanged, stderr rides the output stream).
#include <doctest/doctest.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string>
#include <unistd.h>

#include "sidecar_shell.h"

namespace {
bool collect(void *ctx, const char *buf, size_t len) {
    ((std::string *)ctx)->append(buf, len);
    return true;
}

struct run_t {
    std::string out;
    std::string err; // what reached the program's own stderr
    int code = -1;
};

run_t run(const char *cmd) {
    run_t r;
    char path[] = "/tmp/sidecar_stderr_XXXXXX";
    int tmp = mkstemp(path);
    int saved = dup(STDERR_FILENO);
    dup2(tmp, STDERR_FILENO);
    sidecar_shell_opts_t opts = {};
    opts.watch_fd = -1;
    opts.ctx = &r.out;
    opts.on_output = collect;
    opts.term_grace_ms = 100;
    sidecar_shell_result_t res;
    sidecar_shell_run(cmd, &opts, &res);
    r.code = res.code;
    dup2(saved, STDERR_FILENO);
    close(saved);
    char buf[512];
    lseek(tmp, 0, SEEK_SET);
    ssize_t n;
    while ((n = read(tmp, buf, sizeof(buf))) > 0) r.err.append(buf, n);
    close(tmp);
    unlink(path);
    return r;
}
} // namespace

#ifdef NORNS_LINUX_DESKTOP
TEST_CASE("desktop: stderr is not part of the output, it reaches the program's stderr") {
    unsetenv("NORNS_CAPTURE_STDERR");
    run_t r = run("echo out; echo oops >&2");
    CHECK(r.out == "out\n");
    CHECK(r.err == "oops\n");
    CHECK(r.code == 0);
}
TEST_CASE("desktop: the owner's case, ls of a missing folder prints nothing to read") {
    unsetenv("NORNS_CAPTURE_STDERR");
    run_t r = run("ls /nonexistent_pack_dir/*.wav");
    CHECK(r.out == "");
    CHECK(r.err.find(".wav") != std::string::npos); // the complaint is in the log, not in the answer
    CHECK(r.code != 0);
}
TEST_CASE("desktop: an explicit 2>&1 in the command still merges") {
    unsetenv("NORNS_CAPTURE_STDERR");
    run_t r = run("echo oops >&2 2>&1; { echo both >&2; } 2>&1");
    CHECK(r.out.find("both") != std::string::npos);
}
TEST_CASE("desktop: NORNS_CAPTURE_STDERR=1 brings the merge back") {
    setenv("NORNS_CAPTURE_STDERR", "1", 1);
    run_t r = run("echo oops >&2");
    CHECK(r.out == "oops\n");
    CHECK(r.err == "");
    setenv("NORNS_CAPTURE_STDERR", "0", 1);
    r = run("echo oops >&2");
    CHECK(r.out == "");
    unsetenv("NORNS_CAPTURE_STDERR");
}
TEST_CASE("desktop: a missing command still reports 127, its complaint goes to the log") {
    unsetenv("NORNS_CAPTURE_STDERR");
    run_t r = run("definitely_not_a_command_xyz");
    CHECK(r.code == 127);
    CHECK(r.out == "");
    CHECK(r.err.find("not found") != std::string::npos);
}
#else
TEST_CASE("device and macOS (no desktop define): stderr rides the output stream, as before") {
    setenv("NORNS_CAPTURE_STDERR", "0", 1); // the variable means nothing there
    run_t r = run("echo out; echo oops >&2");
    CHECK(r.out == "out\noops\n");
    CHECK(r.err == "");
    unsetenv("NORNS_CAPTURE_STDERR");
}
#endif
