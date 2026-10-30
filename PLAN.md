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
Plan: `docs/port/windows-plan.md` (plan only, no code yet). Owner decision: **no VST3 plug-in**; a Windows standalone that does everything the Linux version does, working next to Ableton Live and an RME Fireface (ASIO), with Ableton's tempo and transport driving norns.
- **GATE D, resolved toward (owner to confirm in `DECISIONS.md`)**: no JACK. One audio callback (PortAudio, ASIO and WASAPI) pumps crone and an in-process SuperCollider 3.14.1 (`scpump.dll`, MSVC build with an external-audio-driver patch); JACK2 for Windows stays the fallback if the patch fails at M0b.
- Clock: Ableton Link first, MIDI clock over loopMIDI as fallback. Devices: direct COM monitor for both grids (serialosc optional), RtMidi, SDL.
- Build: MSYS2 UCRT64 (norns) plus MSVC (SuperCollider) in GitHub Actions `windows-latest`; Inno Setup per-user installer; no signing yet.
- Milestones: M0 toolchain and headless boot, M1 audio out and audio doctor, M2 window and keyboard, M3 grids and MIDI, M4 Ableton (return route, Link), M5 maiden/scripts/mods, M6 installer and clean layout, M7 polish. Anything not testable here goes to the hardware checklist.

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
