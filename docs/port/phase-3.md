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
PipeWire's JACK and stopped here: no physical ports in a PipeWire without a sound card. Real laptops have them: verified on
Ken's laptop (see "Laptop results" below).

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

**Tempo accuracy: found a defect, fixed with timestamps.** The first version stamped each message with the time
the reader thread handled it. JACK delivers MIDI in period bursts (21.3 ms at 1024 frames/48 kHz), so arrival times
were quantised: with the dummy driver the tempo read 122.3, 117.2, 122.2 for a true 120, and in a full test run
the first start event printed an **infinite** tempo and beat (two ticks of one period have the same arrival time,
interval 0). Fix, done in step 2 after measuring (I had offered it as an option; the infinite value made it a
defect): the JACK client keeps each event's frame time (`jack_last_frame_time` plus the event offset), and the
reader thread hands every clock message to `clock_midi_handle_message_at(msg, time)` with the event's time in the
clock's time base (now minus how long ago its frame was); the device parser leaves the clock messages of this
input alone (`clock_timed`), so start, continue, stop, SPP and ticks are all handled in one thread, in order.
`clock_midi` also no longer divides by a zero interval: ticks with equal times count, and the interval is measured
over the ticks since the last time stamp. Result in three consecutive runs: tempo `120.0`, beats `0.00`, `18.00`,
`20.00`, `0.00` at the transport events; two new unit tests (timestamps with a frozen system clock give 120.000
within 0.1%, a burst without timestamps keeps tempo and beat finite).
Other MIDI sources (hardware, the keys window) still use handling time: unchanged behaviour.

**Shared files changed in steps 1-2 (re-verify macOS):** `matron/src/clock.cc`, `clock.h` (new
`clock_continue_from_source`), `matron/src/clocks/clock_midi.cc`, `clock_midi.h`, `matron/src/device/device_midi.cc`
(SPP hook for every device; the JACK path and `clock_timed` are `NORNS_LINUX_DESKTOP` only), `clock_midi.cc` (`clock_midi_handle_message_at`, burst handling), `tests/matron/clocks/common/helpers.{cpp,h}`
(weak stub), `tests/matron/clocks/clock_midi/test_clock_midi.cpp`. `device_monitor.cc` and `norns/wscript` are Linux-only
changes. On macOS: plain clock/start/stop behave as before; continue and SPP are new there too.

---

# Laptop results (Ken, Linux Mint 22.2, PipeWire 1.0.5 with WirePlumber; pw-jack and jackd2 installed)

Hardware today: the built-in card, and a USB DAC for the second test. **No external audio interface on Linux for
now.** The RME Fireface is not USB class-compliant, so it cannot be used on Linux (on Windows it still needs ASIO:
Gate D is unchanged); a class-compliant interface may come later.

`pw-jack jack_lsp -p`, built-in card only:
- `Built-in Audio Analog Stereo:capture_FL`, `:capture_FR`: output, **physical**, terminal
- `Built-in Audio Analog Stereo:playback_FL`, `:playback_FR`: input, **physical**, terminal
- `Built-in Audio Analog Stereo:monitor_FL`, `:monitor_FR`: output, **not physical**
- `Midi-Bridge:Midi Through:(capture_0) Midi Through Port-0` and `(playback_0)`: MIDI, **physical**, terminal

`pw-metadata` (settings): `clock.rate` 48000, `clock.allowed-rates` [48000], `clock.quantum` 1024,
`clock.min-quantum` 32, `clock.max-quantum` 2048.

While a browser played audio: non-physical output ports **`Vivaldi:output_FL` / `Vivaldi:output_FR`** appeared, one
JACK client per audio stream; a second stream showed as **`Vivaldi-73`** (numeric suffix).

With a USB DAC (AudioQuest DragonFly Black v1.5) connected: `AudioQuest DragonFly Black v1.5 Analog Stereo:playback_FL/FR`
(input, physical, terminal) and `:monitor_FL/FR`. **It has no capture ports.** Both devices' playback ports are physical.

