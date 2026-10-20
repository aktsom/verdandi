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

int macos_open_url(const char *url) {
    if (url == NULL || !allowed(url)) {
        fprintf(stderr, "open_url: refused\n");
        return -1;
    }
    char *argv[] = {(char *)"open", (char *)url, NULL};
    pid_t pid;
    if (posix_spawn(&pid, "/usr/bin/open", NULL, NULL, argv, environ) != 0) {
        return -1;
    }
    pthread_t t;
    if (pthread_create(&t, NULL, reap, (void *)(intptr_t)pid) == 0) {
        pthread_detach(t);
    }
    return 0;
}
