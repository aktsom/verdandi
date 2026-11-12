/* sdl_modal_win.cc (Windows build): while a window is dragged or resized Windows runs a modal loop inside the window's thread and calls nothing of ours but the window procedure. SDL gives us the raw
 * messages (SDL_SetWindowsMessageHook): on WM_ENTERSIZEMOVE a timer of 8 ms is started, its WM_TIMER calls `tick` (which shows the frames the script drew and draws the box again), WM_EXITSIZEMOVE stops it.
 * so the picture stays alive during the drag at about 60 frames a second whatever the version of SDL does for live resizing. the norns thread never waits for this thread (present_coalesce.h). */
#include <SDL.h>
#include <windows.h>

static void (*g_tick)(void);
static const UINT_PTR TIMER_ID = 0x564E4452; /* "VNDR" */

static void SDLCALL modal_hook(void *, void *hwnd, unsigned int msg, Uint64 wparam, Sint64) {
    HWND h = (HWND)hwnd;
    if (msg == WM_ENTERSIZEMOVE) {
        SetTimer(h, TIMER_ID, 8, NULL);
    } else if (msg == WM_EXITSIZEMOVE) {
        KillTimer(h, TIMER_ID);
    } else if (msg == WM_TIMER && (UINT_PTR)wparam == TIMER_ID && g_tick) {
        g_tick();
    }
}

extern "C" void win_modal_install(void (*tick)(void)) {
    g_tick = tick;
    SDL_SetWindowsMessageHook(modal_hook, NULL);
}
