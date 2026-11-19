/*
 * pin_native_win.c: what Windows itself says about a window's "always on top" (the extended style WS_EX_TOPMOST), for the CI check of the PIN button (VERDANDI_TEST_HOOKS=1). docs/port/phase-m16.md
 */
#include <windows.h>

#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>

// 1 topmost, 0 not, -1 the window is not a Windows window (a headless run uses SDL's dummy video driver)
int pin_native_topmost(SDL_Window *w) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (w == NULL || !SDL_GetWindowWMInfo(w, &info) || info.subsystem != SDL_SYSWM_WINDOWS) {
        return -1;
    }
    return (GetWindowLongW(info.info.win.window, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
}

int view_covered_win(HWND hwnd);

// M28: 1 when other windows hide all of the window, 0 when some of it shows, -1 not told (not a Windows window, e.g. SDL's dummy driver)
int pin_native_covered(SDL_Window *w) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (w == NULL || !SDL_GetWindowWMInfo(w, &info) || info.subsystem != SDL_SYSWM_WINDOWS) {
        return -1;
    }
    return view_covered_win(info.info.win.window);
}
