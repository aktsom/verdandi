# Windows M3: ASIO output, sound input, the RME Fireface UC (approach note and results so far)

Written before and while the code was changed. Context: M1 and M2 run on the owner's PC (WASAPI shared output to "Speakers (RME Fireface UC)", 48000 Hz, 512 frames, 23.4 ms output latency). The M2 design stays: **`norns.exe` owns the sound card through PortAudio; scsynth is a client of the shared-memory bridge.** Licence of ASIO: `docs/port/asio-licence.md`.

## 1. What was built

| Part | Where | What |
|---|---|---|
| Device model | `matron/src/platform/windows/audio/audio_device.[ch]` | one backend interface (`list`, `open`, `start`, `close`, `open_sys`, `close_sys`, `describe`), host-API aware uids `wasapi:<name>`, `asio:<name>`; the decisions (config, fallback chain, input state, level, measurement) are here and run in tests with a fake card |
| PortAudio backend | `audio_backend_pa.c` | lists WASAPI and ASIO devices (loopback devices flagged); duplex stream when the input is on the output's device, a separate input stream (WASAPI, another device) with a ring; ASIO channel selectors for outputs 3+4 etc. and input channels; WASAPI loopback of the default output for SYS; `describe` lists the host APIs in the log |
| `audio.conf` | `output= input= rate= period= out_first= in_l= in_r=` | `output=` missing = the Windows default device; bad values are replaced with a note |
| AUDIO page | `lua/core/menu/audio_win.lua` | HOST, OUTPUT, OUT CH, INPUT, IN L, IN R, RATE, BUFFER, APPLY, TEST, LATENCY, MEASURED, LEVEL; the bottom lines say what runs or why not |
| Input switch | `lua/core/menu.lua`, `weaver.cc` (`_norns.mic_input`, `_norns.app_input`, `_norns.audio_input`, `_norns.audio_measure`) | MIC > SYS > OFF as on Linux; **OFF at every start**, nothing remembered |
| Two builds | `windows/ci/build-portaudio-asio.sh`, `assemble-m1.sh` (`FLAVOR=asio`), workflow jobs `asio`, `package-asio` | default zip WASAPI only; ASIO zip with PortAudio+ASIO, notices and sources |

**MSYS2 or vcpkg for the ASIO PortAudio: MSYS2**, built from source (PortAudio 19.7.0 tag, ASIO SDK from Steinberg's repository, both pinned by commit in `windows/ci/asio-sdk.env`). Reason: `norns.exe` and all its DLLs are MSYS2 UCRT64; the ASIO DLL is a drop-in with the same file name (`libportaudio-2.dll`, the loader goes by the name), so **one `norns.exe` serves both zips**. vcpkg would add an MSVC-built DLL with its own runtime and a second package manager for the same file, and MSYS2's own PortAudio package has no ASIO.

## 2. Behaviour (all of it tested with the fake card on Linux)

- **Fallback chain, never a hang:** chosen device -> (not found) the Windows default device, with the note "audio device 'X' not found, using the default device" -> (rate refused) the device's own rate -> (**ASIO busy or failing**) **the same hardware through WASAPI**, with the note "ASIO driver 'X' is busy: another program has it (close its audio, or use the driver's multi-client mode). Using WASAPI on 'X' instead" -> (nothing works) null audio with "no sound: ... null audio is used". The page shows the short form, the window the whole sentence.
- **Input:** a duplex stream when the input is on the output's device (always so with ASIO, which is one device: an input on another device is refused with that reason), else a separate WASAPI input stream feeding a ring (a drift of the two clocks is absorbed by the ring: surplus blocks are dropped, missing ones are silence, both counted). The input reaches crone's `system:capture_1/2`, so it is crone's ADC and, through crone, scsynth's input buses, exactly as on Linux. **No input device or no loopback: MIC/SYS stay OFF with the reason on the window** ("MIC: no input is open (choose one on SYSTEM > AUDIO, INPUT)").
- **Channels:** IN L and IN R pick any two input channels (1 to N) of the device; the same channel twice is a mono source on both sides; OUT CH picks the pair (ASIO only; WASAPI shared has the stereo pair of the Windows device). The mapping code is one shared function (`vaud_pick_pair`) used by the backend and by the tests.
- **Safe defaults:** input OFF at every start (the log says so); `audio.conf` can name an input but nothing reaches norns until MIC or SYS is chosen.
- **SYS:** WASAPI loopback of the default render device. It hears **everything Windows plays**, including Verdandi's own output if Verdandi plays through that device (feedback!) and **not** what Ableton plays through ASIO (that does not go through Windows' mixer). The window does not warn about that yet (the log line `audio: SYS: listening to what Windows plays ('<device> [Loopback]')` names what is heard); the setups below avoid the feedback case. Monitoring is the Linux rule (`lua/core/menu.lua` calls `_norns.monitor_out`): **MIC and OFF** have crone's input monitor on (so MIC is heard through the output: with speakers next to a microphone that can feed back, which is why MIC is never on at the start), **SYS** has it off (Windows already plays that sound directly, a monitor would double it).
- **Level and measurement:** LEVEL is the peak of the input in dB (falls 12 dB per second); TEST sends a click (8 samples at 0.9) and watches the **raw input** for the first sample above 0.3; MEASURED is the time between them, "no signal" after 2 s. It needs a loop from an output to an input (a cable, or the TotalMix Loopback, setup c) and a quiet script (a loud input is taken for the click). The fake loop of 1024 frames measures 21.33 ms, as it should.

