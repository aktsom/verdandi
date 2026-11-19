/*
 * view_covered_win.c (M28): is a window fully hidden behind other windows? pure Win32 (no SDL), so a Wine test can call it. docs/port/phase-m28.md
 * nine points inside the window rectangle (a 3 x 3 grid, inset by a tenth of the size so that the invisible resize border and the shadow do not count) are asked with WindowFromPoint:
 * the window that is topmost at that point, as its root window. if one of them is our window (or owned by it) the window shows there. none of them: covered. partly covered counts as in view.
 * returns 1 covered, 0 some of it shows, -1 not told (no window, no size).
 */
#include <windows.h>

#include "platform/common/pin_state.h"

int view_covered_win(HWND hwnd) {
    RECT r;
    if (hwnd == NULL || !IsWindow(hwnd) || !GetWindowRect(hwnd, &r)) {
        return -1;
    }
    int w = r.right - r.left, h = r.bottom - r.top;
    if (w < 10 || h < 10) {
        return -1;
    }
    int ours[9];
    int n = 0;
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 3; i++) {
            POINT p;
            p.x = r.left + w / 10 + (w - 2 * (w / 10)) * i / 2;
            p.y = r.top + h / 10 + (h - 2 * (h / 10)) * j / 2;
            HWND hit = WindowFromPoint(p);
            HWND root = hit != NULL ? GetAncestor(hit, GA_ROOT) : NULL;
            ours[n++] = root == hwnd || (root != NULL && GetWindow(root, GW_OWNER) == hwnd);
        }
    }
    return view_covered_from_samples(ours, n);
}
