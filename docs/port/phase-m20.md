# Phase M20 (Windows 0.10.11): the ASIO driver could not be opened a second time, and the sample rate

The owner's logs (RME Fireface UC, "ASIO Fireface USB", ASIO build 0.10.10): the driver opens and plays at the start of Verdandi (an hour with `u0 x0`, about 10 ms, Ableton open next to it; so this driver does allow more than one program). Every later open of the same driver while Verdandi runs ("apply" on the AUDIO page: other pair, other buffer, normal to low latency) fails with `Unanticipated host error: Failed to load ASIO driver` and Verdandi falls back to WASAPI. Only a restart brings ASIO back. And in one run the card was at 44100 Hz in the log while Ableton and the Fireface window said 48000.

## 1. Why a second open failed (reproduced, not guessed)

The five candidates, and what each one turned out to be:

| candidate | result |
|---|---|
| the start-up probe leaves the driver loaded (COM object not released) | No. The probe loads the driver on its own thread, asks, and releases it. The stub driver's log shows one `release` for every `init`. |
| PortAudio's ASIO host API supports one driver per process and the close does not unload | No. `Pa_CloseStream` calls `ASIOExit`, which (SDK `asio.cpp`) calls `removeCurrentDriver`, which releases the COM object. Open, close, open on one thread, 30 times: works. |
| `Pa_CloseStream` without `Pa_Terminate` leaves it loaded | No (same test). `Pa_Terminate` then `Pa_Initialize` also works. |
| **a thread or COM apartment mismatch between the first load and the second** | **Yes.** |
| the driver needs time after the close | No: the reopen is immediate in the test and works. |