## 3. The owner's setups

State of the evidence: **none of this was run on the RME or with Ableton.** The RME facts are from RME's manuals and forum posts quoted in `windows-plan.md` and are **unverified for the Fireface UC and for the driver version installed**.

### (a) Verdandi alone on ASIO
Close Ableton (or set its audio device to something else), start Verdandi, SYSTEM > AUDIO: HOST ASIO, OUTPUT the Fireface driver, OUT CH the pair you listen to, INPUT the same driver if MIC is wanted, BUFFER, K3 APPLY. Latency is the driver's (buffer size from the RME Settings dialog; PortAudio adapts to the block of the BUFFER row and may add up to one block). Expected: LATENCY out about 5 to 12 ms (estimate), plus one block for engine sounds.
If another program (Ableton) has the driver: the page says "no sound... ASIO busy" **or** (the chain above) Verdandi runs on WASAPI on the same hardware with that note. Fix: close the program, or enable the driver's multi-client mode (RME states multi-client ASIO for several of its interfaces; **whether the Fireface UC with your driver does it is not verified**: look in the RME Settings dialog and the driver manual), or take route (b) or (c).

### (b) Verdandi on WASAPI shared next to Ableton (the M2 route; recommended to start with)
Ableton keeps the RME through ASIO. Verdandi uses the **Windows device of the same interface** (HOST WASAPI, OUTPUT "Speakers (RME Fireface UC)" or another pair of it). This worked in M2 (sound heard, Ableton open). The Windows mixer sits in between: a few tens of ms of delay for engine sounds (estimate), no input from Ableton, **SYS does not hear Ableton**. Verdandi's output is on the same hardware output as whatever Windows plays; to keep it apart, send the Windows device's channels to their own pair in TotalMix FX (section below).

### (c) Verdandi's output into TotalMix Loopback, recorded by Ableton (recommended for recording into Ableton)
Idea: Verdandi plays to a pair of the interface that nobody listens to directly; TotalMix FX's **Loopback** function returns that pair as an **input** of the interface; an Ableton audio track records that input. Click by click (names follow RME's manuals; **not seen on your screen; the wording of buttons can differ by TotalMix version**):

