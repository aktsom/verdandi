/* sc_fail.h: sclang's class library did not compile ("Library has not been compiled successfully"): what failed, in plain words (Windows launcher; pure, linux/tests/sc_fail_test.c on real sclang logs).
 * without this the owner saw SUPERCOLLIDER FAIL and nothing else. the same logic is in lua/core/sc_class_check.lua (compile_failure) for the norns screen. */
#ifndef VERDANDI_SC_FAIL_H
#define VERDANDI_SC_FAIL_H
#include <stdio.h>
#include <string.h>

/* returns 1 and the sentence in out when text (sclang's output) says that the class library failed to compile; 0 otherwise */
static inline int scf_explain(const char *text, char *out, size_t n) {
    if (!text || !strstr(text, "Library has not been compiled")) return 0;
    const char *d = strstr(text, "duplicate Class found: '");
    if (d) {
        char names[400];
        names[0] = 0;
        int count = 0;
        const char *p = text;
        while ((p = strstr(p, "duplicate Class found: '")) != NULL) {
            p += strlen("duplicate Class found: '");
            const char *e = strchr(p, '\'');
            if (!e) break;
            count++;
            if (count <= 6) {
                size_t l = (size_t)(e - p);
                if (strlen(names) + l + 3 < sizeof names) {
                    if (names[0]) strcat(names, ", ");
                    strncat(names, p, l);
                }
            }
            p = e;
        }
        char p1[300], p2[300];
        p1[0] = p2[0] = 0;
        const char *nl = strchr(d, '\n');
        if (nl) {
            nl++;
            const char *e1 = strchr(nl, '\n');
            if (e1) {
                size_t l = (size_t)(e1 - nl);
                if (l >= sizeof p1) l = sizeof p1 - 1;
                memcpy(p1, nl, l);
                p1[l] = 0;
                const char *s2 = e1 + 1;
                const char *e2 = strchr(s2, '\n');
                l = e2 ? (size_t)(e2 - s2) : strlen(s2);
                if (l >= sizeof p2) l = sizeof p2 - 1;
                memcpy(p2, s2, l);
                p2[l] = 0;
            }
        }
        for (char *q = p1; *q; q++) if (*q == '\r') *q = 0;
        for (char *q = p2; *q; q++) if (*q == '\r') *q = 0;
        snprintf(out, n, "SuperCollider did not start: two files define the same class (%d class name(s): %s%s). The first two files: %s and %s. Verdandi moves the copy that is not part of its own packs to disabled\\ at the next start (restart norns); two folders of your own it does not touch: move one of them out of the way by hand (never delete)",
                 count, names, count > 6 ? ", ..." : "", p1, p2);
        return 1;
    }
    const char *er = strstr(text, "ERROR: ");
    if (er) {
        char msg[160], file[300];
        msg[0] = file[0] = 0;
        const char *e = strchr(er + 7, '\n');
        size_t l = e ? (size_t)(e - (er + 7)) : strlen(er + 7);
        if (l >= sizeof msg) l = sizeof msg - 1;
        memcpy(msg, er + 7, l);
        msg[l] = 0;
        for (char *q = msg; *q; q++) if (*q == '\r') *q = 0;
        const char *f = strstr(er, "in file '");
        if (f) {
            f += 9;
            const char *fe = strchr(f, '\'');
            if (fe) {
                size_t fl = (size_t)(fe - f);
                if (fl >= sizeof file) fl = sizeof file - 1;
                memcpy(file, f, fl);
                file[fl] = 0;
            }
        }
        if (file[0]) snprintf(out, n, "SuperCollider did not start: its class library did not compile (%s) in the file %s. Move that file, or the folder it is in, out of dust\\code and the extensions folders (never delete) and restart norns", msg, file);
        else snprintf(out, n, "SuperCollider did not start: its class library did not compile (%s). See logs\\sclang.log", msg);
        return 1;
    }
    snprintf(out, n, "SuperCollider did not start: its class library did not compile. See logs\\sclang.log");
    return 1;
}
#endif
