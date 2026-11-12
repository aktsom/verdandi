/* sdl_modal_win.cc (Windows build): while a window is dragged or resized Windows runs a modal loop inside the window's thread and calls nothing of ours but the window procedure. SDL gives us the raw
 * messages (SDL_SetWindowsMessageHook): on WM_ENTERSIZEMOVE a timer of 8 ms is started, its WM_TIMER calls `tick` (which shows the frames the script drew and draws the box again), WM_EXITSIZEMOVE stops it.
 * so the picture stays alive during the drag at about 60 frames a second whatever the version of SDL does for live resizing. the norns thread never waits for this thread (present_coalesce.h). */
#include <SDL.h>
#include <windows.h>
#include <stdio.h>

static void (*g_tick)(void);
static const UINT_PTR TIMER_ID = 0x564E4452; /* "VNDR" */

/* how long the redraws take while the window is dragged or resized: one line in norns.log at the end ("window: 140 redraws in 2.3 s, mean 4.1 ms, slowest 19.8 ms"). the timer asks for a frame every 8 ms: a mean
 * above that, or a slowest far above it, is what a choppy resize looks like */
static double g_sum, g_max;
static unsigned g_n;
static LARGE_INTEGER g_freq, g_t0;

static double ms_since(LARGE_INTEGER a) {
    LARGE_INTEGER b;
    QueryPerformanceCounter(&b);
    return (double)(b.QuadPart - a.QuadPart) * 1000.0 / (double)g_freq.QuadPart;
}

static void SDLCALL modal_hook(void *, void *hwnd, unsigned int msg, Uint64 wparam, Sint64) {
    HWND h = (HWND)hwnd;
    if (msg == WM_ENTERSIZEMOVE) {
        QueryPerformanceFrequency(&g_freq);
        QueryPerformanceCounter(&g_t0);
        g_sum = g_max = 0;
        g_n = 0;
        SetTimer(h, TIMER_ID, 8, NULL);
    } else if (msg == WM_EXITSIZEMOVE) {
        KillTimer(h, TIMER_ID);
        if (g_n > 0) {
            fprintf(stderr, "window: %u redraws in %.1f s while the window was moved or resized, mean %.1f ms, slowest %.1f ms (the timer asks for one every 8 ms)\n", g_n, ms_since(g_t0) / 1000.0, g_sum / g_n, g_max);
        }
    } else if (msg == WM_TIMER && (UINT_PTR)wparam == TIMER_ID && g_tick) {
        LARGE_INTEGER t;
        QueryPerformanceCounter(&t);
        g_tick();
        double d = ms_since(t);
        g_sum += d;
        if (d > g_max) g_max = d;
        g_n++;
    }
}

extern "C" void win_modal_install(void (*tick)(void)) {
    g_tick = tick;
    SDL_SetWindowsMessageHook(modal_hook, NULL);
}
