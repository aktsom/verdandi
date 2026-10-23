# STATUS

Branch: `linux-port`. Resume rule: read `STATUS.md`, `PLAN.md`, `DECISIONS.md` first.

## Done
- Phase 0 inventory: `docs/port/INVENTORY.md`.
- Gate A decided by Ken: option 1, platform folders in this fork (`DECISIONS.md`).
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

## Test state
`linux/tests/run_all.sh` (about 2 minutes): no unexpected failures at the end of step 5 and in the latest
runs. One run of `boot:headless` failed once and passed on 3 standalone repeats and in later `run_all` runs;
the cause was not found (suspected a timing race at startup). The check now says which condition failed.

## In progress
- Nothing. Phase 2 is complete. Phase 3 has not been started: its approach note
  (`docs/port/phase-3-clock.md`, plus the audio/device parts of Phase 3) comes first.

## Next
- Ken: review `HARDWARE-CHECKLIST.md` (sections after Phase 1, 2 step 4, 2 step 5, clock) and the macOS
  re-verification list at the end of `docs/port/phase-2.md`.
- Then Phase 3 approach note, no code before it.

## Not testable here / notes
- macOS not rebuilt after the edits to shared sources (list in `docs/port/phase-2.md`).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb, no desktop session (portals).
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
