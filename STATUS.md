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
- Phase 2, steps per `docs/port/phase-2.md` section 6 (decisions in `DECISIONS.md`):
  1. libmonome pty patch: DONE (`c:vgrid` passes).
  2. dust_import portable copy: DONE (`c:dust_import`, also as an ordinary user; macOS `copyfile` path unchanged).
  3. window (`sdl_bridge.cc` behind `desktop_shell.h`), 4. menu/picker/screenshot/GIF,
  5. "norns keys" A + B: not started. Stop after step 5.
- Then (read-only): clock investigation -> `docs/port/clock-notes.md`; wait for Ken's decision.

## Next
- See above.

## Not testable here / notes
- macOS not rebuilt after the small edits to shared sources (checklist item).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb.
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
