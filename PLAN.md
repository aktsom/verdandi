# PLAN: staged tasks and gates

Work top to bottom. Tick items off in `STATUS.md`. GATE = write to `DECISIONS.md`, notify Ken, continue with independent work.

## Phase 0: Inventory (read-only, no code changes)
- Read `readme-macos.md`, `macos/docs/` (it has a linux inventory and catalog scan), `matron/src/platform/macos/`, `macos/`, `wscript`.
- Produce `docs/port/INVENTORY.md`: every macOS-specific API or file, what it does, and its Linux and Windows equivalent. Include: CoreMIDI, IOKit (grid/arc/crow/serial), IOHIDManager, Cocoa window and menu, ImageIO (GIF/PNG), Core Audio process tap (SYS input), `audio_devices.c`, Finder drop and panel, `open_url.c`.
- Note what is already portable (skins, key mapping, `gif_writer.c` logic, `vgrid_proto.c`).
- **GATE A**: fork vs upstream-as-platform-folders. Recommendation: keep code in `matron/src/platform/linux/` and `windows/` so it can be offered upstream later. Ken decides whether to approach ha1dcre.

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

## Phase 4: Launcher and packaging
- Linux equivalent of `macos/norns.sh` and `app-launcher.sh` (first run creates `~/norns`).
- Bundle SuperCollider, sc3-plugins, maiden, GNU tools assumptions documented.
- **GATE B**: Flatpak vs AppImage (or both). Recommendation to be written after Phase 3 based on audio and USB-access needs.
- Build the packaged artifact; verify install in a clean container.

## Phase 5: Linux acceptance
- Finish `docs/port/HARDWARE-CHECKLIST.md` (real grid/arc, crow, MIDI, audio interface, SYS capture, long-run stability).
- **GATE C**: Ken tests on real hardware and approves Linux before Windows starts.

## Phase 6: Windows standalone (`windows-port` branch, after gate C)
- Extend `INVENTORY.md` with Windows specifics.
- **GATE D**: JACK2 bundle with ASIO/WASAPI vs another audio path. Ken uses an RME Fireface (ASIO) so ASIO must work.
- MIDI (WinMM/WinRT or RtMidi), HID/gamepads, serial for grid/arc/crow (check libmonome Windows support; patch or add backend), virtual grid replacement for the pty trick, GNU tools bundle, symlink-free dust import (copy), installer.
- SYS input via WASAPI loopback (per-process where available).
- Cross-compile or build in a Windows VM; anything not testable goes to the hardware checklist.

## Phase 7: Windows VST3
- Mirror the AUv3 design: thin plugin client talking UDP on 127.0.0.1 to a bridge next to norns. Read `macos/auv3/` and `auv3_bridge` for the protocol first.
- **GATE E**: framework choice (JUCE under AGPL-3.0 compatible with this GPL-3.0 project, or the VST3 SDK directly; confirm current licenses before choosing).
- Validate with a VST3 validator tool; final test in Ableton is Ken's.
