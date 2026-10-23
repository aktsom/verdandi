# Phase 3: audio, devices and the external clock (approach note, for Ken to confirm)

Status: **approach only, no Phase 3 code.** Facts below come from reading the code, from the Phase 1-2 runs, and
from one PipeWire experiment in the build container (no sound card, no session manager: it proves little about a
real laptop, and I say where). Ken's clock decisions are in `docs/port/clock-notes.md` section 4 and `PLAN.md`.

PLAN.md Phase 3 asks for: JACK/PipeWire audio with the `audio.conf` semantics kept; MIC/SYS/OFF input without
the Core Audio tap; real devices through the Linux paths (ALSA MIDI, udev, evdev). Added since: the clock items.

## 0. Order of work and what each step can be tested with here

| # | Step | Testable in the build container? |
|---|---|---|
| 1 | `clock_midi`: SPP and MIDI continue (unit tests) | yes, fully |
| 2 | JACK MIDI input port on matron (clock and notes from other programs) | yes: JACK dummy graph and a test client |
| 3 | crone and the physical-port requirement; audio server detection (jackd, PipeWire-JACK) | partly: dummy jackd yes; PipeWire only as far as a null graph; needs your laptop |
| 4 | `audio.conf` and SYSTEM > AUDIO on Linux (device list, rate, buffer) | list: no sound cards here; apply: dummy driver only |
| 5 | MIC / SYS / APP / OFF through JACK ports | MIC/OFF and APP/SYS between JACK clients: yes; PipeWire monitor ports: needs your laptop |
| 6 | real devices: udev, ALSA MIDI, evdev, serial (grid, arc, crow), permissions | hotplug and hardware: no (checklist) |
| later | ALSA sequencer input (clock-notes option A) | no `/dev/snd/seq` here |

Steps 1-2 first: they are small, independent of the audio-server questions, and fully testable here. Steps 3-5
depend on what PipeWire really exposes, so the first thing I need from you is the output of the commands in
`RUN-ON-LAPTOP.md` (section 4, last paragraph) from a real machine. I will not guess the PipeWire port names.

## 1. Clock: SPP and MIDI continue (`clock_midi.cc`)

