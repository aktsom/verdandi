# Phase M28 (0.10.17): PIN brings the window up when it is not in view

Base: the head of linux-port after M27 is green. macOS is not touched (everything is inside `NORNS_LINUX_DESKTOP`, which the Mac build does not define). No change to sound, latency or any other behaviour.

## What exists
`toggle_pin()` in `platform/macos/sdl_bridge.cc` is where every PIN trigger ends: the button, F7, the right-click item and the MIDI action (the action goes through the SDL event queue, `run_window_action` -> `button_action` -> `toggle_keys` -> `toggle_pin`, so it runs on the main thread and never blocks the MIDI thread). It flips `pin_state_t` and sets `SDL_SetWindowAlwaysOnTop` on every window. On Wayland it only says that PIN cannot work.

## What changes
A press first asks "is the main window in view?" (`platform/common/pin_state.h`, pure functions, tested):
- **not in view**: restore it if minimized, show it if hidden, turn PIN **on** (never off), apply it to every window, raise the main window.
- **in view**: toggle as before.
- Wayland: unchanged (the plain message; no bring-up, nothing new).

The rule for "not in view", kept simple:
- **Linux (X11)**: minimized, or hidden (SDL's `SDL_WINDOW_MINIMIZED` / not shown; window managers unmap a window that is on another desktop, which SDL reports as hidden). "Covered by other windows" is **not** told on X11: Xlib would have to walk the window manager's frames and stack, which is not dependable across window managers. A window that is only covered gets the normal toggle.
- **Windows**: minimized, hidden, or **fully covered**: nine points inside the window (a 3 x 3 grid inset from the edges) are asked with `WindowFromPoint`; if none of them belongs to our window (root of the hit window), it is covered. Partly covered counts as in view. `platform/windows/view_covered_win.c` (pure Win32, so a Wine test can call it).

What actually happens on bring-up: Windows may refuse to give the keyboard focus to a background program; none of the "fake input" tricks (`AttachThreadInput`, synthetic keys) are used. The window is restored (ShowWindow SW_RESTORE) and made topmost by PIN itself (`SetWindowPos HWND_TOPMOST` needs no focus), so it comes in front; it may not get the keyboard focus. On X11 the raise is the normal `_NET_ACTIVE_WINDOW` request; a window manager may refuse the focus, the window is still raised.

## Tests (each shown to fail on the old code: `phase-m28-without.txt`)
- C: `pin_state_test.c` extended: the decision rule (in view / minimized / hidden / covered / unknown), bring-up never turns PIN off, the nine-point sampling rule.
- Wine: a mingw-built test creates real windows and calls `view_covered_win.c` (covered, not covered, partly covered, raised above the cover, the cover gone). First run on CI: Wine without a display does not hit-test windows (the sanity check failed), so the test now checks that precondition, tries Xvfb, and is a SKIP with the reason when neither works; a check that runs and fails is a FAIL. The same call is proved on the real Windows runner (probe steps below).
- Linux window probe (real norns on Xvfb, `VERDANDI_TEST_HOOKS=1`): hide the window, press PIN: it is shown again and PIN is on; PIN already on and hidden: stays on; in view: toggles.
- Windows runner (real desktop): the PIN probe gets the steps minimize -> press, covered -> press, in view -> toggle.
