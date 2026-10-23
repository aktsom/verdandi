# Clock notes: following an external or DAW clock (wishlist item 2)

Read-only investigation. No repository code was changed for it. One scratch experiment outside the repository
(a Link peer, section 2) was run to get evidence rather than guesses. Wishlist: norns' clock must follow an
external or DAW clock, the same on Linux, Windows and macOS; the DAW is Reaper.

## 1. What norns has today (code, all shared; macOS adds almost nothing)

Clock sources are `internal`, `midi`, `link`, `crow` (`matron/src/clock.h`, `lua/core/clock.lua`, parameter
`clock_source`).

**MIDI clock in** (`matron/src/clocks/clock_midi.cc`, 93 lines):
- `device_midi.cc` `dev_midi_consume_buffer` hands every realtime byte (>= 0xF8) of any MIDI device whose
  `clock_enabled` is true to `clock_midi_handle_message`. 0xF8 = tick, 0xFA = start, 0xFC = stop. **0xFB
  (continue) and Song Position Pointer (0xF2) are ignored**; start resets the beat counter to 0.
- Tempo is the mean of the last 24 tick intervals measured with the system clock (no timestamps from the MIDI
  layer), so it is as steady as the delivery path. A gap over 4 beats' worth is treated as a stop.
- Which device: parameter `clock_midi_in` = all / none / vport 1-16 (`midi.update_clock_receive`,
  `lua/core/midi.lua:416`), applied through `_norns.midi.set_clock_enabled` (`weaver.cc:1814`).
- MIDI clock **out** exists (`clock_midi_out_1..16`).

**Ableton Link** (`matron/src/clocks/clock_link.cc`, 180 lines, `third-party/link` as a submodule):
- Compiled when `HAVE_ABLETON_LINK` (default on, `wscript:125`); `main.cc:99` starts a Link thread always
  (`clock_link_init/start`); the session is joined when the source is set to `link`. Tempo, beat and optional
  start/stop sync are followed (`link_start_stop_sync`); quantum is settable (`link_quantum`).
- `third-party/wscript:21`: `LINK_PLATFORM_MACOSX` on macOS, `LINK_PLATFORM_LINUX` otherwise. The macOS port
  only fixed a mutex initialisation in `clock_link_init` (git: `b13bb4d`).

**macOS, as it is today**
- External MIDI clock: yes, through the same parser. CoreMIDI sources arrive via `device_midi_coremidi.inc`;
  other apps can send to the virtual destination norns makes (`NORNS_VIRTUAL_DST_UID`), so a DAW that sends
  MIDI clock to it works.
- Link: yes, same code, `LINK_PLATFORM_MACOSX`. Nothing in `readme-macos.md` or the manual mentions either.
- **The AUv3 does not carry the DAW's musical clock.** The manual's "norns follows the DAW's clock" means the
  *sample clock* (resampling between the DAW and JACK). `macos/auv3/bridge_protocol.h` has audio, raw MIDI
  bytes and bye, but no tempo, no position, no play state; `NornsAU.mm` reads none of the host's musical
  context. MIDI the DAW sends to the plugin reaches norns as the device "Verdandi AUv3", but hosts do not
  normally pass MIDI clock to an instrument/effect plugin.

**Linux desktop build (this branch)**
- **Link is compiled in and works.** Evidence: `HAVE_ABLETON_LINK=1` in the build; the `clock_link` thread
  and Link's own threads are in the running process; and an experiment: a separate Link peer (a 40-line
  program on the same `liblink-c.a`, in the scratchpad, not in the repository) at 97 BPM, norns with
  `params:set("clock_source", 3)`: norns reported **1 peer and `clock.get_tempo()` = 96.99995** within six
  seconds, in this container (Link discovery over loopback/multicast worked here; other networks may differ).
- **MIDI clock in works on the parser level, but norns has no way to receive another program's MIDI on
  Linux.** `device_monitor.cc` only lists hardware rawmidi devices (`/dev/snd/midiC*D*`). The one
  program-visible input is the ALSA "virtual" rawmidi (`dev_midi_virtual_init`, an ALSA *sequencer* client);
  it needs `/dev/snd/seq`, which this container lacks (boot log: "failed to open alsa virtual device").
  The "Verdandi keys" device from Phase 2 is an output-only source for other programs.

## 2. What it takes to follow another program on the same machine

Reaper facts (from user reports and the Cockos wiki, **not verified against Reaper itself**):
- Reaper can send MIDI beat clock and start/stop/SPP to an enabled MIDI output ("send clock to this device").
- Reaper can only *slave* to MTC, SPP or LTC, not to plain MIDI clock: **Reaper must be the master; norns
  cannot drive Reaper by MIDI clock.**
- Reaper has no native Ableton Link that I could confirm; a third-party Reaper extension for Link exists
  (found on a GitHub topic page, name, status and platforms not checked).
- Reaper on Linux lists "ALSA (raw)" and "JACK MIDI"; whether it can use ALSA **sequencer** ports directly
  is not documented in what I found. A seq port may need the `a2jmidid` bridge or PipeWire to show up.

**Option A, MIDI clock through a virtual MIDI port (per OS plumbing)**