What this settles (replaces my earlier "unverified"):
1. **Physical-port detection works on real PipeWire.** The flag is there for the card and the DAC. The failure I
   saw in the container (no physical ports) was the container having no sound card.
2. Physical **MIDI** ports exist too (`Midi-Bridge:...`). crone's lookup (`jack_get_ports(..., NULL type, Physical |
   Output)`) does not filter by **port type**, so on this laptop it would also see the MIDI "Midi Through" port.
   Found by reading the data against `crone/src/Client.h`: the Linux desktop path must ask for audio ports only
   (`JACK_DEFAULT_AUDIO_TYPE`). Tested with a fake physical MIDI port.
3. **MIC/OFF must match capture ports by flag** (output + physical + audio), not by the literal `system:capture_N`
   in `lua/core/menu.lua`: there is no `system:` client on PipeWire. (Step 5; until then MIC/OFF under PipeWire
   will not disconnect anything.)
4. **SYS** (decision 9) uses the `:monitor_FL/FR` ports of the chosen output device (see the feedback analysis).
5. **ALSA MIDI appears as `Midi-Bridge` JACK MIDI ports** (physical): hardware MIDI is visible to JACK MIDI clients,
   so the "Verdandi:midi_in" port can be fed from a hardware keyboard or a DAW through the Midi-Bridge.
6. **Rate is fixed at 48000** here (`allowed-rates [48000]`): under PipeWire the RATE row can only be read-only; the
   buffer is the quantum (32 to 2048, now 1024).
7. Several devices have physical ports at once (built-in plus a DAC): a rule for which one crone uses is needed:
   decision 9.
8. Per-stream JACK clients named after the application, with a numeric suffix for further streams (`Vivaldi-73`):
   APP grouping (step 5) must tolerate the suffix.

## Decision 9 (approved by Ken): which device crone uses when several have physical ports
- **Output:** follow the **system default sink**. Overridable in `audio.conf` by **port-name prefix** (key
  `out_ports=`, for example `out_ports=AudioQuest DragonFly`). Same for the **input**: the default source,
  overridable with `in_ports=`. A prefix matches the JACK **client** part of the name (`<prefix>...:port`).
- **SYS** uses the `monitor_*` ports of the **chosen output** device (see the feedback analysis: open point).
- Query for the default sink, done by `linux/norns.sh` once at start (crone gets the result in `NORNS_OUT_PORTS` /
  `NORNS_IN_PORTS`; crone itself runs no program): `wpctl inspect @DEFAULT_AUDIO_SINK@` and read `node.description`
  (and `node.nick`/`node.name` for diagnostics); for the input `wpctl inspect @DEFAULT_AUDIO_SOURCE@`. The JACK
  client name of a card in your list equals the node's description (`Built-in Audio Analog Stereo`,
  `AudioQuest DragonFly Black v1.5 Analog Stereo`), which is why the description is the prefix to match.
  Alternative if `wpctl` is missing: `pw-metadata -n default 0 default.audio.sink` gives the default sink's
  **node.name** (`{"name":"alsa_output...."}`), which needs a `pw-dump` lookup to turn into the description.
- **Risks:** (a) the JACK client name is not guaranteed to be the description (it follows pipewire-jack's naming
  rules and `node.description` can change with the card's profile); I use it because your `jack_lsp` shows it, and
  fall back to the first physical group with a warning when nothing matches; (b) two identical devices have the
  same description: the first wins (a prefix cannot tell them apart; `audio.conf` could take the full port name);
  (c) `wpctl` output format could change: the parsing is tested against a fixture and fails soft (no prefix, first
  physical group); (d) the default sink can change while norns runs: norns follows it at start only (restart to
  follow); (e) the default **source** can be a monitor (not physical): then the first physical capture group is used;
  (f) a sink without capture ports (the DragonFly) is fine: input and output are chosen independently.

## Step 3 design updates
- **crone (Linux desktop build only, `NORNS_LINUX_DESKTOP`; Pi and macOS keep today's code and throw as before):**
  ask for **audio** ports, group candidates by JACK client, pick the group whose client name starts with the prefix
  (`NORNS_IN_PORTS` / `NORNS_OUT_PORTS`), else the first group (with a warning when a prefix was asked for and not
  found), connect its first two ports (a mono group feeds both channels), never mix ports of two devices. No
  physical audio ports at all: **do not throw**; start unconnected.
- **The warning must be seen in the window and menu, not only in the log** (Ken): crone records warnings
  (`crone_audio_warning()`); at start-up Lua shows them as a **persistent message on the norns window** and as a line on
  SYSTEM > AUDIO; `_norns.audio_warning()` returns the text (nil if none). Wording for the cases: no output ports
  ("no audio output: connect crone:output_1/2 yourself"), no input ports, a prefix not found.
- **`linux/norns.sh` audio server detection** (decision 4): (1) `NORNS_AUDIO_SERVER=jackd|pipewire|auto` (default
  auto); (2) a JACK server that answers is used as it is; (3) none answers, PipeWire is running (`pw-cli info 0`) and
  `pw-jack` exists: the script re-runs itself as `pw-jack linux/norns.sh ...` (a marker prevents a loop); (4) otherwise
  it starts `jackd` as before. `NORNS_DECIDE_ONLY=1` prints the decision and exits, for tests.
  Not decided by the script: the Mint laptop has both jackd2 and PipeWire; without a running `jackd` the answer is
  PipeWire, which is what you want.

## Step 4 design updates (`audio.conf`, SYSTEM > AUDIO)
- `audio.conf` keys: the existing `input= output= rate= period=` (jackd mode) plus `in_ports=` and `out_ports=`
  (port-name prefixes, decision 9).
- `norns.sh` exports `NORNS_AUDIO_SERVER_MODE` = `pipewire` | `jackd` | `external` (a JACK server that was
  already running). **Under PipeWire the INPUT, OUTPUT and RATE rows are read-only** ("managed by PipeWire", rate
  shown as the current one, 48000 on this laptop); **BUFFER** (quantum) is requested with
  `PIPEWIRE_QUANTUM=<period>/<rate>` for norns' own clients and is **marked experimental** (decision 5). In jackd mode the
  device rows work as on macOS, fed by a new `linux/audio_devices.c` (ALSA).
- The page also shows what crone connected ("out: <device>, in: <device>") and the warning, if any.

## Step 5 design updates (not built, waits for Ken)
- **MIC/OFF:** find the capture ports by flag: output + physical + **audio** type; connect/disconnect those of the
  group crone chose (not the literal `system:capture_N`).
- **SYS (decision 9):** the monitor ports of the chosen output device (`<client>:monitor_FL/FR` to `crone:input_1/2`).
- **APP:** list **non-physical audio output ports grouped by client name**, the numeric suffix removed (`Vivaldi`
  and `Vivaldi-73` are one entry; their ports are all connected, FL to input 1 and FR to input 2). Excluded: norns' own
  clients (`crone`, `softcut`, `matron-clock`, `Verdandi`, SuperCollider's `SuperCollider`) and **device clients**
  (clients that also own physical ports: their `monitor` ports are SYS, not an application) and MIDI ports.
  **Refresh as streams appear and vanish:** a JACK port/client registration callback (not polling) marks the list
  changed; the menu list is rebuilt when it opens and while it is open; if the chosen application's streams go away,
  the choice stays ("waiting for Vivaldi") and reconnects when a stream of that name comes back.
- **Feedback analysis (SYS through the sink monitor): there is a loop.** norns' own output (`crone:output_1/2`)
  goes to the chosen sink (decision 9: the default sink), and **the monitor of that sink is the sum of everything
  played into it, norns included**. With SYS on, crone's input then contains norns' own output: anything that
  routes input to output (the input monitor `monitor_level`, an engine like SimplePassThru, softcut/tape recording
  the input) feeds itself, a loop through the sound card's sink at unity gain (it can sustain, and grows with
  reverb or gain). The macOS tap avoids it because it taps "every app but norns' own processes". Prevention and warning I
  will build in step 5 unless Ken decides otherwise:
  1. **Switch the input monitor off while SYS is on** (`_norns.monitor_out(false)`, as the macOS code does for SYS/APP):
     this breaks the direct input-to-output path.
  2. **Warn on the window and on the MIC line** whenever SYS is active through a sink monitor that norns itself plays
     into: "SYS hears norns too; engines that play the input will feed back".
  3. **Offer the loop-free variant**: SYS from *all applications except norns* (every non-physical audio output of
     other clients, norns' own excluded, like the macOS tap), which needs no sink monitor. It is the one that
     matches "every app but norns" exactly. APP never has the loop (one application's own ports).
  This differs from decision 9 as worded ("SYS uses the monitor ports"); I keep decision 9 as the default and ask in
  decision 10 below whether the loop-free variant should be the default instead.
- **Decision 10 (new, for Ken):** SYS as sink monitor (decision 9) with the three safeguards above, or SYS as
  all-applications-except-norns (no loop) as the default, with the sink monitor as an advanced option?


## Step 3 results (crone ports, server detection)

Built tests first (all failed before: no `PortSelect.h`; the old binary stopped with "no ADC ports found" in the no-ports
scenario), then the code. What it does, on the Linux desktop build only (`NORNS_LINUX_DESKTOP`; Pi and macOS keep the old
`connectAdcPorts`/`connectDacPorts`):

- `crone/src/PortSelect.h` (pure logic): candidates must be **audio type and physical**; one client only (the first
  one, or the first whose name starts with the prefix); up to two ports, a single port feeds both channels; a prefix that
  matches nothing warns and falls back to the default; nothing at all returns no ports and a warning.
- `Client.h` reads `NORNS_IN_PORTS`/`NORNS_OUT_PORTS`, records the warning and the chosen client names in
  `AudioStatus.h` and **does not throw**; `_norns.audio_status()` returns warning, input client, output client.
- Window: `sdl_bridge_set_warning` keeps a standing note on the device screen ("AUDIO: not connected, see SYSTEM > AUDIO");
  other toasts show over it and it returns. The full text is printed in the log. (A first version put the whole text in the
  window and it was cut off; short text now, full text on the AUDIO page in step 4.)
- `linux/norns.sh`: decision table (tested with stubs, `NORNS_DECIDE_ONLY=1`):

  | situation | action |
  |---|---|
  | a JACK server answers | use it (server "pipewire" if we re-ran under pw-jack or it has `Midi-Bridge:` ports) |
  | none answers, `NORNS_JACK_DRIVER` given or `NORNS_AUDIO_SERVER=jackd` or PipeWire not running | start own jackd |
  | none answers, PipeWire runs, pw-jack found | run this script again under `pw-jack` |
  | PipeWire runs, no pw-jack | message with `apt install pipewire-jack`, exit 1 |
  | still no JACK under pw-jack | message, exit 1 (no loop) |

  Device prefixes, strongest first: environment, `audio.conf` (`in_ports=`, `out_ports=` in the norns home), the session's
  default source/sink read with `wpctl inspect` (`node.description`, which is the JACK client name; a default source that
  is a "Monitor of ..." is not taken as an input).
- Not verified on a real PipeWire: that `wpctl`'s `node.description` equals the JACK client name on every system (it
  was on Ken's laptop data), and the pw-jack re-run itself (tested with stubs and, earlier, by hand in the container).
  Changed shared files: `crone/src/main.cpp`, `crone_main.h` (now `extern "C"` for both languages), `matron/src/weaver.cc`
  (Linux-only functions), `matron/src/platform/macos/sdl_bridge.{cc,h}` (standing note: no effect while none is set),
  `lua/core/menu.lua` (a hook that only exists when `_norns.audio_status` does). Add to the macOS re-verification list.

## Step 4 results (audio.conf, SYSTEM > AUDIO on Linux)

Tests first (`linux/tests/audio_page_test.lua` for four modes, new cases in `launcher_test.sh`, `probe_audio_restart.lua`),
watched them fail, then:

- `lua/core/menu/audio.lua`: `NORNS_AUDIO_SERVER_MODE` (set by `norns.sh`) selects the behavior; unset = macOS, unchanged.
  `jackd`: as macOS, devices from `linux/audio_devices` (ALSA cards: `hw:CARD=<id>`, built by `linux/build.sh`).
  `pipewire`: INPUT / OUTPUT show what crone connected to, RATE shows the system rate, all read-only; BUFFER asks for a
  quantum and says "exp.". `jack` (a server we did not start): everything read-only, no APPLY. crone's warning is on the
  bottom line in every mode. Writing `audio.conf` keeps `in_ports=`/`out_ports=` and any other line (the card choice by
  prefix is made by editing the file; a picker is step 5 material if wanted).
- `norns.sh`: reads `audio.conf` (`input= output= rate= period=`; environment wins), builds the jackd arguments
  (`-C`/`-P` only for the alsa driver; one side chosen means the other is `hw:0`), falls back to defaults and
  `audio.conf.failed` if jackd does not start with the chosen settings, restarts jackd when SYSTEM > AUDIO leaves the
  audio mark (own jackd only), and under PipeWire turns `period=` into `PIPEWIRE_QUANTUM=<period>/<system rate>`
  for everything it starts. `NORNS_DECIDE_ONLY` also prints `DECIDE-JACKD`, `DECIDE-RATE`, `DECIDE-QUANTUM` for the tests.
- **Bug found and fixed on the way:** the sidecar's "detached" actions (SYSTEM > RESTART, SLEEP, and APPLY here) ran
  `sudo -n systemd-run ...` on desktop Linux too; without passwordless sudo and systemd (a container: "System has not
  been booted with systemd") the restart never happened. `norns/sidecar.cpp` now uses a plain shell for
  `NORNS_LINUX_DESKTOP` as for macOS. Shared file changed (Pi unchanged: the `#if` covers macOS and Linux desktop only).
