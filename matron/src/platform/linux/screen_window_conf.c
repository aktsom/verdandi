/*
 * screen_window_conf.c: see screen_window_conf.h
 */

#include "screen_window_conf.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void sw_conf_defaults(sw_conf_t *c) {
    memset(c, 0, sizeof *c);
    c->border = 1;
}

static void say(sw_log_fn log, const char *fmt, const char *a, const char *b) {
    if (log == NULL) {
        return;
    }
    char line[320];
    snprintf(line, sizeof line, fmt, a, b);
    log(line);
}

static char *trim(char *s) {
    while (*s != '\0' && isspace((unsigned char)*s)) {
        s++;
    }
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) {
        *--e = '\0';
    }
    return s;
}

// a whole decimal integer (optional minus) in lo..hi
static int to_int(const char *v, long lo, long hi, int *out) {
    if (*v == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    long n = strtol(v, &end, 10);
    if (errno != 0 || *end != '\0' || n < lo || n > hi) {
        return 0;
    }
    *out = (int)n;
    return 1;
}

static int to_flag(const char *v, int *out) {
    char t[8];
    size_t n = strlen(v);
    if (n == 0 || n >= sizeof t) {
        return 0;
    }
    for (size_t i = 0; i <= n; i++) {
        t[i] = (char)tolower((unsigned char)v[i]);
    }
    if (!strcmp(t, "1") || !strcmp(t, "on") || !strcmp(t, "true")) {
        *out = 1;
        return 1;
    }
    if (!strcmp(t, "0") || !strcmp(t, "off") || !strcmp(t, "false")) {
        *out = 0;
        return 1;
    }
    return 0;
}

void sw_conf_parse(const char *text, sw_conf_t *c, sw_log_fn log) {
    sw_conf_defaults(c);
    int have_x = 0, have_y = 0;
    const char *p = text;
    while (*p != '\0') {
        const char *nl = strchr(p, '\n');
        size_t len = nl != NULL ? (size_t)(nl - p) : strlen(p);
        char line[256];
        size_t keep = len < sizeof line - 1 ? len : sizeof line - 1;
        memcpy(line, p, keep);
        line[keep] = '\0';
        p += len;
        if (*p == '\n') {
            p++;
        }
        char *l = trim(line);
        if (*l == '\0' || *l == '#') {
            continue;
        }
        char *eq = strchr(l, '=');
        if (eq == NULL) {
            say(log, "screen-window.conf: ignored a line without '=' (%s%s)", "", "");
            continue;
        }
        *eq = '\0';
        char *k = trim(l);
        char *v = trim(eq + 1);
        int n;
        if (!strcmp(k, "detached")) {
            if (to_flag(v, &n)) { c->detached = n; } else { c->detached = 0; say(log, "screen-window.conf: detached='%s' is not 0 or 1, using %s", v, "0"); }
        } else if (!strcmp(k, "fullscreen")) {
            if (to_flag(v, &n)) { c->fullscreen = n; } else { c->fullscreen = 0; say(log, "screen-window.conf: fullscreen='%s' is not 0 or 1, using %s", v, "0"); }
        } else if (!strcmp(k, "border")) {
            if (to_flag(v, &n)) { c->border = n; } else { c->border = 1; say(log, "screen-window.conf: border='%s' is not 0 or 1, using %s", v, "1"); }
        } else if (!strcmp(k, "w")) {
            if (to_int(v, 128, 16384, &n)) { c->w = n; } else { c->w = 0; say(log, "screen-window.conf: w='%s' is not a size (128..16384), using the %s", v, "default"); }
        } else if (!strcmp(k, "h")) {
            if (to_int(v, 128, 16384, &n)) { c->h = n; } else { c->h = 0; say(log, "screen-window.conf: h='%s' is not a size (128..16384), using the %s", v, "default"); }
        } else if (!strcmp(k, "x")) {
            if (to_int(v, -32768, 32768, &n)) { c->x = n; have_x = 1; } else { have_x = 0; say(log, "screen-window.conf: x='%s' is not a place (-32768..32768), using the %s", v, "default"); }
        } else if (!strcmp(k, "y")) {
            if (to_int(v, -32768, 32768, &n)) { c->y = n; have_y = 1; } else { have_y = 0; say(log, "screen-window.conf: y='%s' is not a place (-32768..32768), using the %s", v, "default"); }
        } else {
            say(log, "screen-window.conf: unknown key '%s' ignored%s", k, "");
        }
    }
    c->has_pos = have_x && have_y;
    if (c->has_pos == 0) {
        c->x = c->y = 0;
    }
}

int sw_conf_format(const sw_conf_t *c, char *buf, size_t n) {
    int len = snprintf(buf, n, "detached=%d\n", c->detached ? 1 : 0);
    if (len < 0 || (size_t)len >= n) {
        return -1;
    }
    size_t at = (size_t)len;
    char tmp[64];
    if (c->has_pos) {
        snprintf(tmp, sizeof tmp, "x=%d\ny=%d\n", c->x, c->y);
        if (at + strlen(tmp) >= n) { return -1; }
        strcpy(buf + at, tmp);
        at += strlen(tmp);
    }
    if (c->w > 0 && c->h > 0) {
        snprintf(tmp, sizeof tmp, "w=%d\nh=%d\n", c->w, c->h);
        if (at + strlen(tmp) >= n) { return -1; }
        strcpy(buf + at, tmp);
        at += strlen(tmp);
    }
    snprintf(tmp, sizeof tmp, "fullscreen=%d\nborder=%d\n", c->fullscreen ? 1 : 0, c->border ? 1 : 0);
    if (at + strlen(tmp) >= n) { return -1; }
    strcpy(buf + at, tmp);
    return (int)(at + strlen(tmp));
}

int sw_conf_load(const char *path, sw_conf_t *c, sw_log_fn log) {
    sw_conf_defaults(c);
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    char text[4096];
    size_t n = fread(text, 1, sizeof text - 1, f);
    fclose(f);
    text[n] = '\0';
    sw_conf_parse(text, c, log);
    return 0;
}

int sw_conf_save(const char *path, const sw_conf_t *c) {
    char text[512];
    if (sw_conf_format(c, text, sizeof text) < 0) {
        return -1;
    }
    char tmp[1100];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (f == NULL) {
        return -1;
    }
    int ok = fputs(text, f) >= 0;
    ok = fclose(f) == 0 && ok;
    if (!ok || rename(tmp, path) != 0) {
        remove(tmp);
        return -1;
    }
    return 0;
}
