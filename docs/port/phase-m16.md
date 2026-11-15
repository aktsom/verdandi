# Phase M16 (Windows 0.10.7): PIN, always on top for every Verdandi window

Approach note. The owner wants one button that keeps all Verdandi windows on top of other windows until it is turned off.

## What it is
- **The button.** On Windows the KEYS button's slot is now **PIN** (the virtual keyboard is not built on Windows; the slot only showed "not on Windows yet"). On Linux and macOS nothing changes: KEYS, its label, its window, F7 and the action "keys" are as before (`KEYS_LABEL` in `device_skin.h` and `#ifdef NORNS_WINDOWS` branches only).
- **What a press does.** `toggle_pin` in `sdl_bridge.cc` flips one state (`pin_state.h`) and applies it to every window that exists: the main window, the grid, arc and keys panes (only the arc exists on Windows) and the detached screen window (`screen_window_sdl()`). Every window that is created later gets the state at once (`pane_open`, the main window's creation, the screen window's `decorate` callback), so the arc opened later, or closed and opened again, is on top at once. SDL does it with `SDL_SetWindowAlwaysOnTop`, which on Windows is `SetWindowPos(HWND_TOPMOST)`; it works the same for every SDL window type.
- **The look.** The button is lit while PIN is on: it reuses the lit state of the KEYS slot (`skin.keys_open`), the same look as GRID and ARC when their windows are open. A short toast says "ALWAYS ON TOP: ON/OFF".
- **Start state.** Always OFF at every start. Nothing is saved.
- **F7 and the menu.** F7 and the right-click menu entry "Always on top (PIN)" (ticked while on) do the same as the button.
- **MIDI.** The action that was called `keys` is called **`pin`** on Windows (same place, number 8 of 14, so the page, learning, "ASSIGN ALL", the stored port, the master switch and the saving are the existing ones). A file that has `act.keys.*` lines (the old action did nothing on Windows) is read as `pin`. The button and the action are one function, so they cannot get out of step: a MIDI toggle lights the button, a click on the button is what the next note toggles back.
- **Not covered by it:** system dialogs (the folder picker, the file picker) are not Verdandi's SDL windows and are not made topmost.

## Safety (so that nothing gets stuck on top)
Turning it off never needs another program: the main window's PIN button (it is itself on top), F7 in the main window, the menu entry or the MIDI action. A topmost window can always be reached with Alt+Tab or by closing Verdandi. If the detached screen window is fullscreen and PIN is on, it covers the screen like any fullscreen window: use Alt+Tab, then the main window's button (the main window is topmost too).

## Tests
- C `linux/tests/pin_state_test.c` (also built with `NORNS_WINDOWS`): off at the start, one toggle for the main, arc and screen windows, a later window and a closed-and-reopened one get the state at once, the second toggle turns all off, the next start is off; the Windows action list has `pin` where `keys` was (index 7, 14 names, neighbours unmoved), the Linux list is untouched.
- Lua `linux/tests/pin_action_test.lua` (real MIDI MAP layer, Windows and Linux platform): learned from a note with the port stored, the same note from another port does nothing, one `window_action("pin")` per press, the master switch, saved as `act.pin`, old `act.keys` lines read as `pin`; on Linux the action is still `keys`.
- CI in the real program, **with real windows** (no `--headless`, `VERDANDI_TEST_HOOKS=1`; `windows/ci/maiden_probe.py` probe `pin`, `smoke-m1.sh` `m16-check-pin`): `_norns.pin_report(n)` writes one line to `norns.log` with, for every window, the flag SDL has and Windows' own `WS_EX_TOPMOST` style (`pin_native_win.c`). Steps: start (off), arc opened and the screen detached (off), PIN (all three on and the button lit), arc closed (others stay), arc opened again (on), screen closed and opened again (on), PIN off (all off), then the MIDI action: learned from a note of a port (port stored), the same note from another port (nothing), a note from the learned port (on, windows and button follow), again (off).

## Not tested without a real PC
How it feels over the owner's other programs (a DAW, a browser, full-screen programs), several screens and mixed display scaling, the taskbar and full-screen games (Windows treats them specially), Windows' own "focus assist"/virtual desktops, and a real MIDI controller for the action. The CI runner has one desktop and no other program to be covered.