- End to end (dummy driver, no card): apply writes `rate=44100`/`period=256`, norns restarts, jackd restarts with
  those values, crone comes back (`run_all.sh`, "audio:apply on our own jackd ...").
- Not tested here: real ALSA cards, two different cards as input and output, PipeWire quantum requests, the page on
  a real window with a long device name (the stub cuts names by character count; the page uses real text extents).
  See `HARDWARE-CHECKLIST.md`, "After Phase 3 steps 3-4".

## Step 5 results (MIC/OFF by flag, SYS, APP, optional sink monitor)

Decision 10, as decided by Ken: **SYS = every application client except norns' own clients; the sink monitor only as an
optional extra with a warning.** Decision 9 stands (crone follows the default sink, `audio.conf` overrides).
Tests first (`tests/crone/test_input_route.cpp`, `linux/tests/input_test.sh` + `probe_input.lua` with a fake card, fake
application streams and a late stream), then the code:

- **`crone/src/InputRoute.h`** (pure logic): an *application* is a client with audio output ports, none of them physical, that
  is not norns (`crone`, `softcut`, `SuperCollider`, `Verdandi`, `Verdandi ctl`, each also with a numeric suffix) and not a card
  (a client that owns any physical port: its `monitor_*` ports are not an application). Streams of one name are one entry
  (`Vivaldi`, `Vivaldi-73`). First port feeds `crone:input_1`, second `crone:input_2`, one port feeds both; several streams each
  give a pair. MIC = the capture ports of the chosen card by flag (physical, output, audio; the card from `in_ports=` /
  default source), never a MIDI port. Monitor = the `monitor_*` ports of the chosen output card.
