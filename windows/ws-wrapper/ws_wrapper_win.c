/*
 * ws_wrapper_win.c: ws-wrapper for Windows (the Linux one is ws-wrapper/src/main.c: fork, pipes, waitpid). it starts a program as a child with its standard input and output on pipes and puts them on a websocket:
 *     ws-wrapper.exe ws://127.0.0.1:5555 C:\\...\\norns.exe [arguments]
 * what the browser's norns console (maiden, port 5555) types goes to the child's stdin; what the child writes (stdout and stderr) goes to the websocket AND to this program's own stdout, which is the log of the
 * launcher. the exit code of the child is this program's exit code (the launcher reads 42 as "restart"). the child is in the job object of the launcher (it is started inside it): ending the job ends it.
 * WS_WRAPPER_ALLOWED_ORIGINS (comma separated): a client that sends an Origin header (every browser does) is only kept if its origin is in the list; clients without one (maiden-repl, scripts) are kept.
 * the Windows build binds to 127.0.0.1 only: the launcher gives such a URL.
 */
#include <windows.h>
#include <shellapi.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include <nng/nng.h>
#include <nng/protocol/bus0/bus.h>
#include <nng/transport/ws/websocket.h>

static HANDLE child_in_w, child_out_r, child_proc;
static nng_listener listener_ws;
static nng_socket sock_ws;
static const char *allowed_origins = NULL;
static volatile LONG stopping;

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

static void check_origin(nng_pipe pipe, nng_pipe_ev ev, void *arg) {
    (void)ev;
    (void)arg;
    char *origin = NULL;
    if (nng_pipe_get_string(pipe, NNG_OPT_WS_REQUEST_HEADER "Origin", &origin) != 0) {
        return; /* no Origin header: not a browser */
    }
    if (!origin_allowed(origin)) {
        fprintf(stderr, "ws-wrapper: connection from origin '%s' refused\n", origin);
        nng_pipe_close(pipe);
    }
    nng_strfree(origin);
}

static void fatal(const char *func, int rv) {
    fprintf(stderr, "ws-wrapper: %s: %s\n", func, nng_strerror(rv));
    exit(1);
}

static void bind_sock(const char *url) {
    int rv;
    if ((rv = nng_bus0_open(&sock_ws)) != 0) fatal("nng_bus0_open", rv);
    if ((rv = nng_listener_create(&listener_ws, sock_ws, url)) != 0) fatal("nng_listener_create", rv);
    if ((rv = nng_listener_set_bool(listener_ws, NNG_OPT_WS_SEND_TEXT, true)) != 0) fatal("WS_SEND_TEXT", rv);
    if ((rv = nng_listener_set_bool(listener_ws, NNG_OPT_WS_RECV_TEXT, true)) != 0) fatal("WS_RECV_TEXT", rv);
    allowed_origins = getenv("WS_WRAPPER_ALLOWED_ORIGINS");
    if (allowed_origins != NULL && allowed_origins[0] != '\0') {
        if ((rv = nng_pipe_notify(sock_ws, NNG_PIPE_EV_ADD_PRE, check_origin, NULL)) != 0) fatal("nng_pipe_notify", rv);
        printf("ws-wrapper: accepting browser connections from: %s\n", allowed_origins);
    } else {
        allowed_origins = NULL;
    }
    /* a port still held by the previous run (a restart): try again for ten seconds */
    for (int attempt = 1; (rv = nng_listener_start(listener_ws, 0)) != 0; attempt++) {
        if (attempt >= 20) fatal("nng_listener_start", rv);
        fprintf(stderr, "ws-wrapper: nng_listener_start: %s (attempt %d/20, again in 500 ms)\n", nng_strerror(rv), attempt);
        Sleep(500);
    }
    printf("ws-wrapper: %s is open\n", url);
}

static void *loop_rx(void *p) {
    (void)p;
    while (!stopping) {
        char *buf = NULL;
        size_t nb;
        if (nng_recv(sock_ws, &buf, &nb, NNG_FLAG_ALLOC) != 0) {
            if (stopping) break;
            Sleep(10);
            continue;
        }
        DWORD w;
        if (!WriteFile(child_in_w, buf, (DWORD)nb, &w, NULL)) {
            fprintf(stderr, "ws-wrapper: write to the child failed\n");
        }
        nng_free(buf, nb);
    }
    return NULL;
}

