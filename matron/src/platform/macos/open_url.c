/*
 * open_url.c: see open_url.h
 */

#include <pthread.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>

#include "open_url.h"

extern char **environ;

static int allowed(const char *url) {
    if (strncmp(url, "https://", 8) != 0 && strncmp(url, "http://", 7) != 0 && url[0] != '/') {
        return 0;
    }
    for (const unsigned char *c = (const unsigned char *)url; *c; c++) {
        if (*c < 0x20 || *c == 0x7f) {
            return 0;
        }
    }
    return 1;
}

static void *reap(void *p) {
    waitpid((pid_t)(intptr_t)p, NULL, 0);
    return NULL;
}

#ifndef __APPLE__
#include <stdlib.h>
// xdg-open with the user's own environment. linux/norns.sh gives norns the norns home as HOME (matron and sclang look there), and
// xdg-open finds the user's default browser in HOME/.config/mimeapps.list and HOME/.local/share/applications: with the norns
// home as HOME it finds none and falls back to the desktop's first browser. so xdg-open gets the user's own HOME and XDG folders
// back, which the launcher recorded as NORNS_USER_<NAME> (an XDG folder that was not set is removed). without NORNS_USER_HOME (started
// some other way) the environment is passed on as it is. nothing else (BROWSER, PATH, DISPLAY, XDG_CURRENT_DESKTOP...) is touched.
static const char *restored[] = {"XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"};
#define NRESTORED (sizeof restored / sizeof restored[0])

static int spawn_xdg_open(pid_t *pid, char *const argv[]) {
    const char *user_home = getenv("NORNS_USER_HOME");
    if (user_home == NULL || user_home[0] == '\0') {
        return posix_spawnp(pid, "xdg-open", NULL, NULL, argv, environ);
    }
    size_t n = 0;
    while (environ[n] != NULL) {
        n++;
    }
    char **env = calloc(n + NRESTORED + 2, sizeof(char *));
    char *owned[NRESTORED + 1] = {NULL};
    size_t m = 0, o = 0;
    if (env == NULL) {
        return posix_spawnp(pid, "xdg-open", NULL, NULL, argv, environ);
    }
    for (size_t i = 0; i < n; i++) {
        int drop = strncmp(environ[i], "HOME=", 5) == 0;
        for (size_t k = 0; k < NRESTORED && !drop; k++) {
            size_t l = strlen(restored[k]);
            drop = strncmp(environ[i], restored[k], l) == 0 && environ[i][l] == '=';
        }
        if (!drop) {
            env[m++] = environ[i];
        }
    }
    char buf[4096];
    snprintf(buf, sizeof buf, "HOME=%s", user_home);
    owned[o] = strdup(buf);
    env[m++] = owned[o++];
    for (size_t k = 0; k < NRESTORED; k++) {
        char name[64];
        snprintf(name, sizeof name, "NORNS_USER_%s", restored[k]);
        const char *v = getenv(name);
        if (v != NULL) {
            snprintf(buf, sizeof buf, "%s=%s", restored[k], v);
            owned[o] = strdup(buf);
            env[m++] = owned[o++];
        }
    }
    env[m] = NULL;
    int rc = posix_spawnp(pid, "xdg-open", NULL, NULL, argv, env);
    for (size_t i = 0; i < o; i++) {
        free(owned[i]);
    }
    free(env);
    return rc;
}
#endif

int macos_open_url(const char *url) {
    if (url == NULL || !allowed(url)) {
        fprintf(stderr, "open_url: refused\n");
        return -1;
    }
#ifdef __APPLE__
    char *argv[] = {(char *)"open", (char *)url, NULL};
    pid_t pid;
    if (posix_spawn(&pid, "/usr/bin/open", NULL, NULL, argv, environ) != 0) {
        return -1;
    }
#else
    // xdg-open, found on PATH. a page or a folder; it hands the work to the desktop and returns
    char *argv[] = {(char *)"xdg-open", (char *)url, NULL};
    pid_t pid;
    if (spawn_xdg_open(&pid, argv) != 0) {
        return -1;
    }
#endif
    pthread_t t;
    if (pthread_create(&t, NULL, reap, (void *)(intptr_t)pid) == 0) {
        pthread_detach(t);
    }
    return 0;
}
