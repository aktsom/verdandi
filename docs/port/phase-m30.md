# M30: the windows-latest release lost the ASIO zip

No product code changed. Only release publishing (`windows/ci/publish-release.sh`, `.github/workflows/windows-m1.yml`) and its test.

## What happened (run 44723649106, commit 25cb7da, version 0.10.18)

- One workflow (`windows-m1`) builds both zips and has ONE release job, `Publish the zip to GitHub Releases`, that waits for both package jobs. So there was no race between two publishing jobs and no path filter that skipped the ASIO job: its build jobs ran and the ASIO package job started.
- The ASIO package job's step "Start it headless and check" has a limit of 30 minutes. On 0.10.16 (run 44627179517) it took 23 minutes; on 25cb7da it ran from 11:05:38 to 11:34:59, the whole 30 minutes, and was cut off. The checks that had not finished were all recorded as "NOT FOUND", the job's Gate step (19 failed checks) failed on purpose, and the upload of `m3-asio-zip` was skipped. That is by design: a zip whose checks failed is not handed to the release.
- `publish-release.sh` then ran with no ASIO zip. Its clean-up loop at the end of the update of `windows-latest` removed every ASIO file ("not in this run, remove it"). That is why `Verdandi-windows-asio-latest.zip`, its versioned copy and its `.sha256` were gone, while 0.10.15 to 0.10.17 (all ASIO jobs in time) had them.

So: the cause was (1) the step limit that left almost no room, and (2) a publish script that deleted the other zip's files when its own run had none.

## What changed

- `publish-release.sh`: it only adds or replaces. When the run has no ASIO zip it keeps the ASIO files already on `windows-latest` and writes a note on the page ("the ASIO zip on this page is the one of the older build X"), plus a workflow warning. When the run has an ASIO zip, the ASIO files of older builds are replaced and the fixed names are never removed.
- After publishing, the script reads the release itself and fails (exit 1, with the names) if `Verdandi-windows-latest.zip`, its `.sha256`, `Verdandi-windows-asio-latest.zip`, its `.sha256` or `BUILD.txt` is not there.
- `windows-m1.yml`: the ASIO package job has 90 minutes (job) and 75 minutes (step) instead of 30, so a slower runner does not cut off a run that is working.
- Test: `linux/tests/release_publish_test.sh` (stand-in for `gh`, test `windows:publishing a build ...`). New cases: old ASIO files are kept when the run has none; a release without the ASIO zip, or without the default zip, fails the publish step with the names; with an ASIO zip the older versioned ASIO file is replaced. Six checks fail on the old script (`docs/port/phase-m30-without.txt`).

What this cannot do: if the ASIO checks really fail, there is still no new ASIO zip for that commit. The release then keeps the last good ASIO zip and says so, and the per-commit release `windows-<hash>` of that commit has the default zip only. The ASIO zip of an old build is never presented as the new one.

## Second cause, found on the next run (72380cf)

With the limits raised, the ASIO job ran 22 minutes and its step passed, but one check failed: `m20-check-asio-reopen`, the probe `asio-reopen-back`. The probe asks the running program to apply a setting and reads the answer line `VT_APPLY ...` from the console stream. The program's own log line (`clock: internal ticks woke ...`, every 10 s) was written into the same stream and cut the answer in two, so the probe found no answer ("rc=?") and judged the test failed, although the driver had reopened correctly (the next probe, `asio-reopen-refused-goes-back`, passed). A flake of the test, not of the program; it gated the ASIO zip out of the release a second time. This time the new publish step did its job: it failed the publish with "windows-latest is missing: Verdandi-windows-asio-latest.zip ..." and the release page said that the ASIO zip was not made.

Fix (CI test code only, `windows/ci/maiden_probe.py`): when the answer line is lost, the probe asks again (up to three times; both calls leave the program in the same state, so asking twice is harmless). I could not run this probe here (it needs the Windows runner); the proof is the next Windows run.

## ONE ZIP? (check only, nothing built)

