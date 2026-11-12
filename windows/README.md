# Windows: milestone M0 (build check), step by step

M0 builds no product. It answers one question: **can the tools we need build and start on a Windows machine?** GitHub builds it for you on a Windows computer in the cloud; you download the result and look at one report. Nothing is installed on your PC.

Plan and context: `docs/port/windows-plan.md`. The scripts are in `windows/ci/`, the workflow is `.github/workflows/windows-m0.yml`.

## 1. Switch on Actions (once)

1. Open your copy (fork) of the repository on github.com.
2. Click **Actions** in the row of tabs under the repository name.
3. If you see a page saying workflows are disabled: click the green button **I understand my workflows, go ahead and enable them**. (A fork starts with this switched off.)
4. Check **Settings > Actions > General**. **Actions permissions** must be **Allow all actions and reusable workflows** (the workflow uses two helper actions from outside GitHub: `msys2/setup-msys2` and `ilammy/msvc-dev-cmd`). Click **Save** if you changed it.
5. A private repository uses your free monthly minutes, and Windows minutes count double. A full M0 run is expected to take about 15 to 30 minutes (the first run: SuperCollider 7 minutes, MinGW part 4 minutes), so under one hour of quota. A public repository has no limit.

## 2. Start the first run

A push that happened before you switched Actions on does not start anything. Start it yourself in one of two ways:

- **Easiest: make a tiny edit on github.com.** Open the branch **linux-port** (the branch menu on the left above the file list), open `windows/README.md`, click the pencil (Edit this file), type a space at the end of any line, click **Commit changes...**, choose **Commit directly to the linux-port branch**, click **Commit changes**. Any change under `windows/` or to the workflow file starts a run.
- Or ask for a new push in the session; every later push that touches `windows/` starts a run by itself.

(There may also be a **Run workflow** button on the left of the Actions tab under **windows-m0**. GitHub shows it only for workflows that exist on the default branch, which we do not write to, so do not count on it.)

## 3. Watch it

1. **Actions** tab. A run called **windows-m0** appears at the top, with a yellow circle while it works.
2. Click it. You see four boxes: **M0a SuperCollider 3.14.1 (MSVC)**, **M0a MinGW toolchain, Lua, libmonome, Link**, **M0b boot smoke** (starts when the first box is done) and **Report and artifact**.
3. Expected: the first box takes the longest (the SuperCollider build took about 7 minutes in the first run). A red cross on a box is normal at this stage and is exactly what M0 is for: the report says which step and why.

## 4. Download the result

1. When all boxes are finished, stay on the run page and scroll to the very bottom: **Artifacts**.
2. Click **verdandi-m0** (about 100 MB or less; you must be logged in to github.com). A zip downloads. The other entries (`m0-out-...`) are the parts of each box, you do not need them.
3. In Explorer: right-click the zip, **Properties**, tick **Unblock** at the bottom (if it is there), **OK**. Then right-click, **Extract All**.
4. Open **M0-REPORT.md** with Notepad. You should see a table with one line per step and a result (PASS, FAIL or SKIP) and, below it, the last lines of every failed step.
5. Optional, and only if the report shows `smoke-*` and `sc-*` steps passed: double-click **verdandi-test.cmd**. It unpacks SuperCollider next to itself, compiles its class library together with norns's classes and renders one second of a sine offline. It plays no sound, opens no audio device, needs no admin rights and touches nothing outside its folder. Windows may say it protected your PC: **More info, Run anyway** (the file is plain text, open it with Notepad first if you want to read it). It writes **M0-LOCAL-REPORT.txt** and ends with "Done".

## 5. What to send back

- **M0-REPORT.md** from the zip (always, also if everything passed).
- If you ran it: **M0-LOCAL-REPORT.txt**.
- If a box is red: the link of the run page (address bar), and the zipped `logs` folder from the artifact if the report's excerpt is not enough.
- Your Windows version (Windows key, type `winver`, Enter) and whether an antivirus window popped up at any time.
- Nothing else: no passwords, no tokens. The files contain no personal data.

## 6. Things that can go wrong, and what they mean

