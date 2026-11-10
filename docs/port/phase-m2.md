# Windows M2: real audio output (approach note)

Written before the code (working agreement). Context: `docs/port/windows-plan.md`; M1 is tested on a real PC (window, keyboard, SELECT, awake opens, null audio). Goal of M2: **sound**: the owner hears awake through the default Windows output, chooses the device in SYSTEM > AUDIO, and gets a plain note instead of a hang when the device is busy or missing. No ASIO (M3), no input from the sound card.

## The design, and why (the recommendation asked for)

Three ways to join the three audio programs of a norns (crone's mixer and softcut, SuperCollider's engines, the sound card):

| design | what it is | verdict |
|---|---|---|
| **A. two device clients**: scsynth plays through PortAudio, crone through PortAudio | two streams on the same device, no connection between them | **rejected**: crone must receive the engines (it mixes them with softcut, tape, reverb, levels, and records them); the AUDIO and MIX pages would not work |
| **B. scsynth inside norns.exe** (the `scpump` idea of the plan) | libscsynth as a library, one callback runs both | **not now**: scsynth is started by sclang (`Server.boot`) as its own program; moving it in needs a patched sclang boot path and a second look at every `Server` call of norns's classes. Large, and untestable on a runner without a card. Kept as the later option if the bridge's extra block ever matters |
| **C. one clock, a bridge (built)**: norns.exe owns the card and runs crone's blocks in the card's callback; scsynth has **no device**: its driver computes one block each time norns.exe hands it one, through a named shared memory and a named event | JACK-like in structure; Windows' own WASAPI timing drives everything | **chosen** |

Why C: (1) **one clock**: crone, softcut, the clocks and the engines all run at the card's rate, so there is no drift between engines and mixer and no sample-rate conversion between two devices; (2) it reuses what M1 proved: crone and matron already talk to the JACK-compatible backend (`jack_null`), which now runs its blocks from the card's callback (`verdandi_jack_null_process`) instead of from a timer thread; (3) the same flow works with **no card** (the timer thread paces norns.exe, scsynth follows the bridge exactly as with a card), so the CI runner tests the whole chain, and a busy or missing device falls back to silence without changing anything else; (4) the bridge is a header (`matron/src/platform/windows/audio/verdandi_bridge.h`) shared by norns.exe and the scsynth patch: one protocol, tested on Linux (in a thread, as two processes against a real patched scsynth) and under Wine (two Windows processes: the real named memory and event). Cost: **one block of extra latency for engine sound** (the engine's block is ready for the next callback). At 512 frames that is 10.7 ms; the AUDIO page can lower the block.

## Data flow

```
 WASAPI shared (PortAudio) callback, norns.exe, 512 frames @ 48000 Hz by default
   -> verdandi_jack_null_process(): capture ports = silence (no input yet); runs the clients in order:
        crone (mixer, softcut, tape, ...)  -> its output_5/6 = the feed for engines (ADC)
        "SuperCollider" client (audio_bridge_host.c): output_5/6 -> shared memory, signal the event; takes scsynth's block of the previous callback -> crone:input_5/6
        (the client breaks the dependency loop: crone reads the engine one block late)
      crone output_1/2 -> system:playback_1/2 -> the card
 scsynth.exe (no device): wait for the event -> run its engine for the block -> write the answer
```
`crone:output_5/6` and `input_5/6` and the client name `SuperCollider` with `in_1 in_2 out_1 out_2` are exactly what sclang's `jack_connect` lines wire on Linux; norns.exe makes these connections itself (a helper thread waits for crone's ports), the `jack_connect.cmd` stand-ins of M1 stay harmless.

## Parts

