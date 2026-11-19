# Phase M26 (0.10.15): the built-in PUSH 2 preset, and the MIDI MAP learn timer

Base: 4dda51f (0.10.14). Only `lua/core/midimap_settings.lua`, `lua/core/midimap.lua`, tests, `windows/VERSION` and docs changed. Sound, latency, other presets, the launcher: untouched.

## 1. PUSH 2
- The built-in PUSH 2 is now the owner's verified mapping: E1 CC15 (relative 2's complement, sens 5), E2 CC71, E3 CC72, K1 CC9, K2 CC102, K3 CC103 (threshold 63), arc encoders A1-A4 CC75-78 (relative, gain 3, accel off), and the actions as step notes/CCs (mix 20, tape 21, home 22, params 23, arc 24, pin 25, detach 26, mute 27; input, grid, maiden, manual, fullscreen, screenshot none). It names no device and no channel. It is built in code from a text table (`builtin_from_text`) that goes through the same checks (`finish_ctl`, `finish_action`) as a preset file.
- Sensitivity: the built-in is written on the current scale (sens_scale=2), so sens 5 is stored as 5 and is not converted. Checked: the test reads the preset, saves it (file says `sens_scale=2`, sens 5), loads it four times, and reads a preset file with `sens_scale=2` and sens 5: always 5.
- An action that does not exist on the platform (`pin` on the Mac, `keys` on Linux/Windows) is skipped without a log line.
- The `(UNVERIFIED)` mechanism stays for other presets (the `unverified` argument of `preset()`, the page hint); the PUSH 2 no longer uses it. The page shows no UNVERIFIED note for it.
- Not changed: NONE, GENERIC REL 2S; the owner's `midimap.conf` and saved presets (checked byte for byte after load, reload and listing). A settings file with `preset=PUSH 2` loads and keeps its own saved mapping. A preset file saved earlier under the name PUSH 2 is ignored (the name is reserved by the built-in; one PUSH 2 in the list).

## 2. The learn timer
- Before: the learn used one metro (`metro.init(...)`) to tick every 0.25 s. norns has a fixed pool of metros; a script such as cheat codes 2 can use them all, `metro.init` then returns nil, and `timer:start()` raised "attempt to index a nil value (upvalue 'timer')" in the key handler. Result: the error line, the page not redrawn after LEARN, and no ticks at all: no time-out of PICK/LISTEN/ASK, no finishing of a suggestion by silence, no countdown.
- Now: the tick is a clock coroutine (`clock.run`, `clock.sleep(0.25)`), which can never run out. No metro is used or taken from a script. A script change clears every clock coroutine, so a start within 1 s of the last tick is skipped (the ticker lives) and later starts begin a new ticker. A tick that raises an error is caught and logged once per tick as `MIDI MAP: the learn tick raised an error`, never shown on screen. Without a `clock` (tests) nothing ticks and `M.tick()` can be driven by hand as before.
- Other `metro.init` uses in the shared Lua: `core/script.lua` (pcall, result checked: safe), menus use their fixed metros 31-36 (never from the pool). `lib/pattern_time.lua` and `lib/beatclock.lua` are script libraries that use the result unchecked: they take the script's own metros, so the same error can only appear when a script already used them all; not changed (not MIDI MAP).

## 3. Tests (each fails without its fix, see `phase-m26-without.txt`)
- `midimap_push2_test.lua` (Linux, Windows, Mac): the preset values, the sens checks, the file cases, no log lines, the unverified mechanism.
- `midimap_metro_test.lua`: the real `core/metro.lua` with all 36 metros used; a full learn (pick, listen, time-out, an action learn, confirm by silence, restart after the clocks were cleared).
- Changed: `midimap_settings_test.lua`, `midimap_page_test.lua` (no UNVERIFIED for PUSH 2; generic built-in mechanics use GENERIC REL 2S).
