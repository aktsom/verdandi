# Phase M24: the Windows behaviours compared with the Linux port (a read-only study)

Date: 2026-11-19. Nothing in the program, the version, the workflows or the releases was changed. Method: the phase notes M2 to M23, STATUS.md, HARDWARE-CHECKLIST.md and the git history were read; each claim below was then checked in the code. Three claims were also checked by running things in this container (jackd dummy, Xvfb, the real norns build): a dead JACK server, a busy port 5555, and the timing of the MIDI test. Where I am guessing, the text says "guess".

Left out on purpose (they exist only because Windows is different): the audio backend (WASAPI, ASIO, the COM thread, sample-rate follow), the MIDI backend (WinMM, loopMIDI cables, route measurement, the OSC input), serial-port grid detection, the launcher, zips, Defender, update-and-run and the release steps, packaging of maiden, git and busybox, building the plug-in packs and the "twins" crash hunt, and the UTF-8 manifest and long-path code.

## 1. The table

"Shared" means one piece of Lua or C that Linux also runs. Effort: small = about a day, medium = a few days, large = more.

| Item | Linux has it | Where the code lives | Effort for Linux |
|---|---|---|---|
| Encoder sensitivity 1 to 9, old files converted once | YES | shared Lua (`midimap_value.lua`) | none |
| Lag fix for the drawn knobs and the arc rings (redraw at most every 16 ms) | YES | shared C (`sdl_bridge.cc`, `redraw_throttle.h`) | none |
| MIDI learn remembers the port | YES (two-port interfaces like the Push 2 on Linux: not checked, guess it works) | shared Lua | none |
| MIDI MAP: arc encoders A1 to A4, MODE, GAIN, ACCEL, ONE TURN, CLEAR, ARC KEYS | YES | shared Lua | none |
| ARC DRAG option (up/down or circle) | PARTLY: the option exists, but the default is "circle" on Linux and "up/down" on Windows | shared Lua, one default line | tiny |
| Virtual arc: wheel, drag, Shift slower, push, mouse capture, keys | YES (it came from Linux) | shared C | none |
| Ctrl = four times faster on the arc | NO (Linux uses the Super key, which opens the menu on Mint when let go; guess) | `#ifdef` in the shared C | tiny |
| PIN (window always on top), also as a MIDI action | NO | Windows-only (the KEYS button's place, `pin_native_win.c`) | small to medium |
| Readable lists with a fixed info area, no scrolling text | PARTLY: the info area is on the script list and the file browser (shared); the new SYSTEM pages and the brighter text are Windows-only | shared helper `winui.lua`, Windows-only pages | small |
| AUDIO page (driver, device, channel pairs, buffer, refusal messages) | NOT NEEDED: Linux has its own page for jackd, PipeWire and JACK | two separate pages (`audio.lua`, `audio_win.lua`) | none |
| AUDIO status line with u and x | PARTLY: xruns are counted and shown as a warning on HOME, not on the AUDIO page | Windows-only page | small to medium |
| Names of the card's channels | NOT NEEDED (JACK shows port names) | Windows-only | none |
| HOME page statistics | YES (Linux always had them) | shared | none |
| `util.file_exists` true for folders | NOT NEEDED (a Linux fopen opens folders) | shared Lua | none |
| Duplicate-class guard | PARTLY: Linux reports a duplicate after SuperCollider says so, it does not prevent it | Windows launcher plus shared `sc_class_check.lua` | medium |
| Grids and arcs dark at quit | YES (freeze, then off, also on SIGTERM, SIGHUP, SIGINT) | shared C | none |
| The launcher's end event | NOT NEEDED (Linux uses signals) | Windows-only | none |
| One copy only, second start raises the window | YES, and the second start touches no log | Linux `norns.sh` | none |
| Log rotation | YES | `linux/tidy.sh` | none |
| Tape finished on every way of ending | PARTLY: Quit, window close and SLEEP yes; RESTART, the shutdown action and any signal no (a real gap, see 3c) | shared C (`matron_cleanup`) | small |
| sclang or scsynth dying is noticed and restarted | NO (a gap, see 3c) | Windows launcher plus shared `engine_fail.lua` | medium |
| A card that drops out is tried again, the chosen device remembered | NO (see 3c) | Windows-only `audio_device.c` | medium to large, needs the laptop |
| Busy ports 5555 / 5556 do not stop Verdandi | NO, and worse: norns does not start at all (see 3c) | Windows-only wrapper and launcher | small to medium |
| UTF-8 folders | NOT NEEDED | Windows-only | none |
| Screenshots and GIFs in Pictures/Verdandi | PARTLY: Linux saves directly into the Pictures folder, no subfolder | `#ifdef` in the shared C | tiny |
| Extra sample folders (SYSTEM > EXT FOLDERS) | NO: the Lua page and `extfolders.c` are shared, but the C function is registered only on Windows | mostly shared | small to medium |
| Main window size and place remembered | NO (Linux opens centred every time; the detached screen window does remember) | Windows-only `win_state` | small |
| A dead server stops a script load at once, with a plain line | YES, but only while a script is loading | shared Lua | none |
| Long file names in the file browser (real name used) | YES | shared Lua | none |
| The owner's wishlist items that were built | They are shared code (colour presets, MIDI control of the window, detach). I did not check each wishlist line one by one. | shared | none |

## 2. What Linux gets for free

Shared Lua: the sensitivity scale, MIDI MAP with the learned port and the arc encoders, the info area of the script list and file browser, the HOME page, the file browser's real names, the dead-server message while a script loads. Shared C: the redraw limit for the knobs and the arc rings, the virtual arc, grids and arcs going dark at quit (also on signals), the tape closing on a normal quit. The Windows work shared one file with the Linux window code (`sdl_bridge.cc`), so those parts cannot drift.

## 3. The specific checks

### 3a. Shared pages and copies
- Pages that are Windows-only files: `audio_win.lua` (the AUDIO page; `audio.lua` loads it when `_norns.audio_devices` exists), `midiwin.lua` (MIDI ROUTES) and `gridwin.lua` (GRID PORTS). Linux has no copy of these; it has its own AUDIO page and VIRMIDI page instead.
- Pages that are shared with small Windows branches: `devices.lua`, `menu.lua` (a block that only runs when `_norns.audio_devices` exists: it makes the SYSTEM pages brighter and starts the audio log), `system.lua`, `midimap_settings.lua` (the arc-drag default) and `util.lua`.
- `winui.lua` is the one helper used by both worlds (Windows pages and the shared script list and file browser).
- Can they drift? The two AUDIO pages cannot drift, they are different pages for different servers. The risk is the shared helper: a change for the Windows pages also changes the Linux script list. What keeps them equal today: the Lua page tests run in the Linux test job (for example the AUDIO page and list-code tests), and the C window code is one file with `#ifdef` blocks. One of those tests (the list-code font test) is known to fail on both old and new code, so it guards less than it seems.

### 3b. The intermittent test "virtual MIDI device sends through JACK MIDI"
- Not the program. The program code is identical on both runs. In the failing CI run the first failing line was empty and only the last check failed ("a client that is not connected must get nothing"); all other checks of that test, including the notes, order, 24 clock ticks and the event count, passed.
- That last check reads the output file of the second background listener. The two listeners are started in the background and listen for a fixed 12 seconds. The test never waits for them: it reads their files as soon as the probe's shutdown (about 2.5 s after the last command) has ended. The first listener's lines were found, the second (started a moment later) was not complete.
- I measured the margin locally: the listeners finish about 1.0 to 1.2 s before the probe returns, also with 8 busy loops on 4 cores (3 runs, no failure). So a failure needs a runner more than a second slower than this container.
- Conclusion: most likely a race in the test (a margin of about one second between a fixed listening time and the end of the probe), not in the program. Confidence: fairly high, not proven; I could not make it fail here and the CI run did not keep the second listener's file. Nothing was fixed.

### 3c. What the Linux audio path does today (run here with jackd dummy, the real norns build)
- JACK server dies (own-jackd mode, simulated with `pkill jackd`): norns and sclang keep running; scsynth exits (code 0); crone's shutdown handler is empty (the code comment says "FIXME: nothing to do?"); the log shows only JACK's socket errors; the user sees nothing and nothing restarts. Sound stays gone until the owner restarts by hand. This is the same problem the Windows audit found.
- sclang or scsynth dies: `norns.sh` waits only for norns itself and never looks at sclang. Only a script that is loading notices, through the log line "Server exited" (shared `engine_fail.lua`). The note file that Windows uses to tell the user (`.verdandi-note`) is already read by the shared Lua, but nothing on Linux writes it.
- Card or PipeWire drops out: crone connects to the card's ports once, at start (`Client.h`). From the code, I expect that after the card comes back nothing connects crone again (guess; PipeWire's session manager may do something on its own; this cannot be tested here, there is no PipeWire and no card in this container).
- Restart during a tape recording: on Linux, RESTART and the shutdown action are `pkill -TERM norns`. The signal thread switches the LEDs off and ends the process with the default action, so `matron_cleanup` (which finishes the tape) never runs. The existing test `tape_finalize_test` shows that a recording ended that way has no valid WAV header. Only SLEEP, Quit and the window close are safe. This is exactly the Windows audit finding, and it is real on Linux.
- Busy port 5555: I held 127.0.0.1:5571 and started the Linux `ws-wrapper` with a child program: it tried 20 times, then crashed with a segmentation fault, and the child never ran. On Linux `norns.sh` starts norns (5555) and sclang (5556) through this wrapper, so a program holding 5555 or 5556 stops norns or sclang from starting at all. Windows fixed this in M22; Linux did not get it.

