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

# Windows M1: the first runnable build (no sound yet)

M1 gives you a program: unzip it anywhere and double-click `Verdandi.exe`. It opens the norns window, boots norns's Lua side, starts SuperCollider in the background on a silent "null" audio device and lets you run scripts and click through the menus. **Not in M1:** sound, grids, MIDI, Link, maiden, an installer. Approach: `docs/port/phase-m1.md`.

## Get it

1. Actions (as in step 1 above, once). The workflow **windows-m1** starts by itself when a push changes the program (or `windows/`); you can see it in **Actions** on the left under "windows-m1". It takes roughly 20 to 30 minutes (a guess; the first M0 run took 20 minutes for SuperCollider and MinGW together).
2. Open the finished run, scroll to **Artifacts** at the bottom:
   - **m1-zip**: `Verdandi-windows-M1.zip`, the program (about 100 to 150 MB, a guess).
   - **verdandi-windows-m1**: `M1-REPORT.md` (every step PASS or FAIL), the logs of the automatic test run and its screenshot (`m1-run`).
3. Right-click the downloaded zip, Properties, tick **Unblock**, OK. Extract all into a folder of your own (not Downloads\ inside the zip viewer).
4. Double-click **Verdandi.exe**. Windows may say it protected your PC: More info, Run anyway (the build is not signed).

## What you should see
The norns window within about 20 seconds; the home screen; the menus (F10 or the right mouse button). The checklist of what to try is in `docs/port/HARDWARE-CHECKLIST.md` ("Windows M1").

## Windows M2: sound (what to click, what you should hear, what to send back)
The same workflow (**windows-m1** in Actions; it builds M2 now) and the same zip (`Verdandi-windows-M1.zip` in artifact **m1-zip**: the name did not change, the program inside is version 0.2.0). Unpack it into a new folder as before.
1. Start `Verdandi.exe`. Before you start, **close programs that hold the sound device in exclusive mode** (Ableton with its RME driver in ASIO is fine; WASAPI shared mode works next to it).
2. Open the menu (F10 or right mouse button) > SYSTEM > **AUDIO**. OUTPUT lists your Windows playback devices (E3 changes it); the bottom line shows `48000 Hz <ms> <device>`. INPUT says "none yet" (no input in M2). Pick your speakers or headphones, K3 on **APPLY**: Verdandi restarts itself (the window closes and opens again, 20 to 30 seconds).
3. Load **awake** (SELECT, K3). **You should hear the notes** through the device you chose. Turn the volume of the MIX page (and Windows) up if not. K2/K3/E1-E3 change the sound as on a norns.
4. Try BUFFER (64 to 1024) on the AUDIO page: smaller = lower delay but more risk of crackles; 512 is the default. Say which is the smallest that stays clean.
5. **Break it on purpose:** (a) play audio in another program in **exclusive mode** (or unplug the headset you had chosen) and start Verdandi: it must not hang; the window shows a note (`NO SOUND. ... device busy ...`) and the AUDIO page says "no sound: device busy/missing, null audio"; scripts still run, silently. (b) Choose the device again after it is free and APPLY.
6. **Send back:** `%USERPROFILE%\Verdandi\logs\norns.log` and `sclang.log` (the lines starting `audio:` and `audio bridge:` say the device name, the rate, the block and the latency Windows reports), the file `audio.conf` from `%USERPROFILE%\Verdandi`, the **name of the device** as Windows shows it (Settings > Sound), whether the sound crackled at 512 and at 256, how long the delay between a key and the sound feels (roughly: not noticeable / noticeable / annoying), and the `M1-REPORT.md` of the run.
Nothing is changed in Windows' sound settings by Verdandi. No ASIO in M2 (M3).

### M2, second round: what changed and what to check
Restarts no longer crash (the program now ends at once instead of closing Lua under running threads), the launcher stops old `norns.exe`/`sclang.exe`/`scsynth.exe` of the same folder before a start and starts sclang only after norns.exe has made the sound bridge, a slow SuperCollider start no longer ends in SUPERCOLLIDER FAIL (a late answer completes the start-up), and AUDIO > OUTPUT `default` means "follow the Windows default". Steps: `docs/port/HARDWARE-CHECKLIST.md`, "Windows M2, second round". A crash report now names the functions; to read one on your side: `python windows\ci\resolve_crash.py norns.exe --report crash-....txt` (the `norns.exe` of the same build).

## Scripts and maiden in M1
- The zip carries a small set of scripts (awake) in `dust-seed\code`; on the first start they are copied to `%USERPROFILE%\Verdandi\dust\code` when that folder is empty (a folder that already has anything is never touched).
- **Maiden is not in this build yet**; the MAIDEN button says so on the screen. To add scripts, copy a script folder (for example `awake`, from its GitHub page: Code > Download ZIP, unpack so that `awake.lua` is in `dust\code\awake\`) into `%USERPROFILE%\Verdandi\dust\code`, then open SELECT. Scripts that use a shared library (`lib`) bring it in their own folder.
- When maiden comes to Windows its project installer needs `git` (it clones the script repositories) or at least `curl`. Both can be provided without administrator rights: `curl.exe` is part of Windows 10 (1803) and 11 already; MinGit (the portable Git for Windows zip, GPL-2.0) can be unpacked next to the program and found through the program's own PATH. Neither is needed for M1.
- Windows Firewall may ask about `norns.exe` and `sclang.exe` (they listen for OSC messages). Everything works if you cancel the prompt; nothing leaves your computer in M1.

## What to send back
`M1-REPORT.md` (always), and from `%USERPROFILE%\Verdandi\logs` the files `launcher.log`, `norns.log`, `sclang.log` (and everything in `crash\` if there is something), plus what you saw. Windows version (`winver`), and whether an antivirus window appeared.