1. **Verdandi:** SYSTEM > AUDIO: HOST WASAPI, OUTPUT the interface's playback device (the one Windows lists for it, e.g. "Speakers (RME Fireface UC)" or the 3+4 / other pair device if the driver offers one), APPLY. (If ASIO is available to Verdandi at the same time as Ableton through multi-client: HOST ASIO, OUT CH 3+4.)
2. **TotalMix FX:** the upper row shows the hardware inputs, the middle row the **software playback** channels (what programs play through the driver), the lower row the hardware outputs. Find the playback channels Verdandi plays to (in the middle row, the pair that moves when Verdandi plays; the names are the pair names, for example "AN 1/2" for the Windows default device).
3. Select the **hardware output** strip of the pair you want to use for the return (for example AN 3 and AN 4, lower row). Open its **settings** (the Settings button of the strip / the Settings panel, "Channel" section) and switch **Loopback** on. (RME documents Loopback for the UCX, UFX and 802; **whether the Fireface UC's TotalMix has it is not verified. If the setting is not there, use a cable from an output to an input as the fallback**.) With Loopback on, that output pair is not a physical output any more: it is the return.
4. Route Verdandi's playback channels to the loopback pair: click the playback strip (middle row), then in the lower row click the fader of AN 3 and AN 4 (the "submix" view); raise them to 0 dB. Verdandi's sound now goes to the loopback pair; to **also** hear it, route the same playback strip to the outputs you listen on (AN 1/2) at the level you like.
5. **Ableton Live:** Preferences > Audio: Driver Type ASIO, Audio Device the Fireface; **Input Config**: enable the input pair that is the loopback (the same number as the output, AN 3 / AN 4, "3/4"). In a new **audio track**: Audio From **Ext. In** and the pair 3/4, Monitor **In** (or Auto), arm the track. Verdandi's sound shows on the track's meter.
6. **What to check:** you hear Verdandi (via the routing to 1/2), the track meter moves, nothing hums or doubles (a path that goes from the loopback back to Verdandi's own input would feed back: do not choose the loopback pair as Verdandi's input unless you want that).
7. **Input of Verdandi from Ableton (optional):** the other way round, send an Ableton track to the pair that Verdandi uses as INPUT (hardware output of Ableton -> TotalMix -> loopback or an input). This is a second loop; try it after the first works.

What I could not verify: all TotalMix button names and positions, that the UC offers Loopback, that the Windows device and the ASIO driver can be used at the same time, and what Ableton shows.

### Which one first
(b) first (it worked), then (c) with WASAPI. ASIO (a) when the sound at 512 frames is not responsive enough and Ableton is closed or the driver is multi-client.

## 4. Latency, honestly

Numbers below are **estimates from the code paths**, not measurements; the page and the log give the real ones.

| Part | At block 512 (10.7 ms) | At 256 (5.3 ms) | At 128 (2.7 ms) |
|---|---|---|---|
| norns.exe callback (crone, softcut, the MIX): the card's own output latency | LATENCY "out" | same | same |
| **engine sounds: the extra block in the bridge** (scsynth computes the block the card needs next) | **+10.7 ms** | +5.3 ms | +2.7 ms |
| input to crone (MIC): input latency of the driver | LATENCY "in" | same | same |
| MIC through an engine (a script that processes the input in scsynth) | in + out + 1 bridge block + 1 for the return | | |

- The page shows `out X in Y +Z ms`: X and Y are what the host API reports (PortAudio's `outputLatency` and `inputLatency`), Z is the one block of the bridge, **added only for sounds made by scsynth** (engines, effects in scsynth); softcut, tape and the monitor path are in the card callback and do not pay it.
- **MEASURED** is the real round trip output -> loop -> input (TEST), which includes the driver, the Windows mixer where there is one, and the cable or Loopback; it does **not** include the bridge block.
- **Smaller blocks (128, 256):** the BUFFER row offers 64 to 1024. At each size the page counts **under** (bridge underruns: scsynth was late for a block) and **xrun** (the host API flagged an underflow or overflow at the card). The default stays **512** until you report which sizes stay clean on your PC; the Linux test with the fake card runs 128 without drops (`small` scenario), a real card and scsynth on a busy PC may not. With ASIO the buffer of the driver is what really counts (RME Settings dialog); the BUFFER row is what norns asks PortAudio for.
- Unmeasured: all real numbers above.

## 5. Tests

On Linux (and Wine for the same C code compiled for Windows): `linux/tests/audio_chain_test.c` (fake card: device list text with APIs, latencies and loopback flags; config keys; ASIO ok, ASIO busy -> WASAPI with the note, ASIO driver gone, input duplex / separate / mono / ASIO channels, MIC without input, SYS with and without a loopback, OFF silent and the level falling, measured round trip 21.33 ms and "no signal", xrun counting), `audio_pa_test.c` (the PortAudio backend on Linux: unknown device and unknown ASIO driver refused as not found, host APIs described, the loopback open does not hang), `audio_page_windows_test.lua`, `input_windows_test.lua`, `assemble_flavor_test.sh`, `release_publish_test.sh`. On the CI runner (no sound card): `m2-check-audio` (the new log lines, ASIO listed only in the ASIO zip), `m2-check-fallback` (a missing output and input, channels), `m3-check-input` (MIC says no with a reason, SYS answers, OFF, measure says no signal), the ten restarts. **Not tested anywhere:** WASAPI loopback in MSYS2's PortAudio, any real ASIO driver, the separate input stream's drift handling on real cards, the real RME.
