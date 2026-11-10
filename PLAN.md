# PLAN: staged tasks and gates

Work top to bottom. Tick items off in `STATUS.md`. GATE = write to `DECISIONS.md`, notify the owner, continue with independent work.

## Phase 0: Inventory (read-only, no code changes)
- Read `readme-macos.md`, `macos/docs/` (it has a linux inventory and catalog scan), `matron/src/platform/macos/`, `macos/`, `wscript`.
- Produce `docs/port/INVENTORY.md`: every macOS-specific API or file, what it does, and its Linux and Windows equivalent. Include: CoreMIDI, IOKit (grid/arc/crow/serial), IOHIDManager, Cocoa window and menu, ImageIO (GIF/PNG), Core Audio process tap (SYS input), `audio_devices.c`, Finder drop and panel, `open_url.c`.
- Note what is already portable (skins, key mapping, `gif_writer.c` logic, `vgrid_proto.c`).
- **GATE A**: fork vs upstream-as-platform-folders. Decided (option 1): code in `matron/src/platform/linux/` and `windows/`, shared files in place until a separate move commit. This is the owner's own version; nothing is offered upstream and nobody is contacted.

## Phase 1: Headless Linux build and boot
- Reproducible build script for Ubuntu 24.04 (deps, waf configure, build).
- Boot norns with Xvfb plus `jackd -d dummy`; use `macos/tests/norns_probe.sh` style probing to drive the Lua REPL.
- Run all tests that do not need macOS frameworks (window_keys, device_skin, vgrid proto, keyboard_hardware, menu_pages, input_modes, output_fader, virtual_home).
- Write `docs/port/phase-1.md` with results and failures.

## Phase 2: Desktop layer for Linux (`matron/src/platform/linux/`)
- SDL window running matron on its own thread; reuse `device_skin.c`, `vgrid_skin.c`, `varc_skin.c`, `vkeys_skin.c`.
- Virtual grid/arc through the pty path (should work as-is); virtual keyboard as an ALSA sequencer virtual port named "norns keys".
- Stubs for oled, gpio keys/encoders, battery, i2c as on Mac.
- Dust import and file drop (SDL drop events, plus XDG portal for dialogs if available); screenshot PNG and GIF writer without ImageIO.
- Menu actions (screenshot, import, open folders) without Cocoa.

## Phase 3: Audio and devices on Linux
- JACK (PipeWire-JACK on modern distros). Replace the macOS `audio_devices.c` enumeration; keep `audio.conf` semantics.
- MIC/SYS/OFF input: SYS and APP modes via JACK/PipeWire port connections; remove the Core Audio tap dependency.
- Real devices via the norns Linux paths (ALSA MIDI, udev, evdev) where upstream already supports them.
- **External clock, MIDI first** (decided by the owner, `docs/port/clock-notes.md`; wishlist item 2). Approach note `docs/port/phase-3-clock.md` before code. In this order:
  1. `clock_midi`: support Song Position Pointer (0xF2) and MIDI continue (0xFB), with unit tests (extend `tests/matron/clocks/clock_midi`). **Continue must not reset the beat counter** (start still does); SPP sets the beat position. Shared code: macOS behavior for plain clock/start/stop stays as is, re-verify on macOS.
  2. **JACK MIDI input port** on matron's JACK client (`jack_client.cpp`) feeding the existing MIDI parser as a norns MIDI device (works with PipeWire and without `/dev/snd/seq`; a program such as Reaper sends clock to it). Part of the Linux baseline. Test headless: a JACK MIDI test client sends 0xF8/0xFA/0xFB/0xFC/SPP into the dummy-driver JACK graph and the tempo/beat are checked from Lua. Real Reaper goes to the hardware checklist.
  3. **ALSA sequencer input** (client "Verdandi" with a writable port) later: after the JACK MIDI input works, not needed for the baseline gate. Needs `/dev/snd/seq`; untestable in the build container, hardware checklist.
  4. Ableton Link stays as the secondary path (already built and working on Linux; Windows build define in Phase 6). Reaper side: ReaBlink (see clock-notes.md); MIDI clock is the primary path.

