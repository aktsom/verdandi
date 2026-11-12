/* maiden_port.h: who holds maiden's TCP port, and what the launcher does about it (Windows launcher; pure, linux/tests/maiden_port_test.c).
 *   - nobody listens                                   -> MP_FREE: start our maiden
 *   - a program called maiden.exe listens (any folder)  -> MP_STOP_STALE: it is a maiden of an earlier program folder (or a copy that was left running) that serves other files ("404 on /maiden"):
 *                                                          stop it, then start ours. only the name is the test, as in the clean-up of stale norns, sclang and scsynth
 *   - another program listens                           -> MP_FOREIGN: nothing is stopped, maiden is not started, and the MAIDEN button says why (the text of mp_why) */
#ifndef VERDANDI_MAIDEN_PORT_H
#define VERDANDI_MAIDEN_PORT_H
#include <stdio.h>
#include <string.h>

typedef enum { MP_FREE, MP_STOP_STALE, MP_FOREIGN } mp_action;

static inline int mp_ieq(const char *a, const char *b) {
    for (; *a && *b; a++, b++) {
        char x = (char)((*a >= 'A' && *a <= 'Z') ? *a + 32 : *a), y = (char)((*b >= 'A' && *b <= 'Z') ? *b + 32 : *b);
        if (x != y) return 0;
    }
    return *a == 0 && *b == 0;
}

/* held: some process listens on the port; exe: its file name without folder ("" when unknown) */
static inline mp_action mp_decide(int held, const char *exe) {
    if (!held) return MP_FREE;
    if (exe && mp_ieq(exe, "maiden.exe")) return MP_STOP_STALE;
    return MP_FOREIGN;
}

/* the plain line for the norns screen and the window note (short: it has to fit) */
static inline void mp_why(char *out, size_t n, int port, const char *exe) {
    if (exe && exe[0]) snprintf(out, n, "maiden is not started: port %d is used by %s", port, exe);
    else snprintf(out, n, "maiden is not started: port %d is used by another program", port);
}
#endif
