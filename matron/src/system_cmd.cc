#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "events.h"
#include "sidecar.h"

#include "system_cmd.h"

//----------------------------
//--- types and variables

#ifdef NORNS_TEST
void *(*system_cmd_test_realloc)(void *, size_t) = realloc;
#define CAPTURE_REALLOC system_cmd_test_realloc
#else
#define CAPTURE_REALLOC realloc
#endif

// accumulated command output, capped at SYSTEM_CMD_CAPTURE_MAX
typedef struct {
    char *buf;
    size_t len;
    bool failed;
    bool truncated;
    int cb_ref;              // unused on the sync path
    sidecar_status_t status; // sync path only
} capture_t;

static void capture_append(void *ctx, const char *chunk, size_t size) {
    capture_t *cap = (capture_t *)ctx;
    if (cap->truncated) {
        return;
    }
    if (size > SYSTEM_CMD_CAPTURE_MAX - cap->len) {
        size = SYSTEM_CMD_CAPTURE_MAX - cap->len;
        cap->truncated = true;
        fprintf(stderr, "system_cmd: output exceeded cap, truncating\n");
    }
    if (size == 0) {
        return;
    }
    char *grown = (char *)CAPTURE_REALLOC(cap->buf, cap->len + size);
    if (grown == NULL) {
        cap->truncated = true;
        fprintf(stderr, "system_cmd: out of memory, truncating\n");
        return;
    }
    memcpy(grown + cap->len, chunk, size);
    cap->buf = grown;
    cap->len += size;
}

static void capture_discard_on_transport_failure(capture_t *cap, sidecar_result_t result) {
    if (result != SIDECAR_TRANSPORT_FAILED) {
        return;
    }
    cap->failed = true;
    free(cap->buf);
    cap->buf = NULL;
    cap->len = 0;
}

static void capture_null_terminate(capture_t *cap) {
    char *out = (char *)CAPTURE_REALLOC(cap->buf, cap->len + 1);
    if (out == NULL) {
        fprintf(stderr, "system_cmd: out of memory, dropping output\n");
        free(cap->buf);
        cap->truncated = true;
        cap->len = 0;
        out = (char *)calloc(1, 1);
        if (out == NULL) {
            cap->buf = NULL;
            return;
        }
    }
    out[cap->len] = '\0';
    cap->buf = out;
    cap->len += 1;
}

// FIXME the settings password change passes a plaintext password through here,
// and stderr reaches the journal and maiden. fixing it needs a way to pass a
// secret on stdin rather than in the command string
static void log_cmd_failure(const char *label, const char *cmd, const char *err) {
    fprintf(stderr, "%s: command (%s) failed: %s\n", label, cmd != NULL ? cmd : "", err != NULL ? err : "unknown error");
}

static void post_cmd_done(const char *cmd, void *ctx, const sidecar_status_t *status) {
    capture_t *cap = (capture_t *)ctx;
    capture_discard_on_transport_failure(cap, status->result);

    if (status->result == SIDECAR_TRANSPORT_FAILED) {
        log_cmd_failure("system_cmd", cmd, status->err);
    }

    // FIXME failure and silent success both arrive as "". telling them apart
    // needs an extra callback argument, which changes the signature every
    // script's norns.system_cmd callback is written against
    capture_null_terminate(cap);
    union event_data *ev = event_data_new(EVENT_SYSTEM_CMD);
    ev->system_cmd.capture = cap->buf; // freed when the event is handled
    ev->system_cmd.cb_ref = cap->cb_ref;
    event_post(ev);
    free(cap);
}

static void finish_sync_capture(const char *cmd, void *ctx, const sidecar_status_t *status) {
    (void)cmd;
    capture_t *cap = (capture_t *)ctx;
    capture_discard_on_transport_failure(cap, status->result);
    cap->status = *status;
    cap->status.err = NULL;
}

static void post_launch_done(const char *cmd, void *ctx, const sidecar_status_t *status) {
    const int cb_ref = (int)(intptr_t)ctx;
    const bool ok = (status->result == SIDECAR_OK);
    const char *err = status->err;

    if (status->result == SIDECAR_TRANSPORT_FAILED) {
        err = "no answer from the sidecar, the action may still have started";
    }

    if (!ok) {
        log_cmd_failure("system_cmd_detached", cmd, err);
    }

    union event_data *ev = event_data_new(EVENT_SYSTEM_CMD_DONE);
    if (err != NULL) {
        ev->system_cmd_done.err = strdup(err);
    }
    ev->system_cmd_done.cb_ref = cb_ref;
    ev->system_cmd_done.ok = ok;
    event_post(ev);
}

typedef struct {
    const char *name;
    const char *cmd;
    const char *unit;
} system_action_t;

