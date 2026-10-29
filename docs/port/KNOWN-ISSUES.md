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

**Fixed (the owner's decision), desktop Linux build only (`NORNS_LINUX_DESKTOP`; Pi and macOS keep the 16 KiB stack and the old
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
a shared Lua file; not done, waiting for the owner.

## 6. The internal clock freezes (0.06 beats/s instead of 2) with SYS/APP under PipeWire + WirePlumber (found by the owner's bisect; reproduced; FIXED for the Linux desktop build)

**The owner's bisect:** healthy at 37d244b5 (about 21 beats in 11 s at 120 BPM), slow at 78eedb02 (0.625 beats in 11 s) and everything after.

**Mechanism.** The internal clock's time comes from `jack_client_get_current_time()` (`matron/src/jack_client.cpp`): the 32-bit
`jack_frame_time()` of the client "matron-clock", extended to 64 bits. Under PipeWire that value is the frame counter of the
**driver of the graph the client's node is in**, not a wall clock. All JACK clients share one group (`node.group = group.dsp.0`: norns'
clients and every other application's, seen with `pw-dump`), so when the graph is re-organised (here: SYS links application
streams into crone, which makes the group run under the sound card's / null sink's driver) the counter's base changes. The code
accepts a forward jump and **ignores every backward delta** ("backward jitter"). Measured in the failing run:
`jack frame time jumped by +560.691 s (forward, accepted)` once, then `-503.146 s (backward, ignored)` on every reading for the rest
of the run: the clock's time stands still for the 503 s it takes the new base to catch up with the stored value. The clock thread
(`clock_internal.cc`) sleeps `tick + (next_tick - now)`; with `now` frozen that grows by one tick per tick, so the beat rate falls
off: 0.54 beats in 8 s (0.067 beats/s; the owner: 0.625 in 11 s).

**Why step 5 and not before:** SYS/APP are the first thing in norns that links other applications' ports into crone. MIC and OFF
(and links made by hand from outside) leave the group's driver as it was.

**Reproduction** (private PipeWire + WirePlumber with a null sink as driver, seven fake JACK clients with application-like and
card-like ports, `linux/tests/clock_rate_test.sh`, internal clock at 120 BPM, beats per second over 8 s; expected 2.000):

| build / setup | input at start | beats per second |
|---|---|---|
| 78eedb02..HEAD, PipeWire + WirePlumber | SYS | **0.067, 0.062** (0.54 and 0.50 beats in 8 s) |
| same, with 5 stream clients appearing and vanishing | SYS | 0.067 |
| same | MIC | 2.000 |
| same | OFF (MIC off) | 1.990 |
| same, stream churn only | MIC | 2.000 |
| same, links made by hand from outside | MIC | 2.000 |
| HEAD, PipeWire **without** WirePlumber | SYS (also with churn) | 2.000 |
| HEAD, own jackd (dummy driver) | SYS | 2.000 |
| 37d244b5 (before step 5), PipeWire + WirePlumber | (no SYS there) | 2.000 |
| scratch copy of HEAD with the proposed fix, PipeWire + WirePlumber | SYS | **2.000** |

Not reproduced without WirePlumber (the driver does not change), nor with the dummy driver of jackd; a real sound card driver
and Reaper, as on the laptop, are not available here. `NORNS_CLOCK_DEBUG=1` (a diagnostic added to `jack_client.cpp`, desktop Linux
only, off by default) prints every jump of the frame time: on the laptop it would show whether the same forward/backward pair
happens there.

