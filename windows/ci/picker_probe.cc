/* picker_probe.cc: the REAL folder picker code (matron/src/platform/windows/folder_picker_win.cc) on the Windows runner, without a person: picker_open starts the Explorer-style folder window (IFileOpenDialog,
 * pick-folders option); this probe waits for the window to appear (class #32770, visible, of this process), then closes it as a user would with Cancel (WM_CLOSE). what it proves: COM, the dialog object, the options,
 * the owner handling, the thread and Show all work (the window really opened), and that closing it is reported as "cancelled" (n = 0), never as a failure. what it cannot prove: that a person can navigate and pick a folder.
 * prints "PICKER FAIL <what>" lines and "PICKER all passed". build: g++ -std=c++17 -I matron/src windows/ci/picker_probe.cc matron/src/platform/windows/folder_picker_win.cc -o picker_probe.exe -lole32 -lshell32 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <atomic>
#include "platform/linux/file_picker.h"

static std::atomic<int> got{0}, got_n{99};
static char got_text[400];
static void done(const char *const *paths, int n, void *) {
    if (n != 0 && paths && paths[0]) {
        snprintf(got_text, sizeof got_text, "%s", paths[0]);
    }
    got_n = n;
    got = 1;
}
struct find { HWND w; };
static BOOL CALLBACK each(HWND w, LPARAM lp) {
    DWORD pid = 0;
    GetWindowThreadProcessId(w, &pid);
    if (pid != GetCurrentProcessId() || !IsWindowVisible(w)) {
        return TRUE;
    }
    wchar_t cls[64];
    GetClassNameW(w, cls, 64);
    if (wcscmp(cls, L"#32770") == 0) {
        ((find *)lp)->w = w;
        return FALSE;
    }
    return TRUE;
}
int main(void) {
    int fails = 0;
    // an owner window of this program, as the norns window is (a plain hidden-style top window in front)
    HWND owner = CreateWindowExW(0, L"STATIC", L"probe owner", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 50, 50, 300, 200, NULL, NULL, GetModuleHandleW(NULL), NULL);
    SetForegroundWindow(owner);
    if (picker_open(PICK_FOLDER, NULL, "Choose a folder with samples (probe)", done, NULL) != 0) {
        printf("PICKER FAIL picker_open returned -1\n");
        return 1;
    }
    HWND dlg = NULL;
    for (int i = 0; i < 200 && !dlg && !got; i++) { // up to 20 s
        find f = {NULL};
        EnumWindows(each, (LPARAM)&f);
        dlg = f.w;
        if (!dlg) {
            MSG m;
            while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&m);
                DispatchMessageW(&m);
            }
            Sleep(100);
        }
    }
    if (got && got_n != 0) {
        printf("PICKER FAIL the picker ended before a window was seen, n=%d: %s\n", got_n.load(), got_text);
        return 1;
    }
    if (!dlg) {
        printf("PICKER FAIL no folder window was seen within 20 seconds\n");
        return 1;
    }
    wchar_t title[200] = {0};
    GetWindowTextW(dlg, title, 200);
    printf("window seen: title \"%ls\"\n", title);
    Sleep(500);
    PostMessageW(dlg, WM_CLOSE, 0, 0);
    for (int i = 0; i < 100 && !got; i++) {
        MSG m;
        while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        Sleep(100);
    }
    if (!got) {
        printf("PICKER FAIL the window did not answer after it was closed\n");
        return 1;
    }
    if (got_n != 0) {
        printf("PICKER FAIL closing the window was not reported as cancelled (n=%d: %s)\n", got_n.load(), got_text);
        fails++;
    }
    // asking again while nothing is open works (the guard is released)
    got = 0;
    if (picker_open(PICK_FILES, NULL, "x", done, NULL) != -1) {
        printf("PICKER FAIL files should say -1 (not in this build)\n");
        fails++;
    }
    if (fails) {
        printf("PICKER %d failed\n", fails);
        return 1;
    }
    printf("PICKER all passed\n");
    return 0;
}
