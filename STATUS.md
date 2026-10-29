# STATUS

Branch: `linux-port`. Resume rule: read `STATUS.md`, `PLAN.md`, `DECISIONS.md` first.

## Done
- Phase 0 inventory: `docs/port/INVENTORY.md`.
- Gate A decided by the owner: option 1, platform folders in this fork (`DECISIONS.md`).
- Phase 1, headless Linux build and boot (`docs/port/phase-1.md`): `linux/setup-deps.sh`, `linux/build.sh`,
  `linux/norns.sh`, `linux/tests/`. Builds on Ubuntu 24.04 x86_64, boots with Xvfb + jackd dummy + crone + sclang.
- **Phase 2, all five steps of `docs/port/phase-2.md` section 6 are done and pushed:**
  1. libmonome pty patch (`linux/patches/`): the virtual grid and arc open on Linux. `c:vgrid` passes.
  2. `dust_import` portable copy (macOS `copyfile` path unchanged); `c:dust_import` passes, also as an ordinary user.
  3. The Verdandi window on Linux (`sdl_bridge.cc` behind `platform/common/desktop_shell.h`): device skin, oled,
     mouse, keyboard as a hid keyboard, virtual grid and arc (LEDs, deltas, keys). Tested under Xvfb.
  4. In-window menu (right button, F10), file dialogs (XDG portal via GDBus, zenity, kdialog), screenshot, GIF,
     import, folders via xdg-open, Quit. Tested with a stub zenity and a **mock** portal; the real portal is not tested.
  5. "Verdandi keys" MIDI: (A) internal norns MIDI device, tested (click, typed notes, close and reopen);
     (B) ALSA sequencer port, written and runtime-optional, **not tested** (no `/dev/snd/seq` here).
- Clock investigation (read-only): `docs/port/clock-notes.md`. Decisions planned in `PLAN.md` (Phase 3: SPP and
  MIDI continue, JACK MIDI input, later ALSA seq input; Phase 7: plugin transport) and `WISHLIST.md`.