**Fix (option A, the owner's decision; applied in `jack_client.cpp`, `NORNS_LINUX_DESKTOP` only, macOS and Pi unchanged):** keep the raw frame time of the
last accepted reading separately from the total, and treat a backward jump of more than one second as a **new base** to follow
(the total does not go back, and does not stand still until the old base is reached): `last_raw = current`. Small backward
jitter is ignored as before, wrap-around is unchanged. Verified in a scratch copy: the existing `test_matron_jack_client` cases
pass (4 of 4) and SYS under PipeWire + WirePlumber runs at 2.000 beats per second. A forward jump (the other direction of a
base change) is still accepted: harmless for the clock (its catch-up logic skips ahead), but it moves Link and MIDI-clock
timestamps once; `clock_get_system_time` stays what it is. Wider alternative: take the internal clock's time from `CLOCK_MONOTONIC`
and use JACK time only where audio frames matter. Applied: the PipeWire flavor of `clock_rate_test.sh` is now a normal check in `run_all.sh` (2.000 beats per second with SYS).

**Regression test:** `linux/tests/clock_rate_test.sh` measures beats per second of the internal clock while the input is SYS
(applications linked into crone) in a busy graph: the jackd flavor and the PipeWire + WirePlumber flavor are both normal checks in `run_all.sh`.

**Until it is fixed:** do not use SYS or APP on a PipeWire desktop with WirePlumber if the internal clock matters (MIC and OFF are fine).

### What the accepted forward jump does (measured; NOT fixed, handling proposed)
After the fix a **backward** base change is followed, but a **forward** one (the base jumping up, as the first jump of 560 s in the
failing run) is still accepted as time that passed. Measured with `linux/tests/forward_jump_test.sh` (an `LD_PRELOAD` shim adds 560 s to
`jack_frame_time` once; internal clock 120 BPM; a script with one coroutine on `clock.sync(1)`, eight on `clock.sleep(0.5)`, and a 2 ms metro
that records the largest beat it reads):
- **The beat counter itself does not advance by 1000 beats.** Beats were 16 before and 18.9 one second after the jump, on schedule: the clock
  thread publishes one tick, then its catch-up logic skips ahead.
- **But a reader sees +1120 beats for up to one tick (about 21 ms):** `clock_get_reference_beat` is `reference.beat + (now - last_beat_time) / beat_duration`,
  and `now` is already 560 s later while `last_beat_time` is still the last tick's. The 2 ms metro read at most **1136.96** beats (real: about 17).
- **A burst:** the scheduler thread (1 ms loop) saw that transient value: the `clock.sync` coroutine fired **10 times within about 10 ms** (all with beat 1136.94 to
  1136.96) and then stood still for about 5 s (10 beats) before it ran normally again (events 9 to 18 at 4.00 s, event 19 at 9.05 s). Each of the eight
  `clock.sleep` coroutines woke **once early** (the sleep deadline is in clock time; 8 extra events), then ran normally.
- Handling proposed (not applied; `docs/port/clock-forward-jump-proposal.diff`, desktop Linux only): a forward delta of more than a second that the wall clock
  (`CLOCK_MONOTONIC`) does not explain (more than the elapsed time plus one second) is also a new base: advance by the elapsed wall time and re-base on the new raw value.
  Verified in a scratch copy with the same measurement: no transient (largest beat read 20.17, real 20.17), no burst (sync events every 0.5 s without a gap), no early
  sleep wake-ups (200 sleep events at the end as expected). The first reading at start-up is exempt (the base is taken as it is). The existing unit tests do not run with
  `NORNS_LINUX_DESKTOP`, so they are unaffected.

### Follow-up option, documented (not planned now): `CLOCK_MONOTONIC` for the internal clock
The cleaner long-term version is to take the internal clock's time from `CLOCK_MONOTONIC` and use JACK's frame time only where audio frames matter (Link, MIDI timestamps,
engine sync): then no change of the graph's driver can disturb the clock. It touches how every clock source relates to JACK time, so it is a design step of its own
(shared code: Pi and macOS too), not a patch.

## 7. SYS: a microphone capture stream is taken as an application; and SYS is not heard at the output (the owner's laptop test; 7.1 and the monitor-mode condition FIXED, unlinking NOT built)

### 7.1 Reaper's microphone capture is linked into crone as if it were an application (bug in step 5)
**Observed (the owner):** `PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL/FR` linked to `crone:input_1/2` next to the browser; clapping at the
laptop microphone moved the input and monitor lanes; after closing Reaper it stopped.

**Cause (code):** `crone/src/InputRoute.h`, `listApps()`: an application is "a client with audio output ports, none physical, not norns, not a card". It
looks at the client and at flags only, **never at the port's name or direction of the stream**. In PipeWire's JACK view a *capture* stream (Reaper
reading the microphone through the ALSA plugin) is a client whose output ports are called `monitor_FL/FR` (the signal it receives from the source), not
`output_FL/FR`. It has no physical flag, is not norns, owns no physical port: it passes every test. My unit tests and the fake clients only had
playback-stream clients (`output_*`), so the case was not covered.

**Reproduced here** (`jackd` dummy, fake clients: a card with a 440 Hz tone on its capture ports, a client "Vivaldi" with `output_FL/FR` and 440 Hz, a client
`PipeWire ALSA [reaper]/ALSA Capture [reaper]` whose ports are `monitor_FL/FR` with 440 Hz, SYS chosen): `jack_lsp -c` shows
`crone:input_1` fed by `PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL` **and** `Vivaldi:output_FL`, input 2 likewise with `_FR`: exactly the owner's graph.

**Options (for 7.1):**
1. **Port-name rule (recommended):** SYS and APP take only ports whose name part starts with `output` (playback streams: `output_FL`, `output_1`, `out`...) and never
   ones starting with `monitor` or `capture`. Small, testable (add a capture-stream client to the fake graph and to `test_input_route.cpp`). Weakness: an
   application whose JACK-visible ports have unusual names (a real JACK application with `out_1`, `audio_out`...) would need the rule to be "not monitor/capture"
   (a deny-list) rather than "output" (an allow-list): the deny-list is the safer choice, a playback stream not named `output*` then still works.
2. **Also exclude by client name:** clients whose name contains "Capture" (`ALSA Capture [..]`, `... Input ...`): fragile, translation- and version-dependent. As an addition
   only, not alone.
3. **Ask PipeWire:** `pw-dump` / the node's `media.class` (`Stream/Output/Audio` is playback, `Stream/Input/Audio` is capture) is the exact answer; the JACK API does not expose it
   (only the pretty-name metadata), so it needs a `pw-dump` call (a program per refresh, JSON parse) or the PipeWire API itself (a new dependency): heavier.

### 7.2 In SYS the output lane does not move and nothing is heard from norns (by design of one flag; not a missing connection)
**Cause (code), with evidence:**
- `lua/core/menu.lua:246` (`_menu.set_input`): `_norns.monitor_out(mode ~= "system" and mode ~= "app")`: **in SYS and APP the input monitor is switched off**
  (`o_set_monitor_out(0)` -> `crone_set_enabled_monitor_out(0)`). I put it there, copying the macOS logic, on the reasoning that the application also plays
  directly, so norns must not play it a second time.
- `crone/src/MixerClient.cpp`: with `enabled.monitor_out == false` the ADC monitor is **not mixed into the DAC bus** (`processFx`: `if (enabled.monitor_out) bus.ins_in.mixFrom(bus.adc_monitor...)`
  and not into the reverb send either), and in the tape writer it goes **to the tape only** (`tape_sink = dac_sink + adc_monitor`). So in SYS the dry input is never in the output.
- The lanes: **monitor lane** = `monPeak`, updated from `bus.adc_monitor` every block whether or not it is mixed into the output; **input lane** = `inPeak` (the ADC); **output
  lane** = `outPeak` of `SinkDac`, i.e. what is really sent to the card. So with SYS: input and monitor lanes move, the output lane does not: exactly the owner's observation. In MIC
  the monitor is on, so claps show in the output lane. awake's own audio reaches the output through the engine (`ext_source`), unaffected by the flag, which is why it shows in SYS.
- **Measured** (`jackd` dummy, 440 Hz tone on the card's capture ports and on a browser-like client; default engine; meter values 0..64 as in the MIX page):

  | input | input lane | **output lane** | monitor lane | engine lane |
  |---|---|---|---|---|
  | MIC | 46 | **50** | 46 | 33 |
  | SYS | 40 | **32** | 40 | 32 |
  | OFF | 0 | 24 | 0 | 25 |

  (24 and 25 are the meters' floor with nothing playing; SYS's 32 is only the engine's path, MIC's 50 the monitor on top.)
- **What does work in SYS today:** (1) **recording and sampling**: the input goes to `softcut` (`adc -> cut`), to the tape (`tape_sink` takes the monitor when `monitor_out` is off,
  so tape records the application), and to SuperCollider (`ext_sink = adc_source`); (2) **processing**: an engine or softcut voice that processes the input plays its result through
  `ext_source` / `cut_source` into the output, which is heard (and the output lane moves). The owner's test script (awake) does not process the input, so there was nothing to hear; the
  sound that was heard was the application's direct path to the sound card.
- What is missing is only **hearing the dry input through norns**, and that is off on purpose to avoid the double sound.
- **Related bug found while reading (sink-monitor mode):** `mode ~= "system" and mode ~= "app"` is **true for the optional "monitor" mode**, so the input monitor stays ON there, although
  `HARDWARE-CHECKLIST.md` and `phase-3.md` say it is switched off. With the sink monitor (which contains norns' own output) that is the loop the warning is about. To be fixed
  with whatever is decided below (one condition: add `and mode ~= "monitor"`).

### 7.3 Hearing processed SYS audio without hearing the application twice: options
In PipeWire the browser is a stream linked to the sound card's playback ports (`Vivaldi:output_FL -> Built-in Audio Analog Stereo:playback_FL`, the owner's `jack_lsp -c`). norns also
receives it (a second link from the same port to `crone:input_1`). Hearing the result of processing while the dry sound also reaches the card is the "twice".
1. **Leave as is (today).** Dry sound direct, only the processed/wet part from norns. Right for send-style effects (reverb, delay: dry direct + wet from norns) and for recording/sampling.
   Wrong for effects that replace the sound (pitch shift, filter, granular): you hear the original and the result together. No work.
2. **norns unlinks the application's direct link to the sound card while SYS/APP is on, and plays the dry sound itself (input monitor ON).**
   norns (the "Verdandi ctl" client, which already tracks ports and streams) calls `jack_disconnect(app_port, card_playback_port)` for the applications it takes (all for SYS, the one for APP),
   remembers the links, and puts them back when SYS/APP ends, when norns quits and, as a safety net, in `linux/norns.sh`'s cleanup. This is what the macOS code comment describes
   ("the app is muted while it is tapped: its sound comes out of norns"). The dry sound then goes through norns' monitor path (level and reverb send on the MIX page, tape, engines), so it is
   heard once, with the wet part added by scripts. *Pros:* exactly "process and hear the result". *Cons / risks (not tested on a real machine, no pulse streams here):*
   - **latency:** the application's sound now takes the round trip through norns (one quantum in, one out: about 21 ms each at 1024/48000, lower with `PIPEWIRE_QUANTUM`): a video's picture
     and sound drift apart by tens of milliseconds;
   - **WirePlumber may link it again** (when the stream restarts, the default sink changes, or on its own rescans); norns would have to unlink new links too (a port-connection callback; a race
     with the session manager is possible);
   - **if norns crashes** the links stay removed: the applications stay silent until restored (mitigation: a saved list in the norns home that `norns.sh` restores at start and in its exit trap);
   - the unlink touches other applications' routing: needs to be obvious (a note on the device, "apps now heard through norns") and per choice (SYS = all applications, APP = one);
   - **applications that are not linked to the card** (already routed elsewhere, to Reaper, say) are left alone; a link to a different sink than the card is a choice to respect: only links to the
     card crone plays to are removed.
   Try it by hand first: `pw-jack jack_disconnect "Vivaldi:output_FL" "Built-in Audio Analog Stereo:playback_FL"` (and `_FR`) while SYS is on and the browser plays: if you then hear the browser only
   through norns, and the link does not come back by itself after a minute and a track change, option 2 is viable on your system.
3. **Make it an explicit mode instead of changing SYS:** keep SYS as it is (record, sample, wet-only processing) and add a fourth input mode "SYS through norns" (option 2's behavior), chosen on purpose
   (MIC > SYS > SYS+ > OFF, and in the menu). Safer for users who do not want norns touching routing; the cost is one more mode and a clear name.
4. **A virtual sink instead of unlinking** (`pw-loopback` / a null sink "Verdandi capture" created by norns; the applications are moved to it; norns reads its monitor and plays to the card): robust
   against WirePlumber re-linking, and applications can be chosen per stream, but it changes the default sink and the user's stream routing (pulse `move-sink-input`), needs `pactl`/`pw-cli`/
   `pw-metadata`, and is much more invasive. Not recommended as a first step.
5. **Mute the stream** (`wpctl set-mute`, `pw-cli` volume): does not work: the mute/volume is applied inside the stream node, so the ports norns reads carry silence too.
6. **Lower the application's volume to taste and use wet-only effects**: no code; a workaround for option 1.

**Recommendation:** fix 7.1 now with option 1 (port-name deny-list) plus the fixture and test; fix the `monitor` condition in 7.2; offer 7.3 option 3 (an explicit "SYS through norns" mode with option 2's unlink and restore,
tested first by hand by the owner as above) rather than changing what SYS means. Awaiting the owner's decision; nothing is implemented.

### Decisions on item 7 (the owner) and what was done
- **7.1 fixed (option 1, as a deny-list):** `InputRoute.h` `isDeniedPort()`: SYS and APP skip every port whose name part starts with `monitor` or `capture` (case-insensitive);
  anything else, `output_*` or not, still counts. A client that has only such ports is no application at all; a client with both takes its `output_*` ports only.
  Tests first: the fake graph has the capture stream `PipeWire ALSA [reaper]/ALSA Capture [reaper]` with `monitor_FL/FR` (`fake_card ... capstream`), `tests/crone/test_input_route.cpp`
  has the same client in its desktop fixture plus four new cases, `run_all.sh` checks that neither SYS nor APP is fed by it and that it is not in the app list.
- **Sink-monitor condition fixed:** `lua/core/menu.lua` now switches the input monitor off for `monitor` mode too (`mode ~= "system" and mode ~= "app" and mode ~= "monitor"`). Test:
  `linux/tests/input_monitor_test.lua` (MIC and OFF hear the monitor; SYS, APP and the sink monitor do not; the warning is shown in the sink monitor mode); it failed before the change.
- **Unlinking (7.3 options 2 and 3) is NOT built (the owner's decision).** The owner's hand test on the laptop: a stream whose direct link to the sound card was removed
  (`jack_disconnect`) **stayed unlinked for over a minute and through pause/play**, but **a brand new stream (`Vivaldi-123`) was created with the direct link in place**. So WirePlumber
  does not re-link an existing stream that lost its link, but links every new stream: unlinking would need **continuous re-checking** (a port-registration or port-connect callback
  that removes the card link of each new stream as it appears, with the race against the session manager, plus restoring on exit). Revisit after the owner has used SYS for a while.

## 8. A script's "install missing libraries" (K3) fetched Raspberry Pi binaries and then broke SuperCollider on every start (investigated read-only; nothing built; proposals below)

**What happened (owner's laptop):** the script "twins" offered to install missing dependencies with K3; it appeared to run; the script then said it could not connect to matron; norns
had to be closed. After that SuperCollider failed on every start: `~/verdandi-home/.local/share/SuperCollider/Extensions/supercollider-plugins/` held `AnalogChew_scsynth.so`,
`AnalogDegrade_scsynth.so` and `AnalogLoss_scsynth.so`, "ELF 32-bit LSB shared object, ARM" (`wrong ELF class: ELFCLASS32` in `sclang.log`). Moving the folder away fixed it.

### 8.1 What the K3 install does, and where it comes from (not this repository)
The install is **the script's own code**, not a norns feature. norns itself has no "install dependencies" function: this repository has only the system updater (`lua/core/menu/update.lua`,
`update/update.sh`, for the Pi). The screen "Missing SuperCollider Libraries ... K3: Install" is `lib/installer/installer.lua` of the script (a library that several community scripts copy;
read from the script's public source for this note: `installer.lua`, `twins.lua` line 50:
`installer:new{requirements = {"AnalogChew","AnalogLoss","AnalogDegrade"}, zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}`).
Sequence:
1. **At script load** `Installer:scan()` runs `find` over `/usr/local/share/SuperCollider/Extensions`, `/home/we/.local/share/SuperCollider/Extensions` and `/home/we/dust/code` for, per
   requirement, `<Name>.sc` **and** `<Name>_scsynth.so` (also `<Name>.so`), skipping `*ignore*`. Both halves must be found, else the library counts as missing and the script shows the install screen
   instead of loading its engine (`engine.name = installer:ready() and 'twins' or nil`).
2. **K3: `install_libs()`** builds one shell command and runs it with `norns.system_cmd` (the sidecar, 4 minute limit):
   `rm -rf /tmp/norns-installer/ignore && mkdir -p /tmp/norns-installer/ignore '/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins' && wget -q -O .../bundle.zip '<zip>' && cd ... && unzip -o -q bundle.zip && find . \( -name 'AnalogChew.sc' -o -name 'AnalogChew.so' -o -name 'AnalogChew_scsynth.so' ... \) -type f -exec cp {} '/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins/' ';' && cd /tmp && rm -rf norns-installer`.
   The bundle is **hard-coded to the Raspberry Pi build**; the script does not look at the machine's architecture.
3. **Result check:** it scans again; if nothing is missing it shows "Libraries Installed. Restart to Load the Engine / K3: Restart".
4. **K3 again: `do_restart()`** runs, with Lua's `os.execute` (synchronous, in matron's thread):
   `sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service` and shows "Restarting..." (it never leaves that state by itself).
5. A later "update" path of the same library: `git -C <script> fetch/pull --ff-only` through `norns.system_cmd`, then `norns.rerun()` or the same restart for a changed engine.

I downloaded the release asset to look inside: `PortedPlugins-RaspberryPi.zip` (236 KB) holds `Classes/*.sc` and `*_scsynth.so` files, and `AnalogChew_scsynth.so` is "ELF 32-bit LSB shared object, ARM": exactly the
files on the laptop. (Names I tried for a Linux or x86_64 asset of that release tag, `PortedPlugins-Linux.zip` and three more, return 404; I could not list the release's assets because the API is blocked from here.)

### 8.2 Which steps behave differently on the Linux desktop build
| Step | On the Pi | On this build |
|---|---|---|
| paths `/home/we/...` in the commands | the real folder | translated by `lua/core/virtual_home.lua` (`os.execute`, `norns.system_cmd`) to the norns home: the files land in `~/verdandi-home/.local/share/SuperCollider/Extensions/supercollider-plugins/`, **which sclang and scsynth do read** because `HOME` is the norns home |
| `wget`, `unzip`, `find -printf`, `git`, `nice`, `timeout` | present | present on a desktop (GNU userland); `wget` and `unzip` are not guaranteed (not installed by `linux/setup-deps.sh`) |
| the downloaded Raspberry Pi **binaries** | run | **cannot load on x86_64**: scsynth stops at the first `dlopen` error. Reproduced here: with the three ARM files in place `sclang.log` shows `*** ERROR: dlopen '...AnalogDegrade_scsynth.so' err '...: wrong ELF class: ELFCLASS32'` followed by `Server 'localhost' exited with exit code 0`, no engine registers (`PROBE engines 0`), matron times out and shows `### SCRIPT ERROR: SUPERCOLLIDER FAIL` (`lua/core/startup.lua`): **every start fails until the files are moved** |
| `sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service` | restarts norns (older unit names; a current Pi has `norns-main`/`norns-sclang`) | **there are no such units** (norns is started by `linux/norns.sh`); `sudo` may ask for a password; nothing restarts |
| the restart mechanism that does exist here | `systemctl` units | `_norns.restart()` / `norns.restart`: leaves `.norns-restart` and ends norns, `linux/norns.sh` starts it again (`matron/src/system_cmd.cc`, desktop table); scripts that call `systemctl` themselves bypass it |
| the SYSTEM > UPDATE of norns | updates the system | not available: the "update" action only prints a note (`system_cmd.cc`) |

### 8.3 Why "could not connect to matron" (what the code allows to say, and what it does not)
- **Not a missing OSC or websocket route, not a missing maiden as such:** the install itself never talks to matron; it runs inside it. What can say "cannot connect to matron" is a *client of matron's socket*
  (the `maiden-repl` terminal client, `maiden-repl/src/io.c`: "connection failed", or the script editor/REPL over the websocket on 127.0.0.1:5555), when matron does not answer.
- **The likely cause is the restart step**, which is synchronous and runs `sudo` in matron's own thread (`os.execute`, which `virtual_home.lua` only translates, it does not detach). In `--terminal` mode `sudo` asks for the
  password on the terminal and **blocks matron's Lua thread and event loop** until it is answered or times out (minutes); with a passwordless sudo the command returns at once with "Unit norns-jack.service not found" and
  the script sits on "Restarting...". In either case the window or a connected REPL appears dead, which fits "could not connect to matron" and "norns had to be closed". There is no maiden in the Linux build (the web editor is not built),
  so a web maiden cannot be the source.
- **I cannot prove which of the two it was** without the terminal output of that moment: the exact message, and whether a `sudo` password prompt was on screen. If it recurs, please keep the text.
- Command not available here: yes, `systemctl restart norns-*` (see the table); also `sudo` itself in non-interactive use.

### 8.4 What kinds of scripts work on this build as they are, and what kinds do not
Based on the static scan of the 351-script community catalog made for the macOS port (`macos/docs/02-katalog-scan.md`, `catalog-scan.json`; nothing was executed, so these are expectations, not test results for Linux):
- **Work as they are (about half):** 177 scripts with no shell calls, no `/home/we` paths, only core UGens and no binaries: softcut, MIDI, grid/arc and clock scripts, scripts with the built-in engines (PolyPerc, PolySub ...): 140 scripts use no engine at all, 49 a built-in one.
- **Work with what the build or the package provides (about 40%, category B):** `/home/we` paths (82; translated), POSIX shell commands (`mkdir`, `rm`, `cp`, `curl`, `git`, `find` ... : present on Linux, GNU `stat`, `sha256sum`, `timeout`, `shuf` fine on Linux),
  sc3-plugins UGens (71 scripts: Decimator, SVF, MoogLadder ...: `sc3-plugins-server` is installed by `linux/setup-deps.sh`; mi-UGens (MiRings, MiClouds) and the ChowDSP "Analog*" plugins are **not** in the Ubuntu packages and need x86_64 builds),
  cjson (15 scripts ship a Linux/ARM `cjson.so`; the build registers cjson as the global `_json` but a script's own `require "cjson"` goes through Lua's package search: a bundled ARM `.so` would fail the same way; not checked here),
  engines from other catalog scripts (41; an engine needs the other script installed, as on norns).
- **Do not work as they are:**
  - **Prebuilt Pi (ARM) binaries**, downloaded by an installer or shipped in the repository: the PortedPlugins bundle above, `*_scsynth.so` UGens (FormantTriPTR, PulsePTR, TrianglePTR), `audiowaveform`, `soxgo`, `jack_capture`, `aubioonset` (about 20 repositories). They load or run only on ARM.
  - **System commands of the device:** `sudo systemctl ...` (norns-*), `apt`/`apt-get` (2), `dpkg`, `ldconfig`, `iwgetid`, `powershell`; `pkill` (5 scripts; could match other processes); `jack_connect`/`jack_disconnect` (5 scripts) work only if the port names exist (`system:capture_N` does not under PipeWire).
  - **Hardware:** GPIO keys and encoders are replaced by the window, keyboard and MIDI mapping; the battery gauge, i2c (headphone amp, ADC) and the OLED controller are stand-ins that do nothing (`hardware_null.cc`: battery, i2c and ssd1322 are empty), so scripts that read the battery, set the headphone gain or rely on display hardware settings get no effect.
  - **Wi-Fi/system menu actions and the SYSTEM > UPDATE:** not available.
  - **Hard-coded `/home/we` inside SuperCollider engine files** (`.sc` code): not translated (only Lua file calls and shell command strings are).
- **Category C (25) and D (8)** of the scan (shell commands built at run time, single cases) can only be judged by running them.

### 8.5 Proposals (nothing built; for the owner to decide)
**A. A startup check for plug-ins of the wrong architecture** (like the serialosc and audio notes):
- When: in `linux/norns.sh`, **before** norns and sclang start (the failure is fatal for the whole SuperCollider server, so it has to be known before sclang boots), and again when a script finishes installing (the next start).
- Scan: the SuperCollider extension folders that scsynth reads: `$HOME/.local/share/SuperCollider/Extensions` (that is the norns home), `/usr/local/share/SuperCollider/Extensions`, `/usr/share/SuperCollider/Extensions`, recursive; every `*.so` and `*.scx`.
- Test: read the ELF header (first 20 bytes: byte 4 is the class, 1 = 32-bit, 2 = 64-bit; bytes 18-19 are the machine, 0x3E x86_64, 0xB7 aarch64, 0x28 ARM) and compare with `uname -m`. A file that is not ELF is ignored. A few lines of `od` or a small C tool; testable without root, with fake headers written by `printf`.
- Report: one log line per file, in plain words, with the exact file name and the command that moves it, for example
  `SuperCollider plug-in .../AnalogChew_scsynth.so is a 32-bit ARM file and cannot load on x86_64; SuperCollider will not start with it. Move it away: mkdir -p ~/verdandi-home/.local/share/SuperCollider/disabled-plugins && mv '.../AnalogChew_scsynth.so' ~/verdandi-home/.local/share/SuperCollider/disabled-plugins/`,
  and a standing note on the device window (the same `_menu.show_note` chain: `EXTENSIONS: wrong-architecture plug-in, see log`), plus, if SuperCollider has already failed, the same line next to "SUPERCOLLIDER FAIL" (the symptom `wrong ELF class` in `sclang.log` can be recognised as well).
- **Optional safe quarantine** (off by default; `quarantine_plugins=1` in `audio.conf` or `NORNS_QUARANTINE_PLUGINS=1`): moves, never deletes, each mismatching file **and the sibling `.sc` class files of the same name** (otherwise the script's installer sees half a library and offers the same download again) into
  `~/.local/share/SuperCollider/disabled-plugins/<date>/` with the relative path kept and a `MANIFEST` of what moved, so it can be put back by hand; only under the norns home (system folders are reported, never touched); logged; then sclang starts. Recommendation: **report always, quarantine on request**, because the failure otherwise repeats at every start and the move is reversible.

**B. Could a script update pick the matching architecture?** Not by itself: the bundle URL is fixed in each script, and the installer has no architecture logic. Options, none built:
1. **Provide the plug-ins ourselves** as x86_64 builds (PortedPlugins and mi-UGens built from source, GPL-3, listed in `docs/port/DEPS.md`) in `/usr/local/share/SuperCollider/Extensions`: the installer's own `find` looks there (point 1 above), so the script finds both halves and **never offers the install**: the cleanest fix, no interception, and it also serves the other scripts that need those UGens. Needs a build step in `linux/setup-deps.sh` (and CI), and a decision about which plug-in packs.
2. **A `wget`/`curl` shim** on `PATH` for norns' shell commands (the launcher prepends a `linux/shims/` folder) that recognises known Raspberry Pi bundle URLs and substitutes a matching-architecture bundle when one exists (and refuses with a clear message when it does not). Works for any script that downloads a Pi bundle; needs the x86_64 bundles from option 1 anyway.
3. **Shims for the device commands** the same way: `sudo` passing through, `systemctl restart norns-*` mapped to the launcher's restart (`.norns-restart` + end norns), `apt`/`apt-get` printing "not available on this build". This would also have made K3 "Restart" work here (and not block matron).
4. **Ask the script author** to choose the asset by `uname -m` (the library is shared by several scripts): outside this project.
Recommendation: A (report, quarantine on request) first, then B1 for the plug-ins the catalog needs most, then B3's restart shim. Nothing here is implemented.

### 8.6 What was built from 8.5 (SuperCollider plug-in check, restart shims) and what was decided
**Plug-in check (8.5 A, report only):** `linux/plugin_arch_check` (built by `linux/build.sh`) is run by `linux/norns.sh` **before** norns and sclang start (and at every restart). It reads the ELF
header (class and machine) of every `.so` and `.scx` in `~/<norns home>/.local/share/SuperCollider/Extensions`, `/usr/local/share/SuperCollider/Extensions` and `/usr/share/SuperCollider/Extensions`, and of
`*_scsynth.so` and `.scx` in `dust/code` (Lua libraries such as `cjson.so` live there too and SuperCollider does not read them), and compares with `uname -m`. For each mismatch it prints **one** line
(`norns.sh: SuperCollider plug-in <path> is built for 32-bit ARM, this machine is x86_64: ... stops at the first bad file ... the list of bad files may be longer than the one error in sclang.log ...
mkdir -p '<home>/disabled-plugins' && mv '<file or folder>' '<home>/disabled-plugins/'`); when every plug-in in a folder inside an extension folder is wrong the command moves the folder, else the file. It
**never moves, changes or deletes anything** (the integration test compares checksums). It writes the paths to `<home>/.plugin-mismatch`; matron re-checks only those files (a stat and 64 bytes each)
every 3 seconds and shows the standing note `PLUGINS: wrong-architecture plug-in, see log` (most urgent after the sink-monitor warning, before the serialosc and audio notes) until none is left.
Off: `NORNS_PLUGIN_CHECK=0` or `plugin_check=0` in `audio.conf`. Not done: the quarantine (8.5 A, optional part) and anything about the script's installer. Tests: `plugin_arch_test.cpp` (fake ELF headers as data:
x86_64, 32-bit ARM, aarch64 on an x86_64 machine, x86 32-bit, big endian, non-ELF, empty, short, unreadable, unknown machine), `plugin_check_test.sh` (a fake extension folder: five mismatches, one line each, nothing changed,
the aarch64 view, the switch, after moving by hand), `plugin_note_test.sh` (norns.sh, the log line once, the note, gone when moved, off). **Limit:** SuperCollider stops at the first bad file, so `sclang.log`
shows one error while the list can be longer; a file this check cannot read (permissions) is skipped; a plug-in whose header is fine but whose libraries are missing is not found by it.

**Restart commands from scripts (8.5 B3, smallest safe fix):** `linux/shims/sudo` and `linux/shims/systemctl`, first on the `PATH` of norns itself (matron and so its sidecar and `os.execute`; not jackd or sclang;
`NORNS_NO_SHIMS=1` switches it off). I checked first how commands run here: `os.execute` is Lua's `system()` (`virtual_home.lua` only translates the path), `norns.system_cmd` and the detached actions are
`/bin/sh -c` in the sidecar (`norns/sidecar_shell.cpp`, `sidecar.cpp`), all with the environment norns started with: so a `PATH` shim covers both without touching Lua's `os.execute`.
- `sudo systemctl restart|try-restart|reload-or-restart norns-*` and `systemctl ...` the same: a restart **request** (`~/.norns-request-restart`), exit 0 **at once**, one line on stderr saying what was done and why. Lua (`lua/core/menu.lua`, the 3 s metro) takes
  the request and calls `_norns.restart()`, the clean restart that already exists (state saved, `linux/norns.sh` starts norns again). If nobody takes the request within `NORNS_SHIM_WATCHDOG` seconds (default 20) the
  shim does what `_norns.reset` does itself (`.norns-restart` and an end signal), so a stuck matron is restarted too. The background job holds none of the caller's pipes.
- `start|reload|enable` of a norns unit: nothing to do, exit 0 with a line; `stop|disable|kill`: refused with a line, exit 1 (close the window instead).
- any other `sudo` command: the real `sudo -n` (never a password prompt that blocks matron's thread; an own `-n` is not doubled); any other `systemctl` command, also with sudo, goes on unchanged to the real programs.
- Tests: `shim_test.sh` (fake real programs: restart variants and options, start, stop, other units, other sudo commands, no doubled `-n`, the watchdog fires and does not fire, the output pipe closes at once), `shim_restart_test.sh`
  (headless norns: the sidecar sees the shims, `os.execute("sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service")` returns in 0.0 s, one shim line, Lua takes the request, `linux/norns.sh` restarts norns and sclang, crone is back).
- **Decision taken (shall be confirmed): shims for these command strings, not a global `os.execute` interception.** A global interception in Lua (replacing `os.execute`/`io.popen` for every script) would also catch commands the
  shims cannot (an absolute `/usr/bin/sudo`, `sh -c "sudo ..."` with a changed `PATH`), but it changes every script's shell calls, hides what runs, and does not cover the sidecar; the `PATH` shims touch only these two names.
  Not covered: a script that calls `/bin/systemctl` or `/usr/bin/sudo` by absolute path, or one that clears or replaces `PATH`. Also not built: `apt`/`apt-get` shims, a `wget` shim, x86_64 plug-in bundles (8.5 B1, B2).

## 9. Centered text with an odd ink width looks squished or blurred (cairo 1.18 draws glyphs at fractional positions; found on the laptop; FIXED for the desktop builds)

**Symptom:** centered headers on PARAMS pages ("modulation", "track 6 options", "track 1 filter", "link") look squished and bolder, letters running together; "midi clock out" is clean; left- and right-aligned
lines are clean; the OLED screenshot shows it too (so it is in the drawing, not in the window scaling).

### 9.1 How the text is drawn here, and how it differs from the device
- `matron/src/hardware/screen.cc` is **identical to upstream norns** (`diff` against `monome/norns` main: no difference). The drawing: an ARGB32 image surface of 128 x 64; `screen_init` sets `CAIRO_ANTIALIAS_SUBPIXEL`,
  then `init_font_faces` replaces it with `GRAY`, and every script load calls `screen.aa(0)` (`lua/core/script.lua:133`), i.e. **`CAIRO_ANTIALIAS_NONE` for text** (the menu panel indicator uses `screen.aa(1)`, gray, `lua/core/menu.lua:541`). No other font
  options are set: hint style and hint metrics stay at cairo's defaults, there is no scaling and no surface conversion on the way (the desktop window paints the same 128 x 64 surface; `screen_export_screenshot` copies it 4x).
- The default font is `resources/norns.ttf` (a pixel font, 8 px) for body text **and** headers: no different face or size for headers, and one `cairo_show_text` per string (no doubled draw).
- **`screen_text_center`** is `cairo_rel_move_to(cr, -extents.width * 0.5, 0); cairo_show_text(...)`: `extents.width` is the **ink width** of the string. **`screen_text_right`** is `-extents.width`. For this font the ink width is a whole number
  of pixels, so right-aligned text starts on a whole pixel (x is a whole number in scripts); centered text starts at `x - width/2`, **which is `.5` whenever the ink width is odd**.
- The device and this build run the **same code**; what differs is **cairo**. This build uses cairo **1.18.0**. cairo 1.16 (what a Raspberry Pi image of the norns era ships) places every glyph on a **whole pixel** (the origin is rounded); a newer
  cairo draws the glyph at the **fractional position** it is given (sub-pixel glyph positioning). I could not fetch the device's cairo; I unpacked Ubuntu's `libcairo2` **1.16.0** package and ran the same program against it (below).

### 9.2 Reproduction and evidence
Harness `docs/port/repro/text_center.c` (the code's surface, font, options and `text_center`, nothing else), and `linux/tests/scripts/text_probe.lua` run in the real norns (`screen.export_screenshot`). Centre x = 64.
Ink widths: "modulation" 43 (odd), "track 6 options" 65 (odd), "track 1 filter" 53 (odd), "link" 13 (odd), "midi clock out" 56 (even), "tempo" 24 (even).

Pixels of "modulation" (the five glyph rows; the same strings and positions in all three) (start x = 64 - 21.5 = **42.5**), `.` empty, `#` full, `-`/`+`/`:` partial:
```
cairo 1.18, aa none (what a script gets)
.................##.....##......##.##..............
...#####..###..######.####.########...###.####.....
...########.####.####.######.##.##.####.####.##....
...########.####.####.######.##.##.####.####.##....
...######.###..####.######.####..####.###.##.##....

cairo 1.18, aa gray
.................--.....--......--.--..............
...-###-..-#-..-##---.----.-##--##-...-#-.-##-.....
...--------.----.----.------.--.--.----.----.--....
...--------.----.----.------.--.--.----.----.--....
...------.-#-..-##-.-##---.-##-..----.-#-.--.--....

cairo 1.16.0, aa none (gray gives the same)
..................#......#.......#..#..............
....####...##...###.#..#.#..###.###....##..###.....
....#.#.#.#..#.#..#.#..#.#.#..#..#..#.#..#.#..#....
....#.#.#.#..#.#..#.#..#.#.#..#..#..#.#..#.#..#....
....#.#.#..##...###..###.#..###...#.#..##..#..#....
```
The screenshot taken by the real norns (`screen.export_screenshot`, 4x) of the same strings shows the same doubled columns for the odd widths and single columns for the even width, with only the values 0 and 255 (the `aa(0)` state of a script).
Count of grey pixels (neither empty nor full) with `gray` anti-aliasing at centre 64: modulation 126, track 6 options 148, track 1 filter 124, link 48, clock 54 (all odd ink widths), **0 for "midi clock out" and "tempo" (even)**.

Same strings, other options (cairo 1.18): hint style none with hint metrics off, and hint style full with hint metrics on: **no change** (anti-aliasing subpixel was not run): the artifact is not a hint option. With `aa none` the stroke is doubled instead of grey.
Starting the string at a whole pixel (rounding the centre) removes it in every option: grey count 0 and the strokes one column wide for all strings.

### 9.3 Cause
**A fractional x from centering (`-ink_width * 0.5`, `.5` for every odd ink width) combined with cairo 1.18's sub-pixel glyph positioning.** On the device's cairo 1.16 the glyph origin is rounded to a whole pixel, so the same `.5` is harmless (the string
lands on column 43 for start 42.5, round half up); here the glyph outline is rasterised at the half-pixel offset: grey in the anti-aliased case, a doubled stroke with `aa(0)`. That is why only centered lines with an odd ink width show it
(right-aligned and left-aligned lines start on whole pixels; "midi clock out" has an even width). Not the cause (each checked above): antialias / hint options, scaling or surface conversion, a doubled draw, a different font face or size.
The same would affect **macOS** (cairo from Homebrew is 1.18 too); the code is shared.

### 9.4 Smallest fix (proposed, NOT applied)
In `screen_text_center` snap the start to a whole pixel the way cairo 1.16 did, instead of passing a half pixel to cairo:
```c
void screen_text_center(const char *s) {
    cairo_text_extents_t extents;
    cairo_text_extents(cr, s, &extents);
    double x, y;
    cairo_get_current_point(cr, &x, &y);
    cairo_move_to(cr, floor(x - extents.width * 0.5 + 0.5), y);   // was: cairo_rel_move_to(cr, -extents.width * 0.5, 0)
    cairo_show_text(cr, s);
}
```
This reproduces the device's output exactly for whole-pixel x (round half up: start 42.5 becomes 43, as cairo 1.16 drew it; verified against the 1.16 library, 0 grey pixels, same columns). A more general version
snaps the current point (x and y, round half up) in `screen_text`, `screen_text_right` and `screen_text_center` before `cairo_show_text`, which also covers scripts that pass fractional x or y to `screen.move` (cairo 1.16 snapped those too); it
would be guarded for the desktop builds (Linux and macOS, where cairo is new) so the device code stays byte for byte as it is. Test (to write first): a C test that draws odd and even widths centered at x = 64 and asserts no pixel is partial with
`aa none` and `gray`, and that the leftmost column of "modulation" is 43. Not covered: text drawn with `screen.text_extents` based manual centering in a script (it passes `x - w/2` itself and has the same half pixel: the general snap would fix it as well).

### 9.5 The general fix, applied (desktop builds only)
`matron/src/hardware/screen.cc`: `snap_text_start()` rounds the start of the text, x and y, **half up to a whole pixel** (what cairo 1.16 does on the device) in `screen_text`, `screen_text_right`, `screen_text_center` and `screen_text_trim`
(which also draws text). The centered and right-aligned offsets are applied before the rounding (`x - width/2`, `x - width`). It is guarded by `NORNS_DESKTOP` (Linux and macOS builds, where cairo is new): **the device code is untouched**: the
preprocessed `screen.cc` without `NORNS_DESKTOP` is identical to the one before the change (compared, 9840 lines, no difference). A text with no current point is left alone (as before).
**Test first** (`linux/tests/screen_text_test.cc`: the real `screen.cc` compiled into the test with stubs; reference images are plain cairo at the position the device would use; pixel-exact comparison of the whole 128 x 64 surface, `aa` none and gray):
on the code before the change the desktop variant failed 3 of 6 cases, 30 of 169 assertions (odd-width centered strings "modulation", "track 6 options", "track 1 filter", "link": start 42.5 instead of 43 and so on; fractional starts from a script; the leftmost
column of "modulation" was 42, expected 43), while the even-width, left-aligned and right-aligned cases passed; after the change all 6 cases (169 assertions) pass, and the device variant (no `NORNS_DESKTOP`: text starts exactly where it is asked to,
also at fractional positions) passes both before and after (2 cases, 49 assertions). Both run in `run_all.sh`.
**Do bundled or common scripts draw text at fractional positions?** Looked at: the core Lua (`lua/core`, `lua/lib`) and 12 community scripts' source (awake, twins, oooooo, barcode, amen, blndr, clcks, glitchlets, kolor, mx.samples, rachim, zxcvbn; 59 text calls, 9 centered, 9 right-aligned):
- Of the `screen.move` calls directly before a text, 32 use whole-number literals, **none** has a decimal literal or a division, 27 use variables or expressions (loop counters, layout variables: not evaluated, not seen to be fractional).
- The core: `lua/lib/ui.lua` (the tab bar, `Tabs`) moves to `MARGIN + col_width * 0.5 + ...` and centers there: with two titles `col_width` is 49 and the centre is `24.5`, a half pixel **before** the centering; its text now lands on the whole pixel the device drew. `lua/lib/graph.lua` has `+ 0.5` moves, but for **lines** (strokes aligned to pixel centres), not text: unchanged.
  Every PARAMS/menu page that centers a header (`screen.text_center`) is affected, for the better: odd widths are now crisp.
- **Effect on how things look:** integer positions are byte for byte as before (tested). Where a text started at a half pixel (centered text of odd ink width, a script's fractional x or y, the two-title tab bar) it is moved by at most half a pixel (round half up) and drawn crisp, as on the device with cairo 1.16;
  nothing else changes. A script that **relies on** the newer cairo's smooth half-pixel placement (animated text moving by fractions of a pixel) would now move in whole-pixel steps, as it does on the device. The sample of scripts shows none that do.
**Not verified:** macOS (the guard includes it; it was not built or run here), and a real device (the 1.16 behavior was checked against Ubuntu's cairo 1.16.0 library, item 9.2).

## 10. A web page in the browser can reach the REPL websockets (and maiden's API) on 127.0.0.1: the same exposure exists on the Mac port (found while planning maiden on Linux; FIXED for the Linux build only)

Evidence and the test: `docs/port/maiden-exposure-evidence.md`.

- The REPL ports 5555 (matron) and 5556 (sclang) are `ws-wrapper` websockets on `127.0.0.1`. Binding to the loopback keeps other computers out, but **any web page open in the owner's browser** can open
  `ws://127.0.0.1:5555`, because browsers do not apply the same-origin rule to WebSockets and `ws-wrapper` did not look at the `Origin` header. What the page sends is run by matron as Lua (`os.execute` and
  everything else a script can do), as the user, while norns runs. maiden has the same property for its HTTP API (no check of `Host` or `Origin`): a cross-site request can install a script into dust, and DNS rebinding can read and write dust.
- **The Mac port is the same**, because `macos/norns.sh` starts `ws-wrapper` and `maiden server --host 127.0.0.1` in the same way. Nothing was changed there (the owner said not to touch `macos/`). What the Mac would need, if the owner decides to:
  set `WS_WRAPPER_ALLOWED_ORIGINS="http://127.0.0.1:5000,http://localhost:5000"` in `macos/norns.sh` for the two `ws-wrapper` lines (the code is in the shared `ws-wrapper/src/main.c` and ignores the variable when unset), and apply
  `linux/patches/maiden-linux-guard-and-units.patch` (its guard half; the unit API half is Linux specific) in `macos/setup-deps.sh`. Not built or tested on the Mac.
- Linux: `linux/norns.sh` sets the origin list for both `ws-wrapper` lines and builds maiden with the guard (see `phase-4-maiden.md`).

## 11. Libraries that locate themselves with `debug.getinfo(1).source` and `_path.code` failed ("attempt to concatenate a nil value (local 'mydir')"); found on the laptop with Cheat Codes 2 (nb); FIXED

- **Symptom:** Cheat Codes 2 does not load: `lib/nb/lib/nb.lua:2: attempt to concatenate a nil value (local 'mydir')`. nb.lua line 1 is `local mydir = debug.getinfo(1).source:match("@?" .. _path.code .. "(.*/)")`.
- **Cause:** `lua/core/virtual_home.lua` shows scripts `/home/we` (`_path.code` is `/home/we/dust/code/`) and translated paths to the real home only where they leave Lua, but its `loadfile` and `dofile` (and `require`'s searcher, which used `loadfile`) simply passed the **real** path on to Lua's own `loadfile`. Lua names a chunk after the file it was given, so
  `debug.getinfo(1).source` was `@/home/<user>/verdandi-home/dust/code/...`, the pattern with the virtual `_path.code` did not match and `mydir` was `nil`. On the device HOME really is `/home/we`, so both agree. Reproduced first, as a Lua test (`known-issues-logs/chunkname-before.txt`: the same error from the fake script) and on a real boot (the script's `source` was the real path and `mydir` nil).
- **Fix** (`lua/core/virtual_home.lua`): `loadfile`, `dofile` and the `require` searcher read the real file but name the chunk with the **virtual** path (`@/home/we/dust/code/x.lua`), by reading the file and calling `load(text, "@" .. virtual_path, mode, env)`. `include` needs no change: it calls `dofile`.
  It keeps what Lua's `loadfile` does: a first line starting with `#` is skipped (the newline stays, so line numbers hold), a UTF-8 byte order mark is skipped, `mode` and `env` are honored (an explicit nil `env` as well), a missing file returns `nil, "cannot open <path>"` (`dofile` raises it), binary chunks load, `loadfile()`/`dofile()` without a name read the standard input. `require` also hands the virtual file name to the chunk as its second argument (what the device gives).
- **Options considered.** (a) the chosen one, `load` with a virtual chunk name: smallest, and `debug.getinfo(n).source`, `short_src`, tracebacks and error messages all show what the device shows. (b) A debug hook or `debug.getinfo` wrapper that rewrites `source` on the way out: slower, touches every call, and still leaves tracebacks and error messages real. (c) Give scripts a real `/home/we` through a mount or user namespace: needs privileges and changes the whole process. 
- **Risks and what changes for the owner:** error messages and tracebacks now show **virtual** paths (`/home/we/dust/code/x.lua:12: ...`), as on the device and in every script's documentation and forum post; the real location is the one printed once at the start of the log (`virtual /home/we -> <real home>`). That seems acceptable to me; if both should show, a debug switch could append the real path to script load errors. Not built; the owner decides.
  A chunk loaded by C (matron's own startup files) keeps its real name: it is not a script. The change is in shared code (`lua/core/virtual_home.lua` is used by the macOS app too, with the same effect there; `macos/` is untouched and the macOS test `macos/tests/virtual_home_test.lua` still passes here; not run on macOS).
- **Other habits checked** (nothing in the Lua core depends on a chunk name; `lua/lib`, `lua/core` and `lua/extn` have no `debug.getinfo` or `.source` use except `norns.try`'s traceback): `norns.state.path`, `norns.state.lib`, `norns.state.data`, `_path.code` are strings built from the virtual path and unchanged; the "folder of this file" idiom
  `debug.getinfo(1,'S').source:sub(2):match('(.*/)')` now gives the virtual folder, which `io.open`, `io.lines`, `os.execute` and `popen` translate (tested: a file beside the script opens); `tab.load`/`loadfile` of data files work as before; `package.loaded` keys are unchanged. Not checked: scripts of the catalog beyond these patterns (there is no list of them here that shows source paths).
- **Tests** (`run_all.sh`): `linux/tests/virtual_chunkname_test.lua` (fake script and libraries in `lib/` and `lib/deep/`, include and dofile with a path built from `mydir`, loadfile and require, shebang, BOM, env, mode, binary chunk, error text, and the real nb library from github.com/sixolet/nb when it can be fetched: `require "nb/lib/nb"` through the script's lib path, `include` of `cheat_codes_2/lib/nb/lib/nb`, nb's own relative include of `lib/player`);
  and `linux/tests/chunkname_test.sh` (a real boot: norns loads a script whose libraries find their folder the same way, with the real nb included by its path and required from dust/code). Before the fix both fail with the reported error.
- **Not verified:** Cheat Codes 2 itself (not fetched here; only nb, its lib), a real norns device, macOS.

**Output format, changed later (plug-in check):** one line **per folder** instead of one per file (a script's installer drops a dozen plug-ins in one folder): the folder, each bad file with what it is, the machine, why SuperCollider fails, one move command for the folder (the folder itself if every plug-in in it is wrong, else the bad files together), how to turn the check off. Same information; the device-window note and the 3-second re-check
are unchanged (the list file still has one path per file). Tests: `plugin_arch_test.cpp` (grouping and the line) and `plugin_check_test.sh` (seven bad files in four folders: four lines, two bad files and a good one in one folder, one in another).

## 12. Two AUv3 instances in one project corrupt each other's audio silently (macOS port; read in the code, **not run**; NOT changed)

Details and line references: `docs/port/multi-instance.md` section 1. Found while investigating several plug-in instances; `macos/` and the AUv3 were **not touched**.
- There is **one** `auv3_bridge` (one JACK client `auv3`, one UDP socket on `127.0.0.1:10200`) and **one** audio adapter. Every plug-in instance connects to the same port: the port is compiled into the plug-in (`NB_PORT`; the bridge reads `NORNS_AUV3_PORT`, the plug-in does not).
- The bridge answers each audio packet to its sender, so both plug-ins look connected, but it pushes both streams into the same adapter: norns' input is the two tracks' blocks interleaved, and each plug-in receives every other block of norns' one output (**expected** from the code: chopped, mixed audio; not heard, there is no Mac here).
- A stop (`NB_BYE`) from either plug-in deactivates the bridge for both until the next audio packet; MIDI from both goes into one CoreMIDI source ("Verdandi AUv3"); a different sample rate flips the adapter back and forth.
- The protocol has no instance id and no way to refuse a second client, so the plug-in cannot tell the user. **Nothing is shown**: this is silent.
- Owner's decision (multi-instance note): the Linux VST3 gets a one-instance guard with a message from the start (`linux-vst3.md`); the AUv3 keeps its behaviour until the owner decides to change it (the fix would be the same guard: first sender wins, others get a "busy" reply and the plug-in shows it; a settable port on the plug-in side).

## 13. A script's global `refresh()` was never called on the desktop screen (scripts that draw in `refresh()`, e.g. eterna, did not update); found on the laptop; FIXED for the Linux build only

**Symptom:** after grid actions the screen of the script `eterna` did not update; F5 twice (menu and back) or typing `redraw()` redrew it once. Timers and clocks were fine.
**What upstream does** (monome/norns, checked against a shallow clone of the current upstream, and the November 2023 update "231114"): `matron/src/hardware/screen/ssd1322.cc`, the **SPI display thread**, loops at 60 Hz (`clock_nanosleep` 16 666 666 ns) and every round, whether or not the display is dirty, posts **`EVENT_SCREEN_REFRESH`**; `events.cc` handles it on the Lua thread with `w_handle_screen_refresh()` (`weaver.cc`), which calls the **global `refresh`** (`lua_getglobal(lvm, "refresh")`, protected call). On the Lua side `core/menu.lua` defines `refresh = norns.none`; `core/script.lua` clears it with the script (`refresh = norns.none`), stores the script's own `refresh` in `norns.script.refresh` and blocks it until `Script.init`; `menu.lua` swaps it with the menu mode (none in the menu, the script's again on return).
**What differs here:** nothing in that chain, **except its start**. The event handler, `w_handle_screen_refresh` and the Lua side are identical to upstream (this repository's copy is the upstream code). The only thing that posts `EVENT_SCREEN_REFRESH` is the `ssd1322` thread, and the desktop screen backend (`hardware/screen/sdl.cc`, `screen:sdl`) has no such thread and never posts it. So on the desktop `refresh()` was never called (the Mac app has the same gap; not touched, see below). A headless test reproduced it: a script whose `refresh()` counts its calls stayed at **0** over three seconds.
**Fix (Linux build only, `#ifdef NORNS_LINUX_DESKTOP` in `sdl.cc`):** `screen:sdl` starts a small thread when the screen is set up that posts `EVENT_SCREEN_REFRESH` every 1/60 s (absolute times, so the rate does not drift) and stops and joins it when the screen is destroyed. The call itself still happens on the **Lua thread** through the event queue, exactly as on the device; the screen thread only posts the event. The Lua code is unchanged, so a script without `refresh()` gets `norns.none` (no call into the script, no error), the call stops when the script is cleared or replaced, and the menu mode swaps it as before.
**Test:** `linux/tests/refresh_test.sh` (in `run_all.sh`): a script whose `refresh()` counts and draws is called **180 times in 3 s** after the fix (**0** before); after another script replaces it and after `norns.script.clear()` the count does not move and `refresh == norns.none`; a script without `refresh()` is unaffected and there is no Lua error in the log.
**Scripts affected** (a search of the 351 community catalog repositories listed in `macos/docs/catalog-scan.json`, shallow clones, for a global `function refresh()` at the start of a line): **14**: asterion, plasma, ashsynth, forge, acrostic, marcovaldo, lamellae, giro, bloom, lemniscate, magpie, esper, **eterna**, dreamsequence. (Methods such as `Grid:refresh()` are not this hook and were not counted; I did not read each script to see how much of its drawing depends on `refresh()`; I did not search scripts that are not in that catalog scan or the owner's own `dust` folder.)
**The Mac app has the same gap and is NOT changed** (the owner asked not to change Mac behaviour): `sdl.cc` is shared, so the fix is behind `NORNS_LINUX_DESKTOP`; whether the Mac should post the event too is the owner's decision.

## 14. A real grid keeps its LEDs after a script change and ignores commands from the Lua prompt (found on the laptop, grid 128 over `ttyACM`, serialosc not running); mechanism found and fixed, NOT confirmed on the hardware

**Symptom:** after awake was left or another script loaded, the grid kept showing awake's LEDs; `g = grid.connect(); g:all(0); g:refresh()` and `g:led(1,1,15); g:refresh()` from the prompt did nothing; unplug and replug cleared it. During the same session awake's pattern had appeared and the keys had worked.
**1. What norns does when a script is cleared:** `Script.clear()` (`lua/core/script.lua`) calls `grid.cleanup()` (`lua/core/grid.lua`), which for **every** device does `dev:all(0)` and `dev:refresh()`, then drops the key and tilt callbacks. `refresh` → `_norns.monome_refresh` → `dev_monome_refresh` (`matron/src/device/device_monome.cc`) → one `monome_led_level_map` per dirty quad (two for a 16x8 grid, at x offsets 0 and 8). **This Lua code, `device_monome.cc`, `device.cc`, `device_list.cc` and `device_monitor.cc` (except the Linux keyboard and JACK MIDI additions) are identical to upstream monome/norns** (diffed against a shallow clone of upstream). The desktop build adds no thread or lock here and no virtual layer in front of a real grid: the virtual grid is a separate device on its own vport.
**2/3. Headless reproduction of the whole path: it is correct.** `linux/tests/grid_led_test.sh` runs norns with the virtual grid (a pseudo terminal that libmonome opens exactly like a serial port) and an `LD_PRELOAD` shim (`write_log.c`) that records every write to a `/dev/pts` device. Result: a script lighting LEDs writes its maps (first level byte `0xf0` for the key at 1,1 at level 15; `07` in the last byte for 16,8 at level 7); a **script change writes all-zero maps for both halves** (x=0 and x=8); `g:led(1,1,15); g:refresh()` and `g:all(0); g:refresh()` from the prompt write the matching maps; no write is short. So on this build the Lua → matron → libmonome chain sends the clear and the prompt commands.
**4. What the device receives (mext protocol, recorded):** after the handshake bytes `00` (query), `01` (get id), `05` (get grid size), every LED update is a `monome_led_level_map`: `1a x y` and 32 bytes of packed levels (two LEDs per byte, high nibble first): 35 bytes per quarter, `1a 00 00 f0 00 …` for the top-left key at 15 and `1a 08 00 …` for the right half; a clear is two such messages with zero levels. That is the documented monome serial protocol (address 1 = LED grid, command 0xA = level map). The tool for the real device: `NORNS_MONOME_TRACE=1 verdandi --terminal 2> trace.txt` lists every write to and read from the grid (hex, with times, from the libmonome patch below).
**Cause (a mechanism that fits every symptom, found in libmonome; not proven on the hardware):** libmonome opens the port `O_NONBLOCK` and `monome_platform_write` did one `write()`; when the port's buffer had no room it returned `EAGAIN` or took part of the bytes, and libmonome **dropped the rest** ("error in write: Resource temporarily unavailable" / "write is missing bytes" on stderr). A cut-off message makes the grid read the start of the next one as the rest of the first, so it ignores or garbles everything until it is reset by unplugging: LEDs stuck, prompt commands without effect, keys still working (the device keeps sending). Reproduced with a pty that stops reading for 300 ms (`linux/tests/monome_write_test.c`): **before** the fix `EAGAIN` errors, none of the last maps arrived and **22 bytes of a message were left half read**; **after**, all arrive whole.
**Fix:** `linux/patches/libmonome-write-retry.patch` (applied with the pty patch by `linux/setup-deps.sh` and `linux/package.sh`; the build is redone when a patch changes): a write waits (poll, up to a second) for room and writes the rest, says in the log if it still could not; plus `NORNS_MONOME_TRACE`. The package ships this libmonome.
**What I could not check, and what differs from the laptop:** the real device (a CDC-ACM serial port with a USB device behind it, real timing and buffer sizes). I cannot say that the laptop's grid hit this path: why a port that takes 35-byte messages at an ordinary redraw rate would be full is not shown (candidates: something else writing to the same port, for example ModemManager probing a new `ttyACM` device, or a second open of it; a burst while the script changed; the earlier raw reads from another program). If the problem stays after the new package: run `NORNS_MONOME_TRACE=1 verdandi --terminal 2> trace.txt`, plug the grid in first, do the awake → other script sequence, and send the file together with `grep -i libmonome` of the terminal output, `systemctl status ModemManager`, and `udevadm info /dev/ttyACM0 | grep -i ID_`.

## 15. norns closed itself (SIGSEGV in the `watch_loop` thread) when a device event arrived for a device without a "product" name; found on the laptop (coredumps); FIXED for the Linux build, the pattern fixed elsewhere too
- **Evidence:** nine norns crashes in `systemd-coredump`; the backtrace of the thread: `strlen` <- `strdup(NULL)` <- a function at offset `0x6b36f` of the norns binary <- `start_thread`. Matching: I built the commit of the laptop's build (b5c7226) and resolved the offset: it is the **return address of the `strdup` call** in `watch_loop` (`device_monitor.cc`; `get_device_name` inlined, right after the loop over `udev_device_get_parent`), 0x6b36a calls `strdup`, 0x6b36f follows. The reported `dev_monome_start` offset (0x6b9f1) is within 0x11 of the one in my build (0x6b9e0), the package binary differs by a few bytes. I did not have the laptop's binary or core dump itself.
- **Mechanism:** `get_device_name` walks the device and its parents for the udev attribute `product` and returned `strdup(current_name)`; for a device with no `product` anywhere (a lid switch, a speaker, a headphone jack, a platform device) it is NULL. The monitor thread gets events for **every** device of the subsystems `tty`, `input` and `sound` (also `change` events, not only plug-ins; the first scan only takes USB devices), so any such event killed norns, at idle too, whenever the desktop or a USB device (grid, mio) produced one.
- **Fix:** a name is always given (the model property, else "unknown", with a log line); `get_alsa_midi_node` checks subsystem, syspath and `opendir` (it called `readdir(NULL)`, and leaked the directory); the same NULL checks, nothing else changed, for `strdup` of: the monome's friendly name and serial (`device_monome.cc`), the serial handler id (`device_serial.cc`, `device_list.cc`), the serial device name (`weaver.cc`), the OSC path, host and port (`osc.cc`), the maiden message (`maiden-repl/msg_queue.c`). The calls with a NULL check already were left.
- **Tests (fail before):** `linux/tests/device_monitor_null_test.cc` (fake udev layer; 6 of 9 cases died with SIGSEGV before the fix), `linux/tests/crash_report_test.sh`.
- **Crash reports:** `docs/port/crash-reports.md`: from now a crash leaves signal, thread name and backtrace in `norns.log` and `crash-report.txt`; the package keeps the function names.
- **The other two crashes (not explained; no core dump or log was available to me):** the SIGABRT in norns (Monday, checkout) and the SIGABRT in sclang (Tuesday, package, after many scripts were installed). Nothing in this fix applies to sclang, which is another program. A norns abort comes from an `abort()`, a failed `assert` or glibc's heap check (double free); the monitor's `assert(udev)` is one candidate only if libudev failed. To find out: `coredumpctl info <pid>` for both (signal, the last stderr lines, the backtrace) and `coredumpctl gdb` with `bt full`; after this build the norns one also writes the report. For sclang: the SuperCollider class library log at start (`~/Verdandi/.../sclang` output in the launcher log, look for "duplicate" or "ERROR: Class") shows the duplicate-class case, which in SuperCollider fails the compile and does not abort by itself.

## 16. SYSTEM > UI: with the computer keyboard a value changed on the press and jumped back on the release, and held keys scrolled on (found on the laptop); FIXED
- **Cause:** the page turned every encoder delta into a step of one in the direction of its sign (`delta > 0 and 1 or -1`). The menu's key bindings (`_menu.keycode` in `lua/core/menu.lua`) send the `-` and `=` keys to the page as `enc(3, value * +-1)` for **every** key event, and the release has value 0: a delta of **0**, which the page read as "down" (`0 > 0` is false), so each release undid or repeated a step, and a held key (repeat value 2) always moved one step per repeat. The other pages use the delta itself (AUDIO: `sel + delta`, then clamp), where 0 does nothing. The encoder events of the window (Option keys mode, QWASZX, the on-screen knobs) have no release event, which is why they were fine.
- **Numbers before the fix** (`linux/tests/ui_keys_test.lua table`, the real keyboard module and menu bindings; start: brightness 0.5, colour yellow, greys 0.7): `=` on COLOUR: press -> pink, two repeats -> custom, **release -> pink**; on BRIGHTNESS: press 0.6, repeats 0.8, **release 0.7**; `-` on BRIGHTNESS: press 0.4, repeats 0.2, **release 0.1**; on GREYS `=`: press 0.8, repeats 1.0, **release 0.9**. A release also wrote the file and told the screen again.
- **Checked and not the cause:** a handler for both key down and up (the page's `key` ignores z = 0), a value re-read from the file (only `init` loads), two handlers for one press (the page has `enc` and `key` only), float rounding (steps are whole tenths, tested), the text entry's key interception (only set while the entry is open, tested closed and after closing).
- **Fix:** the steps take the delta (0 = nothing: no change, no screen update, no write; a repeat of 2 is two steps like on every other page). Test `ui_keys_test.lua` (7 checks failed before): one press = one step for each row, release changes nothing, holding goes one way and never back, UP/DOWN move rows, LEFT/RIGHT are K2/K3 as everywhere, the hex entry opens, takes the keys and closes.
- **Not the same as "arrow keys":** in the menu the arrow keys are UP/DOWN = E2 (rows), LEFT/RIGHT = K2/K3 (as on every page), values change with `-` and `=` (and in the window's keys mode with the arrows = E2/E3, or QWASZX). If you saw the fault with the arrow keys of your keyboard, tell me which of the two modes was on.

## 17. SYSTEM > MODS said "no mods" and no mod was ever found or loaded (sidvagn installed through maiden; found on the laptop); FIXED
- **Upstream:** `lua/core/mods.lua` scans with `norns.system_glob(paths.code .. "*/lib/mod.lua")` (`Mods.scan`); `lua/core/startup.lua` ends with `mods.load_enabled(); mods.load(mods.scan() or {}, true)` (the names in `dust/data/system.mods`, read with `tabutil.load`); `lua/core/menu/mods.lua` lists `mods.scan()`, E3 right/left enables/disables and saves; mods register hooks (`system_post_startup`, `script_pre_init` ...) through `core/hook` and menu pages through `mods.menu.register`. `norns.system_glob` is `_norns.system_glob`, the C `glob()` in `weaver.cc`.
- **Cause:** on the desktop Lua sees the virtual `/home/we` (`lua/core/virtual_home.lua`), so the pattern was `/home/we/dust/code/*/lib/mod.lua`; the C glob works on real paths and finds nothing there (`glob` fails with "no match", `Mods.scan` returned nil, the page said "no mods", startup loaded nothing, and nothing was logged because the code is silent when the scan is empty). `system_glob` was not in virtual_home's list of C functions that take paths (`PATH_FUNCTIONS`), and that list could not have done it alone: the function returns a table of paths.
- **Fix:** `virtual_home.lua` wraps `_norns.system_glob`: the pattern goes out real, the matches come back virtual (nothing changes on the device, the file returns early there). `lua/core/mods.lua` on a computer (`NORNS_PLATFORM`): one log line per mod found (`mod found: name (path), enabled|not enabled`), one for "none found", and a mod that raises is caught: `mod failed: name: <error>`, the other mods still load and norns goes on (on the device an error still propagates as before).
- **Tests (fail before):** `linux/tests/mods_test.lua` (the glob in miniature, the real virtual home, the real page and startup block: 13 of the checks failed before: nothing found; listed in the page, enabling saves, a restart loads it and the hook runs, a mod with an error is reported and the rest load, a folder without `lib/mod.lua` is not a mod) and the headless `window:mods` test in `run_all.sh` (a real boot with a fake mod and a failing one enabled).
- **sidvagn and doubledecker, loaded headless in the real norns (from the catalog scan clone b5240bd and a fresh shallow clone of the voice, 8729b9c):** both are found and load without error (sidvagn: its own copy of the nb wrapper `lib/nb.lua`, which creates the global `note_players`, `musicutil`, `textentry`, `fileselect`, `include`, `grid.connect(2)`; its "post startup" and "cleanup" hooks ran; doubledecker: `lib/voice`, its own `lib/binding` and `lib/preset`, `note_players`, and the SuperCollider class `lib/doubledecker.sc` which SuperCollider compiles because the launcher's `sclang_conf.yaml` includes the whole `dust` folder; the library compiled without an error and the engine list was as usual; its parameters send OSC to sclang on port 57120). **Not checked here:** sound from the voice (it needs a running SuperCollider server with the class and the synthdefs), that the class is really present in the compiled library, a grid on port 2 for sidvagn, MIDI players, the nb library mod itself from the catalog (`nb` as a mod), params saved/restored, Cheat Codes 2's own nb copy next to a mod.
- **Your path:** the owner's mod lives under the norns home; the launcher's home is what `HOME` is; nothing in the fix depends on the folder.

## 18. The norns home was nested (`~/Verdandi/Verdandi`) on PipeWire machines (found by the clean-up inventory); launcher fixed, existing nested homes migrate later
- **Cause:** `linux/norns.sh` exported `HOME` (the norns home) but not `NORNS_HOME`; the re-run under `pw-jack` (PipeWire machines) worked out the default home again from the changed `HOME`, or looked for `~/.config/verdandi/home` under it, and took `<home>/Verdandi`. See `docs/port/clean-layout.md` 1.1.
- **Fix:** `export NORNS_HOME` right after the home is decided. Test (`launcher_test.sh`, no `NORNS_HOME` given: the default home and a config-file home survive the re-run) fails on the old launcher (2 failures) and passes now.
- **The migration is built** (`verdandi tidy flatten --apply` / `--undo`, test `tidy_flatten_apply_test.sh`): renames only, a hard-link backup of `dust/` and `before.tree` first, a typed confirmation, norns must not be running, counts/sizes/listing/inodes of `dust/` checked after, automatic rollback on any mismatch, a failed rename or a TERM/INT/HUP, `--undo` from the manifest (also after a killed run). Nothing is deleted. Not tested here: a nested home on another file system (the tool refuses; the dry run says so) and the owner's real 13 GB `dust/`.

## 19. A browser opened from the window kept its profile and cache in the norns home (`.config/mozilla` in `~/Verdandi`); launcher fixed
- **Cause (reproduced):** the launcher records the user's own `HOME` and XDG folders as `NORNS_USER_HOME` and `NORNS_USER_XDG_*` so that `xdg-open` (MANUAL, MAIDEN, folder buttons) runs with them. The second run of the launcher (under `pw-jack`, PipeWire machines) recorded again, and saw the norns home as `HOME` and `<home>/cache` as `XDG_CACHE_HOME`: so after the re-run `xdg-open` and the browser it started got the norns home as `HOME`. A browser then wrote its profile (`.config/mozilla`, `.mozilla`) and cache into the norns home.
- **Fix:** the user's values are recorded once, by the first run, before anything changes `HOME`; the re-run keeps them. `launcher_test.sh` (`DECIDE-USERENV`): HOME and the XDG folders after the re-run are the user's (2 failures with the old logic, 0 now). The older `open_browser_test.sh` only covered a start without the re-run, which is why it did not catch this.
- **Already there:** a profile that is in the norns home from before is only a leftover; nothing moves it by itself. `stat` shows its date; `verdandi tidy disable <path> <why>` moves it into `disabled/` (restorable). Other programs that a script starts with `os.execute` still get the norns home as `HOME` (that is by design: norns is the HOME of its scripts).
