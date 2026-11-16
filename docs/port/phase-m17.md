# Phase M17 (Windows 0.10.8): grids and arcs go dark at every way of quitting

The owner's report: after quitting Verdandi (normally with the SLEEP row, with or without a script loaded) the LEDs of his two grids (a monome 128 and a 256) stay lit; a mod (sidvagn) draws on the second grid all the time unless it is turned off in the params. On a hardware norns the grid is cleared at shutdown.

## 1. What the code did (read, then measured in CI), by way of quitting

How the Linux port clears them (`docs/port/KNOWN-ISSUES.md` 30): `dev_list_monome_all_off(timeout)` sends every grid and arc zero level maps (plus `monome_led_all(0)`), one thread per device, bounded; it runs in `matron_cleanup` (quit, window close, launcher quit), on SIGTERM/SIGHUP/SIGINT and after a crash report. A script switch clears with `grid.cleanup()` (Lua). Windows used the same call, with these gaps:

| way of quitting | what happened before this phase | why it could leave LEDs lit |
|---|---|---|
| SLEEP row | `norns.shutdown()` saves, calls the script's `cleanup`, then C waits 0.4 s, sends "all off" and ends the process | the script (and a mod) is **not cleared** and its metros go on drawing: a refresh a few milliseconds after the "all off" lights the grid again before the process ends. With no script, a mod's metro does the same. (RESTART clears the script, a mod still draws.) |
| Quit in the right-click menu, window close button | event, then `matron_cleanup`: "all off", fast exit | the same race: the Lua side keeps running until the process ends |
| launcher stops norns.exe (the end of `--exit-after`; a restart request that norns did not answer within 20 s) | `TerminateProcess` on the program, then `TerminateJobObject` | **nothing is sent**: norns gets no chance |
| launcher's own restart after a server stop | a request file, norns runs `_norns.restart()` (script cleared, "all off" after 0.4 s) | only the race of the first rows |
| Task Manager "End task" on Verdandi.exe, a crash that skips the report, a power cut, an unplugged cable | process ended from outside | cannot be answered (see below) |

Two more findings in the same code:
1. **The time-out was none on Windows.** The device layer joined its threads with `pthread_timedjoin_np`, and on Windows that call is the plain `pthread_join` (`compat_win.h`): a grid that does not answer (a busy or half-unplugged port) could hold the quit for ever (until the launcher killed the program).
2. **Nothing flushed the port** before the process ended. A completed `WriteFile` has reached the driver; `FlushFileBuffers` makes the driver finish sending it.

Why "sometimes a script is loaded, sometimes not" does not matter: with a script or with a mod, something draws after the "all off".

I have **not** seen the owner's grids; the race is a conclusion from the code and is shown by the CI run that leaves the new freeze out (below).

## 2. What changed

- **Freeze, then off (`device_monome.cc`, `device_list.cc`).** `dev_list_monome_all_off` first freezes the LED calls of Lua (set, all, refresh, intensity change nothing from then on), then switches every grid and arc off (all quads, the same bytes a script clear writes), under a lock per device so that no half-written refresh is mixed in, then on Windows flushes the port (`windows/libmonome/flush.patch`, `FlushFileBuffers` on a serial port, nothing for the virtual pipe). One thread per device; the caller waits until they are done or until the time-out (800 ms, polled; the threads are never joined, so a device that does not answer cannot hold the quit). The freeze is only set when norns is ending: **script clears and loads are not touched.**
- **The launcher asks first (`verdandi.c`, `main.cc`).** A named event (`Local\VerdandiQuit-<pid>`, handed to norns.exe in `VERDANDI_QUIT_EVENT`) is set before the launcher stops norns.exe by any of its own ways (the end of `--exit-after`, an unanswered restart request, a console close or Ctrl+C when it has a console); norns.exe waits for it on a thread, switches the LEDs off and ends the way every other quit does; only if it does not end within 4 s (3.5 s for a console) it is terminated as before.
- **Fakes for the CI (Windows, `VERDANDI_TEST_HOOKS=1` only).** `vgrid_device_win.c` can also make grids (never offered in the program: the GRID button still says no), records every message a fake grid or arc is sent in `<home>/fakedev-*.log` (one line each: time, lit count) and can stop reading; `device_list.cc` has a "busy port" helper (a thread stuck writing on one grid).

Script switching follows a hardware norns and is unchanged: `grid.cleanup()` blanks every grid at a clear. A mod that keeps drawing redraws on its next metro tick (about 33 ms at 30 frames a second, the same as on a hardware norns). I did **not** add anything that blanks at a switch, and nothing is frozen at a switch. The question whether the blank of a clear should wait for a moment (and be dropped if something draws first) is the owner's: it would be a change from the hardware's behaviour and is not made.

## 3. The virtual arc and the other virtual paths

The virtual arc is a device like the others: it is part of the same "all off" (CI: its pipe recorder ends in a message with no LED lit), the quit of its window thread does not wait for anything. The virtual keyboard and grid are not built on Windows.

## 4. Tests (Windows CI, real norns.exe, fake devices that record what they are sent; `grid_log_check.py` demands that the LAST message of each device is an all off and that the device was lit before)

`m17-*` in `smoke-m1.sh`: SLEEP with a script drawing on two grids and the arc; SLEEP with no script and a "mod" metro; the Quit event (what the menu's Quit and the window's close post; the SDL part is not driven); the launcher's own stop (`--exit-after`); a restart; a busy port (the second grid stops reading and a writer is stuck on it) followed by SLEEP, which must end within 25 s with the first grid dark; and an informational run of the SLEEP-with-mod case with the freeze left out (`VERDANDI_TEST_NO_FREEZE=1`), which prints whether a grid is lit again (it never fails the job). Not driven: a console close of the launcher (the launcher has no console in the shipped program), the Task Manager, a crash, an unplugged cable, the SDL close button itself.

## 5. What cannot be answered

Task Manager "End task" on Verdandi.exe ends the launcher, and the job object ends norns.exe with it at once; a crash, a power cut and a USB unplug send nothing. A grid that was lit then stays lit until a script (or the next start of Verdandi) draws on it. Hardware: a real 128 and 256, serialosc running and holding the port (it can light LEDs again), the iii grid (a MIDI device, not handled).
