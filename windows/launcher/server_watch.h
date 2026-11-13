/* server_watch.h: has the SuperCollider server (scsynth.exe) stopped on its own? (Windows launcher; pure, linux/tests/server_watch_test.c; docs/port/phase-m10.md)
 * sclang prints "Server 'localhost' exited with exit code -1073741819." when its server process ends (a crash is an exit code like 0xC0000005, which sclang prints as a signed number). the launcher reads
 * sclang.log while norns runs; a stop that nobody asked for is answered by a restart of the round (norns.exe, sclang and scsynth: the script and its engine are loaded again), twice at most, then a plain message. */
#ifndef VERDANDI_SERVER_WATCH_H
#define VERDANDI_SERVER_WATCH_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SW_MAX_RESTARTS 2        /* automatic restarts in a row */
#define SW_QUIET_RESET_MS 600000 /* a round that ran this long without a stop starts the count again */

/* the last "Server '<name>' exited with exit code <n>." in text: 1 and the code (as unsigned 32 bit), 0 when there is none */
static int sw_find_exit(const char *text, unsigned long *code) {
    static const char tag[] = "exited with exit code ";
    const char *p = text, *last = NULL;
    while ((p = strstr(p, tag)) != NULL) {
        /* it has to be sclang's own line: "Server '" on the same line before it */
        const char *ls = p;
        while (ls > text && ls[-1] != '\n') ls--;
        if (strncmp(ls, "Server '", 8) == 0) last = p;
        p += sizeof tag - 1;
    }
    if (!last) return 0;
    last += sizeof tag - 1;
    char *end;
    long long v = strtoll(last, &end, 10);
    if (end == last) return 0;
    *code = (unsigned long)(v & 0xFFFFFFFFLL);
    return 1;
}

/* what to do about a stop: 0 = nothing (a normal end, exit code 0), 1 = restart the round, 2 = no more restarts: say so. restarts = how many were made in a row */
static int sw_decide(unsigned long code, int restarts) {
    if (code == 0) return 0;
    return restarts < SW_MAX_RESTARTS ? 1 : 2;
}

/* the plain line for the norns screen and the log. kind 1: restarting; kind 2: giving up */
static void sw_message(int kind, unsigned long code, int restarts, char *out, size_t n) {
    char c[40];
    if ((code & 0xFFFF0000UL) == 0xC0000000UL || code > 255) snprintf(c, sizeof c, "0x%08lX", code);
    else snprintf(c, sizeof c, "%lu", code);
    if (kind == 1) snprintf(out, n, "SuperCollider stopped (error %s): restarting it and the script (%d of %d)", c, restarts, SW_MAX_RESTARTS);
    else snprintf(out, n, "SuperCollider keeps stopping (error %s): not restarting it again. Load another script, or restart Verdandi (see logs/sclang.log)", c);
}
#endif
