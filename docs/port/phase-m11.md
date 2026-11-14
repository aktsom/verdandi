# Phase M11: three small control fixes (Windows 0.10.2)

## 1. K2 on the HOME page: "home.lua:55: attempt to index a nil value (field 'cpu')"
- **Cause (read in the code):** `lua/core/menu/home.lua` draws the statistics from `norns.cpu`, `norns.disk` and `norns.temp`. Those are set by `_norns.stat`, which the *stat thread* (`matron/src/hardware/stat.cc`: free disk, temperature, processor load, every two seconds) calls. The Windows build had an empty `stat_init()` (a stub in `stubs_win.cc`), so the numbers never existed: every redraw of the page with the statistics on, and every key and encoder on it (they redraw), raised the error, and the error note blocked the keys for a few seconds.
- **Fix:** (a) a real stat thread for Windows, `matron/src/platform/windows/stat_win.cc`: free MB on the drive of the user's folder (GetDiskFreeSpaceEx), the load of the whole processor (GetSystemTimes) and of its first four logical processors (NtQuerySystemInformation, the numbers of the Task Manager); the temperature is 0 (Windows gives none without a driver) and the page leaves it out when it is 0. (b) `lua/core/norns.lua` starts with `norns.disk = 0`, `norns.temp = 0`, `norns.cpu = {0, 0, 0, 0}` until the first report. (c) `home.lua` itself no longer breaks on a missing number, a missing audio call or a missing `wifi`.
- **Tests:** `linux/tests/home_page_test.lua` (fails on the old page with exactly the owner's error, passes now); every page of the menu in the REAL norns.exe on the runner (`windows/ci/maiden_probe.py`, probe `repl-menu-pages`): init, redraw, E1-E3 (three turns each), K1-K3 down and up, redraw, deinit, each under pcall, any error fails the check. K3 is not pressed on the pages where it ends or changes the program (RESTART, RESET, UPDATE, SLEEP, SELECT, CLEANUP, MODS, EXT FOLDERS, the colour picker).

## 2. Encoder sensitivity of MIDI-mapped encoders: a new 1 to 9
What the old numbers were (`lua/core/midimap_value.lua`, measured in `linux/tests/midimap_sens_test.lua`): a *speed* `2^((s-5)/2)`: the number by which one unit of the controller is multiplied. Relative encoders: that many steps per unit; absolute knobs: half of it per CC value. The code default was 5 (speed 1); the owner's own choice, 2, is speed 0.354.

| number | old speed | new speed | steps per CC value, absolute (old / new) | CC values per step (old / new) |
|---|---|---|---|---|
| 1 | 0.250 | **0.167** (2/3 of old 1) | 0.125 / 0.083 | 8.0 / 12.0 |
| 2 | 0.354 | 0.201 | 0.177 / 0.101 | 5.7 / 9.9 |
| 3 | 0.500 | 0.243 | 0.250 / 0.121 | 4.0 / 8.2 |
| 4 | 0.707 | 0.293 | 0.354 / 0.146 | 2.8 / 6.8 |
| 5 | 1.000 (old default) | **0.354 (= old 2)** | 0.500 / 0.177 | 2.0 / 5.7 |
| 6 | 1.414 | 0.648 | 0.707 / 0.324 | 1.4 / 3.1 |
| 7 | 2.000 | 1.189 | 1.000 / 0.595 | 1.0 / 1.7 |
| 8 | 2.828 | 2.181 | 1.414 / 1.090 | 0.71 / 0.92 |
| 9 | 4.000 | **4.000 (= old 9)** | 2.000 / 2.000 | 0.50 / 0.50 |
New 1 to 5: each number 1.207 times the one before (a geometric progression); new 5 to 9: 1.834 times. Relative encoders turn the same amount per unit as the speed column says.

- **Conversion of saved settings (once):** files get a line `sens_scale=2` (midimap.conf and each preset file, also the ones you save). A file without it is on the old scale: each encoder's number becomes the new number of the nearest speed (old 1 to 9 become 3, 5, 6, 6, 7, 7, 8, 8, 9); an encoder with no sens line in such a file had the old default (5), so it becomes 7, not the new default, so that nothing jumps. The file is written again with the line at once, so it is never converted twice (tested: read three more times, same numbers). Old 2 becomes new 5 exactly, old 9 stays 9. A mapping that was 1 now has about 2/3 of its old speed: that one is meant (the new 1 is slower).
- **A fresh install** (no file) starts at **5**, the speed of the old 2. Note: the old *code* default was 5 (speed 1), so a fresh install is now 2.8 times slower than a fresh install of 0.10.1; the owner said 2 is the value used. The built-in presets (GENERIC REL 2S, PUSH 2) use the default too. One constant: `V.SENS_DEFAULT` in `midimap_value.lua`.
- Tests: `linux/tests/midimap_sens_test.lua`; the older tests of the layer, the value functions and the settings keep all their checks; they run on the old speeds (an override at their top) because they are about the mechanisms (carry, jump, filters), not the scale, and their text files carry the marker.

## 3. The drawn encoder knob that goes on after the turning stops
- **Cause (read in the code, the numbers are a simulation and a measurement in a headless window):** every turn of E1-E3 is an event for the window (`w_handle_enc` → `sdl_bridge_show_control` → SDL event), and each event did `skin.enc_ticks += delta` and then `redraw(true)`: a FULL redraw of the window (all layers, the screen, the box) one event after the other. A MIDI encoder can send hundreds to a thousand turns a second; one redraw takes longer than the gap between two turns (10 to 30 ms on a normal window), so the events pile up in SDL's queue and the knob keeps turning for as long as the backlog needs: with 1000 turns a second and a 30 ms redraw, 29 seconds (`linux/tests/redraw_throttle_test.c`). The value and the sound do not go through the window, so they stop at once. Nothing is animated or eased: the angle is the sum of the turns (`enc_ticks`), shown as it is.
- **Fix:** (`matron/src/platform/common/redraw_throttle.h`, `sdl_bridge.cc`) the turns are added to the angle at once (an integer add, so the drawn knob can never be behind the value by more than what is not yet drawn); the window is drawn at most every 16 ms, counted from the END of the last draw; the turns that come while a draw is not due wait in the counter and one timer draws them: the last turn always gets its draw. Result in the simulation: 1000 fast turns, 23 draws, the last draw 43 ms after the last turn, no turn waits more than 29 ms.
- **Measured:** the window logs one line per burst ("enc display: N turns, M draws, slowest draw .. ms, a turn waited .. ms in the queue at the most, the last draw .. ms after the first turn"); CI sends 4000 turns in a tight loop, once with the new way and once with `VERDANDI_ENC_THROTTLE=0` (the old way). A headless window (SDL's dummy driver) draws faster than a real one, so the old way's lag there is shorter than the owner's; the numbers are in the CI log.
- Not changed: the keys, the arc and grid windows, the screen; only E1-E3's drawn knob.

## Not tested here
A real window and a real MIDI encoder; the real cost of a redraw on the owner's screen; the feel of the new sensitivity numbers.
