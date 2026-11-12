# Windows M4: MIDI, clock, Link, MIDI MAP, virtual ports (approach note)

Written before the code, kept up to date with it. Version 0.5.0. Grids are not part of M4. Nothing here is specific to one program or one maker: every MIDI device, virtual cable and OSC sender goes through the same rules; Ableton, Push 2, the Fireface and the midronome appear only as examples in the steps below.

## 1. Which MIDI API: WinMM (midiIn / midiOut), and why not Windows MIDI Services yet

| | WinMM | Windows MIDI Services (WMS) |
|---|---|---|
| available | every Windows version; no install, no admin | Windows 11 25H2 and later; Microsoft's release page says the service and its loopback transports are in the box, the SDK/tools are optional. **Not verified on the owner's build 26200.9711, and whether any part needs an installer or admin rights is not verified either** |
| timing | the input callback runs on a system thread; byte-stream, no timestamps better than 1 ms | UMP, timestamps in 100 ns, multi-client |
| clients per port | one (most drivers; some, such as RME's, may offer more) | many |
| work | small, known | a new COM/WinRT API, a runtime that is not in the sandbox, no way to test it here |

Decision: **WinMM now, behind a backend interface** (`midi_port.h`, `vmidi_backend`) so that a WMS backend can be added later without touching the rest. On Windows 11 with WMS, WinMM is replumbed through the service (so WMS endpoints, loopbacks included, appear as ordinary WinMM ports; a report on a similar build says the built-in loopback endpoints were *not* visible to WinMM apps, another says they were: the DEVICES page and the route test will show on the owner's PC which is true). A second-best, not a loss: the timing of the clock does not depend on the API's timestamps, see section 4. Reversible; recorded here rather than in DECISIONS.md because nothing else depends on it.

Sources for the WMS claims (read, not tested): the Microsoft/MIDI releases page and issue tracker on GitHub, the Windows MIDI Services documentation.

## 2. The device layer

`matron/src/platform/windows/midi/`:
- `midi_core.h` (pure, tested on Linux): WinMM lists every port of every device as its own device, cut at 31 characters: `Arturia BeatStep Pro`, `MIDIIN2 (Arturia BeatStep Pro)`, `2- USB MIDI Interface`. `parse_name` takes the wrapper off; `group` puts the ports of one device together; the key (path) of a device is `winmm:<lower case name>` (`#2` for a second device of the same name) and carries **no index of the system**, so it is the same after a replug, another USB socket and a reboot. Names in the list: `Name` (one port), `Name 1`, `Name 2` (several ports, as the Linux build names them), `Name 2` for a second identical device. A MIDI MAP mapping that names the device finds all its ports (`mio` finds `mio 1`).
- `midi_winmm.c`: the WinMM backend. Input callback registers its thread with MMCSS ("Pro Audio") once; sysex through 4 buffers of 4096 bytes; output splits a byte buffer into short messages and sysex.
- `midi_port.cc`: one port pair. The backend's callback hands clock bytes (`F8 FA FB FC`) and song position to the clock **at once on its own thread**, then puts all bytes in an 8 KB ring that norns' device thread reads with the same byte parser as on Linux (running status, sysex in 3-byte chunks, events to Lua). The reader waits in 100 ms slices so that `dev_delete`'s `pthread_cancel` never leaves the lock taken.
- `midi_monitor.cc`: one scan = list + group + diff against the list; the thread scans at the start, when Windows says the devices changed (hidden window, `WM_DEVICECHANGE`) and every 2 s. A device that is listed with fewer ports than it has (one was held) is tried again every 3 s. Lines in norns.log: `midi: found X (2 ports)`, `midi: removed X`, `midi: skipped X: not opened (midi_ignore ...)`, `midi: X opened (input and output)`.
- `device_midi_win.inc`: included by `device_midi.cc` in place of the ALSA functions (as the macOS build does with CoreMIDI); `device_list.cc` keeps its Linux logic (port-level dedupe, sweep of gone devices) with the node test replaced by "is it in the last scan".
- 16 vports as on Linux (`lua/core/midi.lua` is unchanged), at least 16 devices at once (tested with 20).
- **`midi_ignore=`** in `%USERPROFILE%\Verdandi\audio.conf` (names separated by `;`, compared without case, blanks and punctuation, the same rules as Linux): devices Verdandi must not open. Default: none. This is the answer for a controller that another program should have alone (WinMM ports are normally single-client).
- **A port held by another program:** `midiInOpen` answers "allocated". The device is listed with the part that opened (an input held: output only) and the DEVICES page names it with plain words: *"<device>: held by another program (its input)"*; the entry `midi: N held` appears on the DEVICES list itself, `midi routes` opens the page, whose help says: close the port in that program, or put the device's name in `midi_ignore=` and plug it in again. The program is never named by Verdandi (it cannot know).
- Not treated as controllers: the same `V.is_non_controller` rule as Linux (grid-like `iii` devices, the keys window); the OSC input and cables are controllers for ANY.

## 3. Pushing into Verdandi from another program (Push 2 / Ableton as the example)

Ableton owns Push 2's ports; Verdandi does not open them (leave them in `midi_ignore=` if Verdandi would otherwise grab them at start: **start Ableton first, or ignore the device**). What reaches Verdandi: CC and notes that something in Ableton *sends out* through a virtual port or by OSC. Routes: (a) a virtual MIDI port (section 6), (b) OSC (section 7). MIDI MAP learns them like any controller: `ANY` rule, device-name matching, WATCH view, all unchanged. The MIDI MAP PUSH 2 preset was not checked (low priority).

## 4. MIDI clock and timing

- **In:** `clock_midi.cc` (unchanged) gets every tick from the WinMM callback via `clock_midi_handle_message_at(byte, clock_get_system_time())`, `F2` song position the same way, so start/continue/stop/SPP keep their order and no queue sits between the cable and the clock. The device thread sees the same bytes only as MIDI events for scripts (`clock_timed = true` keeps them from being counted twice, as for the JACK device on Linux).
- **Out:** exactly as on Linux: `clock_midi_out_N` toggles per vport and the hidden bare `clock_midi_out` for old scripts are Lua (`lua/core/clock.lua`) and need no change; they send through `dev:send` → `midiOutShortMsg`.
- **Sources:** internal, MIDI, Link, crow, selected in PARAMS > CLOCK as on Linux. A new first line there says what is driving: `driving: internal, 120.0 bpm`, `driving: midi from <device>, 97.5 bpm`, **`midi: no clock coming in`**, `driving: link, 2 peers, 120.0 bpm`, `link on: no peers yet`. (The window's box has no place for it; PARAMS and the log are where it is.)
- **Timing:** the internal clock thread sleeps on a high-resolution waitable timer instead of winpthreads' whole-millisecond sleep, is registered with MMCSS, and measures how late each wake-up was; the scheduler thread (resumes `clock.sync` waits) likewise. Numbers every 10 s in norns.log: `clock: internal ticks woke 120 us late on average, 900 us at worst`; and for an incoming clock: `midi: clock in 'X': 97.5 bpm, tick interval mean 25641 us, jitter 85 us, shortest .., longest ..`. What Lua does after the wake-up (a `clock.sync` loop that sends clock out) is the Linux chain unchanged and has its own jitter, which the numbers above do not include.
- Tested on Linux with fakes: callbacks in the right order, statistics (mean/jitter of a 20.8 ms tick with ±200 µs noise), clock disabled for a device; **not** tested: the real jitter on Windows, the midronome, the RME driver.

## 5. Ableton Link

Real Link (`third-party/link`, GPL-2.0-or-later, as in the Linux build) with `clock_link.cc` unchanged except for one thing: the audio delay (`total_ms` of the AUDIO page: the card's output latency plus what the engine holds back) is added to the time the beat is looked up at, refreshed twice a second, so that a note on beat 1 is heard when the other peers' beat 1 is. `_norns.link_info()` gives peers, tempo and that latency. Link starts when the clock source is "link" (PARAMS > CLOCK); quantum and start/stop sync are the existing params. Tested: CI runs a two-instance probe (`windows/ci/link_pair_probe.cpp`: discovery and tempo follow) with the MinGW toolchain; the Linux run does the same probe. The runner's network may not carry multicast: then the CI says so and does not fail. **Not tested:** Link with Ableton on a real network, the audible alignment with the latency added (the sign of the compensation is by reasoning, check it by ear: Link beat vs Ableton click).

## 6. Virtual MIDI between programs

Windows has no built-in virtual ports without a driver; Verdandi bundles none. Two ways, both appear as ordinary devices (named by the port):
- **loopMIDI** (Tobias Erichsen, free for personal use; installs a driver, so **the installer asks for administrator rights once**; ports are then created per user without admin). Installed on the owner's PC already.
- **Windows MIDI Services** loopback endpoints (Windows 11 25H2+, see section 1).

Click by click (written for the owner's setup; any program that can use a MIDI port works the same):
1. loopMIDI: type a name (for example `to-verdandi`), click **+**. Add a second one (`from-verdandi`) if you want both directions separate (a port is one cable: what one program writes, the other reads).
2. Verdandi starts (or is already running): SYSTEM > DEVICES shows **MIDI ROUTES**: `CABLES 2 found`. SYSTEM > DEVICES > MIDI: give the port a vport (E2 vport, K3, E3 pick `to-verdandi`).
3. **Ableton to Verdandi:** Ableton > Options > Settings > **Link, Tempo & MIDI**: for the *Output* `to-verdandi`: **Track** on to send notes/CC from MIDI tracks whose output is `to-verdandi`; **Sync** on to send MIDI clock; **Remote** is for control from the port, leave it off here. On a MIDI track set *MIDI To* = `to-verdandi` (channel as you like). A Max for Live device that sends CC out of a track does the same. In Verdandi set PARAMS > CLOCK > source = midi if the clock should follow.
4. **Verdandi to Ableton:** in Ableton the *Input* `from-verdandi`: **Track** on (notes into tracks), **Sync** on (Verdandi as the clock master; tick the clock out in PARAMS > CLOCK > midi clock out for that vport), **Remote** on if CCs from Verdandi should map to Ableton controls. In Verdandi `midi.connect(vport)` and `:cc(...)`.
5. If a port is held (Ableton and Verdandi both opening the same loopMIDI port as *input*): a loopMIDI port can be opened by many programs (it is a multi-client driver), so this is usually fine; a hardware port is not.

**Not verified here:** all of this (no Windows, no Ableton, no loopMIDI in the sandbox).

## 7. OSC input (generic, 127.0.0.1 only)

A UDP socket on `127.0.0.1:9201` (audio.conf `osc_in_port=`, 0 = off) is listed as the device **`osc`** and behaves like a MIDI input (vport, MIDI MAP by name `osc`, WATCH, ANY). Messages (`osc_midi.h`): `/cc ch num val`, `/note ch note vel`, `/noteoff ch note [vel]`, `/pitchbend ch val`, `/pc ch prog`, `/touch ch val`, `/midi b0 [b1 [b2]]`; ch is 1 to 16; values are integers 0 to 127, or floats 0.0 to 1.0 scaled to 0 to 127; bundles are taken apart. Anything else is ignored and counted. Bound to the loopback address only: nothing on the network can reach it. Any sender works (TouchOSC, VCV Rack, Reaper, a script, a Max for Live device); `windows/pack/max-for-live-osc-cc.md` is the small example (a Max patch described step by step, since a `.amxd` cannot be made here). Clock does not travel this way: it needs a MIDI route.

## 8. Measuring the routes (instead of assuming)

`SYSTEM > DEVICES > MIDI ROUTES` has a `TEST` row for the OSC route and one for each virtual cable. K3 sends 200 test messages one at a time (about 3 s, a little irregular), takes the time until each comes back and shows *round trip (mean), worst, jitter (standard deviation), n of 200* on the row, in norns.log and in the RESULTS row, whose help names the quickest route. For a cable the port must be open here with both input and output (a loopMIDI port is one cable: send on its output, it comes back on its input); the test messages are control change 119 on channel 16 and are swallowed (scripts do not see them). OSC is measured as UDP through the real loopback of the machine plus our parser. **This is the cost of the route itself; the program at the other end (Ableton's audio/MIDI buffer, VCV's) adds its own on top, which cannot be seen from here.** WMS loopback endpoints are measured the same way if they appear in the list.

The Linux run measures the UDP loopback for real (about 20 µs mean). Whether loopMIDI or WMS is faster on the owner's PC is a thing only his PC can say; the owner's earlier latency problems with loopMIDI are *not* assumed to be loopMIDI's: the number decides.

## 9. Files

New: `matron/src/platform/windows/midi/*`, `lua/core/menu/midiwin.lua`, `windows/ci/link_pair_probe.cpp`, tests `linux/tests/midi_{core,port,monitor,measure}_test.cpp`, `osc_midi_test.cpp`, `midi_page_windows_test.lua`, `clock_driving_windows_test.lua`, `midimap_windows_names_test.lua`. Changed (all guarded by `NORNS_WINDOWS` or by the existence of `_norns.midi_status`): `device_midi.cc/.h`, `device_list.cc`, `clock_internal.cc`, `clock_scheduler.cc`, `clock_link.cc/.h`, `weaver.cc`, `stubs_win.cc`, `devices.lua`, `clock.lua`, `midimap_value.lua`, the CMake file and the source list.
