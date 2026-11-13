# What the Linux port has that the Windows build does not (or has, but it does not work)

Investigation only: nothing in the product was changed for this note. Evidence is the code of build 0.8.3 (commit b83c3a7 and later docs), the Windows CI results of the earlier rounds, and the owner's test reports. "CI" means the Windows runner, which starts Verdandi headless (SDL dummy video): it cannot click a menu or drop a file, so the window features below were read from the code, not exercised. What a test would need is in section 5.

## 1. The right-click menu on Windows, item by item
The menu is the Linux one (`matron/src/platform/linux/desktop_shell_linux.cc`, compiled unchanged on Windows); what each item calls is what differs.

| Item | Calls | Windows | Verdict |
|---|---|---|---|
| Import files... (Ctrl+O) | `picker_open(PICK_FILES)` | stub in `stubs_win.cc`: returns -1, one log line "the file picker: not in this build yet"; the window then says "no file dialog (install zenity or an xdg-desktop-portal)" (a Linux sentence) | **does not work** |
| Import folder... | `picker_open(PICK_FOLDER)` | same stub | **does not work** |
| Copy samples into dust | only sets the mode of the import | nothing to apply it to | **tick without effect** |
| Open the file dialog when a script loads a file | `shell_choose_file` -> `picker_open` | same stub (the script's own on-screen browser keeps working; the tick is saved but the dialog never opens, the note is the Linux sentence) | **does not work** |
| Show the page buttons | Lua / box.conf | shared | working (code shared, owner used the box) |
| Show dust folder | `show_in_finder` -> `ShellExecuteA(open)` on `$HOME/dust` | implemented; ANSI API: a user folder with non-ASCII letters is unverified | working, untested |
| Show tape folder | same, `dust/audio/tape` | same | working, untested |
| Screenshot (Ctrl+Shift+S) | `save_screenshot` (Cairo PNG) | works, but the target is `<home>/Pictures` which does not exist on Windows, so it falls back to the **dust folder** (Linux: the Pictures folder) | partly: saved, in the wrong place |
| Record GIF | `gif_writer.c` (plain C) | same target as above | partly: as above |
| Virtual grid (F6) | `vgrid_open` | stub returns NULL: log "virtual grid failed" and nothing opens | **missing**, the button is there and dead |
| Virtual arc (F8) | `vgrid_open_arc` | stub NULL | **missing** |
| Virtual keyboard (F7) | `keys_backend_open` -> `keys_midi_open` | stub -1: "virtual keyboard failed", nothing opens | **missing** |
| Screen in its own window (F9) | `screen_window.cc` (shared) | shared code; the owner's reports mention keeping its size and place | working (owner used it), not tested by CI |
| Open maiden | `open_maiden` (Windows branch) | works since 0.7.0; the 404 after a stale maiden was fixed in 0.8.2 (CI: stale copy stopped) | working, tested in CI, owner-tested before the 404 |
| Open the manual | button 5 -> `NORNS_MANUAL` | the Windows zip has no manual and the launcher sets no `NORNS_MANUAL`: the note says "manual not found: linux/manual/manual.html" | **missing** |
| Mute output | `output_level` (Lua, crone) | shared | working, untested on hardware |
| MIDI actions enabled | Lua `midimap` | shared, MIDI MAP works on Windows (M4) | working |
| Input: microphone / all apps / off | `_menu.set_input` -> the Windows audio chain (M3) | works (MIC, SYS by WASAPI loopback, OFF); the tick of "all apps" never shows (`app_audio_current` is a stub that returns ""); no per-app input | working, cosmetic gap; SYS and MIC owner-tested at M3 |
| Quit (Ctrl+Q) | `EVENT_QUIT` | shared | working |

## 2. Drag and drop of files and folders
`SDL_DROPFILE` is delivered (shared code), the file goes to the import queue, and `dust_import_kind()` decides what it is. On Windows `matron/src/platform/windows/dust_import_win.c` is a **stub written in milestone M1** ("files dropped on the window are not imported in Windows M1"): `dust_import_kind` always returns "skip". Result for **every** dropped path, file or folder: one log line `dust import: dropping files on the window is not available in this Windows build yet`, and the window says **"nothing to import: not audio or a script"**. So the owner's "importing folders does not work" has two causes, and the same two for files: (1) **drag and drop**: the stub; (2) **Import folder... in the menu**: the missing file dialog. The plan (`windows-plan.md` 2.1) listed both as "shared / the Windows common item dialogs", and neither was ever built; `windows/KNOWN-LIMITS.md` still says so, and so does the release note.

## 3. Virtual grid and arc
Linux: a pseudo terminal that libmonome opens like a USB grid (`vgrid_device.c`, the mext protocol in `vgrid_proto.c`, the window in `vgrid_skin.c`). The virtual grid is one more `DEV_TYPE_MONOME` entry in the device list, so a real grid and the virtual one are two vports at the same time.
Windows: **nothing** (the stub above). The real grids work through libmonome's Windows serial layer (M5, tested with fake serial ports in CI; the owner's grid results have not reached this note). So a script cannot get a virtual grid or arc, and the question "real and virtual at the same time" cannot arise yet. When it is built the same rule holds (both are device-list entries): the pty idea has no Windows equivalent, but libmonome has a hook already in our patch (`windows/libmonome/serial-hook.patch`), so a virtual device can be an in-process pipe that libmonome opens by a name of ours, speaking the unchanged `vgrid_proto.c`. The window code (`vgrid_skin.c`, the pane in `sdl_bridge.cc`) is shared.

