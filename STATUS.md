# STATUS

Branch: `linux-port`. Resume rule: read `STATUS.md`, `PLAN.md`, `DECISIONS.md` first.

## Done
- Phase 0 inventory: `docs/port/INVENTORY.md`.
- Gate A decided by the owner: option 1, platform folders in this fork (`DECISIONS.md`).
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
- **Phase 3 steps 1-5 are done** (the owner's decisions in `DECISIONS.md`; decision 10 decided: SYS = all apps but norns, the sink monitor
  only as an option). Stopped here as asked: waiting for the owner. Open for the owner: nothing
  pending from my side; the laptop checks of step 5, the metro fix and the MIDI auto-connect are in `HARDWARE-CHECKLIST.md`.
  6. The owner's decisions applied: metro stack fix for the Linux desktop build (256 KiB, correct messages, a failed metro says so;
     test with a TLS-pressure preload: 20 of 20 ticks, was 0); no other fixed-stack thread in the repo; tempo page refresh put on the
     wishlist; MIDI auto-connect built (`midi_in_from=` / `NORNS_MIDI_IN_FROM`, 2 s re-check, status under SYSTEM > DEVICES > MIDI).
     Full run_all.sh: 0 unexpected failures. Stopped, waiting for the owner.
  5. MIC/OFF by physical flag, SYS (every application except norns' own clients), APP by name, optional sink monitor; in-window
     menu lists the applications; tests: `tests/crone/test_input_route.cpp`, `linux/tests/input_test.sh` (fake card and streams).
  Also fixed on real-machine reports (see the three bug fixes in RUN-ON-LAPTOP.md): libmonome waf via `python3`, waf in
     `~/.local/share/waf`, the `pw-jack` re-run by absolute path (test with a pw-jack that really execs).
  4. audio.conf and SYSTEM > AUDIO on Linux (modes jackd / pipewire / jack, restart of our own jackd with the new
     settings, PIPEWIRE_QUANTUM request). Found and fixed: SYSTEM > RESTART/SLEEP never worked on desktop Linux
     (`sudo -n systemd-run` in the sidecar). Details: `phase-3.md` "Step 4 results". Full run_all.sh: 0 unexpected failures.
  3. crone on a desktop: audio-type, physical ports of **one** client only (a physical MIDI port or a second card is
     never mixed in), by name prefix (`NORNS_IN_PORTS`/`NORNS_OUT_PORTS`) else the first card; no physical ports:
     boots unconnected and the warning is on the device window ("AUDIO: not connected, see SYSTEM > AUDIO") and
     in the log; `_norns.audio_status()`. `linux/norns.sh`: JACK server that answers is used; else PipeWire running
     means a re-run under `pw-jack`; else own jackd; `NORNS_AUDIO_SERVER`, `NORNS_JACK_DRIVER` given means own
     jackd; default sink/source from `wpctl` become the prefixes under PipeWire; `audio.conf` `in_ports=`/`out_ports=`.
     Tests: `tests/crone/test_port_select.cpp`, `linux/tests/launcher_test.sh`, `linux/tests/audio_ports_test.sh`
     (fake cards incl. physical MIDI ports; no-ports case). Pi/macOS: crone Client.h change is under
     `NORNS_LINUX_DESKTOP` only.
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

## Clock freeze with SYS under PipeWire + WirePlumber (the owner's bisect: 78eedb02): FIXED
Mechanism and numbers: `KNOWN-ISSUES.md` item 6. Fix applied (option A, desktop Linux only: a backward jump of more than 1 s in JACK's frame time is a new base to follow);
`clock_rate_test.sh` PipeWire flavor is now a normal check (2.000 beats per second with SYS). `NORNS_CLOCK_DEBUG=1` kept and described in `RUN-ON-LAPTOP.md`.
**Follow-ups, the owner to decide:** (1) the accepted forward jump: measured (a transient +1120 beats read for up to one tick, a 10-event `clock.sync` burst followed by a 5 s
gap, one early wake per `clock.sleep` coroutine; the beat counter itself does not advance) and a handling proposed in `docs/port/clock-forward-jump-proposal.diff` (verified in
a scratch copy, not applied); (2) `CLOCK_MONOTONIC` for the internal clock, documented as a follow-up option.
**Default input at boot: MIC** (`_menu.input = "mic"`, identical at 37d244b5 and now; with no saved choice nothing is connected or disconnected at boot). What changed at
78eedb02 is that a **saved choice is restored at boot**: `~/verdandi-home/.norns-input` (SYS, APP or the sink monitor) or `.mic-off` (OFF). Before 78eedb02 SYS/APP did not exist
on Linux, so a SYS choice could not be made or restored. If your laptop's norns home has a `.norns-input` file from pressing the MIC button once (MIC > SYS), it starts in SYS.

## MIDI auto-connect: own ALSA client found by thread id
Fixed after a real-laptop test: ALSA reports the id of the thread that created a client, so norns' own virtual RawMIDI port (`Client-128`, a thread of norns) was linked back into `Verdandi:midi_in`
along with Reaper's. Own clients are now matched against the process id, all thread ids and the ids of processes norns started; tests use a client list as data (no ALSA needed).

## SYS fixes after the owner's laptop test (KNOWN-ISSUES item 7)
Fixed: SYS and APP no longer take capture streams (ports named `monitor*` / `capture*`, a deny-list; Reaper's `ALSA Capture [reaper]:monitor_FL/FR` was feeding the microphone into crone),
and the optional sink-monitor mode now really switches the input monitor off. Tests first (fake capture-stream client, unit cases, `input_monitor_test.lua`). Why SYS is silent at the output
(the input monitor is off in SYS/APP on purpose; recording, sampling and processing work) is explained in item 7.2. **Not built (the owner's decision):** unlinking the applications' direct link to
the sound card (the owner's hand test: an unlinked stream stays unlinked, but a new stream is linked again, so it would need continuous re-checking); revisit after the owner has used SYS for a while.

## Real-hardware findings (the owner's laptop)
Recorded in `HARDWARE-CHECKLIST.md` ("Done on a real machine"): silent run, sound under PipeWire, Reaper clock/notes through the
Midi-Bridge all work; the link from Reaper to `Verdandi:midi_in` was dropped several times (design for auto-connect only).

## Next
- The owner: run the laptop steps in `docs/port/RUN-ON-LAPTOP.md` (untested on a real desktop), review `HARDWARE-CHECKLIST.md` (sections after Phase 1, 2 step 4, 2 step 5, clock) and the macOS
  re-verification list at the end of `docs/port/phase-2.md`.
- Steps 4-5 of `docs/port/phase-3.md` follow (step 5 only after the owner's report).
- macOS: re-verify with the shared-file list at the end of `docs/port/phase-3.md` (clock and device_midi changes).

## Not testable here / notes
- macOS not rebuilt after the edits to shared sources (list in `docs/port/phase-2.md`).
- No `/dev/snd/seq`, no real audio device, no display other than Xvfb, no desktop session (portals).
- `SANDBOX.md` (notification hook) still does not exist; no notification was sent.
