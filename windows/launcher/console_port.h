/* console_port.h: the two console websockets of maiden (norns 5555, sclang 5556): which port each one gets, and the plain line when a default port is taken (Windows launcher; pure, linux/tests/console_port_test.c).
 *   - the default port is free                        -> that port, nothing to say
 *   - the default port is held by another program      -> the first free port of the range default+100 ... default+199 (never the other console's port); maiden's page is told (a patched
 *                                                          repl-endpoints.json); one plain line says which program holds the default port
 *   - no free port in the range                        -> 0: norns and SuperCollider run without that console (the wrapper is not used), one plain line says so
 * a busy port never stops Verdandi or its audio. */
#ifndef VERDANDI_CONSOLE_PORT_H
#define VERDANDI_CONSOLE_PORT_H
#include <stdio.h>
#include <string.h>

/* is_free(port, ctx) -> 1 when nothing listens on it. other: the port the other console has taken already (0 = none) */
static inline int cp_choose(int def, int other, int (*is_free)(int, void *), void *ctx) {
    if (def != other && is_free(def, ctx)) return def;
    for (int p = def + 100; p < def + 200; p++) {
        if (p != other && is_free(p, ctx)) return p;
    }
    return 0;
}

/* name: the holder's file name ("" unknown), pid 0 = unknown. what: "norns" or "sclang" */
static inline void cp_why(char *out, size_t n, const char *what, int def, int got, const char *name, unsigned long pid) {
    char who[160];
    if (name && name[0] && pid) snprintf(who, sizeof who, "%s (process %lu)", name, pid);
    else if (name && name[0]) snprintf(who, sizeof who, "%s", name);
    else snprintf(who, sizeof who, "another program");
    if (got > 0) snprintf(out, n, "port %d is used by %s: the %s console in maiden uses port %d instead", def, who, what, got);
    else snprintf(out, n, "port %d is used by %s: the %s console in maiden is off, everything else runs", def, who, what);
}
#endif