1. `verdandi_bridge.h`: ring of 8 blocks each way, counters with barriers, never blocks the card (a late scsynth means silence from the engine path and a counted underrun; no scsynth means nothing is queued), bounded latency (blocks older than 2 are dropped), host close wakes scsynth.
2. `jack_null.c`: external clock (`verdandi_jack_null_external_clock`, `_configure(rate, frames)`, `_process`) and the loop-breaker flag. The null timer path is unchanged.
3. `audio_device.c` (portable, tested): the decisions. Values from `audio.conf` (`output=`, `rate=`, `period=`) and the environment, replaced by defaults with a note when out of range (rate 44100/48000/88200/96000, block a multiple of 64 up to 2048; default 48000 and 512). Order: chosen device -> if it is **not found**, the default device with a note -> if the rate is refused, the device's own rate -> otherwise (**busy**, no device, cannot start) **null audio with a note**; never a hang, never an exception. One log line per decision; `audio.conf.failed` is written for the AUDIO page and removed after a good start.
4. `audio_backend_pa.c`: PortAudio, WASAPI host API only, shared mode, `paWinWasapiAutoConvert` when the header has it (the Windows mixer converts the rate), 2 channels float, `framesPerBuffer` = the block, suggested latency = max(block, the device's low latency). Lists output devices as `wasapi:<name>` (a name stays the same between runs, an index does not).
5. scsynth: `windows/patches/scsynth-null-audio.patch` now holds the bridge driver (`VERDANDI_BRIDGE=<name>`), the null clock (`VERDANDI_NULL_AUDIO=1`, also the fallback when the bridge is missing after 20 s) and leaves PortAudio unused by Verdandi: **scsynth never opens a device**, so nothing can hang on one.
6. `Verdandi.exe`: names the bridge per round (`VerdandiBridge-<pid>-<round>`), `--null-audio`, and a restart loop: norns.exe ending with **exit code 42** (SYSTEM > RESTART, APPLY on the AUDIO page) makes the launcher stop sclang and scsynth and start both again, so a new device takes effect. The Windows-safe launch rules (sclang from its folder with relative ASCII arguments) are unchanged.
7. SYSTEM > AUDIO (`lua/core/menu/audio.lua`): the output list comes from `_norns.audio_devices()`, saved in `audio.conf` like on Linux; INPUT is shown read only ("none yet"); the bottom line shows `<rate> Hz <ms> <device>` or the plain fallback words; a fallback also shows a note on the window (`menu.lua`).
8. Logs (`logs\norns.log`): `audio: PortAudio ...; host APIs: ...`, `audio: device '<name>' (Windows WASAPI shared), 48000 Hz, 512 frames per block (10.7 ms), output latency 21.3 ms`, `audio bridge: ...`, and in `sclang.log` the driver's lines.

## ASIO (M3) and the WASAPI-only cost
- **Licence.** Steinberg released the ASIO SDK under a **dual licence since October 2025: the proprietary agreement or GPLv3** (their press release of 2025-10-15; the SDK's FAQ says choosing GPLv3 means the product is released under GPLv3 including source, and the ASIO name needs their trademark rules). Verdandi is GPL-3.0, so the GPLv3 option fits; the SDK would be a build input downloaded in CI, not committed (`DEPS.md`). **Not checked by me:** the text of the SDK's own `LICENSE.txt` (read it before a release) and the trademark rules (calling the output "ASIO" in a menu). A WASAPI-only build stays a CMake-level fallback.
- **WASAPI-only cost** (estimates, **not measured**): shared mode runs through the Windows audio engine with a 10 ms period (Windows 10 and later; PortAudio's WASAPI does not use the 3 ms IAudioClient3 mode as far as I know). Expect an output latency of about 20 to 30 ms, plus the block of crone (10.7 ms at 512) and the bridge block for engine sound: **roughly 40 to 55 ms from a key to sound for engine voices at 512 frames, 30 to 40 ms at 256**. ASIO on the interface (RME) would be about 5 to 12 ms. Exclusive-mode WASAPI would be lower but blocks every other program (not offered). The numbers are the first thing to measure with the owner's PC (a loopback recording of a click, M3).

## What cannot be tested here
Everything on a real card: PortAudio's WASAPI on Windows (is WASAPI built into MSYS2's PortAudio? the log line `host APIs:` says), the real latency, the Windows mixer's rate conversion, device names with accents, hot-unplug. **Tested here:** the whole chain with a fake card on Linux and under Wine (crone stand-in, bridge host, scsynth stand-in; busy, missing, rate-refused devices; audio.conf values); a real patched scsynth (3.14.1 source, Linux PortAudio build) against the bridge host: 440 Hz sine, input pass-through, zero underruns in 14 s; two Windows processes with the named memory and event under Wine; the PortAudio backend against libportaudio on Linux (no card: not found, fallback); the AUDIO page; the launcher restart loop under Wine; the mingw cross-compile of every source.