- **`app_audio_linux.cc`** (replaces the stub): a JACK client "Verdandi ctl" does the connections and reads the port list. While
  SYS, APP or the monitor is on, a port/client registration callback wakes a thread that connects a new stream (a browser that
  starts playing) after 150 ms, without polling. A mode change is exact (what is not wanted is disconnected from
  `crone:input_1/2`); a new stream only adds. An application that is not running yet is picked up when it appears.
- **`lua/core/menu.lua`**: on Linux (`_norns.mic_input` exists) MIC/OFF use the card's ports by flag instead of the literal
  `system:capture_N`; SYS and APP are offered (`_norns.app_input`, `_norns.monitor_out` are now registered on Linux too);
  the MIC button goes MIC > SYS > (SINK MONITOR, if enabled) > OFF; while the sink monitor is on the device shows "INPUT: sink
  monitor hears norns too, feedback possible", otherwise the audio warning (if any) or nothing. SYS and APP switch crone's
  input monitor off (as on macOS): the applications also play directly, so norns must not play them a second time, and
  there is no loop because norns' own output is not an input source.
- **In-window menu** (right click or F10): "Input: microphone", "Input: all apps", the sink monitor if enabled, one line per
  running application (up to six, the list is made when the menu opens), "Input: off". The selection is kept for the next start
  like on macOS.
