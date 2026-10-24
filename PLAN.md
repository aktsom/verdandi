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
- Linux equivalent of `macos/norns.sh` and `app-launcher.sh` (first run creates `~/norns`).
- Bundle SuperCollider, sc3-plugins, maiden, GNU tools assumptions documented.
- **GATE B**: Flatpak vs AppImage (or both). Recommendation to be written after Phase 3 based on audio and USB-access needs.
- Build the packaged artifact; verify install in a clean container.

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
- Extend `INVENTORY.md` with Windows specifics.
- **GATE D**: JACK2 bundle with ASIO/WASAPI vs another audio path. The owner uses an RME Fireface (ASIO) so ASIO must work.
- MIDI (WinMM/WinRT or RtMidi), HID/gamepads, serial for grid/arc/crow (check libmonome Windows support; patch or add backend), virtual grid replacement for the pty trick (from Phase 5.5), GNU tools bundle, symlink-free dust import (copy), installer.
- SYS input via WASAPI loopback (per-process where available).
- Cross-compile or build in a Windows VM; anything not testable goes to the hardware checklist.

## Phase 7: Windows VST3
- **Plugin transport (Option C of `docs/port/clock-notes.md`)**: design a transport message (tempo, PPQ position, playing) into the UDP bridge protocol (`bridge_protocol.h`) from the start; the bridge turns it into MIDI clock, start/stop/continue and SPP for an internal norns MIDI device (same pipe approach as the keys device), so `clock_midi` follows the DAW with no virtual MIDI driver. The same message is added to the macOS AUv3 (host musical context; cannot be tested here, hardware checklist). Written down in the Phase 7 approach note before code.
- A **Linux VST3** is wanted in principle: decide at Gate E (it would give Option C on Linux; today PLAN.md has no Linux plugin).
- Mirror the AUv3 design: thin plugin client talking UDP on 127.0.0.1 to a bridge next to norns. Read `macos/auv3/` and `auv3_bridge` for the protocol first.
- **GATE E**: Linux VST3 yes/no and framework choice (JUCE under AGPL-3.0 compatible with this GPL-3.0 project, or the VST3 SDK directly; confirm current licenses before choosing).
- Validate with a VST3 validator tool; final test in a DAW (Reaper) is the owner's.
