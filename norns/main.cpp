#include <exception>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#ifdef __APPLE__
#include <pthread.h>
#include <sys/event.h>
#else
#include <sys/prctl.h>
#endif
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "crone_main.h"
#include "matron_main.h"

#include "sidecar.h"

#ifdef __APPLE__
#include "platform/macos/sdl_bridge.h"

static int norns_argc;
static char **norns_argv;

// darwin has no PR_SET_PDEATHSIG: the sidecar watches its parent with kqueue instead
static void *watch_parent(void *p) {
    (void)p;
    int kq = kqueue();
    struct kevent ke;
    EV_SET(&ke, getppid(), EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    if (kq < 0 || kevent(kq, &ke, 1, NULL, 0, NULL) < 0 || kevent(kq, NULL, 0, &ke, 1, NULL) >= 0) {
        _exit(0);
    }
    return NULL;
}

// matron and crone run off the main thread; the main thread belongs to cocoa (sdl_bridge)
static void crone_at_exit(void) {
    crone_stop();
}

static void *norns_thread(void *p) {
    (void)p;
    try {
        crone_main();
    } catch (const std::exception &e) {
        // no jack server (norns started on its own, jackd gone): a message, not a crash report
        fprintf(stderr, "norns: cannot start audio: %s\n", e.what());
        _exit(1);
    }
    // matron_cleanup() ends with exit(): stop crone's jack clients before exit tears down the
    // objects their process callbacks use
    atexit(crone_at_exit);
    matron_main(norns_argc, norns_argv);
    matron_cleanup();
    crone_cleanup();
    sidecar_client_cleanup();
    exit(0);
    return NULL;
}
#endif

int main(int argc, char **argv) {
    // update.sh gates the final reboot on this. exiting 0 before any
    // fork/jack/hardware init proves the new binary links
    if (argc > 1 && strcmp(argv[1], "--check") == 0) {
        printf("norns: --check ok\n");
        return 0;
    }

    int exec_name_size = strlen(argv[0]);

    int sync_pipe[2];
    if (pipe(sync_pipe) == -1) {
        perror("pipe");
        return 1;
    }

    if (fork() == 0) {
        close(sync_pipe[0]);

        strncpy(argv[0], "sidecar [norns]", exec_name_size);

#ifdef __APPLE__
        pthread_setname_np(pthread_self(), "sidecar");
        pthread_t watcher;
        pthread_create(&watcher, NULL, watch_parent, NULL);
#else
        // child, set the thread name to sidecar for added clarity in gdb
        if (prctl(PR_SET_NAME, (unsigned long)"sidecar") < 0) {
            perror("prctl(PR_SET_NAME)");
        }

        // arrange to receive SIGHUP when the thread which forked the child exits
        if (prctl(PR_SET_PDEATHSIG, SIGHUP) < 0) {
            perror("prctl(PR_SET_PDEATHSIG)");
        }
#endif

        // detach this processes stdin from parent
        int fd = open("/dev/null", O_RDONLY);
        dup2(fd, 0);

        sidecar_server_main(sync_pipe[1]);
    } else {
        close(sync_pipe[1]); // Parent closes write end

        // block here until the child writes a byte (meaning NNG listener is up)
        char b;
        read(sync_pipe[0], &b, 1);
        close(sync_pipe[0]);

        // parent
        sidecar_client_init();

#ifdef __APPLE__
        norns_argc = argc;
        norns_argv = argv;
        sdl_bridge_init();
        pthread_t tid;
        pthread_create(&tid, NULL, norns_thread, NULL);
        sdl_bridge_run();
#endif
        crone_main();
        matron_main(argc, argv);

        matron_cleanup();
        crone_cleanup();
        sidecar_client_cleanup();
    }
    return 0;
}