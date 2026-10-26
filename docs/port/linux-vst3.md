# Linux VST3: approach note (before any plug-in code)

Status: **approach note only. No plug-in code, no repository code changed.** Written after the owner's decisions on `docs/port/multi-instance.md`. For each claim the note says whether it was **read** (in this repository or in the VST3 SDK sources, which were cloned into a scratch folder for reading and not built), **measured** here (`multi-instance.md`), or **expected / unverified**. Section 14 lists what I could not check.

## 1. Decisions this note builds on (from the owner)

1. **One plug-in instance at a time, with a clear message** (option D), built in from the start, with a **settable bridge port** and an **instance id and a version field in the protocol**, so that "one norns per instance with a supervisor" (option A) can be added later without redoing the plug-in. Option A is not wanted now (`multi-instance.md`, section "Decisions taken").
2. **The first plug-in is a Linux VST3**, tested in **Reaper on the owner's Linux Mint 22.2 laptop with PipeWire**. Windows follows later and reuses what it teaches. `PLAN.md`: Phase 7 = Linux VST3 (steps 7.1 to 7.6), Phase 8 = Windows VST3.
3. `macos/` and the AUv3 are not touched (their two-instance problem is `KNOWN-ISSUES.md` item 12). The AUv3's protocol header stays as it is; the new protocol is a new file.
4. Design rule from `CLAUDE.md`: the plug-in is a **thin client**: it moves DAW audio, MIDI and transport over loopback UDP to a bridge (a JACK client next to norns) and does nothing else.

## 2. Overview

```
Reaper (VST3 host)                         norns side (one instance, Linux)
┌──────────────────────┐   UDP 127.0.0.1   ┌───────────────┐  JACK   ┌──────────────┐
│ Verdandi.vst3        │ ───────────────►  │ verdandi      │ ──────► │ crone:input  │
│  audio thread:       │  hello, audio,    │  bridge       │         │ (matron,     │
│   lock-free rings    │  midi, transport, │  (JACK client)│ ◄────── │  crone,      │
│  network thread:     │  heartbeat        │               │ audio   │  softcut,    │
│   UDP, hello, guard  │ ◄───────────────  │               │         │  sclang)     │
│  status parameters   │  ack/busy, audio, │   MIDI out ───┼───────► │ Verdandi:    │
└──────────────────────┘  status           └───────────────┘  JACK   │ midi_in      │
                                                                MIDI └──────────────┘
```

- **Plug-in** (new): a VST3 effect with stereo in, stereo out and an event input, built with the framework of section 3.
- **Bridge** (new, Linux): like `auv3_bridge`, a separate process and JACK client. It owns the one-instance guard, takes over crone's audio inputs and outputs while a plug-in is connected, resamples between the DAW clock and the JACK clock, and turns the transport message into MIDI clock for norns.
- **norns** is unchanged except for two small things listed in 8 and 9 (the input router stands down while a plug-in is connected; nothing else is needed for the clock, which already follows MIDI clock, start, stop, continue and song position through `Verdandi:midi_in`).

## 3. Framework choice

All licenses were read from the repositories' own files on 2026-10-26; none of this is legal advice.

