/*
 * view_covered_wine_test.c (M28): the real Win32 call behind "is the window fully covered?" (matron/src/platform/windows/view_covered_win.c), run under Wine on an X display (run_all.sh, windows: tests):
 * real windows are created, one is moved over another, and view_covered_win must say covered / partly / not covered. cross-built with mingw-w64:
 *   x86_64-w64-mingw32-gcc -I matron/src linux/tests/view_covered_wine_test.c matron/src/platform/windows/view_covered_win.c -o view_covered_wine_test.exe -luser32
 */
#include <stdio.h>
#include <windows.h>

int view_covered_win(HWND hwnd);

static int fails = 0;
#define CHECK(c, what)                                                                                                 \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL %s\n", what);                                                                                 \
        }                                                                                                              \
    } while (0)

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    return DefWindowProcA(h, m, w, l);
}

static void pump(void) {
    MSG msg;
    for (int i = 0; i < 30; i++) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        Sleep(20);
    }
}

static HWND make(int x, int y, int w, int h) {
    HWND hw = CreateWindowExA(WS_EX_TOOLWINDOW, "viewtest", "t", WS_POPUP | WS_VISIBLE, x, y, w, h, NULL, NULL, GetModuleHandleA(NULL), NULL);
    return hw;
}

int main(void) {
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "viewtest";
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    RegisterClassA(&wc);

    HWND a = make(100, 100, 400, 300);
    pump();
    CHECK(view_covered_win(a) == 0, "a window with nothing over it is not covered");
    CHECK(view_covered_win(NULL) == -1, "no window: not told");

    HWND b = make(80, 80, 440, 340); /* all of a, and more */
    pump();
    CHECK(view_covered_win(a) == 1, "a window fully over it: covered");
    CHECK(view_covered_win(b) == 0, "the window on top is not covered");

    SetWindowPos(b, NULL, 100, 100, 150, 300, SWP_NOZORDER); /* only the left part of a */
    pump();
    CHECK(view_covered_win(a) == 0, "partly covered counts as in view");

    SetWindowPos(b, NULL, 80, 80, 440, 340, SWP_NOZORDER);
    pump();
    CHECK(view_covered_win(a) == 1, "covered again");
    SetWindowPos(a, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE); /* raised above the cover (what PIN's always-on-top does) */
    pump();
    CHECK(view_covered_win(a) == 0, "raised above the cover: in view again");

    DestroyWindow(b);
    pump();
    CHECK(view_covered_win(a) == 0, "the cover is gone: in view");
    DestroyWindow(a);
    if (fails) {
        printf("%d failed\n", fails);
        return 1;
    }
    printf("view_covered: all passed\n");
    return 0;
}