- **Gate B first step (decided by the owner, `DECISIONS.md`; `docs/port/packaging.md` section 7):** `.deb` first.
  Done and pushed: engine check on the bundled SuperCollider 3.14.1 (all six engines run; differences from 3.13.0 in
  `docs/port/supercollider-3.14.md`); installed mode in `linux/norns.sh` (home: `NORNS_HOME`, `~/.config/verdandi/home`, `~/Verdandi`;
  shared with a checkout through the `norns` link); `linux/package.sh` (`sc`, `libmonome`, `maiden`, `tree`, `deb`, `all`, `clean-root`, `check`;
  neutral identity, privacy scan); clean-root test `linux/tests/package_test.sh` (in `run_all.sh`; passes: install in a clean Ubuntu 24.04,
  no missing library, boot as a normal user, maiden, engines); udev rule + test. `run_all.sh`: 0 unexpected failures
  (the maiden server tests are SKIPped here because maiden is not built in the default home; the package's maiden was built and answers).
  Found: libmonome's compiled-in protocol path (fixed in the package). Open: font licences (DEPS.md, before any public release);
  `package.sh clean-root` itself (the full build in a fresh root) was **not run**; second-start "bring window forward" not built.
  Not testable here (HARDWARE-CHECKLIST.md, "The package"): the laptop, desktop menu, real grid/arc, udev hotplug, USB IDs of older devices.
- **`package.sh clean-root` fixed and run end to end** (owner's laptop report: `SUDO_USER` of the host leaked into the root; `docs/port/packaging.md` 7.2):
  the root now has its own root user (`env -i`), no host account in the environment or the file ownership, stage markers and a log
  (`build/package/package-<command>.log`), the failing stage is named, a good build removes the root. Two more failures only the end-to-end run
  showed (npm did not trust the proxy certificate; maiden failing silently in setup-deps) are fixed. End to end here, as root with a
  `SUDO_USER` that does not exist in the root: 8 minutes (plus about 3 once for the cached base root), `.deb` 13.5 MB, root 2.8 GB while it
  exists and removed afterwards (`PACKAGE_KEEP_ROOT=1` keeps it). Installed and booted by `linux/tests/package_test.sh`: pass.
  `run_all.sh`: 0 unexpected failures; `NORNS_CLEAN_ROOT_TEST=1` adds the end-to-end build. Not tested: the laptop itself (a run there without a proxy).
- **Browser buttons, display name, panel icon** (`docs/port/packaging.md` section 8):
  (1) MAIDEN/MANUAL opened Firefox because `linux/norns.sh` sets `HOME` to the norns home and `xdg-open` read the default browser from
  there; matron now gives `xdg-open` (only) the user's own HOME/XDG folders back (`NORNS_USER_*`); test `open_browser_test.sh` fails on the old
  behaviour. Not run: the laptop's real `xdg-open`/Vivaldi. (2) The display name is "Verdandi Linux", defined once in `linux/brand.sh`
  (window title, menu entry + comment, .deb description, manual title/heading, new `readme-linux.md`); internal names unchanged; Mac window title
  unchanged; attribution and licence files intact; test `display_name_test.sh`. (3) Menu entry has `StartupWMClass=norns` (= the window class, now set
  explicitly by the launcher), window icon from the installed icon; tested under Xvfb with `xprop`.
- **`refresh()` bug** (eterna did not update the screen; `KNOWN-ISSUES.md` item 13): upstream posts `EVENT_SCREEN_REFRESH` every 1/60 s from the SPI display thread;
  the desktop screen backend never did, so a script's global `refresh()` was never called (counter 0 in the headless test). Now the Linux `screen:sdl` posts it at 60 Hz
  (a small thread, joined when the screen is destroyed; the call is on the Lua thread via the event queue); test `refresh_test.sh`: 180 calls in 3 s (was 0), none after the
  script is replaced or cleared, scripts without `refresh()` unaffected. 14 of the 351 catalog scripts define it. The Mac has the same gap and was not changed.
- **Grid LEDs stuck / prompt commands ignored on a real grid** (`KNOWN-ISSUES.md` item 14): the whole path from Lua to the serial port was checked headless with a recording shim
  (script LEDs, clear on script change for both halves, prompt `g:led`/`g:all`: all correct, identical to upstream). Found in libmonome: a non-blocking write that the port takes only in part
  was dropped, cutting a protocol message in the middle (reproduced with a stalled pty: 22 bytes left half read). `linux/patches/libmonome-write-retry.patch` finishes such writes and adds
  `NORNS_MONOME_TRACE=1`. **Not confirmed on the laptop's grid**; how to send a trace is in the item and in HARDWARE-CHECKLIST.md.
- **UI plan, step 1 (preview and plan only, no product code changed):** `docs/port/ui-plan.md` and `docs/port/ui-previews/` (17 PNGs made by the real norns and the real skin code with `make_previews.sh`):
  screen +20/22/25 percent in the box, grey options (gamma 0.7 recommended, level 4: 68 -> 101) and brightness 100/70/40, plan for the SCREEN page, the colour mapping, screenshots/GIFs, tests and risks.
  Finding: the screen is drawn at a whole number of device pixels (3 today); the next is 4 = +33 percent, so +20..25 percent needs a fractional pixel size. Added later: a +33 percent preview (exactly 4 device pixels per screen pixel; fits with the box and window unchanged, or 26 units wider with the cluster's spacing kept) and the pixel counts of +25 (`ui-plan.md` 1.4, 1.5). Round 2 added: the owner's layout (no OUT slider, MUTE in the top row, keys and encoders +15 percent, screen at 4 px, box and window unchanged) as pictures with and without labels and an alternative arrangement, with numbers, hit-test check and risks (`ui-plan.md` 1.6). Waiting for the owner's choice.
- **UI step 2 built** (`docs/port/ui-plan.md` 1.7): the Linux window is arrangement A without labels: the screen at exactly 4 device pixels per screen pixel, the box and window unchanged (960 x 630 units, 992 x 662 px),
  no OUT slider, MUTE the 11th button of the top row (id 17, with its LED), keys and encoders 15 percent bigger, no K/E text. A second layout table in `device_skin.c` selected by `NORNS_LINUX_DESKTOP`;
  the enum: `SKIN_MUTE = 17` on Linux, the Mac's `SKIN_FADER = 17` / `SKIN_MUTE = 18` untouched, and `macos/tests/device_skin_test.c` passes unchanged. The slider code in `sdl_bridge.cc` is compiled out on Linux.
  Tests first (55 failures before): `linux/tests/device_skin_linux_test.c` (geometry, hits, rendered window, keyboard-mapping checksum). Updated: the window click coordinates, the maiden and manual button probes, the manual,
  RUN-ON-LAPTOP, HARDWARE-CHECKLIST ("The new window layout"). Not built (later steps): the greys, the brightness, the SCREEN page, the detachable window. Needs the owner's eyes on the laptop.
  Step 2b (preview and plan only): `ui-plan.md` 1.8 (margin around the screen: the Mac's is 4.3 % / 7.3 % of the screen, Linux today 2.7 % / 5.5 %; options abs / shrink / grow, recommendation grow) and 1.9 (resizing: only the screen is whole-pixel, which explains the text looking different when smaller; option A designed, tests and risks); pictures in `docs/port/ui-previews/`. Nothing built.
  A run of `run_all.sh` while another test was still running on the same Xvfb display produced two false failures (grid LED, maiden launcher); both pass alone and in a clean full run.
- **UI step 2b built** (`docs/port/ui-plan.md` 1.10, 1.11; decided by the owner: "grow" margin and resize option A): bezel 556 x 293.3 units, the screen 512 x 256 (4 px) with the Mac's margins (4.3 % / 7.3 %), keys and encoders re-placed; the screen scales with the window (crisp at whole multiples of the screen scale, nearest-enlarge + best-filter in between, always 2:1, mouse mapping from the rectangle); smallest window on Linux is half the design size. All behind `NORNS_LINUX_DESKTOP`, Mac table and `macos/tests/device_skin_test.c` unchanged. Tests first (compile error, then 0 failures): `device_skin_linux_test.c`; `package_version_test.sh`.
  **My readings, not given to me:** (1) "the dpkg version fix" = the .deb version did not grow between commits of one day (the hash is not ordered); it is now `0.1~git<date>.<commit count>.<hash>` and checked with `dpkg --compare-versions`. If you meant another problem with the version, tell me. (2) the 50 % minimum window size (1.9.3).
  `run_all.sh` after the last change: 67 PASS, 0 unexpected failures (clean-root build opt-in, not run).
  Not verified: the laptop (look and taste), HiDPI / fractional scaling, the Mac build.
- **Clean-up, step 1 done: launcher fix** (`KNOWN-ISSUES.md` 18): `NORNS_HOME` is exported before the pw-jack re-run, so the home is no longer nested (`launcher_test.sh`, no `NORNS_HOME` given: 2 failures on the old launcher, 0 now). The owner confirmed the clean-up plan (layout, CLEAN UP page, limits 5 runs / 10 MB / launcher.log 1 MB / 5 crash reports / 64 MB cache, 2 `.deb`, hard-link backup, dry run first). Order: launcher fix, dry run of the migration, tidy tool + CLEAN UP page + log limits, build output. mi-UGens support is postponed (not built).
- **Clean-up, step 2 done: the dry run of the migration** (`verdandi tidy flatten`, `linux/tidy.sh`, test `tidy_flatten_test.sh`): reads only (the test compares paths, sizes, modes, times and content hashes before and after), prints the nested and outer contents, names on both sides, links into the nested folder, small files holding the old path (the SuperCollider settings), the plan and `RESULT ready|not-ready|nothing-to-do`; `--apply` refuses ("not built yet"). **To run on the laptop** (norns can be running, it only reads): `verdandi tidy flatten` (or `linux/norns.sh tidy flatten`; `--home PATH` for another home) and send the output. The real move is built only after the owner has seen that output and said go.
- **Clean-up, step 3 done: the tidy tool, the CLEAN UP page and the log limits** (`linux/tidy.sh`, `lua/core/menu/cleanup.lua`; tests `tidy_test.sh`, `tidy_flatten_test.sh`, `cleanup_page_test.lua`, `launcher_logs_test.sh`, `crash_report_test.sh`, `plugin_check_test.sh`): logs now live in `<home>/logs/` (5 runs per log, `launcher.log` 1 MB, 10 MB per running log via a 60 s `tidy cap`), crash reports are one file per crash in `logs/crash/` (last 5, no file unless something crashes), the graphics cache is in `<home>/cache/` (64 MB), plug-ins for another machine are moved into `disabled/` with a manifest and can be restored, SYSTEM > CLEAN UP lists DISABLED / LOGS / CRASHES / SEEDED / CACHE and the only deleting row is REMOVE >N DAYS (one confirmation). `dust/`, `audio.conf` and `ui.conf` are never touched. The migration's `--apply`/`--undo` are still not built.
- **Clean-up, step 4 done: build output** (`linux/package.sh`, test `package_out_test.sh`): the newest 2 `.deb` stay, `stage/` is removed after a good build, `package.sh status` (reads only) and `package.sh clean [cache]` (never a `.deb`); `launcher_logs_test.sh` now also checks that a start writes nothing into the account's own home folder. Not measured: the time of a build after `clean cache` (needs the network; not run here).
- **Step 4, a detachable screen window: PLAN WRITTEN, no product code changed** (`docs/port/detach-plan.md`; pictures in `docs/port/detach-previews/`, three small measurements in `docs/port/detach-measurements/`). Findings: keyboard events do not depend on the window that has the focus (only the in-window menu shortcuts Ctrl+O/Ctrl+Shift+S/Ctrl+Q/F10 are tied to the main window), mouse handlers use the main window's geometry and must not see the new window's events, devices and MIDI never pass through windows, screenshots and GIFs read the screen surface not a window; the main window's in-between scaling filter is too slow for a big free window (70-320 ms per frame at 1366-2900 px; BILINEAR 2.7-12 ms, mean difference about 1/255). Ten questions for the owner at the end of the plan; nothing is built before he answers.
- **File dialog off by default (right-click menu item "Open the file dialog when a script loads a file")**: how it worked and how it works now are in `docs/port/ui-settings-plan.md` (Addition). `fileselect` no longer opens the system dialog unless the item is ticked; saved as `file_dialog=` in `ui.conf`, applied at once, tick shown after a restart; macOS and the device unchanged (the gate is the Linux-only `_norns.ui_file_dialog`). Tests first: `file_dialog_setting_test.lua` and the window scenario (`probe_file_dialog*.lua`); the window scenario fails 6 checks with the old behaviour. Menu probe positions in `probe_menu.lua` re-checked (the menu is one row longer).
- **Full `run_all.sh` after the file-dialog change: 0 known, 0 unexpected failures** (a first run had 2: a test name too long for a log file name, now shortened, and one `midi:auto-connect (conf)` "the test did not cut the link" that did not repeat in the second run: a timing flake of that test, not touched by this change).
- **Migration built: `verdandi tidy flatten --apply` and `--undo`** (owner's go after the dry run: dust/ 3985 files and links, 13G, same file system). Tests first, `tidy_flatten_apply_test.sh` (64 checks, scratch home like the owner's: nested dust with spaces in names, a link into the nested folder, one elsewhere, one broken, a browser profile, sclang_conf.yaml with the old path, an outer home with leftovers and a name on both sides): refusals (norns running, no typed line, nothing changed), backup (before.tree, dust.list, hard-link copy, MANIFEST, STATE), moves by rename (times kept), check of count, size, listing and inodes of dust/, `sclang_conf.yaml.old` + new file, link rewrite optional (yes/no), `--full-copy`, `--undo` gives exactly the first state, a killed run is undone by `--undo`, SIGTERM and a vanished file roll back by themselves, a name that appears during the move is never overwritten. The dry run now names the broken link and the links that point elsewhere (paths and targets). **Not run on any real data.** For the owner: `docs/port/RUN-ON-LAPTOP.md` (dry run again, close Verdandi, `--apply`, send the output).
- **Full `run_all.sh` after the migration: 0 known, 1 unexpected failure, and it was only the test's name (a `/` in it broke the log file name); renamed, the test passes (64 checks). Everything else passed.**
- **Browser profile in the norns home (KNOWN-ISSUES 19): reproduced and fixed.** The re-run under pw-jack recorded the norns home as the user's HOME for `xdg-open`; the user's values are recorded once now (`launcher_test.sh`, 2 failures before, 0 now).
- **Clean-up steps 3-4, full `run_all.sh`**: 0 known and 5 unexpected failures on the first run, all in tests (not in the code): two test names with a `/` (the log file name), the SYSTEM page list in `ui_settings_test.lua` (now has CLEAN UP), `plugin_check_test.sh` (the new `.plugin-fix` list file), and the installed-package test running an old `.deb` (rebuilt with `package.sh tree` + `deb`). Each was then re-run on its own and passes (`package_test.sh`, `package_out_test.sh`, `ui_settings_test.lua`, `plugin_check_test.sh`; `launcher_logs_test.sh` passed before); I did not repeat the whole 25-minute run after the fixes.
- **Clean-up plan written, awaiting the owner's confirmation** (`docs/port/clean-layout.md`, nothing built, no user data touched): inventory of everything created in and outside the norns home; **the nested home `~/Verdandi/Verdandi` is a launcher bug** (reproduced): `HOME` is exported but `NORNS_HOME` is not, and the re-run under `pw-jack` on PipeWire machines recomputes the default home from the changed `HOME`; proposed layout (`logs/`, `logs/crash/`, `disabled/` with a manifest, `backups/`, `cache/`), one tool `verdandi tidy`, a SYSTEM > CLEAN UP page, limits (5 runs per log, caps, crash reports only at a crash), `package.sh status/clean`, and a migration (dry run, typed confirmation, renames only, hard-link backup, undo). Six questions at the end of the plan.
- **mi-UGens / emplaitress investigated** (`docs/port/mi-ugens.md`, plan only, nothing built): the mod always downloads a 32-bit ARM pack (oomph release, commit 762548f) into the user extension folder and only looks there; any installed class that cannot build stops SuperCollider enabled or not (reproduced with the bundled 3.14.1, trace in `sclang.log`). An x86_64 build of mi-UGens `v0.0.9` takes 13 s against the package's SC source and is byte-identical to upstream's Linux release zip; with it the voice initialises and a note measures peak 0.45 on the JACK ports (headless). The pack must be in the user extension folder before sclang starts (a system-folder copy alone makes the mod fetch ARM files beside it: duplicate classes). Recommendation: ship it in the package outside the scanned folders and let the launcher seed it, plus a missing-class/duplicate-class startup check. Licences: GPL-3.0-or-later wrapper, MIT (Mutable Instruments code), BSD-2 (libsamplerate). Not checked: the laptop, sound quality, other scripts' installers (read only).
- **UI: GREYS became CONTRAST** (higher = more): 0 to 1 in steps of 0.1, default 0.5; gamma = 1 - c up to 0.5, then 0.5 - 0.2 (c - 0.5): 0 is the old linear mapping, 0.5 gamma 0.5 (the previous default), 1 gamma 0.4 (table in `docs/port/ui-settings-plan.md`: level 3 is 51, 60, 70, 83, 97, 114, 118, 122, 126, 130, 134; level 1 is 17 ... 86). `ui.conf` key `contrast`; an old `greys=` is converted to the nearest contrast (1.0 -> 0, 0.7 -> 0.3, 0.5 -> 0.5, 0.4 -> 1) with a log line and never written again; bad or out-of-range contrast = 0.5 with a log line. Tests first (`ui_settings_test.lua`, `ui_keys_test.lua`). Manual, RUN-ON-LAPTOP, HARDWARE-CHECKLIST and the plan updated; pictures re-made.
- **UI step 3 BUILT** (`docs/port/ui-settings-plan.md`, decisions of the owner recorded there): SYSTEM > UI below AUDIO on the computer: BRIGHTNESS (0.1 to 1, default 1, factor b^0.6), COLOUR (white, yellow FFD000, pink FF80B8, custom hex via the pset-name text entry, dark colours raised to full value), GREYS (gamma 0.4 to 1.0, **default 0.5**; level 3 comes out at 114 at 0.5, 83 at 0.7, 51 at 1.0; level 1 at 66, 38, 17); `ui.conf` in the norns home (four keys, unknown keys ignored with a log line, damaged values fall back per key); applied at once through `_norns.ui_look`, loaded at start by `core/ui_settings`; screenshot and GIF follow the window (the GIF has a mapped palette); `screen.export_png` raw; RESET leaves `ui.conf`. Mac and device unchanged (`NORNS_LINUX_DESKTOP`, `NORNS_PLATFORM`, `_norns.ui_look ~= nil`). Found on the way: the desktop screen backend draws in RGB565, so the old window's greys were slightly off 17 n and tinted green (level 4 = 66, 69, 66); the mapping reads the green channel and snaps flat levels. Tests first (all failed): `ui_look_test.c` (89600 values equal to the Python reference, black stays black, white stays white, gif palette), `ui_settings_test.lua` (hex parsing, text entry with the real keyboard module, save/load, damaged file, SYSTEM list), the headless window test (window, screenshot and gif equal). Pictures: real-window captures `ui-previews/ui-greys.png`, `ui-colours.png`, `ui-brightness.png`. Needs the owner's eyes on the laptop (HARDWARE-CHECKLIST "SYSTEM > UI"). Not built: the detachable screen window.
- **Mods FIXED** (`docs/port/KNOWN-ISSUES.md` 17): SYSTEM > MODS said "no mods": the C `glob` behind `norns.system_glob` got the virtual `/home/we/...` pattern and found nothing; `virtual_home.lua` now wraps it (pattern real, matches virtual); on a computer `mods.lua` logs every mod found and every failure and a failing mod no longer stops the others. Tests first: `mods_test.lua` (13 checks failed before) and the headless `window:mods` boot test. sidvagn and the doubledecker voice load without error headless; sound, grid port 2 and the nb mod itself are for the laptop (HARDWARE-CHECKLIST "Mods").
- **SYSTEM > UI keyboard bug FIXED** (`docs/port/KNOWN-ISSUES.md` 16): a key release (delta 0 from `-` and `=`) was read as one step down, so values jumped back on release and a held key scrolled; the page now uses the encoder's delta like the other pages (0 = nothing). Test first `ui_keys_test.lua` (7 failed before, with the numbers in KNOWN-ISSUES). Not tested on the laptop's keyboard.
- **Crash on the laptop FIXED** (`docs/port/KNOWN-ISSUES.md` 15): `strdup(NULL)` in the udev `watch_loop` thread (`get_device_name`, device without a "product" attribute), offset 0x6b36f matched by building commit b5c7226; same pattern fixed in the monome, serial, OSC and maiden-repl code; `get_alsa_midi_node` NULL/opendir checks. Tests first: `device_monitor_null_test.cc` (SIGSEGV before, fixed), `crash_report_test.sh`. New: crash reports (`docs/port/crash-reports.md`: signal, thread name, backtrace in `norns.log` and `crash-report.txt`, core dump kept) and the package keeps function names (+374 KB uncompressed, +28 KB compressed). The other two crashes (norns SIGABRT, sclang SIGABRT) are **not explained**: no cores here, `coredumpctl info` of both is needed. Not tested: the laptop itself (a real hotplug of the grid / mio with the new build).

## Test state
`linux/tests/run_all.sh` (about 2 minutes): no unexpected failures on an idle machine in the latest runs.
`boot:headless` is a **test race under CPU load**: 14 of 36 stress runs failed (0 of 12 at 2 busy loops per CPU).
Cause found (the probe does not wait for norns/sclang to be ready), fix proposed and proven in scratch (10/10
under load) but **not applied**: `docs/port/KNOWN-ISSUES.md`, logs in `docs/port/known-issues-logs/`.
`linux/tests/stress_boot.sh` repeats the check.

## In progress
- **Phase 3 steps 1-5 are done** (the owner's decisions in `DECISIONS.md`; decision 10 decided: SYS = all apps but norns, the sink monitor
  only as an option). Stopped here as asked: waiting for the owner. Open for the owner: nothing
  pending from my side; the laptop checks of step 5, the metro fix and the MIDI auto-connect are in `HARDWARE-CHECKLIST.md`.
  6. The owner's decisions applied: metro stack fix for the Linux desktop build (256 KiB, correct messages, a failed metro says so;
     test with a TLS-pressure preload: 20 of 20 ticks, was 0); no other fixed-stack thread in the repo; tempo page refresh put on the
     wishlist; MIDI auto-connect built (`midi_in_from=` / `NORNS_MIDI_IN_FROM`, 2 s re-check, status under SYSTEM > DEVICES > MIDI).
     Full run_all.sh: 0 unexpected failures. Stopped, waiting for the owner.
  5. MIC/OFF by physical flag, SYS (every application except norns' own clients), APP by name, optional sink monitor; in-window
     menu lists the applications; tests: `tests/crone/test_input_route.cpp`, `linux/tests/input_test.sh` (fake card and streams).
  Also fixed on real-machine reports (see the three bug fixes in RUN-ON-LAPTOP.md): libmonome waf via `python3`, waf in
     `~/.local/share/waf`, the `pw-jack` re-run by absolute path (test with a pw-jack that really execs).
  4. audio.conf and SYSTEM > AUDIO on Linux (modes jackd / pipewire / jack, restart of our own jackd with the new
     settings, PIPEWIRE_QUANTUM request). Found and fixed: SYSTEM > RESTART/SLEEP never worked on desktop Linux
     (`sudo -n systemd-run` in the sidecar). Details: `phase-3.md` "Step 4 results". Full run_all.sh: 0 unexpected failures.
  3. crone on a desktop: audio-type, physical ports of **one** client only (a physical MIDI port or a second card is
     never mixed in), by name prefix (`NORNS_IN_PORTS`/`NORNS_OUT_PORTS`) else the first card; no physical ports:
     boots unconnected and the warning is on the device window ("AUDIO: not connected, see SYSTEM > AUDIO") and
     in the log; `_norns.audio_status()`. `linux/norns.sh`: JACK server that answers is used; else PipeWire running
     means a re-run under `pw-jack`; else own jackd; `NORNS_AUDIO_SERVER`, `NORNS_JACK_DRIVER` given means own
     jackd; default sink/source from `wpctl` become the prefixes under PipeWire; `audio.conf` `in_ports=`/`out_ports=`.
     Tests: `tests/crone/test_port_select.cpp`, `linux/tests/launcher_test.sh`, `linux/tests/audio_ports_test.sh`
     (fake cards incl. physical MIDI ports; no-ports case). Pi/macOS: crone Client.h change is under
     `NORNS_LINUX_DESKTOP` only.
  1. `clock_midi`: song position (0xF2) and continue (0xFB), tests first. Continue does not reset the counter;
     start after SPP begins at the position (once); stop forgets a waiting position. 17 clock test cases pass.
  2. JACK MIDI input: client "Verdandi", port `midi_in`, device "Verdandi JACK in", no auto-connect,
     `NORNS_JACK_MIDI=0` switches it off. Clock messages use the event's exact JACK frame time
     (`clock_midi_handle_message_at`): in the test the tempo reads 120.0 and beats 0 / 18 / 20 / 0 at start, stop
     (after SPP 16 beats), continue (no reset) and the second start. Found and fixed on the way: an arrival-time
     version gave tempo 117-122 and once an infinite tempo (ticks of one JACK period have equal arrival times);
     `clock_midi_init` did not reset the smoothing buffer.
  Test infrastructure: the probe waits for norns/sclang readiness (applied, decision 2), and waits for `jackd` to be
  gone between runs (a race that made the portal scenario fail after the zenity scenario).
- Full `linux/tests/run_all.sh`: 0 unexpected failures at the end of step 2 (one run after the last change).
  Not run again 36 times: the stress test of the readiness fix was 8 of 8 at the heaviest load before step 1.
  The leftover `sidecar [norns]` processes seen in my sandbox come from starting the tests with `nohup`
  (SIGHUP is then ignored, so they do not die with norns); a normal terminal is not affected.

## Clock freeze with SYS under PipeWire + WirePlumber (the owner's bisect: 78eedb02): FIXED
Mechanism and numbers: `KNOWN-ISSUES.md` item 6. Fix applied (option A, desktop Linux only: a backward jump of more than 1 s in JACK's frame time is a new base to follow);
`clock_rate_test.sh` PipeWire flavor is now a normal check (2.000 beats per second with SYS). `NORNS_CLOCK_DEBUG=1` kept and described in `RUN-ON-LAPTOP.md`.
**Follow-ups, the owner to decide:** (1) the accepted forward jump: measured (a transient +1120 beats read for up to one tick, a 10-event `clock.sync` burst followed by a 5 s
gap, one early wake per `clock.sleep` coroutine; the beat counter itself does not advance) and a handling proposed in `docs/port/clock-forward-jump-proposal.diff` (verified in
a scratch copy, not applied); (2) `CLOCK_MONOTONIC` for the internal clock, documented as a follow-up option.
**Default input at boot: MIC** (`_menu.input = "mic"`, identical at 37d244b5 and now; with no saved choice nothing is connected or disconnected at boot). What changed at
78eedb02 is that a **saved choice is restored at boot**: `~/verdandi-home/.norns-input` (SYS, APP or the sink monitor) or `.mic-off` (OFF). Before 78eedb02 SYS/APP did not exist
on Linux, so a SYS choice could not be made or restored. If your laptop's norns home has a `.norns-input` file from pressing the MIC button once (MIC > SYS), it starts in SYS.

## Text placement fix (KNOWN-ISSUES item 9)
Done, test first: on the desktop builds `screen.cc` rounds the start of every text (`screen.text`, `text_right`, `text_center`, `text_trim`) to a whole pixel, as the device's cairo 1.16 does, so centered text with an odd ink width
("modulation", "track 6 options", "link" ...) is crisp again; the device build is byte for byte unchanged (preprocessed source compared). `linux/tests/screen_text_test.cc` (real `screen.cc` in the test) runs in `run_all.sh`.
Not verified: macOS, a real device. Scripts checked for fractional text positions: none found in 12 community scripts; the core tab bar had one (fixed by the snap).

## SuperCollider plug-in check and restart commands from scripts
Done, tests first: (1) before SuperCollider starts, `linux/norns.sh` runs `linux/plugin_arch_check` (ELF class and machine of the plug-ins in the extension folders and `dust/code`, against `uname -m`): one plain log
line per wrong file with the move command into `<norns home>/disabled-plugins`, a standing note on the device window until none is left, report only (nothing is moved), off with `NORNS_PLUGIN_CHECK=0` / `plugin_check=0`;
(2) `linux/shims/sudo` and `systemctl` (first on norns' own `PATH`): `sudo systemctl restart norns-*` from a script returns at once and norns restarts itself (`_norns.restart()`), other sudo commands get `-n`; one line logged.
Decision to confirm: PATH shims for these command strings rather than a global `os.execute` interception (options in `KNOWN-ISSUES.md` 8.6). Not built: quarantine, installer or x86_64 bundles.

## serialosc conflict on the grid's serial port (Level 1)
Norns now detects another process (serialosc's `serialosc-device`) on the serial port of a grid or arc it opened, logs one plain line per plug-in with the stop/start commands and the
replug hint, and shows a standing note on the device window while it lasts; off with `NORNS_SERIALOSC_CHECK=0` / `serialosc_check=0`. Detect and warn only: nothing is stopped, no OSC. Details:
`phase-3.md`, `RUN-ON-LAPTOP.md`, `HARDWARE-CHECKLIST.md`.

## MIDI auto-connect: own ALSA client found by thread id
Fixed after a real-laptop test: ALSA reports the id of the thread that created a client, so norns' own virtual RawMIDI port (`Client-128`, a thread of norns) was linked back into `Verdandi:midi_in`
along with Reaper's. Own clients are now matched against the process id, all thread ids and the ids of processes norns started; tests use a client list as data (no ALSA needed).

## SYS fixes after the owner's laptop test (KNOWN-ISSUES item 7)
Fixed: SYS and APP no longer take capture streams (ports named `monitor*` / `capture*`, a deny-list; Reaper's `ALSA Capture [reaper]:monitor_FL/FR` was feeding the microphone into crone),
and the optional sink-monitor mode now really switches the input monitor off. Tests first (fake capture-stream client, unit cases, `input_monitor_test.lua`). Why SYS is silent at the output
(the input monitor is off in SYS/APP on purpose; recording, sampling and processing work) is explained in item 7.2. **Not built (the owner's decision):** unlinking the applications' direct link to
the sound card (the owner's hand test: an unlinked stream stays unlinked, but a new stream is linked again, so it would need continuous re-checking); revisit after the owner has used SYS for a while.

## Real-hardware findings (the owner's laptop)
Recorded in `HARDWARE-CHECKLIST.md` ("Done on a real machine"): silent run, sound under PipeWire, Reaper clock/notes through the
Midi-Bridge all work; the link from Reaper to `Verdandi:midi_in` was dropped several times (design for auto-connect only).

## maiden on Linux: built (phase-4-maiden.md, "Result")

Built by `linux/maiden-build.sh` (setup-deps.sh and build.sh run it; `NORNS_NO_MAIDEN=1` skips), started by `linux/norns.sh` on 127.0.0.1:5000 (`NORNS_MAIDEN_PORT`), MAIDEN button opens it or shows a note.
The browser-origin exposure was reproduced first (`maiden-exposure-evidence.md`), then fixed: `ws-wrapper` Origin check (opt-in env var, the Mac does not set it) and a Host/Origin guard in the Linux maiden patch; the unit API is off.
KNOWN-ISSUES item 10: the Mac port has the same exposure, untouched. Tests added to `run_all.sh`: maiden:server/origin, maiden:launcher, maiden:install, maiden:button.
Open: maiden license notices file not generated (the licenses are collected in DEPS.md); apt `golang-go` 1.22 not tried (1.24.7 used); a fresh Ubuntu 24.04 image not used (this container, uid 65534, no `python`).
Needs your laptop: `HARDWARE-CHECKLIST.md`, section "maiden".

## maiden and `--terminal` (found on the laptop)

Confirmed from the code: matron's Lua prompt is one stdin/stdout stream (`matron/src/input.cc` reads stdin). `--terminal` leaves it on the terminal; without it `ws-wrapper` binds it to the websocket on 5555 (what maiden's page and `maiden-repl` use).
They are exclusive by construction. Not changed: `--terminal` keeps its meaning (the headless tests drive matron through it). Added: a launcher line in `--terminal` mode, a note in the window when MAIDEN opens the page without a console,
RUN-ON-LAPTOP wording, the way to have both (start without `--terminal`, run `maiden-repl` in a second terminal), and a launcher test section for `--terminal`. The non-terminal assertions (5555 on 127.0.0.1 only, a websocket reaches the Lua REPL, a foreign Origin is refused)
were already in `maiden_launcher_test.sh`.

## Chunk names under the virtual /home/we (KNOWN-ISSUES item 11): FIXED

Cheat Codes 2 (nb) failed with `mydir` nil: `loadfile`/`dofile`/`require` passed the real path to Lua, so `debug.getinfo(1).source` was the real path. Now the chunk is named with the virtual path (`lua/core/virtual_home.lua`, shared with the Mac app, `macos/` untouched).
Tests first (both failed before): `linux/tests/virtual_chunkname_test.lua`, `linux/tests/chunkname_test.sh`, with the real nb library when the network allows. Errors and tracebacks now show virtual paths, as on the device. Not run: Cheat Codes 2 itself, macOS.

## Plug-in check output, MANUAL button, maiden licenses

- Plug-in check: one line per **folder** (files, what they are, one move command, how to turn it off); note and 3-second re-check unchanged. Unit and integration tests updated, with two bad files in one folder and one in another.
- MANUAL button: the launcher sets `NORNS_MANUAL` to `linux/manual/manual.html`; the window shows "manual not found: ..." when it is not there (test `manual_button_test.sh`). **The manual is written** (outline approved): `linux/manual/manual.html`, 14 sections with a table of contents and a sources comment per section, including known limitations (ARM plug-ins, Pi system commands, `--terminal` vs maiden's console, serialosc). Tests: `manual_test.sh` (file, links, sources comments, no external resources, names and paths exist in the code) and `manual_button_test.sh` (the button opens it). Whether each sentence is true is for the owner's reading (HARDWARE-CHECKLIST).
- Licenses of maiden's Go modules (40), bundled npm packages (118) and build tools are in `docs/port/DEPS.md`, with what needs attention (one MPL-2.0 module, notices not carried by the build, five npm packages without a license file) and what could not be determined. No code changed for it.

## Several plug-in instances in one project: investigation (no code changed)

`docs/port/multi-instance.md`: today's AUv3 cannot serve two instances (one bridge, one stream; read, not run); the inventory of ports, JACK names and files; measurements of 1/2/4 headless instances (own namespaces: no clashes, ~0.46 GB and ~6.5 % of a core idle each, 4.5 to 7 s to start; with port flags and homes alone only one survives); options A to D assessed.
Recommendation: build the one-instance guard with a message (D) into the plug-in plan, do not build per-instance norns (A) now, B never, C only as a separate feature. Harness and raw outputs in `docs/port/multi-instance/`. Decision for the owner: D now? and whether A is wanted at all.

## Plug-in plan: Linux VST3 first, one instance at a time (approach note written, no plug-in code)

Decisions (owner): option D (one instance with a clear message, a settable bridge port and an instance id in the protocol from the start); option A documented, not wanted now; AUv3 untouched (`KNOWN-ISSUES.md` item 12); first plug-in = Linux VST3 in Reaper on the owner's Mint laptop, Windows later. `PLAN.md`: Phase 7 = Linux VST3 (steps 7.1 to 7.6), Phase 8 = Windows VST3. Approach note: `docs/port/linux-vst3.md` (framework choice with licenses, protocol, guard, transport to clock, audio and latency, tests, recall, risks, open decisions = GATE E in `DECISIONS.md`). `CLAUDE.md` still says the VST3 belongs to the Windows step: the owner may want to update it.

## Packaging investigation (Gate B): written, no code changed

`docs/port/packaging.md` (+ `docs/port/packaging/` with the scripts and the last output): recommendation **`.deb` first** (Ubuntu 24.04 / Mint 22), bundled SuperCollider 3.14.1 **without Qt**, program read-only under `/opt/verdandi`, home in a user folder, AppImage possibly later, Flatpak not recommended. Run here: read-only program tree boots; Qt-less SuperCollider built from source boots norns (closure 18 MB vs 238 MB); an experimental `.deb` installs in a clean Ubuntu 24.04 and boots headless. Found: SuperCollider's data path is compiled in (not relocatable); the bundled SuperCollider must not be called `sc/` (norns' own folder). Not tested: AppImage, Flatpak, the laptop. `CLAUDE.md` now says Linux VST3 first, then Windows. GATE B is open in `DECISIONS.md`.

## Next
- The owner: run the laptop steps in `docs/port/RUN-ON-LAPTOP.md` (untested on a real desktop), review `HARDWARE-CHECKLIST.md` (sections after Phase 1, 2 step 4, 2 step 5, clock) and the macOS
  re-verification list at the end of `docs/port/phase-2.md`.
- Steps 4-5 of `docs/port/phase-3.md` follow (step 5 only after the owner's report).
- macOS: re-verify with the shared-file list at the end of `docs/port/phase-3.md` (clock and device_midi changes).

## Not testable here / notes
- macOS not rebuilt after the edits to shared sources (list in `docs/port/phase-2.md`).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb, no desktop session (portals).
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