| you see | meaning |
|---|---|
| no run starts after the edit | Actions are not enabled yet (section 1), or the edit was made on another branch than linux-port |
| "workflow is not allowed" / action blocked | Settings > Actions > General must allow all actions (section 1, step 4) |
| the SuperCollider box is red at `sc-fftw` or `sc-vcpkg-libs` | a download or a package failed: send the run link, this is a normal M0 finding |
| the report says SKIP | the step was not tried because an earlier one it needs failed |
| the artifact is missing | the report box did not run; open the run page, click the red box, copy the last lines |


---

# Get the newest Windows build (releases, the updater, which build is running)

Every successful run of the workflow **windows-m1** on the branch `linux-port` publishes its zip to **GitHub Releases**. You do not have to dig through Actions artifacts any more, and a build can no longer be mistaken for an older one: the zip, the folder inside it, the home screen and the logs all carry the version and the short git hash.

## The one link to bookmark
`https://github.com/<owner>/<repository>/releases/tag/windows-latest`  (use the address of your fork: open the repository in the browser and add `/releases/tag/windows-latest`). That page is **always the newest build**. It lists the commit message, the checks of the run that passed, the known limits, and the zip: `Verdandi-windows-<version>-<short hash>.zip`. Every commit also keeps a page of its own (`/releases/tag/windows-<short hash>`, marked pre-release; the newest 20 are kept).

## Get it, the easy way: update-and-run.cmd
The zip contains `update-and-run.cmd` (and `update-and-run.ps1`, the PowerShell variant it falls back to). Double-click it in any build folder:
1. It reads which build this folder is and which one is newest (a few bytes: `BUILD.txt` of the release).
2. If the newest is not here yet, it downloads the zip (curl.exe of Windows 10/11), checks its SHA-256 (certutil), and unpacks it into a **new folder** `Verdandi-<version>-<hash>` next to the old one (tar.exe). Nothing is overwritten.
3. If Verdandi is running it asks to close it. It lists the older unpacked builds and asks whether to remove them (default: no; the folder you started it from is never removed by itself; the data folder never).
4. It starts the new `Verdandi.exe`.
No administrator rights, no installation. **Your files stay in `%USERPROFILE%\Verdandi`** (dust, logs, settings): the script never touches that folder. If the download fails it says why in plain words (no internet, nothing published yet, the repository is private, a damaged file), changes nothing and offers to start the build you have. It needs the repository to be **public** (a private repository cannot be read without logging in: download the zip in the browser then).

## By hand
Open the bookmark, download the zip, right-click it > Properties > tick **Unblock** > OK, Extract All into a folder of your own, double-click `Verdandi.exe` in the folder `Verdandi-<version>-<hash>`.

## Which build is running?
- On the norns screen: the **home page** shows `<version> <hash>` at the bottom right; **SYSTEM** shows it at the top right while the list is scrolled to the top.
- In `%USERPROFILE%\Verdandi\logs`: the first lines of `launcher.log` (`Verdandi build 0.2.0 4c82066`) and of `norns.log` (`Verdandi Windows build ...`, then `norns version`, `git hash`).
- In the folder: `BUILD.txt` (the build, the time, the commit and its message).