## Phase 4: Launcher and packaging
- Linux equivalent of `macos/norns.sh` (done: `linux/norns.sh`; **installed mode** done: the home is `NORNS_HOME`, else `~/.config/verdandi/home`, else `~/Verdandi`; the `norns` link is created or moved, shared with a developer checkout).
- maiden: done (Phase 4 note `docs/port/phase-4-maiden.md`).
- **GATE B decided**: `.deb` first (Ubuntu 24.04 and Mint 22), one file per release, no apt repository; Flatpak not now; AppImage later and optional; a narrow udev rule for monome devices; font licences open before any public release (`DECISIONS.md`, `docs/port/packaging.md`).
- First step done: `linux/package.sh` (SuperCollider 3.14.1 without Qt, sc3-plugins, libmonome for the final prefix, maiden, norns; `.deb` with a neutral identity and a privacy scan), the clean-root test (`linux/tests/package_test.sh`, in `run_all.sh`), the udev rule and its test, `docs/port/supercollider-3.14.md` (all six engines run on 3.14.1).
- Next: build the `.deb` on the laptop (`package.sh clean-root` or `all`) and install it there (`HARDWARE-CHECKLIST.md`, "The package"); the answer on the four fonts before any release; a generated notices file for maiden's modules (packaging.md section 5.5); "bring the running window forward when started twice".
- AppImage (optional, later): same tree and SuperCollider, plus a way around the compiled-in SuperCollider path, the FUSE question, a first-run desktop entry.

## Phase 5: Linux acceptance
- Finish `docs/port/HARDWARE-CHECKLIST.md` (real grid/arc, crow, MIDI, audio interface, SYS capture, long-run stability).
- **GATE C**: the owner tests on real hardware and approves Linux before Windows starts.

## Phase 5.5: OSC / serialosc support (between Linux acceptance and Windows)
Goal: real grids and arcs through **serialosc**, and a **virtual grid/arc that works without the pty trick**, so one transport serves Linux, Windows and macOS (Windows has no ptys; Phase 2's libmonome patch on Linux is a stopgap).
- First: approach note `docs/port/phase-osc.md` before any code. It covers: how norns finds devices today (`device_monome.cc`, libmonome paths) and what changes; libmonome's OSC protocol (`monome_open("osc.udp://host:port/prefix")`, `BUILD_OSC_PROTO`) vs. a small own OSC client; serialosc discovery and hotplug (`/serialosc/list`, `/serialosc/notify`, `/serialosc/add|remove`); the virtual grid and arc as an in-process serialosc-compatible UDP server on 127.0.0.1 (replaces `vgrid_device.c`'s pty and the libmonome patch; `vgrid_proto.c` is the mext side and would get an OSC sibling); whether to bundle serialosc itself (ISC licence; needs libmonome, liblo, libuv, libudev on Linux; check Windows/macOS builds) or require it to be installed; port clashes with a serialosc already running on the machine; arc support (rings, delta, key); rotation, intensity and level messages.
- **GATE F**: transport and packaging decision (libmonome OSC vs own client; bundle serialosc or not; macOS migration or keep pty there). Question goes to `DECISIONS.md`.
- Then: implement behind the gate decision; tests that need no hardware (virtual grid and arc over OSC end to end, a fake serialosc for discovery); the real grid/arc via serialosc goes into `docs/port/HARDWARE-CHECKLIST.md`.
- Keep macOS behavior unchanged unless the owner decides at Gate F to move it.