- Result in the fake-card test: SYS connects Vivaldi, Vivaldi-73 and mpv (FL to input 1, FR to input 2) and nothing of crone,
  softcut, SuperCollider, the card's capture or monitor; a stream started later is connected within 3 s; APP "Vivaldi" has
  both Vivaldi streams only; the monitor mode has the card's `monitor_FL/FR` only; MIC again has the capture ports only; OFF
  has no peers; the app list has no suffix and no norns clients.
- **Not tested:** real PipeWire streams (names with real applications; whether a stream's output port group always has the
  JACK client name of the application and appears on the first sound or already at stream start), the menu items on screen,
  a stream with a monitor-only or surround layout (more than two ports: the first two are used).
  Changed shared files: `matron/src/weaver.cc` (`_app_input`, `_monitor_out` no longer macOS-only), `matron/src/platform/macos/app_audio.h`
  (a new define), `matron/src/platform/common/desktop_shell.h` (menu ids), `lua/core/menu.lua` (guarded by
  `_norns.mic_input` / `NORNS_SYS_MONITOR`, macOS unchanged), `norns/wscript`.

## Design (not built, waits for Ken): optional auto-connect for MIDI input

**Problem seen on Ken's laptop:** Reaper's "virtual" MIDI output has to be connected to `Verdandi:midi_in` by hand, and the link
has been dropped several times although neither port disappeared (PipeWire's Midi-Bridge can drop a link when the bridge
client restarts or Reaper reopens its device, without the JACK port vanishing).

