/*
 * ws-wrapper
 *
 * this utility launches an arbitrary executable as a child process,
 * and binds the child's standard I/O to a ws socket
 *
 */

#include <assert.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/wait.h>
#include <unistd.h>

#include <nng/nng.h>
#include <nng/protocol/bus0/bus.h>
#include <nng/transport/ws/websocket.h>

#define PIPE_READ 0
#define PIPE_WRITE 1
#define PIPE_BUF_SIZE 4096

pid_t child_pid;
int pipe_rx[2];
int pipe_tx[2];

pthread_t tid_rx, tid_tx;

nng_listener listener_ws;
nng_socket sock_ws;

// WS_WRAPPER_ALLOWED_ORIGINS (optional, comma separated, e.g. "http://127.0.0.1:5000,http://localhost:5000"):
// a client that sends an Origin header (every browser does, for every websocket, whatever page it is on)
// is only kept if that origin is in the list. clients without an Origin header (maiden-repl, scripts) are
// kept. unset: no check at all, as before (the macOS launcher does not set it).
static const char *allowed_origins = NULL;

static bool origin_allowed(const char *origin) {
    size_t n = strlen(origin);
    const char *p = allowed_origins;
    while (*p != '\0') {
        const char *end = strchr(p, ',');
        size_t len = end != NULL ? (size_t)(end - p) : strlen(p);
        if (len == n && strncmp(p, origin, n) == 0) {
            return true;
        }
        if (end == NULL) {
            break;
        }
        p = end + 1;
    }
    return false;
}

// called before the connection joins the socket: nothing it sends is read, nothing is sent to it
static void check_origin(nng_pipe pipe, nng_pipe_ev ev, void *arg) {
    (void)ev;
    (void)arg;
    char *origin = NULL;
    if (nng_pipe_get_string(pipe, NNG_OPT_WS_REQUEST_HEADER "Origin", &origin) != 0) {
        return; // no Origin header: not a browser
    }
    if (!origin_allowed(origin)) {
        fprintf(stderr, "ws-wrapper: connection from origin '%s' refused\n", origin);
        nng_pipe_close(pipe);
    }
    nng_strfree(origin);
}

void fatal(const char *func, int rv) {
    fprintf(stderr, "%s: %s\n", func, nng_strerror(rv));
    exit(1);
}

void quit(void) {
    nng_close(sock_ws);
}

void bind_sock(nng_listener *listener, nng_socket *sock, char *url) {
    int rv;

    printf("attempting to bind socket at url %s\n", url);

    if ((rv = nng_bus0_open(sock)) != 0) {
        fatal("nng_bus0_open", rv);
    }
    if ((rv = nng_listener_create(listener, *sock, url)) != 0) {
        fatal("nng_listener_create", rv);
    }
    if ((rv = nng_listener_set_bool(*listener, NNG_OPT_WS_SEND_TEXT, true)) != 0) {
        fatal("listener set option: WS_SEND_TEXT", rv);
    }
    if ((rv = nng_listener_set_bool(*listener, NNG_OPT_WS_RECV_TEXT, true)) != 0) {
        fatal("listener set option: WS_RECV_TEXT", rv);
    }
    // TODO: set TLS options

    allowed_origins = getenv("WS_WRAPPER_ALLOWED_ORIGINS");
    if (allowed_origins != NULL && allowed_origins[0] != '\0') {
        if ((rv = nng_pipe_notify(*sock, NNG_PIPE_EV_ADD_PRE, check_origin, NULL)) != 0) {
            fatal("nng_pipe_notify", rv);
        }
        printf("accepting browser connections from: %s\n", allowed_origins);
    } else {
        allowed_origins = NULL;
    }

    // retry binding to handle port still held by a previous instance
    // (e.g., during systemd Restart=always after a slow shutdown).
    int attempt = 0;
    const int max_retries = 20;
    const int retry_delay_ms = 500;
    while ((rv = nng_listener_start(*listener, 0)) != 0) {
        attempt++;
        if (attempt >= max_retries) {
            fatal("nng_listener_start", rv);
        }
        fprintf(stderr, "nng_listener_start: %s (attempt %d/%d, retrying in %dms)\n",
                nng_strerror(rv), attempt, max_retries, retry_delay_ms);
        usleep(retry_delay_ms * 1000);
    }
}

