#!/bin/bash
# a crash in a thread (strdup(NULL), the owner's crash) and an abort leave a readable report in the log and in crash-report.txt: the signal,
# the thread's name, the backtrace with the exported function names; and the default action is kept (killed by the signal, core dump allowed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HERE/../../matron/src/platform/linux"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat > "$T/c.cc" <<'SRC'
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "crash_report.h"
extern "C" __attribute__((noinline)) void bad_strdup_in_thread(const char *s) { char *p = strdup(s); printf("%s", p); }
static void *worker(void *) { pthread_setname_np(pthread_self(), "watch_loop"); volatile const char *z = NULL; bad_strdup_in_thread((const char *)z); return NULL; }
int main(int argc, char **argv) {
    crash_report_install(argv[1]);
    if (argc > 2) abort();
    pthread_t t; pthread_create(&t, NULL, worker, NULL); pthread_join(t, NULL);
    return 0;
}
SRC
g++ -g -rdynamic -O0 -I"$P" "$T/c.cc" "$P/crash_report.cc" -o "$T/c" -lpthread || { echo "FAIL: build"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
( ulimit -c 0; "$T/c" "$T/report.txt" 2> "$T/err.txt" ); rc=$?
[ $rc -eq 139 ] || bad "exit status $rc, want 139 (killed by SIGSEGV: the default action is kept)"
for f in err.txt report.txt; do
    grep -q "norns crashed: SIGSEGV" "$T/$f" || bad "$f: no signal line"
    grep -q 'thread "watch_loop"' "$T/$f" || bad "$f: no thread name"
    grep -q "bad_strdup_in_thread" "$T/$f" || bad "$f: no function name in the backtrace"
done
( ulimit -c 0; "$T/c" "$T/report2.txt" abort 2> "$T/err2.txt" ); rc=$?
[ $rc -eq 134 ] || bad "abort: exit status $rc, want 134"
grep -q "norns crashed: SIGABRT" "$T/err2.txt" || bad "abort: no signal line"
grep -q "norns crashed: SIGABRT" "$T/report2.txt" || bad "abort: not in the report file"
[ $fail -eq 0 ] && echo "crash_report_test: all passed"
exit $fail
