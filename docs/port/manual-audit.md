# Manual audit (linux/manual/manual.html)

Done before the rewrite. Facts were read from the code (file named for each item); "not verified" marks what could not be checked here (no real sound card, grid, arc, Wayland session, laptop) or is not built. The manual itself carries no such marks; the hardware items stay in `HARDWARE-CHECKLIST.md`.

## 1. What the product has now

**Window.** The norns drawing with the screen, K1-K3, E1-E3 and the row of buttons MIX, TAPE, HOME, PARAMS, MIC, GRID, ARC, KEYS, MAIDEN, MANUAL, MUTE (`sdl_bridge.cc`, `skin`). Resizable (`SDL_WINDOW_RESIZABLE`), closing it quits. Mouse: click keys, drag or scroll knobs, wheel elsewhere = nearest knob; no output fader on the window (the output level is the OUT column of MIX and PARAMS > EDIT > LEVELS). Hide the row: right-click item "Show the page buttons". Drop files on it to import.

**Screen window** (`screen_window.cc`): F9 detach / bring back, F11 fullscreen (screen window only), Shift+F11 title bar on/off, double click = fullscreen, a panel in the box says how to bring it back, state in `screen-window.conf`. F12 is **not built** (`scan-fkeys.sh` calls it "kept for a later snap to a whole scale, hidden").

**Virtual devices:** F6 grid, F7 keyboard, F8 arc (`keyboard.lua`, also from the keys window). Arc keys 5 6 / T Y / G H / B N (`arc_keys.c`, `keyboard.lua`).

**Shortcuts handled in C** (`desktop_shell_linux.cc` `shell_menu_key`, `menu_build` hints, `screen_window.cc`): F10 (menu), Ctrl+Q (quit), Ctrl+O (import), Ctrl+M (mute), Ctrl+Shift+M (MIDI actions), Ctrl+Shift+S (screenshot), F9, F11, Shift+F11. In Lua (`keyboard.lua`): F1-F4 pages, F5 menu, F6-F8, `1 2 3`, Enter/Space (K3), Esc/Backspace (K2), Q W / A S / Z X, Shift = 5 steps, arrows in scripts (E2 up/down, E3 left/right), Alt + the keys and Alt+Esc (`window_keys.c`: Option toggles the hardware-key mode), Ctrl+C / Ctrl+V on colour rows and in the picker (`menu/ui.lua`, `menu/box.lua`, `menu/picker.lua`).

**Right-click menu** (`menu_build`): Import files (Ctrl+O), Import folder, Copy samples into dust, Open the file dialog when a script loads a file, Show the page buttons, Show dust folder, Show tape folder, Screenshot (Ctrl+Shift+S), Record GIF / Stop GIF recording, Virtual grid (F6), Virtual arc (F8), Virtual keyboard (F7), Screen in its own window (F9), Open maiden, Open the manual, Mute output (Ctrl+M), MIDI actions enabled (Ctrl+Shift+M), Input: microphone / all apps / (sink monitor, only with `sys_monitor`) / each application / off, Quit (Ctrl+Q).

**HOME:** SELECT, SYSTEM, SLEEP (SLEEP quits norns, `sleep.lua`). Plus the upstream pages MIX, TAPE, PARAMS.

**SYSTEM on a computer, in order** (`system.lua`): DEVICES, AUDIO, MODS, SCREEN, THEME, MIDI MAP, CLEAN UP, RESET, RESTART. Rows:
- DEVICES: midi, grid, arc, hid, keyboard layout; a SERIALOSC entry while the serialosc note is on; MIDI shows how many ports are auto-linked.
- AUDIO: INPUT, OUTPUT, RATE, BUFFER, APPLY (read-only under PipeWire except BUFFER; no APPLY with a foreign JACK).
- MODS: list, E3 right/left enables/disables, restart to load.
- SCREEN: PRESET, COLOUR, BRIGHTNESS, CONTRAST, SAVE, DELETE (own presets only).
- THEME: STYLE, PIXEL LOOK (only with PIXEL), PRESET, BOX, KEYS, ENCODERS, BUTTONS, FONT, SAVE, DELETE.
- MIDI MAP: PRESET, LEARN, E1 E2 E3 K1 K2 K3, A1-A4 (+ GAIN, ACCEL, ONE TURN), WATCH, ARC KEYS, ACTIONS, MIDI ACTIONS (master switch), ON CLASH, SAVE AS / DELETE.
- CLEAN UP: groups (disabled, logs, crashes, seeded packs, cache), ARM PLUG-INS line when needed, REMOVE > N DAYS.
- RESET: one question, then deletes `system.pset`, `system.state`, favourites, the enabled-mods list and the display settings file, and restarts (`reset.lua`); it does not touch `ui.conf`, `box.conf`, `midimap.conf` or `audio.conf`.
- RESTART: one question, restarts norns.

**Looks:** SCREEN presets (WHITE, YELLOW, PINK, own, colour only), THEME styles ALUMINIUM / PIXEL with PIXEL LOOK PIXEL / RETRO / 8-BIT / 16-BIT, THEME presets DARK, LIGHT, COLOUR, MAC and own, the HSB colour picker (HUE, SATURATION, BRIGHTNESS, HEX; keys; Ctrl+C/V; H, C, R).

**Sound:** the launcher chooses own jackd / running JACK / PipeWire through `pw-jack`; MIC button cycle MIC > SYS > OFF, single apps from the menu; `audio.conf` keys `in_ports out_ports input output rate period sys_monitor midi_in_from plugin_check serialosc_check`.

