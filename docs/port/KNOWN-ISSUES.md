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

## 2. crone needs physical JACK ports (RESOLVED for the Linux desktop in Phase 3 step 3; text kept as history)

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

## 4. `error code: 22 (Invalid argument) in "pthread_create"` on key presses (found on a real laptop; reproduced; FIXED for the Linux desktop build)

**What prints it.** `matron/src/metro.cc` (`metro_init`, upstream norns code): every metro runs in its own thread created
with `pthread_attr_setstacksize(&attr, PTHREAD_STACK_MIN)`, i.e. a 16 KiB stack. A metro is (re)started with a new thread
each time. `lua/core/keyboard.lua:209` calls `screen.ping()` for every keyboard event, and `screen.ping()` restarts the
screensaver metro (`lua/core/screen.lua`, metro 36): **one thread per key press**. The menu's K1-hold metro (31) and nav
vanish (35) start more of them: several messages per key.

**Why EINVAL.** With glibc 2.34 and later (Ubuntu 24.04 has 2.39) the thread's static TLS block is carved out of its own
stack, so a stack of `PTHREAD_STACK_MIN` is too small as soon as the process's static TLS is more than a few KiB. How
much static TLS the process has depends on the libraries loaded (a desktop with a GPU driver, PipeWire's JACK library,
Qt/GTK pulled in by dialogs) and it can grow when a library is loaded later, which is probably why it is "intermittent" on
the laptop and absent in my headless container. (The Pi, with its old glibc and few libraries, never hits it.)

**Reproduced here** with a preloaded library that adds static TLS (`__thread char big[N]`, `LD_PRELOAD`), nothing else
changed: with N = 12000 and 24000 every metro start prints exactly `error code: 22 (Invalid argument) in "pthread_create"`
(52 messages for 50 `screen.ping()` calls). Without it: 10000 restarts of the screensaver metro, no message.

**Are key events lost? No.** 100 presses of key `3` under xdotool: 100 key-down and 100 key-up events reach the script both
without the preload and with it (403 error messages in the second run). The keys are not affected, only the metro threads.

**But it is not harmless.** A metro whose thread cannot be created **never runs**: a script's `metro.init(...):start()`
with the large TLS preload produced 0 of 20 ticks (20 of 20 without). On the laptop the failing ones are, at least, the
screensaver timer (it is never restarted, so the screen saver can no longer be postponed by keys) and the K1 long-hold
detection of the menu; any script that starts a metro at a moment when the TLS is already large would fail silently too
(`metro_init` returns without telling Lua).

**Fixed (Ken's decision), desktop Linux build only (`NORNS_LINUX_DESKTOP`; Pi and macOS keep the 16 KiB stack and the old
messages):** `metro_init` uses a 256 KiB stack, the failing call is named correctly (`pthread_attr_setstacksize`,
`pthread_attr_setdetachstate`, `pthread_create`), the attribute object is destroyed, and a metro whose thread cannot be
created says so once on stderr: `metro 31 did not start: pthread_create failed, error code 22 (Invalid argument). it will not tick`.
Test: `linux/tests/tls_pressure.c` (the preload library of the reproduction) with `probe_metro.lua`; `run_all.sh`
"metro:a script metro ticks under TLS pressure": 0 of 20 ticks and 23 messages before the fix, 20 of 20 and none after. With a
400 KB TLS block (more than 256 KiB can take) the message appears once per metro.
**Other small fixed-stack threads: none.** `grep` over `matron`, `crone`, `norns`, `linux` and the third-party code for
`setstacksize`, `PTHREAD_STACK_MIN`, `stack_size`: only `metro.cc` sets a stack size. All other threads (clocks, input, hello,
screen events, JACK MIDI reader, file picker, GIF/import workers, asio's threads in Link, `std::thread`) use the default 8 MiB.
`ssd1322.cc` sets a scheduling policy only and is not built on desktop Linux.

Original proposal, as made: in `metro_init` do not set such a small stack: skip `pthread_attr_setstacksize` (the default
8 MiB is virtual memory, 36 metros cost nothing real) or use at least 256 KiB; fix the three error messages that all say
"pthread_attr_init"; and let `metro_start` report a failed thread (print once per metro) so a script's metro that did not start
is visible. Needs a test with the TLS preload (the reproduction above works as a test). Shared file (`metro.cc`): the Pi
keeps working with a larger stack, memory is not an issue there either.

## 5. PARAMS > CLOCK tempo does not refresh on its own with an external clock (investigated; same as upstream)

With `clock_source` = midi (or link, crow) the tempo shown on PARAMS > CLOCK changes only when the cursor is moved.
**This is upstream norns behavior, not specific to this port.** Compared with `monome/norns` main (fetched today):
`lua/core/clock.lua` is identical in the relevant part: a coroutine updates the parameter every second with
`params:set("clock_tempo", external_tempo, true)`: the `true` means "silent", no action and no menu redraw. The params page
(`lua/core/menu/params.lua`) has no `refresh` function (`refresh = norns.none` in upstream too) and no hook on the tempo
parameter, so nothing redraws it; it redraws on input and on a few events (midi learn, rebuilds). The value is also rounded to
a whole number and refreshed once per second at most. A fix would be small (a `refresh` function for the params page, or a
redraw after the silent `params:set` when the tempo changed and the CLOCK page is open) but it changes upstream behavior in
a shared Lua file; not done, waiting for Ken.