## Phase 6: Windows standalone (`windows-port` branch, after gate C)
Plan (version 2): `docs/port/windows-plan.md` (every Linux feature with its Windows replacement, clock model, audio route, grids, milestones with effort guesses, decisions). Owner decisions: **no VST3 plug-in**; a Windows standalone that does everything the Linux version does, next to Ableton Live and an RME Fireface UC (ASIO). Clock: **both Ableton Link and MIDI clock (start/stop/continue/SPP), selectable, with a note of which one drives**. Audio: shared RME driver + TotalMix FX Loopback into an Ableton track; fallback WASAPI. Grids: 2023-24 grid 128 (USB CAFE:1110) and 2011 grid 256 (FTDI 0403:6001), direct COM by USB ids and serial, serialosc optional. Plug and play, per-user installer, unsigned for now.
- **GATE D, resolved toward (owner to confirm in `DECISIONS.md`)**: no JACK. One audio callback (PortAudio) pumps crone and an in-process SuperCollider 3.14.1 (`scpump.dll`, external-audio-driver patch); JACK2 for Windows is the fallback if the patch fails (gate at M0c).
- Build: MSYS2 UCRT64 (norns) plus MSVC (SuperCollider) in GitHub Actions on `windows-2022` (not `windows-latest`, which now carries Visual Studio 2026); Inno Setup per-user installer.
- Milestones: **M0a** toolchain and dependencies (SuperCollider build, MSYS2 packages, Lua 5.3, libmonome, Link probe, portable tests, porting inventory), **M0b** boot smoke (sclang compiles norns classes, scsynth offline render, path with spaces), **M0c** minimal platform layer + `scpump` prototype (feature code, separate approval), M1 audio out and doctor, M2 window and OSC virtual grid, M3 grids and MIDI, M4 clocks and Ableton, M5 maiden/scripts/plug-in heal, M6 installer and clean layout, M7 polish.
- **M1 (first runnable build, null audio) is built and under test in CI** (`docs/port/phase-m1.md`, `docs/port/windows-plan.md` section 8b): Windows platform layer in `matron/src/platform/windows/` (stubs with one log line each, compat headers, JACK-compatible null backend, crash handler, shell runner), scsynth null audio driver patch, CMake build, launcher `Verdandi.exe`, workflow `windows-m1.yml` with a headless start test and the zip as artifact. Not in M1: sound, grids, MIDI, Link, maiden, installer. What only the owner can check: `HARDWARE-CHECKLIST.md` "Windows M1".
- **M2 (real audio output, WASAPI) is built and works on the owner's PC (sound heard; build 0.2.0). Second round of fixes after that test: crashes at restart (Lua closed under live threads, resolved from the CI build's symbols), start-up race, launcher restart safety, AUDIO "default", a crash reporter with function names; a 10x start/restart test in CI (see STATUS).** Original note: M2 was built, not yet run on Windows (`docs/port/phase-m2.md`, plan section 8c). Design chosen: norns.exe owns the card (one PortAudio WASAPI shared-mode callback runs crone's blocks), scsynth has no device and is clocked and fed through a shared-memory audio bridge. SYSTEM > AUDIO lists devices (`audio.conf`), a busy or missing device falls back to null audio with a note. ASIO is M3 (licence: dual proprietary/GPLv3 since 2025-10; text of the SDK licence still to be read). What only the owner can check: `HARDWARE-CHECKLIST.md` "Windows M2".
- **Distribution convenience (built, untested on GitHub):** every successful `windows-m1` run on `linux-port` publishes the zip `Verdandi-windows-<version>-<hash>.zip` to GitHub Releases (`windows-<hash>` per commit, `windows-latest` updated in place); `update-and-run.cmd`/`.ps1` in the zip fetches and starts the newest build next to the old ones; the build id shows on the home page, in `BUILD.txt` and in the first lines of `launcher.log` and `norns.log`. See STATUS and `windows/README.md`.
- **M0a and M0b are prepared (setup only, no product code):** `.github/workflows/windows-m0.yml`, `windows/ci/`, `windows/pack/`, and the owner's click-by-click guide `windows/README.md`. The owner enables Actions on the fork and starts a run; the report in the artifact says what built. Anything not testable here goes to the hardware checklist.

## Phase 7: Linux VST3 [PARKED by owner decision; reference only: docs/port/plugin-feasibility.md] (the first plug-in; tested in Reaper on the owner's Linux Mint laptop, PipeWire)
Decided by the owner (after `docs/port/multi-instance.md`): the first plug-in is a **Linux VST3**; Windows follows later and reuses what it teaches. **One plug-in instance at a time, with a clear message** (option D); option A (one norns per instance with a supervisor) stays a documented future option and is not planned.
Approach note: `docs/port/linux-vst3.md` (written before any plug-in code). Work in this order; each step has headless tests unless marked "owner":
- **7.1 Protocol and bridge core (no plug-in yet).** A new, versioned bridge protocol in a shared header (not `macos/auv3/bridge_protocol.h`, which stays as it is): hello with an **instance id**, a version field, a settable bridge port (default 10200, announced in a runtime file), audio, MIDI, a **transport message** (tempo, PPQ position, play state), heartbeat, status, bye, and the **one-instance guard** (busy reply with a readable message). A Linux bridge (a JACK client next to norns, like `auv3_bridge`) and a fake plug-in client for tests.
- **7.2 Transport to norns' clock.** The bridge turns the transport message into MIDI clock, start, stop, continue and song position and plays it into the existing internal device route (`Verdandi:midi_in`, which already follows them: Phase 3). Audio takeover of crone's inputs and outputs while a plug-in is connected, coordinated with the input router (MIC/SYS/APP/OFF). Tests: fake plug-in + headless norns, tempo and position follow, guard behaviour, latency measurement.
- **7.3 The plug-in.** VST3 (framework per Gate E), thin client over loopback UDP, no allocation or locks in the audio thread, passes audio through (with a matching delay) when norns is not running, reports a constant latency, status as read-only parameters, state = instance id and version (more later). Tests: the SDK's validator tool, a headless fake host that loads the plug-in and drives audio, MIDI and `ProcessContext`.
- **7.4 Start and find norns.** Bridge discovery through a runtime file; optional auto-start of norns from the plug-in (decision in the note); `linux/build.sh` builds and installs the plug-in (opt-out), `DEPS.md` for the SDK.
- **7.5 Acceptance (owner).** Reaper on the owner's laptop: the plug-in scans and loads, audio both ways through norns, latency compensation, MIDI, tempo and transport following, the guard message with a second instance, behaviour when norns is not running or crashes, project save and load. Goes into `HARDWARE-CHECKLIST.md`.
- **7.6 Project recall (optional, after 7.5).** Script name and parameter set stored in the plug-in state (what and what not: the note, section 10).
- **GATE E (open)**: framework choice and the open decisions of `docs/port/linux-vst3.md` section 13 (recommendation there: the VST3 SDK directly, MIT). Question in `DECISIONS.md`.
- Keep macOS and the AUv3 unchanged. The two-instance problem of the AUv3 is written down in `KNOWN-ISSUES.md` item 12.

## Phase 8: Windows VST3 [DROPPED by owner decision] (after Phase 6 and Phase 7)
- Reuse the protocol, the bridge logic and the plug-in code of Phase 7; what changes is the norns-side delivery (JACK MIDI becomes the internal pipe device of the keys type), the audio path (JACK for Windows or the Windows standalone's audio path from Gate D), process start and the bundle layout.
- Windows-specific checks as in Phase 6 (ASIO, the owner uses an RME Fireface); tests that cannot run here go to the hardware checklist.
- The same one-instance guard and message.

## Phase 9: MIDI MAP, MIDI control of the on-screen keys and encoders (Linux desktop; BUILT, see `docs/port/midi-map-plan.md` section 9)
Plan: `docs/port/midi-map-plan.md` (no code yet; one stand-in picture). A tap in `_norns.midi.event` that turns mapped CC / notes into E1-E3 and K1-K3 events; learn by clicking a control in the window; absolute and relative (two's complement, sign-magnitude, offset binary) encoders; `midimap.conf` and presets; a MIDI MAP page below THEME. The params MAP wins a clash; scripts always receive every message. Starts only when the owner says so; the open decisions are in section 8 of the plan.

## Phase 10: the virtual arc from MIDI and the keyboard (Linux desktop; BUILT, see `docs/port/arc-plan.md` section 9)
Plan: `docs/port/arc-plan.md` (no code yet; one stand-in picture): A1 to A4 in MIDI MAP (learn by clicking the ring, GAIN, ACCEL, calibration), the keys 5/6 T/Y G/H B/N, the Beatstep Pro split and a WATCH view. Starts only when the owner says so (decisions in section 8 of the plan).

## Phase 11: MIDI actions, the buttons of the window from a MIDI controller (Linux desktop; BUILT, see `docs/port/midi-actions-plan.md` section 9)
Plan and what was built: `docs/port/midi-actions-plan.md`. 14 actions (MIX TAPE HOME PARAMS INPUT GRID ARC KEYS MAIDEN MANUAL MUTE DETACH FULLSCREEN SCREENSHOT) on a note, a CC button or an encoder step, learned in MIDI MAP > ACTIONS (also ASSIGN ALL); `_norns.window_action` runs the same `button_action` as the mouse; a master switch as a page row, a ticked menu item and Ctrl+Shift+M, saved in `midimap.conf`. Needs the owner's Beatstep Pro for the pads (`HARDWARE-CHECKLIST.md`).