**MIDI, DAW:** the virtual MIDI device "virtual" with the JACK ports `Verdandi:midi_in` and `Verdandi:midi_out`, `clock_source` midi, optional auto-link (`midi_in_from`, `midi_out_to`), KEYS window = MIDI device "norns keys" (+ ALSA port where available). No VST3 / plug-in exists yet (planned; `docs/port/linux-vst3.md`); nothing to say about Reaper except the JACK MIDI route.

**Grids:** real grid/arc/crow over USB (udev rule `70-verdandi-monome.rules`), serialosc conflict note and guide, a grid listed once.

**maiden:** button, port 5000 (`NORNS_MAIDEN_PORT`), consoles 5555/5556, `--terminal` excludes the norns console. **Mods** in `dust/code/<name>/lib/mod.lua`. **Scripts:** `dust/code`, import, maiden, SELECT. Scripts that fetch Raspberry Pi plug-ins: plug-in check, "PLUGINS" and "SUPERCOLLIDER FAIL" notes, CLEAN UP > ARM PLUG-INS, `verdandi tidy disable`.

**Files and tools:** the home (`~/Verdandi`, `~/.config/verdandi/home`), `logs/` (5 runs kept), `logs/crash/` (last 5), `disabled/`, `backups/`, `cache/`, `box-presets/`, `midimap-presets/`, `screen-presets/`, `screen-window.conf`; commands `verdandi`, `verdandi --terminal`, `verdandi tidy ...`, `verdandi scan-fkeys`. Package: `.deb`, `/opt/verdandi`, `/usr/bin/verdandi`, menu entry "Verdandi Linux", icon, udev rule.

## 2. The current manual compared with that

Size: 14 sections, 11 200 words (about 25 printed pages). Too long, developer-facing.

**Missing**
- Installing from the `.deb` (the normal way): the manual starts with `git clone` and `setup-deps.sh`, and never says `apt install`, the menu entry, or `~/Verdandi`.
- A quick start; a keyboard cheat sheet; a "which file stores what" table that covers every settings file (`screen-presets/`, `box-presets/`, `midimap-presets/` are only in prose; `screen-window.conf`, `box.conf` are missing from the settings table).
- F10 (open the menu from the keyboard), Ctrl+C / Ctrl+V on colour rows are not in the keyboard table.
- SYSTEM > DEVICES (keyboard layout, SERIALOSC), SYSTEM > RESET and the HOME page (SELECT, SLEEP) are described in one sentence or not at all.
- What to do with a crash report (the folder is named only in a table).
- How to update (a newer `.deb`; the old text says "get a new version of the repository").

**Outdated or wrong**
- "No plug-in version (VST3 is planned for the Windows version)": the plan is Linux first; nothing is built (not verified: no plug-in exists to check).
- "The owner also ran it on Linux Mint ... reported results that led to the fixes": a personal and history note.
- All `~/verdandi-home/...` paths describe the old checkout layout; the installed layout is `~/Verdandi`.
- "was called UI / BOX in earlier versions" (twice), "the first versions", "an older ui.conf ..." history in the SCREEN section, "fixed in this build" rows in the troubleshooting table, "now also lists" wording: history, to be removed.
- SYSTEM list says "WIFI, UPDATE, the password and the display settings are not offered" in section 12 only; fine, kept in one line.

**Old names** (to be absent from the new text and from the test): SYSTEM > UI, SYSTEM > BOX, GREYS, OUT fader / output slider, SCREEN button, SCREEN's HEX row, a CUSTOM colour list. Searched: the current text has none of the removed names except the history phrases above ("it was called UI", "it was called BOX", "CONTRAST was called GREYS" is in the checklists only) and the line "There is no output slider on the window" (kept as a plain fact, worded without the old name).

**Duplicated**
- Keys: the keyboard table, the "buttons" paragraph, the screen-window section, the right-click table and the MIDI actions text each repeat F-keys and Ctrl keys.
- serialosc: four places (window note text, MIDI/grid section, troubleshooting, limitations).
- The colour picker and text entry keys are described in the window section and again in MIDI MAP.
- Troubleshooting and "Known limitations" overlap (ARM plug-ins, `--terminal` console, serialosc).

**Developer detail removed in the rewrite:** environment variable table (kept short, only those a user may need), the SC path overrides, shims, SynthDef compat, clock jump internals, the pixel-size arithmetic of the screen window, test names, repository build steps (moved to one line pointing at `docs/port/RUN-ON-LAPTOP.md`).

## 3. Not verified here (kept out of the manual or stated as the code says)
- Upgrade and removal of the `.deb` (`packaging.md`: no postinst/prerm exercised); the manual only says the files you made are in your own folder, which the package test checks.
- Real sound cards in many setups, real grids/arcs/crow, the udev rule IDs of older grids, Wayland vs X11 behaviour (window raise, saved window place, clipboard), the PUSH 2 preset numbers (the page itself says UNVERIFIED), Reaper.
- The look on the laptop's real screen (`HARDWARE-CHECKLIST.md`).
- F12: not built, so not in the manual.

## 4. What the rewrite does
One quick start, then sections in the order of the app (window, HOME, SYSTEM pages in menu order, sound/MIDI/grids), a shortcut cheat sheet, a settings-and-files table, "If something goes wrong", licences. The checks are in `linux/tests/manual_test.sh`: the section list, the removed names, one section per SYSTEM page (read from `lua/core/menu/system.lua`) and one entry per shortcut handled in C (read from `desktop_shell_linux.cc`, `screen_window.cc`, `keyboard.lua`).