static void *loop_tx(void *p) {
    (void)p;
    char buf[4096];
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    for (;;) {
        DWORD n = 0;
        if (!ReadFile(child_out_r, buf, sizeof buf, &n, NULL) || n == 0) {
            break; /* the child ended: the pipe is closed */
        }
        DWORD w;
        if (out != INVALID_HANDLE_VALUE && out != NULL) {
            WriteFile(out, buf, n, &w, NULL);
        }
        nng_send(sock_ws, buf, n, 0);
    }
    return NULL;
}

/* the rest of the command line as one string for CreateProcess: each argument quoted by the rules of CommandLineToArgvW */
static void append_arg(wchar_t *cmd, size_t cap, const wchar_t *arg) {
    size_t at = wcslen(cmd);
    if (at + 3 >= cap) return;
    if (at) cmd[at++] = L' ';
    bool quote = arg[0] == 0 || wcspbrk(arg, L" \t\"") != NULL;
    if (quote) cmd[at++] = L'"';
    for (const wchar_t *c = arg; *c && at + 4 < cap; c++) {
        unsigned slashes = 0;
        while (*c == L'\\') { slashes++; c++; }
        if (*c == 0) {
            for (unsigned i = 0; i < slashes * (quote ? 2u : 1u) && at + 2 < cap; i++) cmd[at++] = L'\\';
            break;
        }
        if (*c == L'"') {
            for (unsigned i = 0; i < slashes * 2 + 1 && at + 2 < cap; i++) cmd[at++] = L'\\';
            cmd[at++] = L'"';
        } else {
            for (unsigned i = 0; i < slashes && at + 2 < cap; i++) cmd[at++] = L'\\';
            cmd[at++] = *c;
        }
    }
    if (quote) cmd[at++] = L'"';
    cmd[at] = 0;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: ws-wrapper.exe ws://127.0.0.1:PORT PROGRAM [arguments]\n");
        return 2;
    }
    char url[256];
    if (WideCharToMultiByte(CP_UTF8, 0, argv[1], -1, url, sizeof url, NULL, NULL) <= 0) return 2;
    setvbuf(stdout, NULL, _IONBF, 0);

    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE child_in_r, child_out_w;
    if (!CreatePipe(&child_in_r, &child_in_w, &sa, 0) || !CreatePipe(&child_out_r, &child_out_w, &sa, 0)) {
        fprintf(stderr, "ws-wrapper: no pipes\n");
        return 3;
    }
    SetHandleInformation(child_in_w, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(child_out_r, HANDLE_FLAG_INHERIT, 0);

    wchar_t cmd[32768];
    cmd[0] = 0;
    for (int i = 2; i < argc; i++) append_arg(cmd, 32768, argv[i]);
    STARTUPINFOW si;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = child_in_r;
    si.hStdOutput = child_out_w;
    si.hStdError = child_out_w;
    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof pi);
    if (!CreateProcessW(NULL, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        fprintf(stderr, "ws-wrapper: cannot start the program (error %lu): %ls\n", (unsigned long)GetLastError(), cmd);
        return 4;
    }
    CloseHandle(pi.hThread);
    child_proc = pi.hProcess;
    CloseHandle(child_in_r);
    CloseHandle(child_out_w);

    nng_ws_register();
    bind_sock(url);
    pthread_t tx, rx;
    pthread_create(&tx, NULL, loop_tx, NULL);
    pthread_create(&rx, NULL, loop_rx, NULL);

    WaitForSingleObject(child_proc, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(child_proc, &code);
    /* the output that is still in the pipe is passed on, then the socket is closed */
    for (int i = 0; i < 40; i++) {
        DWORD avail = 0;
        if (!PeekNamedPipe(child_out_r, NULL, 0, NULL, &avail, NULL) || avail == 0) break;
        Sleep(50);
    }
    InterlockedExchange(&stopping, 1);
    printf("ws-wrapper: the program ended with exit code %lu\n", (unsigned long)code);
    nng_close(sock_ws);
    return (int)code;
}
