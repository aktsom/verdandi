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
`linux/tests/run_all.sh` (about 2 minutes): no unexpected failures on an idle machine in the latest runs.
`boot:headless` is a **test race under CPU load**: 14 of 36 stress runs failed (0 of 12 at 2 busy loops per CPU).
Cause found (the probe does not wait for norns/sclang to be ready), fix proposed and proven in scratch (10/10
under load) but **not applied**: `docs/port/KNOWN-ISSUES.md`, logs in `docs/port/known-issues-logs/`.
`linux/tests/stress_boot.sh` repeats the check.

## In progress
- **Phase 3 steps 1 and 2 are done** (Ken's decisions in `DECISIONS.md`); **stopped here as asked**. Steps 3-5
  (crone without physical ports, `norns.sh` under `pw-jack`, `audio.conf` under PipeWire, MIC/SYS/APP) wait for
  Ken's laptop output (`docs/port/RUN-ON-LAPTOP.md`, section 4).
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

## Next
- Ken: run the laptop steps in `docs/port/RUN-ON-LAPTOP.md` (untested on a real desktop), review `HARDWARE-CHECKLIST.md` (sections after Phase 1, 2 step 4, 2 step 5, clock) and the macOS
  re-verification list at the end of `docs/port/phase-2.md`.
- Then Ken sends the laptop output; steps 3-5 of `docs/port/phase-3.md` follow (decisions 3, 4, 5 are recorded in `DECISIONS.md`).
- macOS: re-verify with the shared-file list at the end of `docs/port/phase-3.md` (clock and device_midi changes).

## Not testable here / notes
- macOS not rebuilt after the edits to shared sources (list in `docs/port/phase-2.md`).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb, no desktop session (portals).
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