#ifdef __APPLE__
// macOS (macos/norns.sh supervises norns): SLEEP quits norns, it does not power off the Mac;
// RESTART leaves a marker so norns.sh starts norns and sclang again. (pkill -a: macOS pkill
// spares its own ancestors by default, and norns is one of them; in the app the binary is
// named Verdandi, macos/make-app.sh)
static const system_action_t system_actions[] = {
    {"shutdown", "sleep 0.5; pkill -TERM -a -x 'norns|Verdandi'", "norns-shutdown"},
    {"reset", "touch \"$HOME/.norns-restart\"; sleep 0.5; pkill -TERM -a -x 'norns|Verdandi'", "norns-reset"},
    {"update", "echo 'Verdandi: update scripts in maiden, Verdandi itself with a new version of the app'", "norns-update"},
};
#elif defined(NORNS_LINUX_DESKTOP)
// desktop Linux (linux/norns.sh supervises norns): the same as on macOS, without the computer's
// own power control
static const system_action_t system_actions[] = {
    {"shutdown", "sleep 0.5; pkill -TERM -x norns", "norns-shutdown"},
    {"reset", "touch \"$HOME/.norns-restart\"; sleep 0.5; pkill -TERM -x norns", "norns-reset"},
    {"update", "echo 'Verdandi: update scripts in maiden, Verdandi itself with a new version of the app'", "norns-update"},
};
#else
static const system_action_t system_actions[] = {
    {"shutdown", "sleep 0.5; sudo shutdown now", "norns-shutdown"},
    {"reset", "sudo systemctl restart norns-sclang.service norns-main.service", "norns-reset"},
    {"update", NULL, "norns-update"},
};
#endif

static void build_update_cmd(char *buf, size_t len) {
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        home = "/home/we";
    }
    snprintf(buf, len, "/bin/bash %s/norns/update/update.sh", home);
}

//-------------------------------
//-- extern function definitions

bool system_cmd(const char *cmd, int cb_ref) {
    capture_t *cap = (capture_t *)calloc(1, sizeof(capture_t));
    if (cap == NULL) {
        return false;
    }
    cap->cb_ref = cb_ref;
    if (!sidecar_client_cmd_async(cmd, SIDECAR_CMD_TIMEOUT_DEFAULT_MS, cap, capture_append, post_cmd_done)) {
        free(cap);
        return false;
    }
    return true;
}

bool system_cmd_sync(const char *cmd, char **out, size_t *size, sidecar_status_t *status, uint32_t timeout_ms) {
    capture_t cap = {};
    sidecar_client_cmd(cmd, timeout_ms, &cap, capture_append, finish_sync_capture);
    if (status != NULL) {
        *status = cap.status;
    }
    if (cap.failed) {
        *out = NULL;
        *size = 0;
        return false;
    }
    capture_null_terminate(&cap);
    *out = cap.buf;
    *size = cap.len;
    return true;
}

bool system_cmd_detached(const char *cmd, const char *unit, int cb_ref) {
    return sidecar_client_detach_async(cmd, unit, (void *)(intptr_t)cb_ref, post_launch_done);
}

#ifdef NORNS_WINDOWS
// Windows (the launcher Verdandi.exe supervises norns.exe): RESTART ends norns.exe with exit code 42, and the launcher then stops sclang and starts everything again (new audio settings, a new script
// state); SLEEP (shutdown) ends it with 0 and the launcher ends too. the exit runs from a thread after a moment, so that the Lua side has finished the save it does before asking.
#include <pthread.h>
#include "platform/windows/audio/exit_win.h"
#include "platform/windows/midi/midi_win.h"
static void *windows_exit_thread(void *arg) {
    struct timespec ts = {0, 400 * 1000 * 1000};
    nanosleep(&ts, NULL);
    vgrid_win_leds_off(); // a restart or a shutdown: the grids' LEDs off first
    verdandi_win_exit((int)(intptr_t)arg); // (not exit(): see exit_win.h)
    return NULL;
}
#endif

bool system_action(const char *action, int cb_ref) {
#ifdef NORNS_WINDOWS
    if (strcmp(action, "reset") == 0 || strcmp(action, "shutdown") == 0) {
        pthread_t t;
        intptr_t code = strcmp(action, "reset") == 0 ? 42 : 0;
        fprintf(stderr, "system_action: %s, norns.exe ends with exit code %d\n", action, (int)code);
        (void)cb_ref;
        return pthread_create(&t, NULL, windows_exit_thread, (void *)code) == 0;
    }
#endif
    for (size_t i = 0; i < sizeof(system_actions) / sizeof(system_actions[0]); ++i) {
        const system_action_t *a = &system_actions[i];
        if (strcmp(a->name, action) != 0) {
            continue;
        }
        if (a->cmd != NULL) {
            return system_cmd_detached(a->cmd, a->unit, cb_ref);
        }
        char cmd[512];
        build_update_cmd(cmd, sizeof(cmd));
        return system_cmd_detached(cmd, a->unit, cb_ref);
    }
    fprintf(stderr, "system_action: unknown action (%s)\n", action);
    return false;
}