| framework | license (as read) | format support | what it gives | cost for this project |
|---|---|---|---|---|
| **VST3 SDK directly** (steinbergmedia/vst3sdk) | **MIT** since 3.8.0: `LICENSE.txt` of tag `v3.8.1_build_84` and of master says MIT (copyright 2026); the sub-repositories `pluginterfaces`, `base`, `public.sdk` and `cmake` also say MIT; `v3.7.9` still has the old text (dual GPL-3.0 / Steinberg proprietary). The README of 3.8.x says GPLv3 and the proprietary license "are no longer available". | VST3 only (the SDK also ships AUv3 and AU wrappers) | the API, helper classes (`AudioEffect`, `SingleComponentEffect`), the **validator** (a command-line test host) in `public.sdk/samples/vst-hosting/validator`, and hosting classes to write a test host. README lists Ubuntu 24.04 x86_64 with GCC 13.3 as supported (the same toolchain as this repository) | you write the glue yourself: bus setup, parameters, state, the MIDI-to-bytes conversion (section 5), the module entry points. Plain CMake. No GUI toolkit unless VSTGUI is added (BSD-3-Clause, `vstgui` repository) |
| **JUCE 9** | **dual: AGPL-3.0 or the commercial JUCE licence** (`LICENSE.md` of the repository). Under AGPL the plug-in would be conveyed under AGPL-3.0 terms; a GPL-3.0 project may combine with AGPL-3.0 code (the licenses allow it), the AGPL network clause then applies to the combination (this plug-in has no network users: loopback only) | VST3, AU, AUv3, LV2, standalone, ... | the plug-in wrapper (parameters, state, MIDI and play-head info as JUCE types), an editor toolkit on X11 | a **large** dependency for a thin client; AGPL terms for the plug-in; JUCE bundles its own copy of the VST3 SDK, whose license I could not check |
| **DPF** (DISTRHO) | **ISC** (`LICENSE`, 2012-2025) | LV2, VST3, CLAP, standalone from one source | permissive, small, an own VST3 binding | one more layer between us and the host; I did not read its MIDI or time-position handling; `CLAUDE.md` says no CLAP (DPF's extra formats would not be used) |
| **iPlug2** | a zlib-style license with WDL and NanoVG parts (`LICENSE.txt`) | VST3, AU, CLAP, ... | a plug-in framework with a GUI | Linux support status: **not verified** |
| CLAP | MIT | CLAP | – | excluded by the owner (`CLAUDE.md`: no CLAP) |

**Recommendation: the VST3 SDK directly, pinned to tag `v3.8.1_build_84` or newer (MIT).** Reasons: the plug-in is a thin client with no custom user interface (section 4), so JUCE's biggest advantage (the editor toolkit) is not needed while its biggest cost (AGPL terms and size) would be paid; MIT is the simplest license to combine with GPL-3.0 (permissive, one direction); the SDK comes with the validator and the hosting classes that the headless tests need; it is the reference for how Reaper-like hosts behave. The price is boilerplate, mainly the VST3 way of receiving MIDI (section 5.3). If the owner later wants LV2 or CLAP builds from the same code, DPF is the fallback to look at.

License consequences to follow: add the SDK to `docs/port/DEPS.md` with its MIT license and keep its notice with any distribution; the SDK clone is about 250 MB, so fetch it shallowly into the build folder at a pinned tag (as `linux/maiden-build.sh` does for maiden).

**Trademark.** The MIT license does not give the trademark: Steinberg's *VST Usage Guidelines* (`VST3_Usage_Guidelines.pdf` in the SDK, "SDK version 3.8 – 16.10.2025 or higher", read) say that if a product's documentation, web pages or About box refer to "VST", the VST Compatible Logo (or, where space is short, an attribution) must be shown; "VST" in a company name is not allowed; in a product name only as plain text next to the logo. Using the word at all is optional. See the open decision in section 13.

## 4. The plug-in (thin client)

- **Type:** an effect: stereo input bus, stereo output bus, one event input bus (MIDI). Reaper sends MIDI to any effect on a track (expected; owner check). Mono and other layouts: reject at `setBusArrangements` (stereo only) in the first version.
- **No custom editor in the first version.** The plug-in exposes **read-only parameters** that every host shows in its generic plug-in window: *Connection* (not running / starting / connected / busy / lost), and the host's standard *Bypass*. The norns window is norns' own window (as with the AUv3: "norns itself keeps running in its own window"). A custom editor view on Linux would be an X11 embedded window (`X11EmbedWindowID`, in `pluginterfaces/gui/iplugview.h`) driven by the host's run loop: real work, decided later (open decision).
- **Threads.** *Audio thread* (`process`): only lock-free single-producer rings and plain memory copies; no allocation, no locks, no system calls, no logging. *Network thread*: owns the UDP socket, sends heartbeats and audio blocks, receives acks, audio and status, and talks to the *discovery and start* logic of section 6. The threading model is the AUv3's (`NornsAU.mm`: rings plus a network thread), with a heartbeat added.
- **Always the same behaviour when norns is not there:** the audio is passed through, **delayed by the reported latency**, so that connecting norns later does not move the sound in time (the AUv3 passes through undelayed; with a changing latency hosts mis-align tracks).
- **Realtime only.** `ProcessData::processMode` tells the plug-in when the host renders faster than realtime (`kOffline`) or with jitter (`kPrefetch`; read in `ivstaudioprocessor.h`). norns runs in real time and cannot follow, so in those modes the plug-in passes the audio through and says so in the status. A realtime ("online") render works.

## 5. The bridge protocol (version 2)

A new header (proposed place: `plugin/protocol/`, shared by the bridge, the VST3 and later any other client), **not** `macos/auv3/bridge_protocol.h`. Little-endian, fixed sizes, `static_assert`ed. A different magic (`'NRN2'`) from the AUv3's (`'NRNS'`), so an old bridge ignores new packets and the reverse.

### 5.1 Header (36 bytes)

| field | size | meaning |
|---|---|---|
| `magic` | 4 | `'NRN2'` |
| `version` | 2 | protocol version of the sender (2); a bridge answers a hello of another major version with `VERSION` |
| `type` | 2 | see 5.2 |
| `session` | 4 | 0 in `HELLO`; the number the bridge gave in `HELLO_ACK`, echoed in every later packet (a stray or stale packet is ignored) |
| `seq` | 4 | per direction, counts packets |
| `payload_len` | 2 | bytes after the header |
| `flags` | 2 | per type (for audio: transport trailer present) |
| `instance` | 16 | the **instance id** (a UUID created once per plug-in instance, kept in its saved state: section 10) |

The instance id is what makes the guard exact (section 7) and what option A would key homes, ports and windows on later; it is in every packet so nothing has to be added to the wire format when A comes.

### 5.2 Messages

| type | direction | payload |
|---|---|---|
| `HELLO` | plug-in → bridge | plug-in build, host sample rate, maximum block size, channels, capability bits (wants transport, ...), a **label** (≤ 32 bytes: the track name where the host gives it through `IChannelContextInfo`, else a counter), reserved fields (a `slot` hint for option A) |
| `HELLO_ACK` | bridge → plug-in | **status** (`OK`, `BUSY`, `VERSION`, `RATE`, `NOT_READY`), the new `session`, the bridge's constant **latency in frames** to report, JACK rate, the fixed audio block (128), supported version range, a **human-readable message** (≤ 96 bytes, for `BUSY` and errors), the label of the current owner |
| `AUDIO` | both | 128 frames of planar float32 per channel; plug-in → bridge: the DAW input, bridge → plug-in: norns' output for the same `seq`. Optional `TRANSPORT` trailer (flag), so transport arrives with the audio it belongs to |
| `MIDI` | plug-in → bridge (later also back) | a list of events `{frame offset in the block, length, bytes}` (up to 3 bytes, system exclusive in chunks): unlike the AUv3's raw bytes, the offsets keep the timing |
| `TRANSPORT` | plug-in → bridge | flags (playing, recording, cycle, which fields are valid), tempo (BPM), **PPQ position**, bar start, time signature, project time in samples, host sample rate, cycle start and end. Sent standalone when no audio block carries it (host calls without audio) and on change |
| `HEARTBEAT` | plug-in → bridge | empty; every 250 ms from the **network thread** while the instance is active, whether or not the host is calling `process` |
| `STATUS` | bridge → plug-in | about 4 per second: norns running, the script name, JACK rate, xrun count, the clock source; drives the *Connection* parameter and, later, a UI |
| `BYE` | plug-in → bridge | reason; releases the session |

### 5.3 What the host gives (VST3), and what has to be rebuilt as MIDI

Read in `pluginterfaces/vst`:
- **Transport** arrives in `ProcessContext` (`ivstprocesscontext.h`): `state` flags (`kPlaying`, `kCycleActive`, `kRecording`, and the valid-bits `kTempoValid`, `kProjectTimeMusicValid`, `kBarPositionValid`, `kTimeSigValid`, `kCycleValid`, `kClockValid`), `tempo`, `projectTimeMusic` (quarter notes), `barPositionMusic`, `timeSigNumerator/Denominator`, `projectTimeSamples`, `sampleRate`, `samplesToNextClock` (the distance to the next MIDI clock tick at 24 per quarter note). Most fields are marked **optional**: whether Reaper fills them is for the owner's laptop test.
- **MIDI is not raw bytes in VST3.** Notes arrive as `Event`s (`kNoteOnEvent`, `kNoteOffEvent`, `kPolyPressureEvent`, with channel and sample offset), system exclusive as `DataEvent`; **controllers 0 to 127, channel pressure (aftertouch) and pitch bend arrive only as parameter changes** through the plug-in's `IMidiMapping` (controller numbers 0 to 129 in `ivstmidicontrollers.h`; the plug-in must declare a parameter for each controller and channel it wants, 16 channels times 130). Program change and the like are **not** part of that mapping (the SDK lists them for MIDI *output* only), so they are out of the first version. The plug-in therefore has to (a) expose those hidden parameters, (b) merge note events and parameter changes by sample offset, (c) turn them back into MIDI bytes for the `MIDI` message (poly pressure arrives as an event). The AUv3 gets raw MIDI from the AU event list and needed none of this. This is the main piece of "glue" the framework choice decides (JUCE does it for you; with the SDK it is about a day of code and tests). The SDK also has `IMidiMapping2` for MIDI 2.0 hosts; not needed first.
- **Latency:** `IAudioProcessor::getLatencySamples()` (read) is how the plug-in tells the host.

## 6. How the plug-in finds or starts norns, and what it does if norns is not running

- **Finding.** The bridge writes `$XDG_RUNTIME_DIR/verdandi/bridge.json` (`{"protocol":2,"port":10200,"pid":…,"home":"…","started":…}`) atomically when it is ready and removes it on exit. The plug-in reads it (a stale file is recognised by a dead pid) and talks to that port; without a file it tries the default port 10200. **The port is settable and never typed by the user:** default 10200, overridable by `NORNS_PLUGIN_PORT` for the bridge (a different variable from the AUv3's `NORNS_AUV3_PORT`), announced in the file; if the default is taken the bridge takes the next free one and says so.
- **Starting (decision 13.2).** My recommendation: the plug-in starts norns **when no bridge answers and an option "start Verdandi automatically" is on (default on)**: it reads `~/.config/verdandi/launcher.json` (written by the install step of `linux/build.sh`: the path of `linux/norns.sh` and the norns home), and starts it detached (its own session, so closing the DAW does not kill it) **from the network thread**, never from the host's thread. Norns needs about 4.5 s to be ready (measured, `multi-instance.md` 3.1); the status shows "starting". If the launcher file is missing the status says "Verdandi is not installed: run linux/build.sh" (no guessing of paths). The plug-in does not stop norns when it is unloaded (restarting costs 4.5 s and loses the running script's state); norns exits when the user closes its window, as today. A respawn limit (once per minute) prevents a start loop after a crash.
- **If norns is not running** (or has gone): *Connection* shows it; the audio is passed through with the delay of section 4 and a short crossfade at changes; MIDI and transport are dropped; hellos are repeated every second (backing off to 5 s). **If norns crashes while connected:** no packets for 1.5 s ends the session on the plug-in side, the same crossfade, then the retry loop above.

## 7. The one-instance guard and its message

The bridge keeps **one session**: `(instance id, source address, session number, last-seen time)`.

- `HELLO` with no live session: accept, answer `OK`.
- `HELLO` from the **same instance id and the same address**, session live (a host re-preparing the plug-in, a sample-rate change): accept and replace the session.
- `HELLO` from any **other instance id, or the same id from another address** (a duplicated track copies the saved id: both are live), session live: answer `BUSY`, with the message and the owner's label. Nothing else from that sender is read.
- A session ends on `BYE`, or after **1.5 s without any packet** (heartbeats count, so a host that stops calling `process` while stopped does not lose its seat; an idle plug-in whose network thread is alive keeps it).
- Any packet whose `session` does not match is ignored (stale, stray, or a second process on the loopback port).

The message the plug-in shows (as the *Connection* value text and in the log, the host's own plug-in window being the only UI in the first version):
> **Verdandi is already used by another plug-in instance ("<track name>"). Only one instance can use Verdandi at a time: remove or deactivate the other one.**

The rest of the sender is passive: it passes audio through (section 4) and retries every 2 s, so when the first instance is removed the second takes over without a reload. This turns the AUv3's silent corruption into an explicit state. It is cheap, and it is the first thing built after the protocol (7.1).

## 8. How the DAW's transport and clock reach norns

- **Path:** plug-in `TRANSPORT` → bridge → **MIDI clock, start, stop, continue and song position played into norns' JACK MIDI input `Verdandi:midi_in`** (device "Verdandi JACK in"), which already exists, feeds `clock_midi` with the event's own JACK frame time, and handles start (`0xFA`), stop (`0xFC`), continue (`0xFB`), song position (`0xF2`) and 24 ticks per quarter note (`jack_midi_in.cc`, `clock_midi.cc`, tested by `linux/tests/jack_midi_clock_test.c` at 120 BPM). The bridge is a JACK client with a MIDI output port, connected to `Verdandi:midi_in` when a session starts. The delivery sits behind one small function (`deliver_midi(bytes, frame)`) so that Windows can use the internal pipe device (the keys-device approach in `PLAN.md`) later without changing the logic.
- **Conversion rules** (a pure function with unit tests, section 11):
  - play off → on at position 0: `0xFA`; at another position: `0xF2` (the position in MIDI beats = sixteenth notes = PPQ × 4) then `0xFB`;
  - play on → off: `0xFC`;
  - a **jump while playing** (position not continuing from the last block, loop wrap): `0xFC`, `0xF2`, `0xFB` (norns' `clock_midi` uses a song position only when it comes before start, continue or stop);
  - while playing: `0xF8` at every 1/24 quarter note, positioned in the output stream at the frame where the host's PPQ crosses it (from `projectTimeMusic`, `tempo` and `sampleRate`; if the host sets `kClockValid`, `samplesToNextClock` can be used directly); tempo changes need no message: norns measures the tick spacing.
- **Precision (expected):** the first version places ticks with the precision of the 128-frame audio block (2.7 ms at 48 kHz) relative to the audio stream norns plays; norns smooths the tempo over 24 ticks. A finer placement comes later if the owner hears or measures drift. **Reaper must be the master**: norns cannot drive Reaper (`clock-notes.md`).
- **One manual setting stays:** norns' clock source must be `midi` and `clock_midi_in` must include the "Verdandi JACK in" device (PARAMS > CLOCK), a setting norns keeps across starts. Open decision 13.3: let the bridge switch it for the session and restore it afterwards (a command into matron; more coupling), or document the setting.
- **Not in the first version:** norns as the master (MIDI out to the host), Link between plug-in and norns.

## 9. Audio routing and latency under PipeWire and Reaper

- **Routing, norns side.** While a session is live the bridge's JACK ports (`out_1/2`, `in_1/2`) are connected to `crone:input_1/2` and from `crone:output_1/2`, and crone's normal sources and sinks (the card's capture ports, SYS/APP streams, the card's playback ports) are disconnected and **remembered**, then restored at `BYE` or timeout: the AUv3 bridge's `rewire_to_au` / `rewire_back` do this on the Mac, and its code is the model. **New on Linux (small change in norns, expected):** the input router (`matron/src/platform/linux/app_audio_linux.cc`, `input_route.cc`, logic in `crone/src/InputRoute.h`) keeps re-linking SYS/APP streams as they appear; while a plug-in session is live it must stand down (a "plug-in" input mode, selected by the bridge and restored after), and the bridge's client must be in the "own clients" list so SYS never takes it as an application. Test: 7.2.
- **Clocks.** Reaper's audio device and norns' JACK graph may run on different clocks. If both use PipeWire (Reaper through its JACK or ALSA-compatibility path) they share the graph clock, but the plug-in still runs in Reaper's thread and talks over UDP, so the bridge needs an elastic buffer: a ring on each side, primed to a fixed depth, with the resampling ratio steered by the ring fill (libsamplerate, already a dependency; the AUv3 bridge uses jack2's `jack_create_adapter` from libjacknet, which exists in this container's jackd2 packages, but whether it behaves with **PipeWire's** libjack is **not checked**, so I would write the small adapter in the bridge). Sample rates 44.1, 48 and 96 kHz are resampled to the JACK rate; the bridge's `HELLO_ACK` carries the rate.
- **Latency.** Contributions: the plug-in's 128-frame block, the ring prime (the AUv3 uses 256 frames), the bridge's elastic buffer, **one JACK period into crone and one out** (norns' own jackd defaults to 1024 frames, PipeWire's quantum is the graph's), and crone's/SuperCollider's processing. Expected order: 2 to 4 JACK periods plus about 8 ms, that is **tens of milliseconds, fine for effects and sequenced material, not for live monitoring** (expected; to be measured: section 11). The plug-in reports a **constant** latency through `getLatencySamples()` so the host compensates (PDC) and the track stays aligned; options: (a) a fixed conservative value chosen at build/config time, (b) the value from `HELLO_ACK` with `restartComponent(kLatencyChanged)` on connect and disconnect (risk: how Reaper reacts; owner test). Recommendation: start with (b) measured, fall back to (a). The `norns` side can lower the latency by running at a small PipeWire quantum (`period` in `audio.conf`).
- **Offline rendering** is not supported (section 4); real-time render is. **Freeze and bounce** inside Reaper should use the real-time setting (expected to exist; owner check).

## 10. Project recall: what the plug-in stores and what it does not

**First version (7.3): stores only** a state version, the **instance id** (a UUID created at first creation; a duplicated track copies it, which the guard handles because it keys on the address too), and the *start automatically* option. Nothing about the script.

**Second stage (7.6, optional):**
- stores the **script name** (path under `dust/code`, for example `awake/awake.lua`) and the **parameter set** (a pset text from `params:write`), refreshed by the network thread from norns' status (never from the host thread);
- on connect, if norns' running script differs, asks norns to load it and then applies the pset after the script's `init` has finished. The control path into matron needs one more channel from the bridge (for example matron's REPL websocket, which accepts Lua and is already loopback-only and Origin-checked; a decision for that step).

**Not stored, deliberately:** the norns home or any path (meaningless on another machine), `audio.conf`, the clock settings, a script's own data files and patterns, samples, softcut buffers, SuperCollider engine state, window layout, maiden. A project moved to another machine opens the plug-in in the "not installed" or "not running" state with the script name shown; scripts that keep their state only in memory lose it, exactly as on the device. No DAW-specific tricks (some hosts limit state size: the stage-2 state is a few kilobytes).

## 11. What can be tested here, and what needs the laptop and Reaper

### Headless, in this container (no sound card, no DAW)

1. **Protocol unit tests** (doctest, as elsewhere in the repository): encode and decode every message, golden bytes, size limits, garbage and truncated packets, a version mismatch, an unknown type.
2. **Guard tests**, state machine with an injected clock and with real loopback sockets: first hello accepted, second instance gets `BUSY` with the message and the owner's label, the same id re-hello replaces the session, the same id from another address is `BUSY`, owner timeout and takeover, `BYE` release, heartbeats keep a silent owner, wrong session numbers ignored.
3. **Transport conversion tests**: a pure function from transport samples to MIDI events with frame offsets: start at zero, start at a position, stop, jump while playing, loop wrap, tempo changes, odd tempos, block boundaries; assert the exact message order and tick spacing within one frame of the ideal.
4. **Bridge integration on a dummy JACK server**: a loopback client (fake plug-in) sends audio and transport; a fake crone (JACK pass-through) returns it; measure the round trip in frames, check the output is bit-exact at ratio 1, check behaviour with a client at another rate and a simulated drift (±100 ppm), no xruns, and the route takeover and restore. With the **real headless norns** (the existing harness): the tempo and play state follow (`clock.get_tempo()`, start/stop callbacks, beat counter against the sent PPQ), and SYS/APP do not fight the takeover.
5. **Plug-in tests:** the SDK's **validator** run on the built `.vst3` (it loads the plug-in and runs its checks: bus arrangements, processing with different block sizes, state save and restore, parameters, threading; it is a command-line program, so it should run headless; the SDK targets this repository's toolchain, GCC 13.3). **I cloned the SDK for reading but did not build it: a build was not permitted in this session, so that the validator builds and runs in this container is expected but unconfirmed.** A small **fake host** (using the SDK's hosting classes, `public.sdk/source/vst/hosting`) loads the plug-in in-process, drives audio, events and `ProcessContext` for thousands of blocks against a running bridge, and checks bypass, `kOffline` handling, state round trip, no allocation in `process` (an allocation hook), and ThreadSanitizer/AddressSanitizer runs.
6. **Not planned headless:** driving Reaper itself (a proprietary program that needs a license and a display, and whose offline render is not real time).

### Needs the owner's laptop and Reaper (to go into `HARDWARE-CHECKLIST.md`)

- the plug-in is found by Reaper (scan path, `~/.vst3` expected, unverified), loads, shows its parameters;
- audio both ways with PipeWire and a real device; no xruns at the owner's usual quantum; **round-trip latency and PDC alignment** (a click on one track, a parallel dry copy with inverted polarity: they should cancel when norns passes the input through);
- MIDI notes, controllers and pitch bend arrive as the right bytes (the `IMidiMapping` route in Reaper);
- tempo and transport follow: play, stop, locate, loop, tempo changes; which `ProcessContext` fields Reaper fills;
- the guard message with a second instance, and the takeover when the first is removed;
- behaviour when norns is not running, starts late, or is killed while playing; auto-start from the plug-in;
- project save, close, open: the instance id returns; (stage 2) the script and parameters;
- real-time render works; offline render passes the audio through with the status message;
- CPU and memory with a real script and engines (the measured idle norns is 0.56 GB and about 7 % of a core, `multi-instance.md`).

## 12. Repository layout and build (proposal, no files created yet)

- `plugin/protocol/` (the header and codec, shared), `plugin/bridge/` (the bridge, built with waf next to norns, linking JACK and libsamplerate), `plugin/vst3/` (the plug-in and its CMake project against the pinned SDK), `plugin/tests/` (unit, guard, conversion, loopback, fake host), and the existing `linux/tests/run_all.sh` calling them. `macos/` untouched.
- `linux/build.sh` builds the bridge with norns and, unless `NORNS_NO_PLUGIN=1`, fetches the pinned SDK shallowly into the build folder, builds `Verdandi.vst3` (a folder `Verdandi.vst3/Contents/x86_64-linux/Verdandi.so`, the layout the SDK's CMake produces on Linux) and installs it into `~/.vst3`; it writes `~/.config/verdandi/launcher.json`. `linux/norns.sh` starts the bridge next to norns (the way `macos/norns.sh` starts `auv3_bridge`), loopback only.
- `docs/port/DEPS.md`: the SDK (MIT), libsamplerate (BSD-2-Clause, already there).
- For Windows later: the protocol, the bridge logic and the plug-in sources are shared; the audio path, the MIDI delivery, process start and the bundle layout are the platform parts.

## 13. Risks and open decisions for the owner (GATE E in `DECISIONS.md`)

Risks:
- **Reaper-specific behaviour is unverified** (MIDI controller mapping, `ProcessContext` fields, PDC with a changing latency, FX processing while stopped, scan paths, an editor-less plug-in window). Mitigation: the plug-in is built to need little (notes and the mapped controllers, tempo/position/play state with fallbacks) and the owner's checklist covers each.
- **Latency of tens of milliseconds** (expected). Mitigation: measure early (7.2), small quantum, report it accurately.
- **A second process** to keep alive (the bridge) and a heavy norns behind it (0.5 GB). Same as the AUv3.
- **UDP on the loopback** is accessible to any local process; the session number stops accidents, not attackers; the trust level is the same as norns' other local interfaces (loopback only, user-level).
- **Sandboxed hosts** (a Flatpak Reaper) may not share the loopback or the runtime directory with norns: not checked (packaging gate B).
- **The SDK's version policy:** pin a tag; the guidelines on the trademark apply to anything published.
- **Fast render, freeze and bounce** modes cannot work (norns is real time): documented, passes through.

Open decisions:
1. **Framework:** the VST3 SDK directly (recommended), JUCE, or DPF (section 3).
2. **Auto-start norns from the plug-in** (recommended: yes, option on by default, never from the host thread) or "start Verdandi yourself" like the AUv3.
3. **Clock source:** the bridge switches norns to MIDI clock for the session and restores it (more coupling), or the user sets it once (recommended for the first version).
4. **Editor:** none in the first version, status through read-only parameters (recommended), or an embedded X11 view.
5. **Recall depth in the first release:** id only (recommended), or script and parameters from the start.
6. **MIDI from norns back to the host** (norns as a sequencer driving other tracks): not in the first version; the protocol leaves room.
7. **How to refer to "VST"** in published documents: follow Steinberg's guidelines with the logo, or say "plug-in" only.
8. **Latency reporting:** (a) fixed or (b) measured with a restart, decided after the first measurement.

## 14. What I could not check

- Anything in **Reaper**: its audio backends and PipeWire use on Linux, which `ProcessContext` fields it fills, its use of `IMidiMapping`, its plug-in scan paths, its processing of effects while stopped, its offline-render options, its handling of a latency change. (Everything listed is expected from the VST3 documentation and general knowledge.)
- That the **SDK validator builds and passes here** (the SDK was cloned and read only), and that a minimal plug-in written against it loads in Reaper.
- **JUCE's bundled copy of the VST3 SDK license**, DPF's and iPlug2's MIDI and time handling and iPlug2's Linux status (read licenses only); the maintenance state of the frameworks beyond the copyright years seen.
- Whether **jack2's libjacknet adapter** works with PipeWire's libjack (not needed if the bridge brings its own resampler).
- The real **latency, drift and xrun behaviour** (no audio hardware and no real-time load in this container), flatpak sandboxing, Windows.
- **Legal:** the license readings above are mine and not legal advice; the AGPL/GPL combination and the trademark guidelines should be confirmed by the owner before a release.
