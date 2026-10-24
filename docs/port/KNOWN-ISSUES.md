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

## 6. The internal clock freezes (0.06 beats/s instead of 2) with SYS/APP under PipeWire + WirePlumber (found by Ken's bisect; reproduced; FIXED for the Linux desktop build)

**Ken's bisect:** healthy at 37d244b5 (about 21 beats in 11 s at 120 BPM), slow at 78eedb02 (0.625 beats in 11 s) and everything after.

**Mechanism.** The internal clock's time comes from `jack_client_get_current_time()` (`matron/src/jack_client.cpp`): the 32-bit
`jack_frame_time()` of the client "matron-clock", extended to 64 bits. Under PipeWire that value is the frame counter of the
**driver of the graph the client's node is in**, not a wall clock. All JACK clients share one group (`node.group = group.dsp.0`: norns'
clients and every other application's, seen with `pw-dump`), so when the graph is re-organised (here: SYS links application
streams into crone, which makes the group run under the sound card's / null sink's driver) the counter's base changes. The code
accepts a forward jump and **ignores every backward delta** ("backward jitter"). Measured in the failing run:
`jack frame time jumped by +560.691 s (forward, accepted)` once, then `-503.146 s (backward, ignored)` on every reading for the rest
of the run: the clock's time stands still for the 503 s it takes the new base to catch up with the stored value. The clock thread
(`clock_internal.cc`) sleeps `tick + (next_tick - now)`; with `now` frozen that grows by one tick per tick, so the beat rate falls
off: 0.54 beats in 8 s (0.067 beats/s; Ken: 0.625 in 11 s).

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

**Fix (option A, Ken's decision; applied in `jack_client.cpp`, `NORNS_LINUX_DESKTOP` only, macOS and Pi unchanged):** keep the raw frame time of the
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

## 7. SYS: a microphone capture stream is taken as an application; and SYS is not heard at the output (Ken's laptop test; 7.1 and the monitor-mode condition FIXED, unlinking NOT built)

### 7.1 Reaper's microphone capture is linked into crone as if it were an application (bug in step 5)
**Observed (Ken):** `PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL/FR` linked to `crone:input_1/2` next to the browser; clapping at the
laptop microphone moved the input and monitor lanes; after closing Reaper it stopped.

**Cause (code):** `crone/src/InputRoute.h`, `listApps()`: an application is "a client with audio output ports, none physical, not norns, not a card". It
looks at the client and at flags only, **never at the port's name or direction of the stream**. In PipeWire's JACK view a *capture* stream (Reaper
reading the microphone through the ALSA plugin) is a client whose output ports are called `monitor_FL/FR` (the signal it receives from the source), not
`output_FL/FR`. It has no physical flag, is not norns, owns no physical port: it passes every test. My unit tests and the fake clients only had
playback-stream clients (`output_*`), so the case was not covered.

**Reproduced here** (`jackd` dummy, fake clients: a card with a 440 Hz tone on its capture ports, a client "Vivaldi" with `output_FL/FR` and 440 Hz, a client
`PipeWire ALSA [reaper]/ALSA Capture [reaper]` whose ports are `monitor_FL/FR` with 440 Hz, SYS chosen): `jack_lsp -c` shows
`crone:input_1` fed by `PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL` **and** `Vivaldi:output_FL`, input 2 likewise with `_FR`: exactly Ken's graph.

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
  lane** = `outPeak` of `SinkDac`, i.e. what is really sent to the card. So with SYS: input and monitor lanes move, the output lane does not: exactly Ken's observation. In MIC
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
  `ext_source` / `cut_source` into the output, which is heard (and the output lane moves). Ken's test script (awake) does not process the input, so there was nothing to hear; the
  sound he heard was the application's direct path to the sound card.
- What is missing is only **hearing the dry input through norns**, and that is off on purpose to avoid the double sound.
- **Related bug found while reading (sink-monitor mode):** `mode ~= "system" and mode ~= "app"` is **true for the optional "monitor" mode**, so the input monitor stays ON there, although
  `HARDWARE-CHECKLIST.md` and `phase-3.md` say it is switched off. With the sink monitor (which contains norns' own output) that is the loop the warning is about. To be fixed
  with whatever is decided below (one condition: add `and mode ~= "monitor"`).

### 7.3 Hearing processed SYS audio without hearing the application twice: options
In PipeWire the browser is a stream linked to the sound card's playback ports (`Vivaldi:output_FL -> Built-in Audio Analog Stereo:playback_FL`, Ken's `jack_lsp -c`). norns also
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
tested first by hand by Ken as above) rather than changing what SYS means. Awaiting Ken's decision; nothing is implemented.

### Decisions on item 7 (Ken) and what was done
- **7.1 fixed (option 1, as a deny-list):** `InputRoute.h` `isDeniedPort()`: SYS and APP skip every port whose name part starts with `monitor` or `capture` (case-insensitive);
  anything else, `output_*` or not, still counts. A client that has only such ports is no application at all; a client with both takes its `output_*` ports only.
  Tests first: the fake graph has the capture stream `PipeWire ALSA [reaper]/ALSA Capture [reaper]` with `monitor_FL/FR` (`fake_card ... capstream`), `tests/crone/test_input_route.cpp`
  has the same client in its desktop fixture plus four new cases, `run_all.sh` checks that neither SYS nor APP is fed by it and that it is not in the app list.
- **Sink-monitor condition fixed:** `lua/core/menu.lua` now switches the input monitor off for `monitor` mode too (`mode ~= "system" and mode ~= "app" and mode ~= "monitor"`). Test:
  `linux/tests/input_monitor_test.lua` (MIC and OFF hear the monitor; SYS, APP and the sink monitor do not; the warning is shown in the sink monitor mode); it failed before the change.
- **Unlinking (7.3 options 2 and 3) is NOT built (Ken's decision).** Ken's hand test on the laptop: a stream whose direct link to the sound card he removed
  (`jack_disconnect`) **stayed unlinked for over a minute and through pause/play**, but **a brand new stream (`Vivaldi-123`) was created with the direct link in place**. So WirePlumber
  does not re-link an existing stream that lost its link, but links every new stream: unlinking would need **continuous re-checking** (a port-registration or port-connect callback
  that removes the card link of each new stream as it appears, with the race against the session manager, plus restoring on exit). Revisit after Ken has used SYS for a while.