## 4. Feature table (Linux feature list, readme, manual, HARDWARE-CHECKLIST against Windows 0.8.3)
Legend: **OK** working and tested (CI and/or the owner); **OK-hw** working, tested in CI but not on real hardware; **OK-?** code shared with Linux, not exercised on Windows; **PART** partly; **MISSING**; **N/A** cannot exist on Windows.

| Feature | Windows state | Note |
|---|---|---|
| Window, device skin, mouse, keyboard as K/E, the box, THEME, SCREEN, colour picker, pixel looks | OK | owner uses it; settings survive a restart (fixed 0.5.1) |
| Screen in its own window F9, Shift+F11, size and place kept | OK | main window size kept (0.6.0); detached window not exercised by CI |
| Right-click menu | PART | see section 1: 6 of 20 items do not work or are missing |
| Drag and drop of files and folders into dust | MISSING | stub |
| Import menu, file picker for scripts | MISSING | stub |
| Show dust / tape folder | OK-? | needs a check with a non-ASCII user name |
| Screenshot, GIF | PART | saved into dust, not Pictures |
| Virtual grid, virtual arc, virtual keyboard F6-F8, "Verdandi keys" MIDI source | MISSING | stubs |
| Real monome grids (serial, hot-plug, 16 levels, GRID PORTS page, serialosc handling) | OK-hw | M5/M6, CI with fake ports; real grids reported by the owner not seen here |
| Real arcs | OK-hw | same code path as grids, no arc owned, untested |
| crow | MISSING | stub (`dev_crow_init`) |
| Other serial devices (`serial.*` scripts) | MISSING | stub |
| MIDI devices (WinMM), hot-plug, replug, MIDI ROUTES page, loopMIDI cables, OSC input 9201, MIDI MAP, MIDI actions | OK | owner-tested: Fireface MIDI clock, route measurements |
| Clock: internal, MIDI clock in/out, Link (tempo, start/stop) | OK | owner-tested with Ableton |
| Sound: WASAPI, ASIO zip, buffer and rate handling, TEST | OK | owner-tested on the RME |
| Input MIC / SYS / OFF, per-app input | OK / MISSING | SYS by WASAPI loopback works; APP (one program) does not exist |
| MIX page, softcut, tape (record/play), clock, engines | OK-? | shared crone/matron; tape is not exercised by CI or reported by the owner |
| maiden (editor, catalog, REPLs, install scripts), git/curl/busybox, mods, nb voice packs | OK | CI + owner |
| Script dependencies: sc3-plugins (whole), mi-UGens, NamAmp | OK / MISSING | NamAmp not built (source not identified) |
| Plug-in heal, duplicate-class guard, SUPERCOLLIDER FAIL explained, class check | OK | CI |
| SYSTEM > CLEAN UP | PART | the page exists, its tool (`linux/tidy.sh`) is a Linux shell script: the page has nothing to run |
| SYSTEM > WIFI, UPDATE, battery, temperature, disk | N/A | the OS owns them; pages hidden or inert |
| Bonjour / avahi announcement of the OSC service | MISSING | stub: one log line "the OSC service is not announced on Windows"; use 127.0.0.1 |
| Gamepads, USB keyboards as HID devices | MISSING | only the window keyboard is a HID device |
| The manual (MANUAL button) | MISSING | no file shipped |
| Second start brings the window to the front | OK | launcher mutex |
| Crash reports, logs, update-and-run | OK | |
| Installer, signed binaries | MISSING | zip only (decided) |
| VST3 plug-in (Linux Phase 7 / Windows Phase 8) | not started | owner's order: after the standalone |
| VIRMIDI page, ALSA ports, snd-virmidi, JACK-only features, `.deb`, udev rule | N/A | |

## 5. Ranking for a musician with real grids, MIDI hardware, an RME Fireface and the standalone app
1. **Getting samples and scripts into dust** (drag and drop, Import files/folder, the file dialog): used all the time; today the workaround is Explorer into the dust folder. Wrong messages on top of it ("install zenity", "nothing to import"). Steps: (a) fix the two sentences and the stale limits text (about half a day, no risk); (b) a real `dust_import_win.c` (copy of files and folders; audio copied, since links need rights on Windows) reusing the Linux logic and tests (1 to 2 days, testable in CI by dropping through a test hook); (c) the Windows open/folder dialog (`IFileOpenDialog`) for Import and the script dialog (1 day, needs the owner's hands once).
2. **The manual button and the manual** (half a day to point the button at a Windows page; a proper Windows manual 1 to 2 days).
3. **Screenshot and GIF folder** (the Pictures folder of Windows via a known-folder call): a few hours.
4. **Virtual grid and arc** (no grid at hand, or a script that needs an arc or a second grid): 3 to 4 days (libmonome open-hook patch, `vgrid_device_win.c` with a pipe pair, tests with the Linux protocol test unchanged, window code shared).
5. **crow** (only if used): 2 to 3 days (Win32 COM instead of termios, hot-plug by vendor id, a fake-port test as with grids).
6. **Virtual keyboard / "Verdandi keys"**: needs a MIDI output; on Windows that is a loopMIDI cable the owner already has: about 1 day.
7. **Smaller:** the "Input: all apps" tick; CLEAN UP page on Windows (hide it or write a small PowerShell version, half a day to 1 day); Bonjour via the Windows DNS-SD API (1 day, little value); HID gamepads (2 days, little value); a test hook so CI can click the menu and drop files (1 day, pays for itself).

Suggested order: 1a, 2 (button), 3, 1b, 1c, then 4, then the CI click hook alongside whatever comes first, 5 and 6 only if asked.