**Today** (`matron/src/clocks/clock_midi.cc`, 93 lines; byte handling in `device_midi.cc`
`dev_midi_consume_buffer`): realtime bytes 0xF8 (tick), 0xFA (start: counter = -1), 0xFC (stop) are handled; **0xFB
(continue) is ignored; SPP (0xF2 + 2 data bytes) is a normal 3-byte message and not looked at.** The beat is
`counter / 24`; the first tick after a start makes `counter == 0` and that fires `clock_start_from_source`
(which also resets the scheduler's sync events to beat 0).

**Change.**
- `0xF2 lsb msb`: song position in MIDI beats (1 = 6 clocks = a sixteenth note). Set `counter = pos * 6 - 1`, so
  the next tick lands exactly on `pos * 6` (beat `pos / 4`). Handled where the 3-byte message completes in the
  device layer (realtime bytes inside it do not disturb it), and only when the device has `clock_enabled`.
- `0xFB`: **resume; the beat counter is not touched.** If the clock was stopped, the next tick counts on from
  where it was (after an SPP, from the new position). Scripts are told that the transport runs again through
  the same start event (`EVENT_CLOCK_START`), but **without** `clock_scheduler_reset_sync_events()`: a new function
  `clock_continue_from_source(source)` beside `clock_start_from_source`, which keeps resetting to beat 0 for 0xFA.
- 0xFA stays as today (counter = -1: the start resets the counter). SPP then continue is the usual way a DAW
  resumes mid-song; SPP then start is "start from the position", which the standard also allows: after an SPP
  a 0xFA starts at the *position* the SPP set (so SPP is remembered until the next 0xFA uses or drops it; I
  will implement "start after SPP begins at that position, a bare start begins at 0" and test it).
- Link and crow sources are not touched.

**Tests** (`tests/matron/clocks/clock_midi/`, doctest like the existing ones, driven with `tests_set_now`):
SPP then ticks gives beat `pos/4` plus ticks; continue after stop keeps the counter (beat does not return to 0)
and the next tick resumes it; start after stop does reset it; SPP plus continue fires the start event once and
does not reset sync events; a stop, a gap over 4 beats' worth of time and a continue; SPP with `clock_enabled`
off is ignored. A parser-level test for the 3-byte SPP (needs `device_midi.cc`, which includes ALSA): I will
move the byte-level handling behind a small function that the test can call, or test it through the
JACK MIDI path of step 2, which exercises the same parser.

**macOS:** plain clock/start/stop behave as before (same code); continue and SPP are new there too, since it is
shared code. Re-verify on macOS (list in the Phase 2 doc plus these files).

## 2. Clock: JACK MIDI input

**Why.** norns on Linux can only read hardware MIDI (`device_monitor.cc` lists rawmidi devices) and the ALSA
virtual port, which needs `/dev/snd/seq`. A JACK MIDI port makes any program that can send JACK MIDI (and, through
PipeWire's JACK emulation or `a2jmidid`, ALSA and other MIDI) able to send clock and notes to norns. Reaper on
Linux lists JACK MIDI among its MIDI backends (Cockos wiki; unverified in use).

**Design.**
- A new JACK client **"Verdandi"** (separate from the existing `matron-clock` client, so nothing that depends on
  that name changes) with a MIDI input port **`midi_in`** (and, later, `midi_out`). It is created with the other
  JACK clients when matron starts (`JackNoStartServer`, as `jack_client.cpp` does).
- The process callback does no work beyond copying events (bytes and frame offset) into a lock-free ring buffer
  (`third-party/readerwriterqueue` is already there); a reader thread feeds the **existing parser** through a norns
  MIDI device, using the same pipe approach as the keys device (`from_pipe` in `device_midi.cc`). The device is
  registered as "Verdandi JACK in" (name to confirm); it is a normal norns MIDI device: scripts can read it, and the
  clock source `midi` takes it (`clock_midi_in` = all, or its vport).
- Timing: the first version uses the arrival time like every other MIDI device (`clock_get_system_time()` when the
  reader thread sees the byte). The frame offset is kept in the ring, so a follow-up can compute the tick time from
  the JACK frame time (steadier tempo, no thread wake-up jitter); I will measure the jitter in the test before
  deciding it is needed.
- No auto-connection by default: the port shows up in `jack_lsp`, `qpwgraph`, Helvum and Reaper's JACK MIDI
  settings. (Auto-connecting every physical MIDI source is possible later; it can surprise people.)
- Not in this step: JACK MIDI output (clock out to a DAW, norns as master), a UI to pick ports.

**Tests (headless).** jackd dummy + a small test client (C, JACK API, in `linux/tests/`) that sends
0xF8 x 24 per beat at 120 BPM, 0xFA, 0xF2, 0xFB, 0xFC with real timing; the probe sets `clock_source` to midi and
checks `clock.get_tempo()` (about 120), beats after start, SPP position, continue and stop through Lua; plus note
messages arriving at `midi.connect():event`. Under CPU load with the probe's readiness wait (see
`KNOWN-ISSUES.md`: I will fix that wait first, with your OK, or the load tests would be flaky for the same reason).

**Not testable here:** Reaper itself (checklist: send clock to a JACK MIDI port, norns follows tempo, start, stop,
continue, SPP), and the PipeWire exposure of ALSA MIDI.

## 3. crone, physical ports, and the audio server

**Finding (`KNOWN-ISSUES.md` 2).** `crone/src/Client.h`: `connectAdcPorts()` / `connectDacPorts()` look for
`JackPortIsPhysical` capture and playback ports and **throw** if there are none. That is right for a device with a
sound card and is what the Pi and macOS rely on. In my PipeWire experiment (`pw-jack`), norns connected to
PipeWire's JACK and stopped here: no physical ports in a PipeWire without a sound card. Real laptops probably
have them, but that is unverified.

**Proposal (crone change, small).**
1. As today: connect to the first two physical ports when they exist.
2. If there are none: try the conventional names `system:capture_*` / `system:playback_*`.
3. If still none: **do not throw.** Start with crone's inputs and outputs unconnected, print one clear line
   ("no physical audio ports: connect crone:output_1/2 yourself, for example with qpwgraph"), and carry on, so
   norns, the clock and the UI work and routing can be done in a patchbay. (The Pi path is unchanged.)
The same applies when a port count is odd (mono microphone case is already handled).

**Audio server detection in `linux/norns.sh` (proposal).**
- Order: a JACK server that already answers (jackd or PipeWire's, for a program started under `pw-jack`) is used as it
  is. If none answers and **PipeWire is running** (`pw-cli info 0` works) and `pw-jack` exists, `norns.sh` re-runs
  itself as `pw-jack linux/norns.sh ...` (so sclang's scsynth and crone talk to PipeWire too). Otherwise it
  starts jackd as now (`alsa` with the device from `audio.conf`, or `dummy`).
- Today, on a PipeWire desktop, plain `linux/norns.sh` finds no JACK server and starts `jackd -d alsa`, which fails
  because PipeWire holds the card; `RUN-ON-LAPTOP.md` tells you to use `pw-jack` yourself. The re-exec removes that step.
  Override: `NORNS_AUDIO_SERVER=jackd|pipewire`.

## 4. `audio.conf` and SYSTEM > AUDIO on Linux

Keep the file and the keys (`input= output= rate= period=`; empty = default). `lua/core/menu/audio.lua` reads
the device list from the tool named in `NORNS_AUDIO_TOOL` (TSV: `uid TAB name TAB inputs TAB outputs TAB rates`).
- **Device list:** new `linux/audio_devices.c` (ALSA `snd_ctl` / `snd_pcm_hw_params`, same TSV; uid like
  `hw:CARD=Fireface,DEV=0`; `--default-input/--default-output`), built by waf next to `norns`; same format, so
  the Lua menu does not change. Used only when jackd drives the card (no PipeWire).
- **jackd mode:** `norns.sh` starts `jackd -d alsa -C <in> -P <out> -r <rate> -p <period>` (`-s` when the two differ)
  and falls back to defaults leaving `audio.conf.failed`, as the macOS launcher does.
- **PipeWire mode:** the card belongs to PipeWire, so INPUT and OUTPUT rows say "managed by PipeWire"; RATE and
  BUFFER are requested for norns' own clients with `PIPEWIRE_QUANTUM=<period>/<rate>` (my understanding of
  pipewire-jack; **unverified here**) and applied by restarting norns, as today. If it does not work as I think, the
  rows are shown read-only.
- RME Fireface under ALSA (Gate D was about Windows ASIO; on Linux the card is a normal ALSA device).

## 5. MIC / SYS / APP / OFF

**Today** (`lua/core/menu.lua`): MIC connects/disconnects `system:capture_N` to `crone:input_1/2` with `jack_lsp
-c`, `jack_connect`, `jack_disconnect`; SYS and APP exist only if `_norns.app_input` is registered, which on
Linux it is not (Phase 2 left it out on purpose), so the button goes MIC > OFF. `_norns.monitor_out(false)`
(crone input monitor to tape only) is generic oracle code.

**Plan.**
- **MIC/OFF:** generalise the port match: any *physical* capture port, found from `jack_lsp -p` flags rather than
  the literal `system:capture_N` (PipeWire may not name them that way; unverified).
- **SYS and APP:** `matron/src/platform/linux/app_audio_linux.c` replaces the stub: the JACK API in matron's own
  client. SYS = the monitor ports of the default sink (PipeWire names and presence to be verified on your
  laptop; plain jackd has no monitor, so SYS is simply not offered); APP = the output ports of another JACK client
  (PipeWire shows each audio-playing application as a JACK client); both connect to `crone:input_1/2` and
  disconnect when changed or when the application goes away. `app_audio_list` fills the in-window menu ("Input:
  system audio", "Input: <application>"). `_norns.app_input` and `monitor_out` get registered for Linux in
  `weaver.cc` once this works.
- Keeps the file markers (`.mic-off`, `.norns-input`) and the labels of the macOS code.

**Tests:** headless with jackd dummy: a test client with a tone as the "application" and a client standing for "system"
playing; SYS/APP connect it; crone's input level polled from Lua (`poll` amp_in_*) shows the tone; MIC/OFF
disconnect and reconnect. **Not testable here:** the real PipeWire monitor/application ports.

## 6. Real devices

- MIDI hardware, HID (evdev), serial (grid, arc, crow): upstream code paths already compiled in the Linux build:
  `device_monitor.cc` (libudev), `device_midi.cc` (ALSA rawmidi), `device_hid.cc` (libevdev), termios. The
  container has no devices, so the udev hotplug code runs but finds nothing. What I can do: check that the monitor
  starts, document the permissions a user needs (`audio` group, `dialout` for serial devices, udev access to
  `/dev/input` for gamepads), and list the real tests in the hardware checklist (USB MIDI keyboard, grid, arc,
  crow, gamepad, hotplug).
- **Real grid/arc** go through libmonome and serial devices (the udev path my libmonome patch leaves alone). The
  serialosc/OSC route is Phase 5.5 (Gate F).

## 7. Risks and what I will not do
- PipeWire is the biggest unknown: port flags, monitor ports, quantum request. I will not claim any of it works
  before it ran on your laptop.
- `crone/src/Client.h` and `clock_midi.cc` are shared with macOS and the Pi: the changes are additive and the old
  behaviour stays when ports/messages are as before; macOS needs a re-run of its tests.
- The stress-test race (`KNOWN-ISSUES.md` 1) will make load-dependent tests flaky until the probe waits for
  readiness. The fix is small and proven in scratch (10/10 under load).

## 8. Decisions I need from you
1. **OK to start with steps 1 and 2** (SPP/continue, then JACK MIDI input), tests first, as above?
2. **Apply the probe readiness fix** from `KNOWN-ISSUES.md` (needed before load tests are meaningful)?
3. crone without physical ports: **start unconnected with a warning** (my proposal) instead of failing?
4. `norns.sh` **re-running itself under `pw-jack`** when PipeWire is running (proposal), or keep it manual?
5. SYSTEM > AUDIO under PipeWire: rows read-only/"managed by PipeWire" plus `PIPEWIRE_QUANTUM` for rate/buffer?
6. Name of the JACK MIDI client/device ("Verdandi" / "Verdandi JACK in") and no auto-connect: OK?
7. MIDI **start after SPP**: begin at the SPP position (my reading of the standard) or always at beat 0 as today?
8. Please run the laptop checklist (at least `pw-jack jack_lsp -p`) so steps 3 and 5 are based on facts.


---

# Steps 1 and 2: results (written after they were done)

**Step 1, SPP and continue.** Done as designed, with tests first (8 new cases in
`tests/matron/clocks/clock_midi/test_clock_midi.cpp`, 15 in all). What the code does now (`clock_midi.cc`):
- 0xF2: counter = position * 6 - 1 (the next tick is the one at the position); the beat moves at once when a tempo is known;
  the position is remembered until a start, continue or stop uses or drops it.
- 0xFA: starts there if a position is waiting, else at beat 0 (counter -1); the start event fires at the first counted tick.
- 0xFB: no counter change; the first counted tick fires `clock_continue_from_source` (a new function: the same event
  to scripts as a start, **without** `clock_scheduler_reset_sync_events()`).
- 0xFC: unchanged, and it forgets a waiting position. Ticks still count while stopped (unchanged behaviour: an
  existing test depends on it); so after SPP and a stop the counter advances if ticks keep arriving.
- Found on the way and fixed: `clock_midi_init()` did not reset the smoothing buffer (harmless at startup, wrong when
  init runs twice, as in the tests).
- SPP parsing in `device_midi.cc` (`dev_midi_consume_buffer`, shared with macOS and every MIDI device).

**Step 2, JACK MIDI input.** `matron/src/platform/linux/jack_midi_in.{h,cc}`: client "Verdandi", port `midi_in`,
real-time callback only copies into a `ReaderWriterQueue` (4096 entries, never allocates) and `sem_post`s; a reader
thread writes the bytes into a pipe; the norns MIDI device "Verdandi JACK in" (`jackmidi:`) reads the pipe with the same
parser and `from_pipe` path as "Verdandi keys". Started from `dev_monitor_scan` (Linux desktop only);
`NORNS_JACK_MIDI=0` turns it off; no auto-connect. Test: `linux/tests/jack_midi_clock_test.c` is a JACK client that plays
a 120 BPM "DAW" (start, a note, SPP 16 beats, stop, continue, start) with frame-accurate timing, and
`probe_jackmidi.lua` + the `clock:` check in `run_all.sh` verify it from Lua. Results of the first complete run:
`start 0.02` (beat), note on and off received, `stop 18.00` (SPP 16 beats at 3.0 s plus 2 beats), `continue 20.00`
(**no reset**), second `start 0.00`. That run also proves the SPP bytes pass the device parser.

**Tempo accuracy, measured, not yet fixed.** With the dummy JACK driver (period 1024 frames = 21.3 ms at 48 kHz) the
tempo estimate read 122.3, then 117.2 and 122.2 (median) for a true 120. The beat position is exact (it counts
ticks); only the tempo estimate and the extrapolation between ticks are affected. Likely cause: JACK delivers MIDI
in period bursts, and the first version timestamps a message when the reader thread handles it, so arrival times are
quantised to the period. **Option (needs your OK, shared code):** keep each event's frame offset through the queue and
give `clock_midi` the exact JACK time (`clock_midi_handle_message_at(msg, time)`); the tick intervals would then be
exact in the JACK time domain. I did not verify this explanation by building the option.

**Shared files changed in steps 1-2 (re-verify macOS):** `matron/src/clock.cc`, `clock.h` (new
`clock_continue_from_source`), `matron/src/clocks/clock_midi.cc`, `clock_midi.h`, `matron/src/device/device_midi.cc`
(SPP hook for every device; the JACK path is `NORNS_LINUX_DESKTOP` only), `tests/matron/clocks/common/helpers.{cpp,h}`
(weak stub), `tests/matron/clocks/clock_midi/test_clock_midi.cpp`. `device_monitor.cc` and `norns/wscript` are Linux-only
changes. On macOS: plain clock/start/stop behave as before; continue and SPP are new there too.
