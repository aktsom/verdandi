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
  3. window (`sdl_bridge.cc` behind `desktop_shell.h`): DONE. The Verdandi window (device skin, oled,
     mouse, computer keyboard as hid keyboard, virtual grid and arc incl. LEDs, deltas, keys) runs
     under Xvfb; `window:` tests in `run_all.sh`.
  4. menu/picker/screenshot/GIF: DONE. In-window menu (right button, F10), file dialogs (portal via GDBus,
     zenity, kdialog), screenshot, GIF, Import, folders via xdg-open, Quit. Tested with a stub zenity and a mock
     portal; the real portal is on the hardware checklist.
  5. "keys" MIDI: DONE. A: internal norns device "Verdandi keys" (click and typed notes reach a script; close and
     reopen work). B: ALSA sequencer port written, runtime-optional, UNTESTED (no /dev/snd/seq here).
  Phase 2 stops here (steps 1-5 done); `HARDWARE-CHECKLIST.md` is updated.
- Clock decisions received and planned (PLAN.md Phase 3 and Phase 7, WISHLIST.md, clock-notes.md 3b-4): SPP/continue, JACK MIDI input, ALSA seq input later, plugin transport. Not started (Phase 3 approach note comes first).

## Next
- See above.

## Not testable here / notes
- macOS not rebuilt after the small edits to shared sources (checklist item).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb.
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
