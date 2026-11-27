# M39 (Linux): Verdandi follows another program's MIDI clock by itself (the default of midi_in_from)

## What the owner found by hand
Reaper's built-in virtual MIDI output (ALSA sequencer client "Client-128", port "Virtual RawMIDI"; in PipeWire the source `Midi-Bridge:Client-128:(capture_0) Virtual RawMIDI`) reaches Verdandi after `pw-link "<that port>" "Verdandi:midi_in"`. With PARAMS > CLOCK > midi clock in = "virtual" Verdandi then follows Reaper's clock, start and stop. The link is lost when either program restarts.

## 1. The way (no new dependency)
The mechanism already exists since M3: `midi_in_from=` in audio.conf (`NORNS_MIDI_IN_FROM`), `matron/src/platform/linux/midi_autoconnect.cc` with the decisions in `crone/src/MidiRoute.h` (tested). It uses the JACK API (`jack_connect` on the JACK client Verdandi already has). On PipeWire this IS a PipeWire link: PipeWire's JACK layer shows the ALSA sequencer ports as `Midi-Bridge:...` and `jack_connect` makes the same link as `pw-link`. A thread looks every 2 s and at once when a port is registered (so a program that starts later, or restarts, is found without a busy loop), logs with a throttle per port, never links norns' own ALSA clients (found through the sequencer by the thread id) nor "Midi Through". It was off unless the owner wrote a list. So the work is the DEFAULT, not a new connection path. The alternative (the ALSA sequencer: subscribe the Reaper port to a sequencer port of Verdandi and bridge it to JACK) would need a second input path into the same device and is not needed: the JACK port `Verdandi:midi_in` is already the device "virtual", with the clock timed by JACK (`jack_midi_in.cc`).

## 2. What changed
- `linux/norns.sh`: with no `midi_in_from` line in audio.conf and no `NORNS_MIDI_IN_FROM`, the value is `Midi-Bridge:Client-*Virtual RawMIDI` and `NORNS_MIDI_IN_FROM_DEFAULT=1`. A line `midi_in_from=<list>` replaces it, a line `midi_in_from=` (empty) turns it off, the environment variable still beats the file.
- `midi_autoconnect.cc` in the default mode: one source only (the one linked already stays; else the first by name; the others are said once: "also found ..., not linked"), because two programs that both send clock into the one device would double every tick. A list the owner writes links every match, as before. Never linked on the input side: norns' own clients, "Midi Through", the kernel's virtual MIDI card (names "VirMIDI", "Virtual Raw MIDI") and the target of `alsa_midi_out_to` (`inputNever`).
- Log, once each: at start the line of the default, "connected <port> to Verdandi:midi_in", and when the program quits "<port> is gone (it was linked ...)", then "connected" again (said at once after a "gone" line; a link repaired without the port going away is limited to one line per minute and port, as before).
- No "no JACK server" line for the default (it is on for everyone). The row "AUTO-LINK" on SYSTEM > DEVICES (MIDI list) shows in the default only while a program is linked ("AUTO-LINK: 1 linked").
- `crone/src/MidiRoute.h`: `defaultInFrom`, `inputNever`, `chooseOne`, `vanished`.

## 3. The default and how to switch it off
`Midi-Bridge:Client-*Virtual RawMIDI`: the `*` stands for the client number and covers both name orders PipeWire has used (`Client-128:(capture_0) Virtual RawMIDI` and `Client-20 Virtual RawMIDI:(capture_0)`). A hardware interface is `Midi-Bridge:<its name>:...` (no "Client-"), the kernel card is "VirMIDI"/"Virtual Raw MIDI" (with a space), Verdandi's own ports are excluded by the checks above. Off: put the line `midi_in_from=` (nothing after it) in `audio.conf`. Another list: `midi_in_from=Midi-Bridge:Reaper;...` (a prefix list, `*` allowed).
Any other program that makes a virtual RawMIDI output (alsa-lib's "virtual" device) also matches: that is what the default is for. The device that receives is still the one called "virtual"; PARAMS > CLOCK > midi clock in must be set to it by the owner (this phase makes the connection automatic, not the clock source).

## 4. Edge cases
- Two matching sources: one linked (above), the other said once. If the linked one goes, the other is linked at the next look.
- None: nothing is linked, nothing is said (the "AUTO-LINK" row stays hidden).
- PipeWire not running: with plain jackd there are no `Midi-Bridge` ports, nothing matches. With no JACK server the thread is not started (as before, no line in the default). The existing fallbacks (jackd, `NORNS_AUDIO_SERVER`) are unchanged.
- A device Verdandi sends to (`alsa_midi_out_to=VirMIDI`): excluded on the input side, so there is no feedback loop.

## 5. Tests
- `tests/crone/test_midi_route.cpp`: both name orders matched; mio, Midi Through, VirMIDI, a plain client, own clients and the `alsa_midi_out_to` target not; one source of two (the linked one stays, else the first); a vanished port.
- `linux/tests/midi_autoconnect_test.sh` scenarios `default` (linked at start, "gone", linked again after the program restarted with another number, exactly one line each, no flood) and `default2` (two sources, mio and the VirMIDI card in the graph: one linked, the second said once), on a real jackd with fake clients, run from `run_all.sh`. They fail on the code before M39 (`phase-m39-without.txt`).

## Not tested here
Reaper, PipeWire's real port names (the fake client uses the names the owner reported), the real clock of a real DAW. `docs/port/HARDWARE-CHECKLIST.md`.