**Setting** (off by default): `midi_in_from=<prefix>` in `audio.conf`, or the environment variable `NORNS_MIDI_IN_FROM`
(the environment wins, as for the other keys). The value is the start of a JACK **port name** (the whole `client:port` string,
so `Midi-Bridge:Client-` matches every Midi-Bridge client of that kind and `Midi-Bridge:Reaper` a named one); several prefixes
separated by `;`. Empty or absent: nothing is ever connected (today's behavior: no auto-connect, decision 6).

**What it does:** the "Verdandi ctl" client (the one of step 5; it lives as long as norns) keeps a list of the prefixes and,
for every **MIDI output port** (type MIDI, output) whose name starts with a prefix, wants a link to `Verdandi:midi_in`.
- **Checks:** at start, on every port registration (registration callback, as for SYS), and on a timer every 2 seconds, because
  the dropped links come without any registration (the timer is the answer to "keeps checking").
- **Repair:** if a wanted link is missing, `jack_connect` it; log "midi: connected X to Verdandi:midi_in" the first time and
  "reconnected" when it was there before; at most one log line per port per minute so a flapping link cannot flood the log.
- **No more than asked:** only ports that match a prefix and only to `Verdandi:midi_in`; a link the user removes by hand
  while the port keeps matching is made again within 2 seconds (that is the point of the setting; the way to stop is to empty
  the setting). Ports of norns' own clients and MIDI **input** ports never match.
- **Visible:** SYSTEM > DEVICES > MIDI shows nothing new; the AUDIO page gets one extra line "midi in: <n> linked" while the setting is
  on (so a user can see it work). No toast on reconnects.
- **Cost/risks:** a 2 s timer thread calling `jack_get_ports` and `jack_port_get_all_connections` (cheap); a prefix that matches a
  port the user does not want (for example a hardware keyboard that is also sent to Verdandi on purpose by a patchbay): the
  prefix is the user's choice, written to be as specific as needed. Not a replacement for the DAW-side fix of why the link drops.
- **Tests (when built, first):** `InputRoute`-style pure logic in `crone/src/MidiRoute.h` (which ports match, which links are
  missing), a fake MIDI source client that is connected, disconnected behind norns' back and must be reconnected within 3 s,
  one that is registered later, and a non-matching one that must stay unconnected.
- **Open question for Ken:** the 2 s interval, and whether the AUDIO page is the right place for the status line.

## MIDI auto-connect: built (Ken's decision: as designed, 2 s re-check; status under SYSTEM > DEVICES > MIDI)

As in the design above, plus these details. Off unless `midi_in_from=<prefixes>` is in `audio.conf` or `NORNS_MIDI_IN_FROM` is set
(environment wins; prefixes separated by `;`, each the start of the whole `client:port` name). `linux/norns.sh` exports the value,
a hook at post-startup starts it (`_norns.midi_in_from`). The thread of `midi_autoconnect.cc` wakes every 2 s and on every
JACK port or client registration, links the matching MIDI output ports to `Verdandi:midi_in` and logs
`midi: connected X to Verdandi:midi_in` (first time) or `midi: reconnected X ...` (a link made again; at most one such line per port
per minute). `NORNS_MIDI_POKE=0` turns the registration wake-up off (tests, to prove the 2 s timer alone repairs a cut link).
- **Status line:** SYSTEM > DEVICES > MIDI (the list of the 16 MIDI ports) shows "AUTO-LINK: n linked" or "AUTO-LINK: none yet"
  under its title while it is on; nothing when it is off. The AUDIO page was not needed. The names of the linked ports are
  available from `_norns.midi_in_status()` (not drawn: no room on the screen).
- **Tests (first):** `tests/crone/test_midi_route.cpp` (prefix parsing, matching, own clients and non-MIDI never match, missing,
  throttle), `linux/tests/midi_autoconnect_test.sh` with a fake MIDI client "Fake DAW", a non-matching "Other" and a client "Late DAW"
  that appears later: linked at start; a link cut behind norns' back is made again within 4 s (conf scenario: only the 2 s timer;
  env scenario: wake-up by registration); the late client is linked; "Other" never; status 1 then 2; the log lines.
  `linux/tests/devices_midi_test.lua` for the page.
- **Not tested:** the real Midi-Bridge and Reaper (the dropped-link case on the laptop).

## Metro stack fix (Ken's decision)
See `KNOWN-ISSUES.md` item 4 (now FIXED for the Linux desktop build): 256 KiB stack, correct error names, a metro that cannot start says so
once; test with a TLS-pressure preload library (`linux/tests/tls_pressure.c`). No other small fixed-stack thread exists in the repo.
Shared file changed: `matron/src/metro.cc` (everything under `NORNS_LINUX_DESKTOP`; the macOS and Pi paths are textually the same as before).
