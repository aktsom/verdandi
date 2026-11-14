/*
 * vgrid_device_win.c: the virtual arc on Windows. same interface as platform/macos/vgrid_device.c (see vgrid_device.h), where the
 * device is a pseudo terminal that libmonome opens like a USB arc. Windows has no pseudo terminals: here it is a named pipe,
 * \\.\pipe\verdandi-arc-<process id>-m0000002, that libmonome opens through the same CreateFile call as for a COM port
 * (windows/libmonome/pipe-device.patch: no baud rate, no comm events for a pipe). the protocol on it is the unchanged mext protocol
 * of vgrid_proto.c, so norns's own monome code, arc.lua and the scripts see an arc like a real one.
 *
 * the virtual grid is NOT built on Windows (not wanted now): vgrid_open says so and returns NULL, the buttons for it stay dead.
 * docs/port/phase-m13.md.
 */

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "platform/macos/vgrid_device.h"

struct vgrid_device {
    HANDLE pipe;
    HANDLE thread;
    volatile LONG stop;
    volatile LONG connected;
    CRITICAL_SECTION lock;       // the LEDs (proto) between the device thread and the window
    CRITICAL_SECTION write_lock; // one write at a time (the window thread and the device thread's answers)
    char path[96];
    vgrid_proto_t proto;
    void (*on_change)(void *ctx);
    void *ctx;
};

// wait for an overlapped call, a tenth of a second at a time, so that a close is noticed. 1: done, 0: stopped
static int wait_overlapped(vgrid_device_t *g, HANDLE pipe, OVERLAPPED *ov) {
    for (;;) {
        DWORD w = WaitForSingleObject(ov->hEvent, 100);
        if (w == WAIT_OBJECT_0) {
            return 1;
        }
        if (g->stop || w != WAIT_TIMEOUT) {
            CancelIoEx(pipe, ov);
            WaitForSingleObject(ov->hEvent, 1000);
            return 0;
        }
    }
}

// bytes to the host (libmonome). nothing is sent while no one has the pipe open
static void send_bytes(vgrid_device_t *g, const uint8_t *m, size_t n) {
    if (!g->connected) {
        return;
    }
    EnterCriticalSection(&g->write_lock);
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    ov.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (ov.hEvent != NULL) {
        DWORD done = 0;
        if (!WriteFile(g->pipe, m, (DWORD)n, &done, &ov) && GetLastError() == ERROR_IO_PENDING) {
            if (WaitForSingleObject(ov.hEvent, 1000) != WAIT_OBJECT_0) {
                CancelIoEx(g->pipe, &ov);
                WaitForSingleObject(ov.hEvent, 1000);
            }
        }
        CloseHandle(ov.hEvent);
    }
    LeaveCriticalSection(&g->write_lock);
}

static DWORD WINAPI run(LPVOID arg) {
    vgrid_device_t *g = (vgrid_device_t *)arg;
    uint8_t in[256], reply[256];
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    ov.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (ov.hEvent == NULL) {
        return 1;
    }
    while (!g->stop) {
        // wait for libmonome to open the pipe
        ResetEvent(ov.hEvent);
        if (!ConnectNamedPipe(g->pipe, &ov)) {
            DWORD e = GetLastError();
            if (e == ERROR_IO_PENDING) {
                if (!wait_overlapped(g, g->pipe, &ov)) {
                    continue;
                }
            } else if (e != ERROR_PIPE_CONNECTED) {
                Sleep(100);
                continue;
            }
        }
        g->connected = 1;
        while (!g->stop) {
            ResetEvent(ov.hEvent);
            DWORD n = 0;
            if (!ReadFile(g->pipe, in, sizeof in, &n, &ov)) {
                if (GetLastError() != ERROR_IO_PENDING) {
                    break; // the client closed it
                }
                if (!wait_overlapped(g, g->pipe, &ov)) {
                    continue;
                }
                if (!GetOverlappedResult(g->pipe, &ov, &n, FALSE)) {
                    break;
                }
            }
            if (n == 0) {
                continue;
            }
            int changed = 0;
            EnterCriticalSection(&g->lock);
            size_t r = vgrid_proto_feed(&g->proto, in, n, reply, sizeof reply, &changed);
            LeaveCriticalSection(&g->lock);
            if (r > 0) {
                send_bytes(g, reply, r);
            }
            if (changed && g->on_change) {
                g->on_change(g->ctx);
            }
        }
        g->connected = 0;
        DisconnectNamedPipe(g->pipe); // libmonome closed it (or we are closing): the next client can come
    }
    CloseHandle(ov.hEvent);
    return 0;
}

