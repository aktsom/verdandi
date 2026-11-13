/* shim_logic.h: what nice, sudo and systemctl do with their command line (pure, no Windows calls: linux/tests/shim_win_logic_test.c runs it on Linux). see shim_win.c */
#ifndef VERDANDI_SHIM_LOGIC_H
#define VERDANDI_SHIM_LOGIC_H
#include <ctype.h>
#include <stdio.h>
#include <string.h>

typedef enum { SHIM_RUN, SHIM_RESTART, SHIM_SAY } shim_action;
typedef struct {
    shim_action action;
    int first;      /* SHIM_RUN: index in argv of the command to run (assignments VAR=value of sudo before it, from 1) */
    int code;       /* SHIM_SAY (and RUN without a command): the exit code */
    char text[300]; /* what is said on stderr ("" = nothing) */
} shim_plan;

/* "C:\\tools\\nice.exe" -> "nice" */
static void shim_basename(const char *path, char *out, size_t n) {
    const char *b = path;
    for (const char *p = path; *p; p++) {
        if (*p == '/' || *p == '\\') b = p + 1;
    }
    size_t i = 0;
    for (; b[i] && i + 1 < n; i++) out[i] = (char)tolower((unsigned char)b[i]);
    out[i] = 0;
    char *dot = strrchr(out, '.');
    if (dot && !strcmp(dot, ".exe")) *dot = 0;
}

static int shim_is_norns_unit(const char *u) {
    return !strcmp(u, "norns") || !strcmp(u, "norns.service") || !strcmp(u, "norns.target") || !strncmp(u, "norns-", 6);
}

static int shim_all_digits(const char *s) {
    if (!*s) return 0;
    for (; *s; s++) if (!isdigit((unsigned char)*s)) return 0;
    return 1;
}

/* sudo's options that take a value */
static int shim_sudo_takes_value(const char *o) {
    static const char *v[] = {"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r", "-t", "--user", "--group", "--host", "--prompt", "--chdir", "--chroot", "--close-from", "--other-user", "--role", "--type", "--command-timeout"};
    for (size_t i = 0; i < sizeof v / sizeof *v; i++) if (!strcmp(o, v[i])) return 1;
    return 0;
}

static void shim_decide(const char *name, int argc, const char *const *argv, shim_plan *p) {
    memset(p, 0, sizeof *p);
    p->action = SHIM_RUN;
    if (!strcmp(name, "nice")) {
        int i = 1;
        while (i < argc) {
            const char *a = argv[i];
            if (!strcmp(a, "-n") || !strcmp(a, "--adjustment")) { i += 2; }
            else if (!strncmp(a, "--adjustment=", 13) || (a[0] == '-' && a[1] == 'n' && a[2]) || (a[0] == '-' && shim_all_digits(a + 1))) { i++; }
            else if (!strcmp(a, "--")) { i++; break; }
            else break;
        }
        p->first = i;
        if (i >= argc) { snprintf(p->text, sizeof p->text, "nice: a command is needed"); p->code = 125; }
        return;
    }
    if (!strcmp(name, "sudo")) {
        int i = 1;
        while (i < argc) {
            const char *a = argv[i];
            if (!strcmp(a, "--")) { i++; break; }
            if (a[0] != '-') break;
            if (shim_sudo_takes_value(a)) i += 2; else i++;
        }
        int j = i; /* VAR=value words are assignments */
        while (j < argc && strchr(argv[j], '=') && argv[j][0] != '-' && argv[j][0] != '=') j++;
        p->first = j;
        if (j >= argc) {
            p->code = 1;
            snprintf(p->text, sizeof p->text, "sudo: a command is needed");
        }
        return;
    }
    if (!strcmp(name, "systemctl")) {
        const char *verb = NULL;
        int norns = 0;
        for (int i = 1; i < argc; i++) {
            const char *a = argv[i];
            if (a[0] == '-') continue;
            if (!verb) verb = a; else if (shim_is_norns_unit(a)) norns = 1;
        }
        p->action = SHIM_SAY;
        if (!verb) { p->code = 1; snprintf(p->text, sizeof p->text, "systemctl: there is no systemd on Windows"); return; }
        if (norns) {
            if (!strcmp(verb, "restart") || !strcmp(verb, "try-restart") || !strcmp(verb, "reload-or-restart") || !strcmp(verb, "try-reload-or-restart")) {
                p->action = SHIM_RESTART;
                snprintf(p->text, sizeof p->text, "norns: there is no systemd on this build ('systemctl %s' was asked for): norns restarts itself instead (restart requested)", verb);
                return;
            }
            if (!strcmp(verb, "start") || !strcmp(verb, "reload") || !strcmp(verb, "enable") || !strcmp(verb, "daemon-reload")) {
                snprintf(p->text, sizeof p->text, "norns: there is no systemd on this build ('systemctl %s' was asked for): norns is already running, nothing done", verb);
                return;
            }
            p->code = 1;
            snprintf(p->text, sizeof p->text, "norns: 'systemctl %s' is not supported on this build (there is no systemd): close the norns window to stop it; nothing done", verb);
            return;
        }
        p->code = 1;
        snprintf(p->text, sizeof p->text, "systemctl: there is no systemd on Windows ('%s' of a unit other than norns was asked for): nothing done", verb);
        return;
    }
    p->action = SHIM_SAY;
    p->code = 2;
    snprintf(p->text, sizeof p->text, "shim: unknown program name '%s'", name);
}
#endif
