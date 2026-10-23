# Verdandi port: Linux first, then Windows (VST3)

Put this file at the root of your fork of ha1dcre/verdandi.

## Goal
Port Verdandi (norns running natively on a desktop, as a standalone app plus a DAW plugin) to:
1. **Linux**: standalone app, plug-and-play (Flatpak or AppImage; decision gate B).
2. **Windows**: standalone app plus a **VST3** plugin (no CLAP). Starts only after Linux is accepted (gate C).

Feature parity target is whatever `readme.md` lists for macOS: norns window with device skin, maiden, virtual grid/arc/keyboard, real grid/arc/crow/MIDI over USB, MIC/SYS/OFF input, sample drop and file picker, MIX page, screenshots/GIFs, and the plugin equivalent of the AUv3.

## Known architecture (from readme-macos.md; verify against code)
- Mac-specific code lives in `matron/src/platform/macos/` and `macos/`. Everything else is upstream norns.
- Audio runs through JACK (jackd) on the Mac too, with SuperCollider (crone) and softcut.
- The AUv3 is a thin client: it sends DAW audio and MIDI over UDP on 127.0.0.1 to `auv3_bridge`, a JACK client next to norns. Do the VST3 the same way.
- The virtual grid and arc are a pty that libmonome opens like a USB device (`vgrid_proto.c`, `vgrid_device.c`).
- Skins and key mapping are plain C with Cairo and have tests; reuse them as the shared desktop layer.

## Working agreement (important)
- **Never write to `main`.** Work on branch `linux-port`, then `windows-port`. Commit small and often with clear messages so a resumed session loses nothing.
- **Push only to the linux-port branch (and later windows-port) of this fork. Never push to main.** Do not open issues or PRs, or contact anyone, including ha1dcre. Those need Ken's approval.
- **Keep `STATUS.md` current**: what is done, what is in progress, what is next. After any interruption or resume, read `STATUS.md` and `PLAN.md` first, then continue from there.
- **Decision gates**: when `PLAN.md` says GATE, or you hit any choice that is not obviously reversible (licensing, packaging format, dropping a feature, large refactors of shared code), write the question to `DECISIONS.md` with options and your recommendation, fire the notification hook (see `SANDBOX.md`), then continue with any independent task. Do not block on a gate if other work is available.
- **Explain before changing**: for each phase, write a short approach note (`docs/port/phase-N.md`) before editing code. For gates it is the note itself that Ken reviews.
- **Do not fake results.** If something cannot be tested here (real audio hardware, real grids, Ableton, Windows), say so in `STATUS.md` and add it to `docs/port/HARDWARE-CHECKLIST.md` for Ken.
- Keep macOS behavior unchanged. Run the existing macOS-independent tests after every change.
- Licensing: this is GPL-3.0. Do not add dependencies with incompatible licenses; list every new dependency and its license in `docs/port/DEPS.md`.

## Linux definition of done
- Builds from a clean Ubuntu 24.04 container with one documented script.
- Boots norns headless (Xvfb plus a dummy JACK driver), loads a script, and passes the Lua and C tests that do not need hardware.
- Window, device skin, virtual grid/arc/keys, drop and file picker, screenshot/GIF, and MIC/SYS/OFF input are implemented.
- Packaged artifact exists and installs without manual dependency steps.
- `HARDWARE-CHECKLIST.md` lists everything Ken must verify with real hardware.