| OS | what Reaper sends to | what norns needs |
|---|---|---|
| macOS | the CoreMIDI virtual destination norns already makes | nothing (works today) |
| Linux | an ALSA seq port or a JACK MIDI port | an **inbound ALSA sequencer port** (client "Verdandi", writable port; read with `snd_seq_event_input`, decode with `snd_midi_event`, feed the existing parser like the keys pipe) and/or a **JACK MIDI input port** on matron's existing JACK client (`jack_client.cpp`), which PipeWire and a2jmidid expose to Reaper. Roughly 150 lines each. Without `/dev/snd/seq` only JACK MIDI works. |
| Windows | a virtual port made by a driver: **loopMIDI** (third-party, ports exist only while its app runs) or the **Windows MIDI Services loopback endpoints** (Microsoft, persistent, new; dynamic ports of other tools are not always visible there) | a Windows MIDI backend in matron (WinMM, WinRT/Windows MIDI Services or RtMidi) listing the port as a device. Needs Phase 6 work anyway. |

Limits: tick/start/stop only (no SPP/continue unless added; the counter restarts at start), tempo is measured
from delivery time so USB/driver jitter shows; the user must set up a port and enable "send clock" in Reaper.

**Option B, Ableton Link**
- Already in the code; verified working on Linux (above); same code on macOS; Windows: Link supports it, the
  build needs `LINK_PLATFORM_WINDOWS` and the asio/winsock bits (Phase 6; not tried).
- Gives tempo, beat phase and optional start/stop, with no port plumbing and nothing OS-specific for norns.
- Needs a Link source **inside Reaper** (third-party extension, status unknown), which is a dependency on a
  plugin Ken must install on each OS. Link aligns phase on the network clock, it is not sample-locked to
  Reaper's timeline and has no SPP-style jump.

**Option C, the DAW plugin carries the transport (AUv3 now, VST3 in Phase 7)**
- Extend the UDP protocol (`bridge_protocol.h`) with a transport message (tempo, PPQ position, playing,
  sent from the host's process context: AU musical context block, VST3 `ProcessContext`). The bridge turns it
  into MIDI clock + start/stop (or SPP) for an **internal** norns MIDI device (the same pipe trick as the
  keys device), so the existing `clock_midi` source follows it. No virtual MIDI driver on any OS, sample-accurate
  to the DAW timeline, the same protocol on macOS and Windows.
- Needs a plugin on the platform: macOS AUv3 exists (Reaper loads AU on macOS); Windows VST3 is Phase 7;
  **there is no Linux plugin in PLAN.md**, so on Linux Option C does not exist unless a Linux plugin is added
  (Reaper loads VST3 on Linux).
- Also fixes "plugin in a DAW but tempo not followed" for every host, not only Reaper.

**Option D, JACK transport** was not pursued: I found nothing saying Reaper syncs to it, and it carries no
tempo map without extra conventions.

## 3. Recommendation

1. **Link first, as the common denominator.** It is the only option that is already built, already verified
   working on Linux, identical on macOS, and needs no per-OS port plumbing in norns; Windows needs one build
   define in Phase 6. Condition: Ken confirms a Link source for Reaper on each OS that he is willing to use
   (the third-party extension, unverified). Cost for norns: about nothing (UI/param polish only).
2. **MIDI clock inbound as the fallback that needs no Reaper add-on:** macOS works; on Linux add the JACK MIDI
   input port first (works with PipeWire and without `/dev/snd/seq`), the ALSA sequencer port second; on
   Windows it comes with the MIDI backend of Phase 6 plus loopMIDI or the Windows loopback.
3. **Option C as the planned best answer for plugin use**, designed into the VST3 phase and added to the
   AUv3 (transport message type in the bridge protocol, internal clock device). Decide at Gate E whether a
   Linux plugin is wanted.
Do not promise norns-as-master towards Reaper: Reaper does not slave to MIDI clock.

## 4. Decisions needed from Ken
1. Is a Link extension in Reaper acceptable (and should I check which one exists and works on Linux, macOS and
   Windows before we rely on it)?
2. Should the JACK MIDI input (and later the ALSA sequencer input) be built in the Linux baseline, or after it?
3. Is a Linux DAW plugin (VST3) wanted, so Option C exists on all three systems?
4. Do you want SPP and MIDI continue (0xFB) supported in `clock_midi` (norns ignores them today)?

## Sources
- [REAPER for Linux (Cockos wiki)](https://www.cockos.com/wiki/index.php/REAPER_for_Linux)
- [Ableton Link topic for REAPER plug-ins (GitHub topic page)](https://fr.github.com/topics/reaper-plugin)
- [REAPER sends clock/SPP to outputs, slaves to MTC/SPP/LTC (user reports)](https://forum.simntonic.com/viewtopic.php?p=3233),
  [Elektronauts thread](https://www.elektronauts.com/t/transport-receive-a-stop-from-reaper-just-pauses-the-octatrack/251680)
- [Windows MIDI Services loopback setup](https://microsoft.github.io/MIDI/tools/midiloopbacksetup/),
  [known issues and workarounds](https://devblogs.microsoft.com/windows-music-dev/windows-midi-services-rollout-known-issues-and-workarounds/),
  [loopMIDI](https://www.tobias-erichsen.de/?p=45)