## 4. Ranked proposal (the owner chooses)

1. Finish the tape on SIGTERM, SIGHUP and SIGINT (RESTART, shutdown, launcher stop, Ctrl+C): the same bounded call the quit path already makes, put into the signal thread before it re-raises the signal. Small, real data loss today, testable here.
2. Busy ports 5555 / 5556: make the Linux wrapper tolerate a busy port (norns still starts, with one plain line saying the console is off), as Windows does. Small to medium, I reproduced the crash here.
3. Arc defaults like Windows: ARC DRAG up/down as the default and Ctrl as the four-times key. Tiny, shared Lua and one `#ifdef`; saved files keep their values.
4. Notice a dead sclang or scsynth and restart (two tries, then a plain line), writing the note the shared Lua already shows. Medium, testable here with stand-ins.
5. Remember the main window's size and place. Small; the code exists for Windows.
6. PIN, always on top. Small to medium; needs a decision where the button goes (the KEYS button's slot holds the virtual keyboard on Linux); SDL does it on X11 (Mint) and not on Wayland.
7. The AUDIO page status line with xrun counts, plus the words for a lost server or card. Small to medium.
8. A card that comes back is connected again (crone reconnects when its target ports return). Medium to large; needs the owner's laptop and a USB card to test.

## 5. Not checked

PipeWire behaviour, a real card, Wayland, the Push 2 on Linux, the real feel of anything. No Windows code was run (no Windows or Wine run for this study).