void *loop_rx(void *p) {
    (void)p;
    size_t nb;
    int rv;

    while (1) {
        char *buf = NULL;
        if ((rv = nng_recv(sock_ws, &buf, &nb, NNG_FLAG_ALLOC)) != 0) {
            if (buf != NULL) {
                nng_free(buf, nb);
            }
            continue;
        }
        if (write(pipe_rx[PIPE_WRITE], buf, nb) < 0) {
            fprintf(stderr, "write to pipe failed\n");
        }
        nng_free(buf, nb);
    }
}

void *loop_tx(void *p) {
    (void)p;
    char buf[PIPE_BUF_SIZE];
    int rv;
    size_t nb;
    while (1) {
        nb = read(pipe_tx[PIPE_READ], buf, PIPE_BUF_SIZE - 1);
        if (nb > 0) {
            buf[nb] = '\0';
            printf("%s", buf);
            // stdout is often a log file (fully buffered); keep it current
            fflush(stdout);
            if ((rv = nng_send(sock_ws, buf, nb, 0)) != 0) {
                // TODO: handle error?
            }
        }
    }
}

void launch_thread(pthread_t *tid, void *(*start_routine)(void *), void *data) {
    pthread_attr_t attr;
    int s;
    s = pthread_attr_init(&attr);
    if (s) {
        printf("error initializing thread attributes \n");
    }
    s = pthread_create(tid, &attr, start_routine, data);
    if (s) {
        printf("error creating thread\n");
    }
    pthread_attr_destroy(&attr);
}

int launch_exe(int argc, char **argv) {
    (void)argc;
    char *url_ws = argv[1];
    char *exe = argv[2];

    // create pipes
    if (pipe(pipe_rx) < 0) {
        perror("allocating pipe for input redirect");
        return -1;
    }

    if (pipe(pipe_tx) < 0) {
        perror("allocating pipe for output redirect");
        return -1;
    }

    // fork the child process
    child_pid = fork();
    if (child_pid < 0) {
        printf("fork() returned an error\n");
        return 1;
    }

    if (child_pid == 0) {
        // child continues...

        // copy i/o to pipes
        if (dup2(pipe_rx[PIPE_READ], STDIN_FILENO) == -1) {
            perror("redirecting stdin");
            return -1;
        }
        close(pipe_rx[PIPE_READ]);
        close(pipe_rx[PIPE_WRITE]);

        if (dup2(pipe_tx[PIPE_WRITE], STDOUT_FILENO) == -1) {
            perror("redirecting stdout");
            return -1;
        }
        if (dup2(pipe_tx[PIPE_WRITE], STDERR_FILENO) == -1) {
            perror("redirecting stderr");
            return -1;
        }
        close(pipe_tx[PIPE_READ]);
        close(pipe_tx[PIPE_WRITE]);

        // launch the child executable
        char **child_argv = &(argv[2]);
        execvp(exe, child_argv);
        perror("execvp"); // shouldn't get here
    } else {
        // parent continues...

        // close unused pipe endpoints
        close(pipe_rx[PIPE_READ]);
        close(pipe_tx[PIPE_WRITE]);

        // set up sockets and threads
        bind_sock(&listener_ws, &sock_ws, url_ws);
        launch_thread(&tid_tx, &loop_tx, NULL);
        launch_thread(&tid_rx, &loop_rx, NULL);
    }

    // wait for the child process to exit
    int wpid, status;
    do {
        wpid = waitpid(child_pid, &status, WUNTRACED | WCONTINUED);
        if (wpid == -1) {
            perror("waitpid");
            exit(EXIT_FAILURE);
        }
        if (WIFEXITED(status)) {
            printf("child exited, status=%d\n", WEXITSTATUS(status));
        } else if (WIFSIGNALED(status)) {
            printf("child killed (signal %d)\n", WTERMSIG(status));
        } else if (WIFSTOPPED(status)) {
            printf("child stopped (signal %d)\n", WSTOPSIG(status));
        } else if (WIFCONTINUED(status)) {
            printf("child continued\n");
        } else {
            printf("unexpected status (0x%x)\n", status);
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("usage: ws-wrapper WS_SOCKET BINARY <child args...>");
    }

    nng_ws_register();
    nng_wss_register();

    setvbuf(stdout, NULL, _IONBF, 0);
    launch_exe(argc, argv);
}
