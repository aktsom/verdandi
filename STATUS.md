# STATUS

Branch: `linux-port`. Resume rule: read `STATUS.md`, `PLAN.md`, `DECISIONS.md` first.

## Done
- Phase 0 inventory: `docs/port/INVENTORY.md`.
- Gate A decided by Ken: option 1, platform folders in this fork (`DECISIONS.md`).
- Phase 1 (headless Linux build and boot): see `docs/port/phase-1.md`.
  - `linux/setup-deps.sh`, `linux/build.sh`, `linux/norns.sh`, `linux/tests/run_all.sh`,
    `linux/tests/norns_probe.sh`; package installs worked in this environment (no blocker).
  - norns builds on Ubuntu 24.04 x86_64 and boots headless (Xvfb, jackd dummy, crone, sclang),
    loads a script, receives key/enc events; 16/16 upstream unit tests, 6 lua tests,
    window_keys and device_skin pass.
  - Two known failures kept for Phase 2: vgrid (libmonome cannot open the pty on Linux) and
    dust_import (copyfile).

## In progress
- Phase 2 approach note written: `docs/port/phase-2.md` (libmonome pty, "norns keys" MIDI,
  dust_import, menu/file picker, sharing `sdl_bridge.cc`, list of Phase 1 shared files for macOS
  re-verification). **Waiting for Ken to confirm the four decisions at its end. No Phase 2 code yet.**

## Next
- After Ken confirms: Phase 2 in the order of `docs/port/phase-2.md` section 6. Starting points: libmonome and the pty, `dust_import` without `copyfile`, SDL window
  using the shared skins, quit handling, ALSA seq "norns keys".

## Not testable here / notes
- macOS not rebuilt after the small edits to shared sources (checklist item).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb.
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