### Does the ASIO build offer everything the normal build does?
- Both zips are the same `norns.exe` and the same everything. They differ in one file, the PortAudio DLL, plus notices (`ASIO-NOTICE.txt`, `licenses\ASIO-SDK-LICENSE.txt`, `source\`, `FLAVOR.txt`).
- Normal zip: MSYS2's PortAudio package, host APIs WASAPI, DirectSound, MME (the comment in `build-portaudio-asio.sh` says so; WDM-KS I could not confirm from the repository). No ASIO.
- ASIO zip: PortAudio 19.7.0 built by `build-portaudio-asio.sh` with `-DPA_USE_ASIO=ON -DPA_USE_WASAPI=ON -DPA_USE_DS=ON -DPA_USE_WMME=ON -DPA_USE_WDMKS=OFF`: ASIO, WASAPI, DirectSound, MME, no WDM-KS.
- Verdandi itself lists and uses only WASAPI and ASIO devices (`audio_backend_pa.c`; DRIVER normal / exclusive use WASAPI, low latency uses ASIO). So for what Verdandi does, the ASIO build already covers every use of the normal build. The smoke test of the ASIO job checks the ASIO API is listed, the WASAPI fallback and the input. Not checked: that the two PortAudio builds behave the same on a real PC for WASAPI (latency, rates); CI has no sound card.

### Licence reason for two zips?
What the SDK's `LICENSE.txt` says (read in a CI log, from the `audiosdk/asio` mirror, not from Steinberg's own file): "This Software Development Kit is licensed under the terms of the Steinberg ASIO License, or alternatively under the terms of the General Public License (GPL) Version 3. You may use the Software Development Kit according to either of these licenses as it is most appropriate for your project on a case-by-case basis (commercial or not)."
- Verdandi is GPL-3.0, so the GPLv3 option fits, and publishing openly on this public fork is what the GPL asks for as long as the corresponding source and licence text travel with the binary (the ASIO zip already carries the SDK licence, PortAudio and SDK source, the source offer and a trademark notice). The note `docs/port/asio-licence.md` says the same.
- Not clear / not verified: (a) the licence text comes from a third-party mirror, not Steinberg's own repository (which is not public); (b) "GPL-3.0-only" or "or later"; (c) Steinberg's trademark rules for the name "ASIO" (the program uses the word only to name the driver interface; no logo); (d) this is a reading by someone who is not a lawyer.
- So the licence is not a reason by itself to need two zips, if the GPL notices and sources go into the one zip. The original reason for two zips was caution (a): not to put SDK code into the default build until the text was read from Steinberg.

### If one zip is possible: what would change
- Build: the default build would use the ASIO PortAudio DLL (or ship both DLLs and choose one). `windows-m1.yml` would lose the separate `package-asio` job and its second headless check, or keep the ASIO job only as a check; `assemble-m1.sh` would drop `FLAVOR`; `publish-release.sh` would lose all ASIO handling (this also removes the two-job problem of this phase).
- Static names: `Verdandi-windows-latest.zip` stays and holds everything. `Verdandi-windows-asio-latest.zip` (and its versioned copy and sha256) would be published for a while as the same file under the old name, so old links and the ASIO `update-and-run.cmd` keep working.
- Risk for the owner's ASIO setup: low if the ASIO zip's DLL is what ships, because that is the DLL used today (same latency, buffer sizes and rates). The risk that is new is for WASAPI-only users: PortAudio's ASIO host API, as far as I know its source (not checked here), loads every installed ASIO driver at `Pa_Initialize`, so a broken or busy driver (Ableton holding the RME) can slow or disturb start-up even when the user only wants WASAPI. Verdandi already handles "ASIO busy" with a fallback, but that is the ASIO build's behaviour today, and this has not been measured on a PC with several ASIO drivers.
- "Load ASIO only if the machine has an ASIO driver": PortAudio 19.7 cannot switch a host API off at run time. The safe way is to ship both DLLs (`libportaudio.dll` without ASIO, and an ASIO one), and have the launcher pick the ASIO one only when a setting asks for it or when an ASIO driver is registered in the Windows registry (`HKLM\SOFTWARE\ASIO`). That keeps WASAPI-only machines on today's DLL. It costs one extra DLL (about 0.3 MB, not measured) and a small launcher change; I have not built or tested it.

### Recommendation
**One zip is possible and I recommend it, with the two DLLs and the registry rule,** after the owner has read the SDK's `LICENSE.txt` from a build (point (a) to (c) above) and says yes. It removes the two-zip publishing problem for good. If the owner does not want to decide the licence question yet, the simpler fix is what this phase did: keep two zips, one release job that only adds and replaces, and a check after publishing. Either way the owner decides; nothing was built for this answer.
