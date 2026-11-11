/* msg_dedupe.h (Windows build only): the same error message again and again is written once, then "repeated N more times" when something else is written (the log of 0.4.0 had one error several hundred times).
 * header only so that linux/tests/dedupe_test.c can run it. not thread safe: the Lua thread is the only caller. */
#ifndef VERDANDI_MSG_DEDUPE_H
#define VERDANDI_MSG_DEDUPE_H
#include <string.h>

typedef struct {
    char last[1024];
    unsigned repeats;
} vmsg_dedupe;

/* returns 1: write the message (and, when *skipped_before > 0, first say that the one before it was repeated that many times), 0: do not write it */
static inline int vmsg_dedupe_check(vmsg_dedupe *d, const char *msg, unsigned *skipped_before) {
    *skipped_before = 0;
    if (d->last[0] && strncmp(msg, d->last, sizeof d->last - 1) == 0) {
        d->repeats++;
        return 0;
    }
    *skipped_before = d->repeats;
    d->repeats = 0;
    strncpy(d->last, msg, sizeof d->last - 1);
    d->last[sizeof d->last - 1] = 0;
    return 1;
}
#endif