An ASIO driver is an in-process COM object registered with `ThreadingModel Apartment`. PortAudio makes it with `CoCreateInstance` on the thread that calls `Pa_OpenStream`, and in PortAudio 19.7 only `Pa_Initialize` (and `PaAsio_ShowControlPanel`) sets up COM; `OpenStream` does not. So the thread that called `Pa_Initialize` (the one that starts the audio at the program's start) can open the driver, and any other thread cannot: the AUDIO page's apply runs on the Lua thread, the watchdog's reopen on its own thread. `CoCreateInstance` fails there, PortAudio reports it as `Failed to load ASIO driver`, and Verdandi's fallback said "busy or in use by another program": a wrong reason.

Reproduction (`linux/tests/asio_backend_test.sh`, the real `audio_backend_pa.c` and the CI's stub ASIO driver under Wine, PortAudio 19.7 built with the ASIO SDK for mingw): open from the thread that started works, again works, from a thread without COM fails with exactly the owner's message, from a multi-threaded COM thread fails, from another single-threaded COM thread works. With the fix all of them work; with the fix taken out the test fails on exactly those lines.

## 2. The fix: one thread for all of PortAudio (in-process; no restart needed)

Every call into PortAudio (list, open, start, close, open_sys, close_sys, describe, card_clock, refresh) is now done by one worker thread that initialises COM as a single-threaded apartment, whichever thread asks (`on_worker()` in `audio_backend_pa.c`). The callers wait for the answer, so nothing else changes. The worker also pumps its message queue while it is idle, as an apartment should. The audio callbacks stay on PortAudio's / the driver's own threads.

I chose this over "restart the audio through the launcher (exit code 42)" because the restart would reload the script and cost seconds on every change of pair or buffer, and the cause is understood and testable. The restart remains the way out if a driver ever misbehaves for another reason; it is not built in.

Also in the stub driver: mode `single` (one client at a time: a second `init` fails while another instance was not released), so a leak of the driver would show.

## 3. The AUDIO page on low latency

The OUTPUT row is the driver; OUT CH picks the pair. Channel names come from the driver (`ASIOGetChannelInfo`, read by the probe): the pairs are called after them, `1+2 Analog`, `9+10 SPDIF`, `11+12 ADAT`, and the help line names the two channels (`outputs 9+10: SPDIF L, SPDIF R`). The same for IN CH (pairs and single channels `3 mono Analog 3`). A driver that names nothing shows the numbers as before. A normal Windows device on the OUTPUT row is unchanged.

## 4. Sample rate

Where 44100 came from: PortAudio's ASIO host API reports as a device's `defaultSampleRate` the FIRST of 44100, 48000, 32000, ... that the driver says it CAN run at (`ASIOCanSampleRate`), which says nothing about the rate the card runs at now. Verdandi at the start follows the "device's rate" for ASIO (so as not to change a clock), so it followed 44100 for a driver that can do both, then opened the stream at 44100. PortAudio then looks at `ASIOGetSampleRate`; if it is not the asked rate it calls `ASIOSetSampleRate(44100)`, which asks the driver to change the card's clock. What the Fireface does while Ableton holds the card (refuses, or says yes and changes nothing, or changes it under Ableton) cannot be known without the card; none of the three is acceptable to rely on. The two log lines the owner saw ("output chosen ... 48000 Hz" and "device ... 44100 Hz") were the rate asked for in `audio.conf` and the rate after following; the second did not say that the card itself might run at something else, and PortAudio's `getStreamInfo` returns the asked rate, not the card's.

What 0.10.11 does:
- Before an ASIO stream is opened the card's clock is read from the driver itself (`ASIOGetSampleRate`, through the probe, which loads the driver for a moment). That is the rate listed for the driver (not PortAudio's default).
- At the start, the engine follows it (44100, 48000, 88200 or 96000; another rate is refused with a plain sentence).
- Verdandi never asks a driver to change the card's clock: a stream is only opened when the engine's rate is the card's rate, so PortAudio's `oldRate != sampleRate` test is never true. When the engine runs at one rate and the card at another (a live change after another program set the clock) the open is refused with: "the card (ASIO driver 'X') runs at 44100 Hz and the engine at 48000 Hz. Verdandi does not change a card's clock, another program may be using it: set the card to the engine's rate, or restart Verdandi so that it follows the card", and the old setting stays. A restart follows the card.
- Detection of a mismatch the driver did not report (a driver that lies, or any host API): the callbacks' frames per second against the PC's clock, over windows of 3 s. More than 5 percent off in two windows in a row: a line in the log (`audio: WARNING at ...: the card really delivers about N Hz of sound, but the engine, softcut and tape run at M Hz ... wrong pitch and speed`) and on the AUDIO page's status line (`RATE? N Hz`, then the sentence). 44100 against 48000 is 8 percent.
- The log has one line for the rates: `audio: rates: the engine, softcut and tape run at 48000 Hz; the card itself runs at 48000 Hz (read from the driver just before it was opened), the same` (or `DIFFERENT, the pitch and speed of everything would be wrong`). The "output chosen" line says "rate asked for".
- Does the engine run at the card's rate? SuperCollider (scsynth, the bridge), crone, softcut and tape all take the engine's rate from `verdandi_jack_null_configure(S.rate, ...)`: one number. If the card's real clock differs from it, everything is played at the wrong pitch and speed (44100 Hz of samples played at 48000 is 8.8 percent faster, 1.5 semitones up). That was possible in the owner's run only if the driver took `ASIOSetSampleRate(44100)` silently while the card stayed at 48000; the new measurement would have said so.

## 5. Tests

- `linux/tests/asio_backend_test.sh` (Wine; SKIP without a mingw ASIO build of PortAudio): list with names, the card's clock, buffer sizes; open and close from the starting thread, a thread without COM, MTA and STA threads, with other pairs and buffers, in `single` mode; a rate that is not the card's is refused with the card's rate, and the stub's log has no `set_rate`; every `init` has its `release`. Runs with the card at 48000 and at 44100.
- `linux/tests/audio_asio_page_test.lua`: channel names in the pair names and help, the status line with the measured rate.
- CI (`windows-m1`, ASIO job, real `norns.exe`, stub driver): `reopen` (driver in `single` mode: other pair and buffer, back, a change that cannot be made goes back to the driver, again, no "busy" and no "Failed to load" in the log, never a `set_rate`), `fromnull` (start without sound, choose the driver while running), `rate44` (the card at 44100: the engine follows it, and the measured rate agrees), `ok` (48000: the same), `hold` (the card at 44100 and held: refused with the plain sentence, never asked to change), `lie` (a driver that reports 48000 and delivers 44100: the warning appears). The check that engine and card rates agree is in `ok` and `rate44` (`asio-rate48-*`, `asio-rate44-*`).

## 6. Not tested (only the owner's PC can show)

- That the RME driver is also reopened by the same cure (it should: the cause reproduces and is cured with the same driver model); how it answers `ASIOGetSampleRate` while Ableton holds it (the start-up probe at the start read 48000 and "loads and starts" while Ableton was open).
- What the real driver does when two programs ask for it, what `ASIOSetSampleRate` would have done, and whether the owner's 44100 run was only a log line or really a clock at 44100 (the new measurement will tell).
- Switching normal to low latency and back on the real card: in CI the runner has no sound card, so "normal" is not available; the path ASIO to ASIO and from no sound to ASIO is tested, and the Windows normal path is unchanged.