static vgrid_device_t *open_arc(const char *id, int rings, void (*on_change)(void *ctx), void *ctx) {
    vgrid_device_t *g = (vgrid_device_t *)calloc(1, sizeof *g);
    if (g == NULL) {
        return NULL;
    }
    // the serial after the last '-' is what libmonome is told (grid_win.cc, serial hook): m0000002, the serial the Linux virtual arc has
    snprintf(g->path, sizeof g->path, "pipe\\verdandi-arc-%lu-m0000002", (unsigned long)GetCurrentProcessId());
    char full[128];
    snprintf(full, sizeof full, "\\\\.\\%s", g->path);
    g->pipe = CreateNamedPipeA(full, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                               PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 4096,
                               4096, 0, NULL);
    if (g->pipe == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "vgrid: the pipe for the virtual arc could not be made (error %lu)\n",
                (unsigned long)GetLastError());
        free(g);
        return NULL;
    }
    InitializeCriticalSection(&g->lock);
    InitializeCriticalSection(&g->write_lock);
    vgrid_proto_init_arc(&g->proto, id, rings);
    g->on_change = on_change;
    g->ctx = ctx;
    g->thread = CreateThread(NULL, 0, run, g, 0, NULL);
    if (g->thread == NULL) {
        CloseHandle(g->pipe);
        DeleteCriticalSection(&g->lock);
        DeleteCriticalSection(&g->write_lock);
        free(g);
        return NULL;
    }
    return g;
}

vgrid_device_t *vgrid_open(const char *id, int cols, int rows, void (*on_change)(void *ctx), void *ctx) {
    (void)id, (void)cols, (void)rows, (void)on_change, (void)ctx;
    static int said;
    if (!said) {
        said = 1;
        fprintf(stderr, "the virtual grid: not on Windows (switched off)\n");
    }
    return NULL;
}

vgrid_device_t *vgrid_open_arc(const char *id, int rings, void (*on_change)(void *ctx), void *ctx) {
    return open_arc(id, rings, on_change, ctx);
}

void vgrid_close(vgrid_device_t *g) {
    if (g == NULL) {
        return;
    }
    g->stop = 1;
    WaitForSingleObject(g->thread, 5000);
    CloseHandle(g->thread);
    CloseHandle(g->pipe);
    DeleteCriticalSection(&g->lock);
    DeleteCriticalSection(&g->write_lock);
    free(g);
}

const char *vgrid_path(const vgrid_device_t *g) {
    return g->path;
}

// nothing to unlink: a pipe has no file
void vgrid_unlink(vgrid_device_t *g) {
    (void)g;
}

void vgrid_key(vgrid_device_t *g, int x, int y, int down) {
    uint8_t m[3];
    vgrid_proto_key(x, y, down, m);
    send_bytes(g, m, 3);
}

void vgrid_enc(vgrid_device_t *g, int n, int delta) {
    // one message carries -128..127
    while (delta != 0) {
        int d = delta < -128 ? -128 : (delta > 127 ? 127 : delta);
        uint8_t m[3];
        vgrid_proto_enc(n, d, m);
        send_bytes(g, m, 3);
        delta -= d;
    }
}

void vgrid_enc_key(vgrid_device_t *g, int n, int down) {
    uint8_t m[2];
    vgrid_proto_enc_key(n, down, m);
    send_bytes(g, m, 2);
}

void vgrid_levels(vgrid_device_t *g, uint8_t level[VGRID_MAX][VGRID_MAX], int *intensity) {
    EnterCriticalSection(&g->lock);
    memcpy(level, g->proto.level, sizeof g->proto.level);
    *intensity = g->proto.intensity;
    LeaveCriticalSection(&g->lock);
}

void vgrid_rings(vgrid_device_t *g, uint8_t ring[VARC_RINGS][VARC_LEDS], int *intensity) {
    EnterCriticalSection(&g->lock);
    memcpy(ring, g->proto.ring, sizeof g->proto.ring);
    *intensity = g->proto.intensity;
    LeaveCriticalSection(&g->lock);
}
