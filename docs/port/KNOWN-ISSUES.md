# Known issues

## 1. `boot:headless` fails when the machine is busy (test race, cause found, fix proposed, not applied)

**Symptom.** `linux/tests/run_all.sh` (check `boot:headless`) sometimes reports, for example:
`missing: engines listed by sclang (crone ready)`, `script loaded with its engine`, `key event`, `encoder event`.

**Stress test** (`linux/tests/stress_boot.sh 36`, 4 CPUs, Ubuntu 24.04 container, this branch at the end of
Phase 2; the whole boot check each time: fresh norns home, Xvfb, jackd dummy, crone, sclang, load a script,
send a key and an encoder event):

| load | runs | passed | failed |
|---|---|---|---|
| idle | 12 | 11 | 1 (run 1, the first run after a pause: cold start) |
| 4 busy loops (one per CPU) | 12 | 11 | 1 (run 21) |
| 8 busy loops (two per CPU) | 12 | 0 | 12 (runs 25-36) |

14 of 36 failed. Every failure is the same early symptom. No failure had a crash, a missing process or an
error from norns, jackd or sclang.

**Cause.** The test does not wait for norns to be ready. `linux/tests/norns_probe.sh` waits for matron's line
`running post-startup`, and `probe_boot.lua` then waits a fixed `#sleep 5` before it asks for the engine list
and loads a script. SuperCollider (class library compile, scsynth start, engines registered) and norns' own
startup (`norns.startup_status.ok`) finish later than that when the machine is busy. Evidence, from the logs
in `docs/port/known-issues-logs/`:
  Checked in all 14 failing logs:
- all 14 have `PROBE engines 0`: when the probe asked, sclang had not reported the engines yet;
- in all 14 that first probe command (log line 151) ran **before** `norns.startup_status.ok` (line 163 in runs
  1 and 21, line 183 in runs 25-36), so the probe started before norns had finished starting;
- 13 of 14 then show `PROBE loaded none nil` (no script, no engine: the load was made too early); run 1 got its
  script loaded (`PROBE loaded probe PolyPerc`) but still had no engines at the probe's first command;
- in all 14 sclang's own log, written later, ends with `>>> /crone/ready` and
  `engines: [ PolySub, SimplePassThru, PolyPerc, TestSine, None ]`: SuperCollider did start correctly, only late.

**Check of the explanation** (scratch copy of `norns_probe.sh`, not the repository): with the probe waiting for
`norns.startup_status.ok` and sclang's `engines: [` before it sends anything, **10 of 10 runs at the heaviest
load (8 busy loops) passed** (22-28 s each), where 0 of 12 passed before.

**Proposed fix (not applied; `linux/tests/norns_probe.sh`)**, apply the same wait in the window and menu
probes automatically because they use this script:

```diff
--- linux/tests/norns_probe.sh
+++ linux/tests/norns_probe.sh (proposed)
@@ -45,6 +45,17 @@
         break
     fi
     sleep 0.2
 done
+# feed commands only when norns has finished starting and sclang has reported the engines (what a script
+# load needs), not after a fixed sleep. up to 90 s.
+n=0
+until grep -q "norns.startup_status.ok" "$LOG" 2>/dev/null && grep -q "engines: \[" "$NORNS_HOME/sclang.log" 2>/dev/null; do
+    n=$((n + 1))
+    if [ $n -gt 450 ] || ! kill -0 $RUN 2>/dev/null; then
+        echo "norns_probe: norns not ready after 90 s, see $LOG"
+        break
+    fi
+    sleep 0.2
+done
 sleep 1
```

Costs: a loaded run takes longer (about 26 s instead of 17 s). The fixed `#sleep` lines in the `.lua` probe files can
stay. The same race very likely exists in `window:` and `menu:` checks (they also start 5 s after post-startup);
they have not failed so far only because they ran on an idle machine. With the fix a failure of the boot check
can still happen if norns really never becomes ready, and the probe then says so.

**Not a product bug as far as these logs show,** but a note for users: loading a script while sclang is still
starting makes the load fail or the engine missing; norns' own start-up loads the last script only after
`startup_status.ok`.

Logs: `docs/port/known-issues-logs/boot-stress-fail-<run>.log` (matron/probe output),
`...-fail-<run>.sclang.log`, `...-fail-<run>.jackd.log` for each of the 14 failing runs, and
`boot-stress-summary.txt` (one line per run).

## 2. crone needs physical JACK ports; PipeWire is not verified (risk found while preparing the laptop guide)

`crone/src/Client.h` (`connectAdcPorts`, `connectDacPorts`) throws "no ADC ports found" / "no DAC ports found"
if the JACK server shows no port flagged `JackPortIsPhysical` (capture and playback). Experiment in this
container: PipeWire's JACK (`pw-jack linux/norns.sh`, `pipewire` and `pipewire-jack` 1.0.5 from Ubuntu, no
session manager, only a null sink and a null source I created) accepted norns' JACK clients, and crone then
stopped with `norns: cannot start audio: no ADC ports found`. This container has no sound devices and no
session manager, so this proves only that crone needs physical-flagged ports and that I could not get such
ports out of a test PipeWire. On a real laptop PipeWire normally exposes the sound card's ports, but whether
they carry the physical flag in the JACK view is **not verified**. See `docs/port/RUN-ON-LAPTOP.md` for what to
try and what to send back, and `docs/port/phase-3.md` for the planned handling.

## 3. Not tested (details in `HARDWARE-CHECKLIST.md`)
ALSA sequencer port of the virtual keyboard; the real XDG file-chooser portal and kdialog; Wayland and any
window manager (only bare Xvfb); the virtual arc turned by dragging the left button; macOS after the shared
source edits; every real device (audio interface, grid, arc, crow, MIDI).
