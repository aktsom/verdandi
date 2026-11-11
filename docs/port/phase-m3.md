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

## 6. Round 2: the owner's test of 0.3.0 (WASAPI shared, RME Fireface UC)

Findings: engine sounds about 34 ms at buffer 512 (unusable for playing); crackle at 128 and 256; the AUDIO page unreadable (dim rows, values cut off, eleven rows).

### 6.1 Why crackle (a diagnosis from the code and the fake card, not yet from your PC)
- In M2/M3 the engine's block, the card's block and the bridge's block were **one number** (`period=`). WASAPI **shared** mode runs on a fixed host period of the Windows audio engine (10 ms, 480 frames at 48000 Hz). Asking for 128 or 256 makes PortAudio re-block 480 into 128 or 256: the callbacks then come **in bursts** (two or three in a row, then a gap).
- Every callback hands one block to scsynth and takes back the answer to the block before. scsynth is **another program**; an answer needs a thread wake-up and a computation. When three callbacks arrive in a row the answers of the first two are not there yet: the bridge counts an underrun and plays **silence for that block**: a click. At 512 the bursts are rarer (about one block per host period) which is why it was clean.
- The same fake-card test now shows it: with the old rule, callbacks of 128 frames in bursts of four (a host period of 512) gave **84 bridge underruns and 351 drops in 638 blocks**; one card callback that runs four engine blocks gave 305 underruns in 636. With the fix both are 0.

### 6.2 What changed
| | Before | Now |
|---|---|---|
| Engine block (crone, scsynth, bridge) | = card buffer | `block=` in audio.conf, **default 128** (2.7 ms), independent of the card |
| Card buffer | asked from PortAudio (re-blocking by the host API) | `buffer=auto` (default): the host API's own period (no re-blocking, no bursts); or 64 to 512 |
| Between card and engine | nothing | two small fifos re-block the card's size into engine blocks (no allocation, no lock, no logging in the callback) |
| Bridge | answers of the last block, or silence | holds back **as many blocks as one card callback (or one host period) runs** (`lag`, 1 to 6), so a burst always finds its answers |
| Callback thread | normal | MMCSS **Pro Audio** (`PaWasapiStreamInfo` thread priority), WASAPI event driven (PortAudio's default) |
| scsynth, norns.exe | normal class | scsynth **high** (set by norns.exe once scsynth attached; same user, no admin), norns.exe above normal |
| Settings | APPLY restarts norns | **live**: only the stream is reopened (`_norns.audio_apply`), norns, the script, scsynth and the bridge run on; if it fails the old setting is reopened and one plain line says why; if nothing opens the engine goes on silently on its own clock and the next apply can bring the card back |

### 6.3 Realistic delay per setting (estimates from the code paths; **the page and norns.log show the real numbers**)
Delay of an engine sound (key to ear) = what the host API reports for the output + the engine's part. The engine's part is `lag x block + the re-blocking prime` (+ one block that the loop breaker in crone's graph adds, 2.7 ms at 128).
| Setting | Output (host API) | Engine part | Total, about |
|---|---|---|---|
| normal, auto (WASAPI shared, 10 ms period) | 20 to 24 ms (23.4 reported on your PC) | lag 4 x 2.7 + prime 2.7 = 13.3 | **35 to 40 ms**. This is the floor of shared mode: Windows' mixer period, not a bug. It was 34 ms before and is not better; it is **clean** |
| normal, buffer 256 or 512 | same | same (lag follows the host period) | same; no gain from smaller numbers in shared mode |
| exclusive, buffer 128 | about 6 to 8 | lag 1 x 2.7 | **10 to 14 ms** if your RME's Windows driver accepts exclusive streams |
| exclusive, buffer 64 | about 3 to 5 | lag 1 x 2.7 (64 < block) | 8 to 11 ms |
| low latency (ASIO), buffer 128 or the driver's own | the driver's | lag 1 x 2.7 | **8 to 12 ms** |
Softcut, tape and the monitor path (everything inside crone) do not pay the bridge part, only the output and the prime.

**Exclusive mode and Ableton.** In exclusive mode a program owns the device alone. If Ableton holds the RME through its ASIO driver, Windows refuses the exclusive stream (and the other way round: while Verdandi holds it exclusively, Ableton and every Windows sound lose the device). Verdandi then says so in one line and uses the normal mode. So exclusive is only for a session in which Verdandi is the only program on that device. Together with Ableton the choices are: normal (about 35 to 40 ms), or low latency (ASIO) if the RME driver lets two programs share it (multi-client, **not verified for the Fireface UC**).

### 6.4 The AUDIO page and the other pages (the UI principle)
- One short list as on a norns: E2 selects, E3 changes, K2 goes back. Rows: **DRIVER** (normal / exclusive / low latency when the ASIO build is used), **OUTPUT**, **OUT CH** (low latency only), **INPUT**, **IN CH** (when an input is chosen), **BUFFER**, **TEST**. No APPLY, no RATE (the rate is the one norns started with; `rate=` in audio.conf).
- Every change applies by itself about a second after the last turn (the status line shows `...`, `applying...`, then `ok` or one plain line such as `busy: another program has it`); on a failure the list shows what runs again.
- One status line: `35 ms  u0 x0` = estimated delay, `u` = scsynth was late for a block, `x` = glitches reported by the card. A longer sentence runs slowly across the line. Details (host API, card and engine blocks, out/in/engine parts, counters and their growth over the last 10 s, input level) are written to `norns.log` every 10 seconds as `audio: ...`.
- TEST row: `no input selected`, `input not open`, `listening...`, `no click heard`, or `NN ms`; the status line carries the sentence (`no click heard (is an output wired to the input?)`).
- Text: unselected rows level 11, the selected row 15 on a bar; values are measured with the real font (tests with cairo's metrics over 100+ views with the longest device names); a long value is cut with `..` or, on the selected row, runs slowly.
- **Other pages (Windows build only):** SYSTEM, DISPLAY, DEVICES, WIFI, SETTINGS, RESTART, RESET, UPDATE, SLEEP, MODS, SCREEN, THEME, MIDI MAP, CLEAN UP, SELECT and PARAMS are drawn through `winui.wrap`: levels 1 to 15 become 8 to 15 (0 stays black), so dim rows are readable; the selected row (15) is still the brightest. Their code is not changed, so their own widths and handlers are as tested before. The detachable screen window and everything of the Linux build are untouched (all of this is behind `_norns.audio_devices`, which only norns.exe has). MIX, TAPE, HOME and the colour picker are not wrapped (meters and colours there depend on the exact levels).
- Colour themes: the levels are indexes of the OLED palette, the theme tints them in the window as before; the remap only changes which index a dim row uses. Not looked at on a screen here.

### 6.5 ASIO in CI
The first real run of the ASIO job (run 42926894743) cloned PortAudio and the SDK (the SDK's `LICENSE.txt` read from the mirror: "licensed under the terms of the Steinberg ASIO License, or alternatively under the terms of the General Public License (GPL) Version 3") and then stopped at CMake: PortAudio 19.7.0 asks for CMake 3.1 and MSYS2's CMake refuses anything below 3.5. Fixed with `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`. Whether PortAudio's own ASIO options then find the SDK is decided by the next run (`PA_USE_ASIO`, `ASIOSDK_ROOT_DIR`, MinGW).