## What to send back
`launcher.log`, `norns.log`, `sclang.log` and everything in `logs\crash\` from `%USERPROFILE%\Verdandi\logs`, **the build line** (version and hash, from the log or the home page), and what you did and saw. If you ran `update-and-run.cmd`, the text of its window if something went wrong.

## One-time setup in the repository settings (click by click)
The workflow asks for the one permission it needs, `contents: write`, for the one job that publishes (the other jobs stay read-only). Usually nothing has to be changed. Check it like this (the names are those of GitHub's pages as I know them, **not verified in your repository**):
1. Open the repository on github.com. Click **Settings** (the tab on the right of *Pull requests*, *Actions*; if you do not see it you are not the owner).
2. On the left click **Actions**, then **General**.
3. Scroll to **Workflow permissions**. If the first publish ends with the error *Resource not accessible by integration* (HTTP 403), choose **Read and write permissions** and click **Save**. Then open **Actions**, the failed run, and click **Re-run all jobs**.
4. Still in **Actions > General**, make sure **Actions permissions** allows actions (*Allow all actions and reusable workflows*, or at least `actions/*` and `ilammy/*`, `msys2/*` which the workflow uses).
5. Only if you have rules for tags: **Settings > Rules > Rulesets** (or *Tags* under *Code and automation*): a rule must not block creating or deleting tags that start with `windows-`.
6. To let `update-and-run.cmd` download without a login the repository has to be **public**: **Settings > General**, scroll to the bottom, *Danger Zone*, **Change visibility**. This is your decision; with a private repository download the zip in the browser (the Releases page works while you are logged in).
7. Check it worked: **Actions** tab > the newest run of *windows-m1* > the job **Publish the zip to GitHub Releases** is green; then the front page of the repository, the box **Releases** on the right: *Verdandi for Windows: the newest build (...)*.

# Windows M1: the first runnable build (null audio; sound came in M2, ASIO and input in M3: see below)

M1 gives you a program: unzip it anywhere and double-click `Verdandi.exe`. It opens the norns window, boots norns's Lua side, starts SuperCollider in the background on a silent "null" audio device and lets you run scripts and click through the menus. **Not in M1:** sound, grids, MIDI, Link, maiden, an installer. Approach: `docs/port/phase-m1.md`.

## Get it

1. Actions (as in step 1 above, once). The workflow **windows-m1** starts by itself when a push changes the program (or `windows/`); you can see it in **Actions** on the left under "windows-m1". It takes roughly 20 to 30 minutes (a guess; the first M0 run took 20 minutes for SuperCollider and MinGW together).
2. Open the finished run, scroll to **Artifacts** at the bottom:
   - **m1-zip**: `Verdandi-windows-<version>-<hash>.zip`, the program (about 20 MB). The same zip is on the Releases page now (see the top of this file).
   - **verdandi-windows-m1**: `M1-REPORT.md` (every step PASS or FAIL), the logs of the automatic test run and its screenshot (`m1-run`).
3. Right-click the downloaded zip, Properties, tick **Unblock**, OK. Extract all into a folder of your own (not Downloads\ inside the zip viewer).
4. Double-click **Verdandi.exe**. Windows may say it protected your PC: More info, Run anyway (the build is not signed).

## What you should see
The norns window within about 20 seconds; the home screen; the menus (F10 or the right mouse button). The checklist of what to try is in `docs/port/HARDWARE-CHECKLIST.md` ("Windows M1").

## Windows M2: sound (what to click, what you should hear, what to send back)
The same workflow (**windows-m1** in Actions; it builds M2 now) and the same zip (`Verdandi-windows-<version>-<hash>.zip` in artifact **m1-zip**, and on the Releases page). Unpack it; the zip holds one folder named after the version and the hash.
1. Start `Verdandi.exe`. Before you start, **close programs that hold the sound device in exclusive mode** (Ableton with its RME driver in ASIO is fine; WASAPI shared mode works next to it).
2. Open the menu (F10 or right mouse button) > SYSTEM > **AUDIO**. OUTPUT lists your Windows playback devices (E3 changes it); the bottom line shows `48000 Hz <ms> <device>`. INPUT says "none yet" (no input in M2). Pick your speakers or headphones, K3 on **APPLY**: Verdandi restarts itself (the window closes and opens again, 20 to 30 seconds).
3. Load **awake** (SELECT, K3). **You should hear the notes** through the device you chose. Turn the volume of the MIX page (and Windows) up if not. K2/K3/E1-E3 change the sound as on a norns.
4. Try BUFFER (64 to 1024) on the AUDIO page: smaller = lower delay but more risk of crackles; 512 is the default. Say which is the smallest that stays clean.
5. **Break it on purpose:** (a) play audio in another program in **exclusive mode** (or unplug the headset you had chosen) and start Verdandi: it must not hang; the window shows a note (`NO SOUND. ... device busy ...`) and the AUDIO page says "no sound: device busy/missing, null audio"; scripts still run, silently. (b) Choose the device again after it is free and APPLY.
6. **Send back:** `%USERPROFILE%\Verdandi\logs\norns.log` and `sclang.log` (the lines starting `audio:` and `audio bridge:` say the device name, the rate, the block and the latency Windows reports), the file `audio.conf` from `%USERPROFILE%\Verdandi`, the **name of the device** as Windows shows it (Settings > Sound), whether the sound crackled at 512 and at 256, how long the delay between a key and the sound feels (roughly: not noticeable / noticeable / annoying), and the `M1-REPORT.md` of the run.
Nothing is changed in Windows' sound settings by Verdandi. No ASIO in M2 (M3).

### M2, second round: what changed and what to check
Restarts no longer crash (the program now ends at once instead of closing Lua under running threads), the launcher stops old `norns.exe`/`sclang.exe`/`scsynth.exe` of the same folder before a start and starts sclang only after norns.exe has made the sound bridge, a slow SuperCollider start no longer ends in SUPERCOLLIDER FAIL (a late answer completes the start-up), and AUDIO > OUTPUT `default` means "follow the Windows default". Steps: `docs/port/HARDWARE-CHECKLIST.md`, "Windows M2, second round". A crash report now names the functions; to read one on your side: `python windows\ci\resolve_crash.py norns.exe --report crash-....txt` (the `norns.exe` of the same build).

## Windows M3: ASIO, sound input, the RME Fireface UC (what to click, what you should hear, what to measure, what to send back)
Two zips now (Releases page, newest build: the link at the top of this file):
- **`Verdandi-windows-latest.zip`** (the default, **WASAPI only**: no ASIO code in it). Start with this one.
- **`Verdandi-windows-asio-latest.zip`** (the same program with PortAudio built with the ASIO host API; it carries the GPLv3 notices and sources of that part: `ASIO-NOTICE.txt`, `SOURCE-OFFER.txt`, `source\`). Why two: `docs/port/asio-licence.md`. `update-and-run.cmd` inside an ASIO folder updates to the ASIO build.
Unpack as before. The program is the same; only `libportaudio-2.dll` differs. Details of the design: `docs/port/phase-m3.md`.

**SYSTEM > AUDIO** (F10 or the right mouse button): one short list as on a norns. E2 selects a row, E3 chooses a value, **K3 applies** (K2 goes back and never applies anything). A row keeps its name and shows the full chosen value at once; a choice that is not applied yet has a `*` at the end of the row (the help box says `* chosen: K3 applies.`). After K3 the mark is `..` while it works, then `ok`, and the line at the bottom says e.g. `BUFFER 256 applied`. Only the sound stream is reopened, norns and your script keep running; there is no restart. Moving to another row clears the message. A small boxed help (three short lines) sits over the lower part of the screen while a row is selected. Why not apply by itself: reopening the card makes a short gap, and a half-turned wheel would reopen it at every step; leaving a page by mistake must never change the sound.
- `DRIVER`: **normal** (the safe choice, works next to other programs) / **exclusive** (lowest delay Windows allows, but nobody else can use that device meanwhile, Ableton included) / **low latency** (ASIO, only in the ASIO zip).
- `OUTPUT`: `default` follows the Windows default device, or a device by name. `OUT CH`: (low latency only) which output pair.
- `INPUT`: none, or an input device (SYS needs no input) (with low latency: the same driver). `IN CH`: appears when an input is chosen: which channels are left and right (`1+2`, `3+4`, ... or one channel `3 mono`).
- `BUFFER`: `auto` (the card's own period: the safe choice) or 64 / 128 / 256 / 512 frames.
- `TEST`: K3 starts the test. The row says `testing...`, then a short result on the row itself (`ok`, `no card`, `NN ms`, `no click`). Without an input it tests the card and the engine by themselves, no cables needed.
- SYS (the MIC button): this build now captures **WASAPI loopback** of the default playback device directly (shared mode only) when PortAudio lists none; if it still cannot, the INPUT row's help says `SYS: needs WASAPI loopback.`
- The line at the bottom is the status: `35 ms  u0 x0` = estimated delay of an engine sound, `u` = SuperCollider was late for a block, `x` = the card glitched. A busy or missing device is one plain line there (`busy: another program has it`) and the list shows what runs again. The details are written to `logs\norns.log` every 10 seconds (lines starting `audio:`).
Everything is saved in `%USERPROFILE%\Verdandi\audio.conf` (`output=`, `input=`, `rate=`, `block=`, `buffer=`, `exclusive=`, `out_first=`, `in_l=`, `in_r=`). `block=` is the engine's block (default 128), `buffer=` the card's; the old `period=` is no longer used.

**The input switch** is the MIC button of the window (or the menu key as on the Linux build): it cycles OFF > MIC > SYS > OFF. **MIC** needs an INPUT chosen on SYSTEM > AUDIO; without one the window says `MIC needs an INPUT: choose one on SYSTEM > AUDIO`, the input stays OFF and the next press goes on to SYS. **SYS needs no INPUT** (it works in normal mode only; in exclusive or ASIO mode it returns to OFF and says `SYS only hears Windows sound in normal mode`). Switching SYS on shows `SYS can feed back; lower softcut or mute if it howls`. **It is OFF every time Verdandi starts** (so a microphone next to speakers cannot feed back). MIC is the INPUT chosen on the AUDIO page. SYS is what Windows plays (WASAPI loopback of the default playback device); it does **not** hear Ableton's ASIO audio and it hears Verdandi's own output if Verdandi plays to that device. A choice that cannot work (no input chosen, no loopback) stays OFF and the window says why.

**Your set-ups, in the order to try them** (the click-by-click for TotalMix FX and Ableton is in `docs/port/phase-m3.md`, section 3; **it has not been tried on the RME**):
1. **(b) WASAPI next to Ableton** (what M2 did): leave DRIVER on normal, OUTPUT the Fireface's Windows device. Hear awake while Live runs.
2. **(c) Into TotalMix Loopback so that Live records it:** TotalMix FX loopback on a hardware output pair, Verdandi on that pair, an Ableton audio track with Ext. In on the loopback input.
3. **(a) ASIO alone:** use the ASIO zip, close Live (or use the driver's multi-client mode if your RME driver has it), DRIVER low latency, OUTPUT the Fireface (it applies by itself). If Live still has the driver, Verdandi says "ASIO driver ... is busy: another program has it (close its audio, or use the driver's multi-client mode)" and plays through WASAPI on the same hardware instead.

**What you should hear / see**
- awake as in M2 on every route. On ASIO the delay is shorter (the page shows LATENCY `out`, about 5 to 12 ms is my estimate for the RME, plus one block for engine sounds).
- With INPUT chosen and MIC on: your input is heard through Verdandi's output; with MIC off nothing from the input reaches norns. Start Verdandi again: the input is OFF again.
- SYS: play a video in a browser (not through Ableton): SYS makes it an input of norns (a script with an input level meter moves).
- TEST: connect the output to an input (a cable, or the TotalMix loopback) and keep the script quiet: the row shows a number in ms; without the loop it says `no click heard` after two seconds.

**What to measure:** for each DRIVER and BUFFER you try, one minute of awake: the status line (`u` and `x` should stay 0) and the lines `audio:` in `logs\norns.log` (they have the numbers every 10 s); the TEST round trip on WASAPI and on ASIO; whether keys feel late (not noticeable / noticeable / annoying).

**What to send back:** `logs\norns.log` (lines starting `audio:`: the host APIs of PortAudio, the choice, the device, the latencies, the input, any note), `sclang.log`, `audio.conf`; the **device list**: run `set VERDANDI_AUDIO_LIST=1` then `norns.exe` in the program folder in a command window (it prints every device with its host API, channels and latencies and exits); the **names of the ASIO drivers** installed (the list shows them in the ASIO zip; the RME one as Windows and Ableton name it); the TotalMix FX version and whether the hardware output strips have a Loopback setting; which of the three set-ups worked.

## Windows M4: MIDI devices, clock, Link, virtual ports (what to click, what you should see, what to measure, what to send back)
Design and reasons: `docs/port/phase-m4.md`. Version 0.5.0. Grids are not in this milestone.

**MIDI devices.** Every Windows MIDI device (USB controllers, the Fireface's MIDI input, virtual cables) is in SYSTEM > DEVICES > MIDI like on a norns: 16 vports, E2 vport, K3, E3 pick the device, and `midi.connect()` in scripts. A device with several ports is `Name 1`, `Name 2`. Unplug and plug in again: it comes back in a moment, under the same name (so MIDI MAP mappings keep working). Names carry no system index.
- **A port that another program has open** (Windows MIDI ports of hardware usually have ONE user): the DEVICES list says `MIDI: 1 HELD`, and `MIDI ROUTES` names the device and says what to do: close that port in the other program, or put the device's name in `midi_ignore=` in `%USERPROFILE%\Verdandi\audio.conf` (names separated by `;`) so that Verdandi does not open it at all, then plug it in again. Rule of thumb: **a controller that your DAW should have for itself goes into `midi_ignore=`** (for example `midi_ignore=Push 2`); a clock source you want in Verdandi is better opened by Verdandi and *not* by the DAW.
- **The midronome through the Fireface:** its clock arrives on the Fireface's own MIDI input, which the RME driver shows as an ordinary MIDI device (see its name in SYSTEM > DEVICES > MIDI). Give it a vport, set PARAMS > CLOCK > source = **midi**: the line above the tempo says `driving: midi from <device>, 120.0 bpm` (or `midi: no clock coming in`). If Ableton holds that port, DEVICES says so: pick one program to have it, or let Ableton be the clock master and send the clock on to Verdandi through a virtual port.
- `PARAMS > CLOCK`: the clock-out toggles per vport are as on Linux.

**Virtual ports (Verdandi <-> other programs).** Install loopMIDI (free, needs administrator rights once to install its driver; you have it), add a port or two. They show in `MIDI ROUTES` as `CABLES n found` and in DEVICES > MIDI by their names. Click by click for Ableton in both directions: `docs/port/phase-m4.md`, section 6. If none is installed `CABLES none` and its help says where to get one. Windows 11 25H2 may also have loopback endpoints of Windows MIDI Services; they appear in the same list if so.

**OSC input (any program).** `127.0.0.1:9201`, messages `/cc ch num val`, `/note ch note vel`, `/noteoff`, `/pitchbend`, `/pc`, `/touch`, `/midi b0 b1 b2`. It is the device `osc` in MIDI MAP. Example client for Max for Live: `max-for-live-osc-cc.md` in this folder. `osc_in_port=0` in audio.conf switches it off.

**Measure the routes.** SYSTEM > DEVICES > MIDI ROUTES > `TEST OSC` and `TEST <cable>`: K3, about 3 seconds; the row shows `0.04 ms j 0.01` (round trip, jitter), norns.log has the full line, RESULTS names the quickest. This is the route itself; the other program's own buffer is on top.

**Link.** PARAMS > CLOCK > source = link: the first line says `link on: no peers yet` or `driving: link, 2 peers, 120.0 bpm`. Quantum and start/stop sync are the existing params. The delay of your audio (the AUDIO page's ms) is added so that beats are heard together.

**What to send back:** `logs\norns.log` (the lines starting `midi:` and `clock:`), `audio.conf`, and the answers in the results template of the report. A screenshot of MIDI ROUTES with a test result is welcome.

## Scripts and maiden in M1
- The zip carries a small set of scripts (awake) in `dust-seed\code`; on the first start they are copied to `%USERPROFILE%\Verdandi\dust\code` when that folder is empty (a folder that already has anything is never touched).
- **Maiden is not in this build yet**; the MAIDEN button says so on the screen. To add scripts, copy a script folder (for example `awake`, from its GitHub page: Code > Download ZIP, unpack so that `awake.lua` is in `dust\code\awake\`) into `%USERPROFILE%\Verdandi\dust\code`, then open SELECT. Scripts that use a shared library (`lib`) bring it in their own folder.
- When maiden comes to Windows its project installer needs `git` (it clones the script repositories) or at least `curl`. Both can be provided without administrator rights: `curl.exe` is part of Windows 10 (1803) and 11 already; MinGit (the portable Git for Windows zip, GPL-2.0) can be unpacked next to the program and found through the program's own PATH. Neither is needed for M1.
- Windows Firewall may ask about `norns.exe` and `sclang.exe` (they listen for OSC messages). Everything works if you cancel the prompt; nothing leaves your computer in M1.

## What to send back
`M1-REPORT.md` (always), and from `%USERPROFILE%\Verdandi\logs` the files `launcher.log`, `norns.log`, `sclang.log` (and everything in `crash\` if there is something), plus what you saw. Windows version (`winver`), and whether an antivirus window appeared.
