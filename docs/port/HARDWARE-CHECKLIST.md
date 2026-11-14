# Hardware checklist for the owner

Things that cannot be tested in the build sandbox. Filled in as phases go.

## After Phase 1
- [ ] macOS: build and run the macOS tests once after the Phase 1 edits to shared sources
      (`maiden-repl/src/page.c`, `pages.c`, `hardware/screen/ssd1322.h`, `hardware/screen/sdl.cc`,
      `hardware/input/sdl.cc`, `crone/src/BufDiskWorker.h`, `norns/wscript`, `wscript`,
      two unit tests). Expected: no change. (`macos/build.sh`, then the commands in readme-macos.md)
- [ ] Linux, real machine: `linux/setup-deps.sh && linux/build.sh && linux/norns.sh` with real
      audio (`NORNS_JACK_DRIVER=alsa`, jackd or PipeWire-JACK) and a display: window opens, sound.
- [ ] Linux, real machine: `/dev/snd/seq` exists (needed by the Phase 2 "norns keys" port).

## After Phase 2 step 4 (menu, file dialogs, screenshot, GIF) - needs a real desktop session
- [ ] File dialog through the real **xdg-desktop-portal** (GNOME and KDE if you have both): menu
      Import files... / Import folder..., and a script's file dialog (lua fileselect). It must open the
      desktop's own dialog, start in the folder given, and return the chosen paths. (The code was tested
      only against a mock portal on a private bus, `linux/tests/mock_portal.py`; the real portals may
      differ in details such as `current_folder` or the dialog's parent window.)
- [ ] **A script's file dialog is now off by default** (right-click menu > "Open the file dialog when a script loads a file", saved as `file_dialog=` in `ui.conf`). With the tick set, a script's chooser opens the real portal dialog as described above; without it, only norns's own browser. Check on a real desktop: tick, open a chooser, pick a file in the portal dialog (the script gets it), cancel the dialog (the browser stays usable), untick (no dialog), restart (the tick is still shown). Tested here only with a stub zenity and the mock portal.
- [ ] The fallbacks on a desktop without a portal: `NORNS_PICKER=zenity` (zenity) and `NORNS_PICKER=kdialog`
      (kdialog was not exercised at all, not even with a stub).
- [ ] "Show dust folder", "Show tape folder", MAIDEN and MANUAL buttons open the file manager / browser
      (`xdg-open`).
- [ ] Drag a sample or a script folder from the file manager onto the norns window (X11 and Wayland):
      audio is linked in dust/audio/mac; with **Shift** held at the drop it is copied. (Shift reads
      SDL's keyboard state; during a drag from another app the state may be stale.)
- [ ] Right button opens the menu, F10 opens it with the keyboard, Escape closes it; Ctrl+O, Ctrl+Shift+S,
      Ctrl+Q work; the menu is readable on a HiDPI screen (scale follows the window's layout scale).
- [ ] Screenshot and GIF land in the pictures folder (XDG_PICTURES_DIR, else ~/Pictures, else dust) and look
      right.
- [ ] Window under Wayland (SDL's wayland driver) and under X11 with a window manager: size, resize,
      keyboard focus, closing the window ends norns. (Tested here only on bare Xvfb without a window
      manager.)

## After Phase 2 step 5 ("Verdandi keys" MIDI source)
The keys window's MIDI device is named "Verdandi keys", as on macOS (`MACOS_PRODUCT " keys"`).
- [ ] **ALSA sequencer port (B), not tested at all here** (this container has no `/dev/snd/seq` and no
      sound kernel modules; the code was only compiled, and the "no sequencer" fallback was exercised).
      On a machine with `/dev/snd/seq` (the `snd-seq` module; PipeWire's ALSA-seq bridge is fine):
      1. start norns, open the keys window (KEYS button or F7);
      2. `aconnect -l` lists client "Verdandi", port 0 "norns keys";
      3. `aseqdump -p Verdandi` (alsa-utils) prints note on/off while you click a key or type on the keys
         window; `aconnect Verdandi:0 <a synth>` plays that synth;
      4. in **Reaper** (Preferences > MIDI Devices): the port appears as an input device (enable it, arm a track
         for MIDI input) and receives the notes;
      5. closing the keys window removes the port; opening it again brings it back; no stuck notes (close the
         window while holding a key);
      6. norns' own device "Verdandi keys" keeps working while a program is subscribed, and when none is.
- [ ] Reaper does not see "norns" as a MIDI **input** of norns (the other direction, the virtual port "norns" made
      by `dev_midi_virtual_init`) unless `/dev/snd/seq` exists: look at the boot log for
      "failed to open alsa virtual device". Needed for the clock/DAW wishlist item (see `clock-notes.md`).
- [ ] Virtual arc (wishlist 1): drag knobs with the left button, push with the right button, scroll; LEDs follow
      a script. (Tested here: LEDs, wheel deltas, push; not tested: left-button drag turning, which uses a
      mouse capture.)

## Clock (from `clock-notes.md`)
- [ ] ReaBlink in your Reaper (ReaPack or the releases page): is there a Linux x86_64 build, does it load, does
      norns (`clock_source` = link) follow Reaper's tempo? Same on macOS and Windows later.
- [ ] Reaper > Preferences > MIDI Devices: the output that reaches norns has "send clock" on; norns follows tempo,
      start, stop (and, after Phase 3, continue and SPP).

## After Phase 3 steps 1-2 (JACK MIDI clock input)
- [ ] Reaper (Linux): add the JACK MIDI output as a MIDI output device, enable "send clock", connect
      Reaper's port to `Verdandi:midi_in` (qpwgraph or `pw-jack jack_connect`; under PipeWire the port exists after
      `pw-jack linux/norns.sh`). norns: clock source `midi`; tempo, start, stop follow Reaper; after moving the
      play cursor and pressing play, the beat position is right (SPP) and continue does not jump to 0.
- [ ] Notes: a keyboard through JACK MIDI (or Reaper's virtual keyboard) reaches a script as the device
      "virtual" (the old name was "Verdandi JACK in").
- [ ] **MIDI out to Reaper (the virtual device's output, `Verdandi:midi_out`):** `pw-jack jack_lsp | grep Verdandi` lists `Verdandi:midi_in` and `Verdandi:midi_out`. In Reaper add a track with a synth (ReaSynth), set the track's input to the MIDI port that `Verdandi:midi_out` reaches (a Midi-Bridge port, or connect it with qpwgraph / `pw-jack jack_connect Verdandi:midi_out "<port>"`), arm it with input monitoring on. In norns choose a script that sends MIDI notes (or at the Lua prompt: `m = midi.connect(1); m:note_on(60, 100, 1)`; vport 1 is "virtual" unless a USB device took it, see SYSTEM > DEVICES > MIDI): you hear the note, `m:note_off(60, 0, 1)` ends it. Also a CC (`m:cc(7, 64, 1)`: the track's volume if it is learned), and a script's clock out (`clock_midi_out` for the virtual device in PARAMS > CLOCK) moves Reaper if it follows MIDI clock. A hold-up of more than a few milliseconds, a note stuck after the note off, or a message that arrives twice is a finding. With nothing connected a script that sends MIDI must run as before (no pause, no error in `logs/norns.log`).
- [ ] **ALSA MIDI port "Verdandi out" (for DAWs that read ALSA MIDI only; this is the test that could NOT be run in the CI container, which has no kernel sequencer; the receiver test `linux/tests/aseq_dump_test.c` skips itself there):** start norns and run `aconnect -l`: a client `Verdandi` with the port `Verdandi out` is listed. `aseqdump -p "Verdandi out"` prints what a script sends: `m = midi.connect(1); m:note_on(60, 100, 1)`, `m:note_off(60, 0, 1)`, `m:cc(7, 64, 1)`, `m:program_change(5, 1)`, `m:pitchbend(8192, 1)`, a script's clock out (PARAMS > CLOCK > midi clock out for the virtual device), `m:start()` / `m:stop()`, and a sysex (`m:send({0xf0, 0x7d, 1, 2, 3, 0xf7})`). Then Reaper (ALSA MIDI, JACK audio): Preferences > Audio > MIDI Inputs lists `Verdandi out`; enable it, put a track on it (Input: MIDI > Verdandi out), arm it, add ReaSynth: you hear the note; add a MIDI logger (the ReaControlMIDI / "MIDI Input Monitor" or View > Monitoring FX) and see the notes. Nothing arrives while the script sends nothing; with nothing subscribed the script runs as before (no pause, no error in `logs/norns.log`). Send a dense burst (a loop of 1000 notes): no crash, at worst a `aseq_out: ... dropped` line, said at most every 10 s. With `alsa_midi=0` in `audio.conf`: no `Verdandi` client in `aconnect -l`. With `midi_in_from=Midi-Bridge:` set and a bridge that shows the port as a JACK port: it is not linked to `Verdandi:midi_in` (no feedback). Connect `Verdandi out` to something that loops back in (a MIDI-through into Reaper, a track that outputs to `Verdandi:midi_in`): no runaway.
- [ ] **A USB MIDI device that comes back (KNOWN-ISSUES 36; the BeatStep Pro):** with norns running and the device listed in SYSTEM > DEVICES > MIDI (two ports), switch the device off (or unplug it) and look at `logs/norns.log`: `midi: Arturia BeatStep Pro 1 vanished (read error -19); it leaves the list`, then `midi: removed ... ` (from udev, or "no udev remove came"); SYSTEM > DEVICES > MIDI no longer lists it. Switch it on again: within a second or two `midi: added Arturia BeatStep Pro 1 (/dev/snd/midiC<n>D0 port 0)` and `... 2`, the device is listed again under the same names on the same vports, a pad or knob reaches the script and a mapped MIDI MAP control works again, **without restarting norns**. Repeat five times, also with a plug into another USB port, and with the device powered on before norns starts. Nothing is spammed in the log (a failing add says one line until it works). Send `logs/norns.log` if one of them does not come back.
- [ ] **Reaper route automatic: `alsa_midi_out_to=VirMIDI` (the owner verified the manual steps; this is the same without the terminal).** (1) No module loaded (`lsmod | grep virmidi` empty), `alsa_midi_out_to=VirMIDI` in `audio.conf`, start norns: the window says `ALSA MIDI: snd-virmidi is not loaded. SYSTEM > DEVICES > VIRMIDI`; DEVICES has a VIRMIDI entry; K3 shows the guide, K3 again asks, K3 yes: the desktop's password dialog opens (Cinnamon's polkit agent), the page says WAITING, then LOADED; cancel the dialog once: FAILED with the command to type. (2) Within about 3 seconds `logs/norns.log` has `aseq_out: connected Verdandi out to VirMIDI 3-0 (28:0)` (the numbers are the card's) and `aconnect -l` shows Verdandi out connected to it; the window says `REAPER: ENABLE VirMIDI 3-0` for a few seconds, and the page names it with its `hw:VirMIDI,<n>` form. (3) Reaper: Preferences > Audio > MIDI Devices > Reset all MIDI devices; tick Enable input for that entry; a track with input MIDI > that device > All channels, armed, and a MIDI logger: a script's notes (`m = midi.connect(1); m:note_on(60, 100, 1)`) appear. Is the entry in Reaper named as the page says? (Report the names you see.) (4) `aconnect -d 128:0 28:0` (cut it): back within 3 seconds, the log says `reconnected`. `sudo rmmod snd-virmidi` and load again (page or terminal): connected again. (5) With `alsa_midi_out_to=` empty: nothing is connected, no VIRMIDI entry, no note. With `alsa_midi_out_to=Arturia`: only the BeatStep Pro's port if it is writable, never Midi Through, the keys window or Verdandi itself. (6) The package: `dpkg -L verdandi | grep virmidi` lists the two example files under `/usr/share/doc/verdandi/examples/` and nothing under `/etc`; after copying them (the manual has the commands) and a reboot the module is loaded and Reaper has one port (`midi_devs=1`).
- [ ] **`midi_out_to=`:** put `midi_out_to=Midi-Bridge:Client-* Virtual RawMIDI` (the start of the input port's name as `jack_lsp` shows it) into `audio.conf`, restart: the link is made, `logs/norns.log` says `midi: connected Verdandi:midi_out to ...`; cut it in qpwgraph and it is back within 2 seconds. Without the line nothing is linked.
- [ ] **The name:** SYSTEM > DEVICES > MIDI lists `virtual` (not "Verdandi JACK in"); a `midimap.conf` from before that names `Verdandi JACK in` still maps (the page shows `virtual`, and the file is written with the new name when anything on the page changes).
- [ ] The tempo readout is steady with Reaper's clock (frame-accurate times are used; see "Tempo accuracy" in
      `phase-3.md`). The test client reads exactly 120.0 on the dummy driver.

## After Phase 3 steps 3-4 (sound card choice, audio server, SYSTEM > AUDIO)
- [ ] `pw-jack`-less start on PipeWire: `linux/norns.sh --terminal` with no JACK server running prints
      "starting again under pw-jack" and then "audio server: pipewire, input '<your mic card>', output '<your default sink>'".
- [ ] The output goes to the **default sink** of the desktop (change it in the sound settings, restart norns: it
      follows) and the input comes from the **default source**; a USB DAC set as default is used.
- [ ] `audio.conf` in the norns home with `out_ports=<start of the card name>` (name as in `wpctl status`) beats the default.
- [ ] A physical MIDI port (`Midi-Bridge:Midi Through`) is never connected as audio (check with `pw-jack jack_lsp -c`).
- [ ] Unplug the chosen card (or name a card that is not there): norns still starts, the device window shows
      "AUDIO: not connected, see SYSTEM > AUDIO" and SYSTEM > AUDIO shows crone's message at the bottom.
- [ ] SYSTEM > AUDIO under PipeWire: INPUT / OUTPUT / RATE show the connected cards and the system rate and do not
      change; BUFFER is marked "exp." and, after APPLY and the restart, `pw-top` shows the quantum you chose for
      the norns clients (a request only: PipeWire may refuse it).
- [ ] Under your own jackd (`NORNS_AUDIO_SERVER=jackd`, needs a card nothing else holds): SYSTEM > AUDIO lists your
      ALSA cards, APPLY restarts jackd with them (`logs/jackd.log`); a setting that does not start falls back to the defaults
      and leaves `audio.conf.failed`. Two different cards as input and output are untested (clocks may drift).
- [ ] SYSTEM > RESTART and SLEEP work (the sidecar used `sudo -n systemd-run` on Linux before this step; now a plain
      shell signals `norns.sh`, as on macOS).

## Done on a real machine (the owner, Linux Mint 22.2, PipeWire 1.0.5, Reaper 7.82)
- [x] Silent run (`NORNS_JACK_DRIVER=dummy`): window, K1-K3, encoders, virtual grid, arc and keys windows, file dialog from the tape page.
- [x] Sound under PipeWire (started as `pw-jack <path>/linux/norns.sh --terminal`, before the re-run was fixed): tape playback, the
      awake script, grid and arc control. `jack_lsp -c`: crone outputs to the built-in playback ports, inputs from the capture
      ports. The ALSA sequencer port "norns keys" appears while the KEYS window is open.
- [x] Reaper's "virtual" MIDI output (Midi-Bridge `Client-<n>` Virtual RawMIDI) connected by hand to `Verdandi:midi_in`: notes
      arrive; clock source midi follows Reaper's tempo; stop, song position and continue arrive and `clock.transport.start/stop`
      fire. Reaper's reset messages produce bursts of cc and pitchbend (expected: Reaper sends all-notes-off/reset controllers).
- [ ] Still to see on the laptop: the three setup fixes in a fresh clone (`python3 ./waf`, waf in `~/.local/share/waf`, the
      `pw-jack` re-run by absolute path); a dropped Midi-Bridge link (design only, `phase-3.md`).

## After Phase 3 step 5 (SYS, APP, MIC by flag)
- [ ] MIC button on the window: MIC > SYS > OFF (> SINK MONITOR only with `sys_monitor=1`). MIC off really silences the input
      (`pw-jack jack_lsp -c`: nothing connected to `crone:input_1/2`); MIC on brings the built-in capture ports back.
- [ ] SYS: play something in the browser: it appears in norns' input (a script that plays or records its input); norns' own
      output is not in the input (no feedback with the input monitor on a script); a second browser stream (`Vivaldi-73`) joins; a
      stream started after SYS was chosen joins within a second or two.
- [ ] APP: right-click menu lists the applications that currently have a stream (without numbers, without norns, without the
      sound card); choosing one hears only that one; the entry stays chosen when its stream stops and comes back with it.
- [ ] The sink monitor (`sys_monitor=1`): the warning "INPUT: sink monitor hears norns too" is on the device screen; with a script
      that plays its input it can feed back (keep the volume down).
- [ ] The choice (SYS / APP) is still there after RESTART.

## After the metro fix and the MIDI auto-connect
- [ ] No more `error code: 22 ... pthread_create` when you press keys on the laptop; a script's metro (an animation, a clock-less
      timer) runs. If a line "metro N did not start" appears, send it.
- [ ] `midi_in_from=Midi-Bridge:Client-` (or the Reaper port's name, see `pw-jack jack_lsp -t | grep -i midi`) in `~/verdandi-home/audio.conf`:
      Reaper's virtual output is linked to `Verdandi:midi_in` by itself after norns starts and after Reaper starts later; cut
      the link by hand (`pw-jack jack_disconnect ...`): it is back within about two seconds; SYSTEM > DEVICES > MIDI shows
      "AUTO-LINK: 1 linked". Watch whether it drops again by itself while neither port disappears (the log says "reconnected").

## After the clock-freeze investigation and the MIDI exclusions
- [ ] On the laptop, with SYS chosen: `NORNS_CLOCK_DEBUG=1 linux/norns.sh --terminal` prints `clock: jack frame time jumped by ...` lines when the
      clock freezes (forward then backward); the same forward/backward pair as in the container confirms the mechanism.
- [ ] The internal clock gives 2 beats per second with SYS on (fix applied; try it with the browser and Reaper running).
- [ ] With the ALSA sequencer present: `midi_in_from=Midi-Bridge:` links Reaper's port but **not** norns' own `Client-<n>` virtual RawMIDI port,
      "Verdandi" (keys window) or `Midi Through` (check `pw-jack jack_lsp -c`; norns' own client is found by the thread id ALSA reports as well as the process id); `midi_in_from=Midi-Bridge:Client-* Virtual RawMIDI` links only Reaper's.

## serialosc and a real grid
- [ ] With `serialosc.service` running (`pgrep -a serialosc` shows a `serialosc-device ... /dev/ttyACM0` process) and a grid plugged in: the log has one
      `serialosc: serialosc has this monome device open as well as norns ...` line with the stop/start commands and the replug hint, and the device window shows
      `GRID: serialosc has this grid, see log`. The line does not repeat.
- [ ] After `sudo systemctl stop serialosc.service` and a replug: the note is gone within a few seconds, no new line, and the grid events are clean.
      (Without the replug the note also goes: the serialosc-device process has ended.)
- [ ] Plug the grid into a different USB port (another ttyACM number) or use the by-id name: the check still finds the right process.
- [ ] `NORNS_SERIALOSC_CHECK=0` or `serialosc_check=0` in `audio.conf`: nothing is reported.
- [ ] An arc (same serial path): the same check.

## SuperCollider plug-in check and restart commands from scripts
- [ ] Put a Raspberry Pi plug-in in the extension folder (for example run the script's installer again, or copy one of the three ARM `.so` files into `~/verdandi-home/.local/share/SuperCollider/Extensions/supercollider-plugins/`) and start norns:
      before SuperCollider starts, the terminal shows one line per folder with the folder, its bad files ("(32-bit ARM)"), "this machine is x86_64", why it fails, and one `mkdir -p ... && mv ... ~/verdandi-home/disabled-plugins/` command for the folder (the folder itself if all its plug-ins are wrong, else the bad files); the device window shows
      `PLUGINS: wrong-architecture plug-in, see log`. Nothing was moved. (SuperCollider itself still fails until you move the files: that is expected, the check only reports.)
- [ ] Run the printed command, restart norns: no line, no note, SuperCollider starts, engines are listed.
- [ ] `NORNS_PLUGIN_CHECK=0` or `plugin_check=0` in `audio.conf`: nothing reported.
- [ ] A script whose installer ends with "K3: Restart" (the one that runs `sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service`): K3 returns at once, the terminal shows the `norns: there is no systemd ...` line,
      norns restarts by itself within a few seconds (state saved), and the window does not freeze waiting for a password.
- [ ] `sudo ls` run by a script (`os.execute("sudo ls")`) returns at once with a sudo message instead of waiting for a password (and, with a passwordless sudo, works).

## maiden (web editor and script catalog; `docs/port/phase-4-maiden.md`)
Everything below needs your laptop (a real browser, the real catalog, real audio). Headless tests already cover: the loopback-only binds, the file API, installing from a zip, loading the installed script in norns, the Origin/Host refusals, the window button.
- [ ] `linux/setup-deps.sh` (or `linux/maiden-build.sh`) as your user on your laptop: maiden is built; time, size, and no warnings that matter. Then `linux/norns.sh` prints `maiden at http://127.0.0.1:5000/maiden`.
- [ ] Click MAIDEN in the window: your default browser opens the page. The tree shows `dust`, the matron and supercollider consoles say "connected" (SuperCollider needs a working audio setup), `print(1+1)` in the matron console prints `2`.
- [ ] Open the page as `http://localhost:5000/maiden` too: the consoles connect as well.
- [ ] Install a script from the community catalog (the library icon; first it must have downloaded the catalog: a few seconds after the first start). It appears under `dust/code`, in HOME > SELECT, and runs. Update it from maiden once.
- [ ] Install a script that has the Raspberry Pi plug-ins (one of the 71 in `macos/docs/02-katalog-scan.md` with "ugen-plugins"): maiden installs it, its K3 install fetches ARM files, norns reports them at the next start (`PLUGINS: ...`), SuperCollider fails as described. Expected, not a maiden problem.
- [ ] Edit a script in maiden, save, and run it from norns (the "run" in maiden's editor sends it to the matron console).
- [ ] Another computer on your network cannot open `http://<your laptop's address>:5000/maiden` (connection refused), nor the consoles.
- [ ] Open a page of another site (any website, with maiden running): nothing happens to norns. (The page cannot be checked by hand without writing one: `docs/port/repro/maiden_exposure.js` does it with a browser; Firefox was not tried at all, only Chromium in the container.)
- [ ] With something on port 5000 (for example `python3 -m http.server 5000`): the launcher says the port is in use; the button shows the note; `NORNS_MAIDEN_PORT=5001` works.
- [ ] Reaper running with norns as a plug-in neighbor: maiden unaffected (no change expected).
- [ ] `linux/norns.sh --terminal`: one line says maiden's norns console is not available in this mode; MAIDEN opens the page, the window shows "maiden: no norns console with --terminal", the page says "not connected to norns" (found on your laptop). Without `--terminal` the page connects.
- [ ] `linux/norns.sh` in one terminal and `build/maiden-repl/maiden-repl` in another: a line typed at the maiden-repl prompt runs in matron, and the maiden page sees the same output.

## The Linux manual (`linux/manual/manual.html`)
- [ ] Click MANUAL in the window: your default browser opens the manual, the table of contents links work, it is readable in light and dark mode.
- [ ] Read it once against what you see: any sentence that is wrong or missing is a bug of the manual (every statement has a "sources" comment above its section in the HTML; the tests check the file, the links, the names, not the truth of each sentence).

## The package (`.deb`; `docs/port/packaging.md` section 7, `linux/package.sh`)
Needs your laptop (Mint 22, PipeWire, a desktop, a real grid). Headless tests already cover: the install in a clean Ubuntu 24.04, no missing library, boot as a normal user, maiden answering, engines listed, the metadata and the privacy scan, the launcher's home decisions, the udev rule's syntax.
- [ ] Build it: `linux/package.sh clean-root` (needs root, debootstrap) or `linux/setup-deps.sh && linux/build.sh && linux/package.sh all`. Build time, size of the `.deb` (about 14 MB here), no warnings that matter. If you build in your own home folder and the privacy scan stops it, that is the scan working: use `clean-root`.
- [ ] `sudo apt install ./verdandi_*.deb` on Mint 22: apt resolves every dependency (list what it wants to add; `pipewire-jack` should already be there), no manual step.
- [ ] Verdandi appears in the application menu with its icon; clicking it starts norns with no terminal; the window opens; the MAIDEN button works; the first start creates `~/Verdandi` (`launcher.log` there holds the launcher's output).
- [ ] A second click while it runs: **the running window comes to the front, no dialog** (see "Starting it a second time" below).
- [ ] Break something on purpose (stop PipeWire and jackd): a dialog says what is wrong instead of nothing happening.
- [ ] **Shared home:** with your developer checkout's home (`NORNS_HOME=… ` or `echo /path/to/home > ~/.config/verdandi/home`), start the package: your scripts and data are there; the `norns` link of that home now leads to `/opt/verdandi`; start the checkout (`linux/norns.sh`) and the link leads back. A real folder called `norns` in the home makes the launcher refuse with a message (it is never replaced).
- [ ] Your usual scripts and the engines Orgn and Eterna with real audio (the headless check only measured the output level of a dummy driver).
- [ ] **A real grid and a real arc**, plugged in after the package is installed: they work as with the checkout. **This also tests the libmonome fix** (the package carries its own libmonome with its protocol modules in `/opt/verdandi/lib/monome`). Then try `lsusb` and `udevadm info` on the serial port to see the numbers and the manufacturer string, and `getfacl /dev/ttyUSB0` (or `ttyACM0`): your user should have an ACL entry without being in `dialout`. Note the IDs of **every** grid and arc you own: the udev rule's numbers are not verified.
- [ ] `sudo apt remove verdandi`: `/opt/verdandi`, the menu entry and the udev rule go; `~/Verdandi` stays.
- [ ] Engines/UGens of scripts you use that needed the distribution's sc3-plugins: they should run on the bundled 3.14.1 (`docs/port/supercollider-3.14.md` lists what is known). Note any script that fails on SuperCollider classes (a Qt GUI class is not in the bundled build).
- [ ] **Browser (found on your laptop):** with Vivaldi as the default browser, click MAIDEN and MANUAL in the window, started from the menu entry and from a terminal with `verdandi`: both open Vivaldi, as `xdg-open http://127.0.0.1:5000/maiden` in a terminal does. If one still opens Firefox, send `echo $BROWSER` and `xdg-settings get default-web-browser` from the terminal you start it in. (Changing the default in Cinnamon's settings while Verdandi runs: close and start it again.)
- [ ] **Name:** the window title and the application menu entry read "Verdandi Linux"; `apt show verdandi` starts its description with it; the JACK/PipeWire graph still shows the client "Verdandi" and your MIDI setup still finds "Verdandi keys".
- [ ] **Panel icon:** after installing the new `.deb`, the running window shows Verdandi's icon (not a gear) in Cinnamon's panel and window list, started from the menu and from `verdandi` in a terminal; `xprop WM_CLASS` on the window still prints `"norns", "norns"`; a pinned launcher groups with the window.
- [ ] **eterna (and the other scripts that draw in `refresh()`):** after installing the new `.deb`, the screen of eterna follows your grid actions without F5. Try one more of: dreamsequence, bloom, plasma, forge. CPU use of norns while a script runs is about as before (60 small events a second).
- [ ] **Grid LEDs (found on your laptop):** with the new `.deb` and the real grid: load awake, leave it / load another script: the LEDs go dark; from `verdandi --terminal`: `g = grid.connect(); g:led(1,1,15); g:refresh()` lights the top-left key, `g:all(0); g:refresh()` clears. If it fails again: `NORNS_MONOME_TRACE=1 verdandi --terminal 2> trace.txt` (grid plugged in before starting), repeat the sequence, send `trace.txt` and the terminal's `libmonome:` lines, `systemctl status ModemManager` and `udevadm info /dev/ttyACM0 | grep -i ID_` (see KNOWN-ISSUES item 14).

## The new window layout (UI step 2: `docs/port/ui-plan.md` 1.6, pictures in `docs/port/ui-previews/layout-ui-a-nolabels.png`)
Look at the window on your laptop (Cinnamon, your real scale) and tell me what is wrong; the tests check the geometry, not the taste.
- [ ] The window opens at the same size as before; the box, the buttons and the screen look like the picture: **the screen is bigger** and its text is sharp with even pixels (no uneven blocks, no blur); the keys and encoders are bigger; there is no OUT slider and no K1..E3 text.
- [ ] The button row: MIX TAPE HOME PARAMS, MIC GRID ARC KEYS, MAIDEN MANUAL, **MUTE** at the right end, same look as the others. Click MUTE: the sound stops and its light comes on; click again: the level you had is back and the light goes out. (If you muted with the old window's slider, nothing is saved from it.)
- [ ] Click and drag K1-K3 and E1-E3: the bigger click areas are where the picture shows them (a key lights when pressed; a knob turns by dragging, by the wheel over it, and the wheel anywhere turns the nearest one).
- [ ] The MIX page: E2 changes the output level of the selected pair; with the mouse on the screen, the OUT column drags, scrolls and double-clicks to 0 dB. PARAMS > EDIT > LEVELS has the output level too.
- [ ] MAIDEN and MANUAL still open your browser (their place moved), MIC still goes through OFF / MIC / SYS / APP, GRID ARC KEYS still open their windows.
- [ ] Screenshot and GIF (right-click menu) still look like the screen (only the layout changed; the greys are the old ones: the brightness step comes later).
- [ ] Resize the window bigger and smaller: everything scales; the screen's pixels stay even at the sizes where 4 x the scale is a whole number (the default size, and for example 1.5 x).
- [ ] Anything cramped or odd: the empty area top right (where the slider was), the tighter spacing of K2 K3 E2 E3 (130 units instead of 155), the screen's nearness to the box's bottom edge.
- [ ] **Margin around the screen (UI step 2b):** the black frame around the screen looks like the Mac's (a bit wider than before, more room above and below than at the sides); the keys and encoders moved a little (K1 E1 up, K2 K3 E2 E3 right).
- [ ] **Resizing:** drag the window to about 75, 100, 125 and 150 percent of its size (and 200 if your screen is big): at 100 and 75 and 125 and 150 the screen's pixels are crisp and even; at sizes in between (for example 90 or 115 percent) the screen is very slightly soft but keeps its shape and its place in the black frame; the window cannot be made smaller than half. Try a script with small text (the MIX page) at each size. Also with your real display scale (fractional scaling, HiDPI) - not testable here.

## Crash fix (KNOWN-ISSUES 15)
- [ ] With the new build, leave norns running with a script (grid and LFOs) for a few hours; plug and unplug the grid and the mio, plug in a USB stick or headphones: norns stays up. `coredumpctl list | grep norns` shows no new entry.
- [ ] If it still crashes: send the newest file in `~/Verdandi/logs/crash/` (and `coredumpctl info` of the newest norns entry). For the two aborts: `coredumpctl info` of the norns SIGABRT (Monday) and the sclang SIGABRT (Tuesday).

## SYSTEM > SCREEN (was UI): brightness, colour, contrast (UI step 3: `docs/port/ui-settings-plan.md`, pictures `docs/port/ui-previews/ui-greys.png`, `ui-colours.png`, `ui-brightness.png`)
Look at it on the laptop's real screen (Cinnamon, your scale) next to the real norns if you can; the tests check the numbers, not the taste.
- [ ] HOME > SYSTEM: the list is DEVICES, AUDIO, **UI**, MODS, RESET, RESTART. SCREEN shows PRESET WHITE, COLOUR #FFFFFF, BRIGHTNESS 1.0, CONTRAST 0.5, SAVE and a bar of 16 greys (no HEX row any more). (CONTRAST was called GREYS in the first build with the numbers the other way round; an old `ui.conf` with `greys=` is converted: 0.5 stays 0.5, 1.0 becomes 0, 0.7 becomes 0.3.)
- [ ] **Cheat Codes 2, the loops page** (the overview with the waveform and the dim labels): open it with **CONTRAST 0** (the old look: the waveform and labels nearly black), then **0.3** (old greys 0.7), then **0.5** (the default, old greys 0.5), then **1.0** (the strongest, old greys 0.4). Which one looks like your real norns? Tell me the number; the default may move. Also: does a higher number now feel like more, like BRIGHTNESS above it? (Also the page in the editing frame, where the waveform is level 4.) Everything else you know (menus, other scripts) should look lighter in the mids at 0.5 and still have clean black and a full white.
- [ ] **Presets:** PRESET with E3: YELLOW (does it look like your yellow OLED?), PINK (the pink you want?). Set BRIGHTNESS 0.6 and CONTRAST 0.8 first: choosing a preset must leave both as they are. The black stays black; the box, keys and THEME colours do not change. K3 on PRESET opens the list (WHITE, YELLOW, PINK, then "MY PRESETS"); K3 chooses, K2 closes it.
- [ ] **A colour of your own:** K3 on COLOUR: the picker opens (HUE, SATURATION, BRIGHTNESS, HEX); the screen follows while you move; K3 keeps ("saved #..."), K2 restores. PRESET then reads e.g. `YELLOW~` (changed since). Ctrl+C / Ctrl+V on the COLOUR row copy and paste a code. In the picker's HEX row type `ff8800` and `#f80`; `12` is refused.
- [ ] **SAVE and DELETE:** SAVE, K3: the name entry ("NAME FOR THIS COLOUR:"); type a name, Enter: "saved: NAME", the list marks it `*`, DELETE appears. Save the same name again: it asks OVERWRITE first. WHITE as a name is refused. DELETE, K3, K3: gone, the colour stays and PRESET reads CUSTOM; on a built-in preset there is no DELETE. Quit and start again: your preset and the current colour are as you left them. Files: `~/Verdandi/screen-presets/name.screen`.
- [ ] **An old ui.conf:** put `colour=custom` and `custom=ff8800` (and `greys=0.7`) in `ui.conf`, start: the screen is orange, PRESET reads CUSTOM, CONTRAST 0.3; save it under a name.
- [ ] **A low brightness:** BRIGHTNESS from 1.0 down to 0.1 in steps; at 0.4 and 0.1 the menus are dim but readable, and the page itself is still usable at 0.1.
- [ ] **Saved:** quit norns and start it again: the same look from the first screens (the very first frame of the boot is plain white/grey before the file is read). `~/Verdandi/ui.conf` has `brightness=`, `preset=`, `tint=`, `contrast=`; edit it by hand to `tint=zzz` and start: white, with a line `ui.conf: tint='zzz' ...` in `norns.log`. RESET (SYSTEM > RESET) leaves ui.conf alone. **Your existing file** (with `greys=0.5`) must keep its look: start norns once, check that CONTRAST shows 0.5 and `norns.log` has `greys=0.5 (the old gamma key) is contrast=0.5 now`.
- [ ] **Screenshot and GIF** (right-click menu) with yellow and brightness 0.7: the PNG and the GIF have the colours of the window. A script's own `screen.export_png` is still plain grey.
- [ ] If it is wrong: which row, which value, and what you saw.

## Mods (KNOWN-ISSUES 17)
- [ ] SYSTEM > MODS lists sidvagn (and every other `dust/code/*/lib/mod.lua`: the nb library, doubledecker, ...). E3 right enables, a "+" shows until the next start; restart norns (SYSTEM > RESTART): `norns.log` says `mod found: sidvagn ... enabled` and `loading mod: sidvagn`, the dot shows next to it on the page.
- [ ] sidvagn: its grid page appears on grid port 2 (or the only grid); notes go to an nb player or MIDI. doubledecker: after the restart its voice is in the nb player list of a script that uses nb (Cheat Codes 2 and others) and sounds (SuperCollider compiled `doubledecker.sc`: `grep -i error sclang.log`).
- [ ] Disable a mod, restart: it is listed, not loaded. A mod with an error shows `mod failed: <name>: <error>` and the others still work.

## The detachable screen window (docs/port/detach-plan.md): what only your desktop can show
The tests here run under Xvfb with **no window manager**, so these could not be seen:
- [ ] **The window frame:** "Verdandi screen" has your desktop's title bar, moves, resizes by its edges and corners, minimises, closes (close = the screen returns to the main window).
- [ ] **Fullscreen (F11)** really fills the display (SDL's own fullscreen needs the window manager; here only the saved state `fullscreen=1` could be checked), on a second monitor too, and F11 returns to the saved size and place. With several monitors: it goes fullscreen on the display it is on.
- [ ] **Borderless (Shift+F11):** the frame goes away; **dragging the picture moves the window and dragging an edge resizes it** (this uses SDL's hit test, which depends on the compositor); Shift+F11 brings the frame back. If dragging does not work on your desktop, tell me which one.
- [ ] **Fractional scaling / high DPI** (Mint: Display > fractional scaling, or 2x): the picture is still crisp at whole multiples of the real pixels and the sizes in the title (points) match; the placeholder text in the main window is readable.
- [ ] **Wayland** (if you ever use it): the saved position may be ignored by the compositor (the size is restored); F10 may not bring the main window forward (focus-stealing rules); borderless dragging may not work.
- [ ] **A second monitor that is later unplugged:** start with `screen-window.conf` holding a place on it (`x=3000`): the window opens on the main display and the log (`~/Verdandi/logs/norns.log`) says the saved place is not on any display.
- [ ] **Stacking and focus:** with focus-follows-mouse or a tiling window manager, the screen window still gets the keys when you click it; F9 works from the main, the screen and the grid window.
- [ ] **The black margin** round the picture in the screen window (like the box's bezel: 4.30 percent at the sides, 7.29 percent above and below) at a small window, a big one and **in real fullscreen on your display**: text never touches the edge. Fullscreen 1920 x 1080 is an in-between size (13.8x) now: look at a letter and say if you would rather have a flat 13x with a bigger margin (`detach-plan.md` section 12).
- [ ] **How the in-between sizes look** to your eye (the fast bilinear filter against the box's slower one; mean difference about 1 of 255 in `docs/port/detach-measurements/`): tell me if an in-between size looks soft.

## Clean layout and CLEAN UP (docs/port/clean-layout.md)
- [ ] `ls -A ~/Verdandi` after a start: `dust`, `audio.conf`/`ui.conf` (if used), `logs`, `cache`, `norns`, `matronrc.lua`, `version.txt`, `.config`, `.local` and a few small marks; no loose logs, no `crash-report.txt`, no `.cache`.
- [ ] After a restart (SYSTEM > RESTART) and a crash of a script, `logs/norns.1.log` has the previous run; a crash leaves one file in `logs/crash/` and still the coredump in `coredumpctl list`.
- [ ] CLEAN UP: the numbers on the page match `du -sh`; REMOVE >30 DAYS shows what is older, asks once, removes only that; your `dust/` is unchanged afterwards (`find ~/Verdandi/dust | wc -l` before and after).
- [ ] The launcher fix: with PipeWire running, start Verdandi from the menu and check that **no** new `~/Verdandi/Verdandi` appears.

## Starting it a second time (docs/port/second-start.md): what only your desktop can show
The tests run under Xvfb with no window manager (stacking order and keyboard focus only):
- [ ] **Another window in front:** with Verdandi running and a browser or terminal covering it, start Verdandi again from the application menu: its window comes to the front and has the keyboard focus, no dialog, no second Verdandi (`pgrep -xc norns` says 1).
- [ ] **A minimised window:** minimise it, start again: it is restored and in front.
- [ ] **Another workspace:** put it on workspace 2, switch to workspace 1, start again: you are taken to its workspace (this is your window manager's choice; Cinnamon and GNOME normally do; say what yours does).
- [ ] **A detached screen window:** both windows come to the front.
- [ ] **Wayland (if you use it):** the compositor may only highlight the window in the panel or ignore the request; there is still no dialog and no second copy.
- [ ] **No window:** start `linux/norns.sh` with a `matronrc.lua` without `screen:sdl`, start it again: one dialog sentence (it did not answer / has no window), no second copy.
- [ ] **A crash:** `kill -9 $(pgrep -x norns)`, start again: a normal start, no "already running".

## /home/we inside SuperCollider (KNOWN-ISSUES 20, 21): what only your laptop can show
- [ ] **dronecaster:** install the new package, start Verdandi (the first start rewrites `sclang_conf.yaml`, the old one stays as `.old`), load dronecaster, start a drone: you hear it. `logs/sclang.log` shows `compiling drones in /home/we/...` followed by a dictionary with the drones, and no `does not know this drone`.
- [ ] **bloom:** load it: the sampled voices sound (its engine reads `/home/we/dust/code/bloom/samples/...`).
- [ ] **The other scripts you use** (awake, concrete, mlre, ...) still sound as before.
- [ ] **`sclang.log`:** about two dozen `Extension ... overwrites ...` lines at start are expected; no other `ERROR`.
- [ ] **mx_malone (item 21):** with nb_mxsynths enabled, `sclang.log` shows `NornsSynthDefCompat: mx_malone ...` once and no `build failed`. Play all 11 models (synthy, icarus, casio, malone, toshiya, piano, epiano, mdapiano, kalimba, triangles, aaaaaa): each one sounds, in particular malone and the ones after it, which were missing before. Say if malone's filter sounds wrong (it is now the intended modulation instead of 3.13's read past the buffer).

## Commands run by scripts (KNOWN-ISSUES 22): what only your laptop can show
- [ ] **mx.samples:** install the new package, start Verdandi, load mx.samples: the packs that are not downloaded say `- get?`, a pack you have does not. Press K3 on one: it downloads (curl) and unpacks (unzip) into `~/Verdandi/dust/audio/mx.samples/<pack>/`, the `- get?` goes away and the pack plays. `logs/norns.log` has the shell's complaints (if any) and no `ls: cannot access` text on the screen.
- [ ] **`curl` and `unzip`** are installed (`command -v curl unzip`); the package recommends them.
- [ ] **Scripts that list folders** (nice-tapes, pitfalls, nornsfetch ...) show nothing odd where a folder is missing.
- [ ] **Optional, for a possible later mode:** `sysctl kernel.apparmor_restrict_unprivileged_userns` and `unshare -rm true; echo $?` (tells whether a mount namespace for scripts' commands would be allowed on your machine; nothing uses it now).

## The look of the box (docs/port/box-style-plan.md): what only your desktop can show
- [ ] **STYLE PIXEL with the DARK look** on your display at your usual window size: are the blocks crisp (at 100 and 150 percent of the starting size they are whole pixels), slightly soft in between, and does the matt dark look read well in a dim room? Say what you would change in the three built-in looks or the MAC look (the Mac box's colours in the pixel style).
- [ ] **The keys (112 units, 1.4 times the encoders) and the 40 unit buttons with the screen's font**: big enough, labels readable (PARAMS, MANUAL, MAIDEN are the tight ones), the lit buttons (colours swapped) clear. If `resources/norns.ttf` were missing the labels fall back to a built-in small font: that is only seen in a broken install.
- [ ] **Colours in the aluminium style**: BOX, KEYS, ENCODERS, BUTTONS, FONT with hex codes you like: does the brushed metal still look like metal (a dark grey, a blue, a warm colour were fine in the pictures)? A part left at its default is as before.
- [ ] **Your own looks**: SAVE a look under a name, see it in the PRESET list after the built-in ones with a `*`, restart, it is still the look in use; save the same name again: it asks OVERWRITE; DELETE asks once and the colours stay; the built-in looks have no DELETE row. Copy `~/Verdandi/box-presets/<name>.box` to another computer (if you have one): it appears there.
- [ ] **Show the page buttons**: untick it: the row is gone, the box and window do not change size, F1-F4 still open the pages; "Open maiden" and "Open the manual" work from the menu; restart: still hidden.
- [ ] **Ctrl+M** mutes and unmutes (the menu item "Mute output  Ctrl+M" shows the tick), with the row hidden a small MUTE button shows while muted and clicking it unmutes; from the screen window too. Play sound while you do it: the output really goes silent and comes back.
- [ ] `verdandi scan-fkeys` on your real `~/Verdandi/dust/code`: the Ctrl+M lines (it could only be checked on a copy of your script list here).


## Box styles: fixes after the first test
- [ ] SYSTEM > THEME or SCREEN, a colour row, K3 (the colour picker), H (the text entry): type more than 6 digits: the seventh is refused with "6 digits max", no text piles up, the lines stay clean. Finish with Enter, Esc, OK, K2, also after a too-long entry: the page keeps its keys every time (if it ever sticks, note the keys pressed and send `logs/norns.log`).
- [ ] PRESET changes only the colours, STYLE only the style (try DARK on aluminium, then STYLE pixel: the colours stay).
- [ ] Drag a window corner in the pixel style and in aluminium: smooth, no ghost frames, and the crisp picture returns about a fifth of a second after you stop. Not measured here: Muffin's live resize on a real display.
- [ ] THEME page, row PRESET: press the RIGHT arrow (K3): the preset list appears at once; up/down move it; RIGHT uses the highlighted look; LEFT closes it. STYLE with RIGHT toggles and the row text changes at once. Navigation never stops reacting. If anything still sticks, `logs/norns.log` has a `THEME page:` line with the reason.
- [ ] HOME > SYSTEM network page (a wireless connection, no `iw` installed): the page shows `SIGNAL: n/a (iw missing)` and the log has no `iw: not found` line.
- [ ] Hex entry (THEME colour rows, the picker behind SCREEN COLOUR): LEFT/RIGHT move through the characters, UP/DOWN switch between the character row and DEL / OK, the keys right of 0 (- and =, `+` and `´` on some layouts) step the characters and keep stepping when held, K3 (Enter or the on-screen key) adds the selected character, Enter accepts, Esc cancels; digits and a-f still type; the seventh digit is refused.

## Colour picker and the clipboard (docs/port/colour-picker-plan.md)
- [ ] The picker on every colour row and on SCREEN COLOUR: live on the box and the screen, K3 keeps and writes once, K2 / Esc / F1 give the old colour back and the file is unchanged; opening on a set colour changes nothing; a grey keeps its hue when the saturation is raised.
- [ ] Ctrl+C / Ctrl+V on X11 and on Wayland (the owner's session): copy to and paste from another program; empty clipboard, a long text, an image: a short message, no change. Pixel style: the live change of the box is smooth (the quick drawing, then the crisp picture a fraction of a second later); not measured here on a real display.
- [ ] Ctrl+O, Ctrl+Q, Ctrl+M, Ctrl+Shift+S and the F keys still work; a script that reads the keyboard still gets Ctrl+C and Ctrl+V outside the menu.

## Pixel looks: PIXEL, RETRO, 8-BIT, 16-BIT (docs/port/retro-look-plan.md; pictures `docs/port/retro-look-previews/`)
- [ ] THEME > STYLE pixel > PIXEL LOOK: the four looks switch at once, are saved in `box.conf` (`pixel_look=`) and come back after a restart; with STYLE aluminium the row is inert and says so. PIXEL is exactly the old look.
- [ ] **Eye strain over hours** (what only you can judge): RETRO's dithered band, speckle and grille; 16-BIT's dithered keys and encoders and its scanline hint; is any of it tiring or distracting? 8-BIT is the plain one for comparison.
- [ ] **Button text next to the blocks:** the labels stay in 2-unit pixels beside 3 or 4 unit blocks: readable and balanced, or too fine? PARAMS and MANUAL are the longest.
- [ ] **Each variant with each look** (DARK, LIGHT, COLOUR, MAC and one of your own): is anything unreadable, too flat or too busy (very light or very dark colour sets saturate the ramp)? Pressed, hover and lit states, MUTE, the toast, the hidden top row.
- [ ] **Hit areas:** every button, key and encoder reacts where it is drawn in each variant (RETRO and 8-BIT move shapes by up to 2 units, buttons are 72 units wide; 16-BIT's by up to 3 and its hit margin is 1 unit).
- [ ] **Dragging the window** in each variant: smooth with the quick drawing, the crisp picture a moment after. 16-BIT is crisp at 100 and 200 percent only (its blocks are 3 units); in between its edges are a little soft. Not measured on a real display here (Xvfb only).

## Small fixes: SYSTEM order, picker messages (installed .deb 0.1~git20261030.3331.a4098441)
- [ ] HOME > SYSTEM lists DEVICES, AUDIO, MODS, SCREEN, THEME, CLEAN UP, RESET, RESTART (MODS directly below AUDIO).
- [ ] Picker: K3 -> `saved #RRGGBB` on the page; K2/Esc -> `restored`; F1 or a page change with a live change -> `restored, not saved` (a toast on the box, a few seconds); the hint `K3 keeps  K2 cancels` fits the screen; on the HEX row Left/Right and `-`/`=` change the brightness.

## MIDI MAP: MIDI controls for E1-E3 and K1-K3 (docs/port/midi-map-plan.md): what only your hardware can show

Everything in the tests ran headless with a JACK client playing the controller (`linux/tests/midimap_send.c`); **no Push 2, no mio, no network link and no real controller was available here.**

- [ ] **The mio (USB MIDI interface), your main route.** Plug it in and look at `norns.log`: `dev_monitor: adding midi device mio` and, if it has several ports, `assigned device name with port: mio 1`, `mio 2`. Send me `amidi -l` and those lines: they say whether norns shows it as **`mio`** (one port) or **`mio 1`, `mio 2`, ...**. SYSTEM > MIDI MAP > E2 > DEVICE lists it by that name (`MIO (ALL PORTS)` only with several ports).
- [ ] Learn something from it: LEARN on the page, click E2 in the window, turn a knob on the controller behind the mio. Then set DEVICE to `mio`, restart norns, unplug and plug the mio into another USB socket (the DEVICE row shows ABSENT while it is away): the mapping still works without touching the page.
- [ ] **Which channel and CC numbers arrive through the interface.** Whatever Windows sends out of the Push 2 chain arrives on the mio; the numbers and the channel may not be the Push 2's own. If two controllers share the mio's port, give each its own channel (the CHANNEL row) or its own CC numbers.
- [ ] **The Push 2 itself** (User mode): apply PRESET > PUSH 2 (marked UNVERIFIED) and check E1-E3 (CC 71-73) and K1-K3 (CC 102-104) with a MIDI monitor, or LEARN each control. Check: are the encoder values two's complement (REL 2S) as the preset says, what a fast turn sends, whether touching an encoder also sends notes (MIDI MAP ignores notes for encoders), and what happens in Live mode (Live's own script owns the controls). Tell me the real numbers and the preset is corrected.
- [ ] **Feel.** Turn an absolute knob (any 0-127 knob) and an endless encoder slowly and fast: is one step per two values (SENS 5) right for the E2/E3 of the scripts you use? Try SENS 1 and 9. The steps go through norns's encoder processing, so a script's own encoder sensitivity and acceleration also apply (a fast burst is multiplied by the acceleration, as with the mouse). Does a fast turn over the DIN cable of the mio lag or arrive in bursts (31.25 kbaud)? Tell me if the 1.5 s pause or the jump limit of 40 get in the way.
- [ ] **The network case** (RTP-MIDI from Windows through rtpmidid or PipeWire): the controller reaches norns only through `Verdandi:midi_in` ("virtual", all sources one device), so use ANY. Check that the link appears (`pw-jack jack_lsp -t | grep -i midi`), that LEARN works through it, what happens when the link drops and comes back (held keys, the first message of a knob is a new starting point), and the delay of a turn.
- [ ] **The iii grid** ("iii grid"): it must not turn or press anything with ANY (it sends notes for its keys). Press its keys with a note mapped to K1 and a device of ANY: nothing happens. Choose it by name and it works.
- [ ] **The params MAP.** In a script that has a params MAP with a CC on your controller, map the same CC to E2: SYSTEM > MIDI MAP shows `!`, a toast warns when the script loads, and with ON CLASH = PARAMS MAP only the parameter moves; with BOTH the parameter and E2 move. The script's own `midi` handler still sees every message.
- [ ] **K1.** A mapped K1 pressed short opens or closes the menu (as the box's K1 does): try it with a script running.
- [ ] The picture: LEARN, click E2: the six controls light in turn (PICK), then only E2 blinks (LISTEN), the banner says `LEARN E2` with the seconds left, and the toast beside E1 says what to do. Escape and the K2 key cancel; 15 seconds of nothing ends it with `LEARN STOPPED`.

## The grid, keys and arc windows: size, position and F7 (found on the laptop; fixed)

What was wrong: F6, F7 or F8 moved the norns window and changed its size (the layout of the Mac app, which fits everything at one scale in the middle of the screen), and F7 could not close the virtual keys window again (the keys window took every key itself, so F7 never reached norns). Now the norns window keeps the size and the position it had, the device windows go round it (below, beside or above, whichever side leaves them largest, never over it unless the screen has no room), and the keys window passes F1 to F12 on like every other window. Tested under Xvfb with no window manager (`window_toggle_scenario`, `extras_layout_test.c`); **a real window manager and a real screen are what is left to check**:
- [ ] Resize and move the norns window as you like, then F6: the grid window appears beside or below it, and the norns window does not move or change size. Close it with F6 (with the grid window in front, and with the norns window in front). Same for F8 (arc) and F7 (keys), several times each.
- [ ] Open all three at once and close them in any order: the norns window stays put; no window ends up off the screen or under the norns window.
- [ ] **F7 closes the virtual keys window** when the keys window is the one in front (the case that did not work), and when the norns window is in front. Notes typed on the computer keyboard still play while the keys window is in front (letters, not F-keys).
- [ ] With the screen detached (F9) repeat the three: the detached screen window and the norns window keep their size and position too.
- [ ] A small screen (or a very large norns window): the device windows shrink to fit and may overlap the norns window only when there is truly no room; none leaves the screen. On a second monitor the windows open on the monitor the norns window is on.
- [ ] Note for the Mac build: unchanged (the new layout is inside `NORNS_LINUX_DESKTOP`).

## The virtual arc from MIDI and the keyboard (docs/port/arc-plan.md): what only your hardware can show

Everything in the tests ran headless: a JACK client played the controller (`midimap_send.c`), `xdotool` typed the keys. **No Beatstep Pro, no real arc, no real keyboard repeat of your desktop.**
- [ ] **The Beatstep Pro's relative mode.** MIDI MAP > WATCH, one encoder, one click right and one left, several times: which verdict (REL OFS, REL 2S, REL SIGN)? Does a fast turn send bigger values (`67`, `5`) or the same value faster? Tell me the values and the CC numbers and channel of its 16 encoders; a BEATSTEP PRO preset can then be made (none is shipped: its numbers are unknown here).
- [ ] **Step size.** How many units does a full physical turn of one Pro encoder give? ONE TURN counts it (K3, one turn, K3): write the number; the default GAIN 8 assumes 128 units a turn.
- [ ] **Arc feel.** Map A1 to an encoder, open the virtual arc, run an arc script you use. Does the ring turn like an arc under the hand at GAIN 8? Try GAIN 4 and 16, ACCEL LOW and HIGH. Does a fast turn over the mio's DIN cable lag or arrive in bursts? Is a slow turn smooth (ticks of 8 are coarser than the 1-tick nudges of a real arc: try GAIN 1 to 3 for fine work)?
- [ ] **The split.** Keep some encoders on E1-E3 and map others to A1-A4: no encoder does both. Learn an arc encoder from a CC an E encoder uses: the question appears; yes moves it, no changes nothing; the `!` shows when two controls could answer to one message (for example both on ANY).
- [ ] **The keys** with your own keyboard and desktop: `5 6 T Y G H B N` in the arc window and, with a script running, in the norns window: the repeat rate and delay of your desktop (400 ticks a second at 25 repeats a second), Shift for fine steps; your national layout (the keys are positions, so the same physical keys); a script of yours that reads the keyboard keeps those keys (run `linux/scan-fkeys.sh` on `~/Verdandi/dust/code`: it lists the scripts that read the keyboard and name any of the eight).
- [ ] **A real arc**, if you ever get one: how its deltas compare (the size of a nudge, of a fast turn, the message rate) with the virtual arc at 8 ticks a unit and with the keys at 16; plug it in next to the virtual one and check that a mapped encoder only drives the virtual arc.
- [ ] **WATCH** while a script with its own MIDI handler runs: nothing is mapped while WATCH is open, the script still receives everything.
- [ ] The arc window closed: a mapped encoder does nothing and says so once (a short message on the box); F8 opens it and the next turn works.

## Text entries and MIDI MAP / the tape page (KNOWN-ISSUES 23, 24, 25): what only your hardware can show

- [ ] With the virtual arc window **open and in front** (after a learn by clicking a ring), type a CC number with **5 and 6** into MIDI MAP > a control > NUMBER, and a preset name starting with B, T, H, N, Y or G: everything is typed, the arc does not move. Close the entry: `5` turns ring 1 again.
- [ ] **Naming a recording with the Beatstep** (KNOWN-ISSUES 27): TAPE page, REC side, K3 (from the keyboard or a mapped K3): the "tape filename" entry opens with `MIDI` in its top right corner. Mapped **E2** moves through the characters (and chooses DEL / OK on the lower row), **E3** switches the row, **K3** (pad or button) adds the character, deletes, or accepts on OK (it acts when you press, not when you let go), **K2** cancels. Is a pad the right choice for K3 and K2 (velocity: a light tap that sends velocity above 0 counts)? Does one click of the encoder move one character, or does norns' encoder acceleration make a slow click do nothing or a fast one jump? Tell me what you would change (the speed is the same as the hardware's own).
- [ ] While an entry is open, touch the mapped **K1, E1, A1-A4** and the action pads: nothing changes in the typed text and the menu does not close. Do the same with a preset name (SAVE AS) and a CC number. After the entry the mapped controls work as before.
- [ ] After a session with MIDI MAP entries and preset saves open the **TAPE page, REC side (E2), K3**: the "tape filename" entry opens and recording starts. If it ever does not, `logs/norns.log` has a line beginning `textentry:` (an earlier entry left active, or another entry still active): send me that line and what you did just before.
- [ ] While an entry is open, click a page button of the window (MIX, TAPE, ...): the entry closes, the page changes, and the TAPE rec name entry still opens afterwards (a mapped K1 no longer does anything during an entry).

## The tape page K3 and handler errors (KNOWN-ISSUES 26)
- [ ] TAPE page, REC side (E2), **K3**: the "tape filename" entry opens with the next free four-digit number, also with files like `0.50 take.wav` in `dust/audio/tape`; recording starts and stops.
- [ ] If any menu key ever fails again, the device window shows `ERROR key: <file>:<line>: <message>` for about 8 seconds and `logs/norns.log` has `menu key handler error: ...`: send me that line.

## MIDI actions (docs/port/midi-actions-plan.md): what only your Beatstep Pro and desktop can show

The window, the JACK MIDI path, the mouse-versus-MIDI comparison, the master switch (page, menu tick, Ctrl+Shift+M) and the saved values are tested headless (`run_all.sh`, `actions_scenario`). These need your hardware:

- [ ] **The pads' notes and channel** in the mode you use: ASSIGN ALL, hit a pad for each of the 14. Which note numbers and channel did the Pro send (the list shows `NOTE 36` ...)? Do the pads send a **note on with a velocity above 0 every time**, also for a light tap? (A velocity-0 note on is a release and never acts.) Does a pad send two note ons for one hit? (The guard is 0.25 s; if yours bounces longer, tell me.)
- [ ] **Release:** hold a pad down and let go: nothing happens on the release, for every action (note off, or a note on with velocity 0, or nothing). Hold a pad: MUTE toggles once, not repeatedly.
- [ ] **Pads in CC mode** (if the Pro can send CC from pads): K3 on an action and hit a pad: a CC is learned as an *encoder step*; for a pad that sends 127/0 open the action (E3 right), set KIND = CC BUTTON and a THRESHOLD, and check the press fires once and the release does nothing.
- [ ] **An encoder as a trigger:** learn an action with an encoder; turn it slowly (one click, wait: fires each time), quickly (one fire per burst, not one per click), the other way (nothing). Is 0.3 s of quiet the right length for your hand?
- [ ] **The same pads and your scripts:** a script that plays notes from the same pads: do the actions fire while you play? (Set the actions' CHANNEL, or use pads the script does not read.) The script still receives every note: check.
- [ ] **Hitting the wrong pad:** with the suggested arrangement (plan, section 6), can you reach the pads you want without hitting MUTE / DETACH / SCREENSHOT? Use ACTIONS > CLEAR or the master switch for a gig.
- [ ] **The feel of the 150 ms button press** (only with the row of buttons shown) and the silence with the row hidden.
- [ ] **FULLSCREEN and DETACH on your desktop** (Linux Mint, your window manager): DETACH opens the screen window; FULLSCREEN makes it fullscreen and back; docked, FULLSCREEN says *FULLSCREEN: DETACH THE SCREEN FIRST (F9)*. (The tests run without a window manager and check the saved state only.)
- [ ] **Ctrl+Shift+M** from the norns window and from the detached screen window on your keyboard layout: the box says *MIDI actions on/off*, the tick in the right-click menu (F10) and the MIDI ACTIONS row agree. `verdandi scan-fkeys` on your real `dust/code`: do any of your scripts name Ctrl+Shift+M? If one does, tell me and I propose another key.
- [ ] **A restart** with the switch OFF: the menu tick is off and the pads do nothing until you switch it on again.

## Crash, frozen script load, LEDs on exit (KNOWN-ISSUES 28, 29, 30): what only your hardware can show

- [ ] **Grid LEDs:** light both real grids (128 and 256) with a script, then end Verdandi four ways: Ctrl+Q, the window's close button, `verdandi restart` (or the launcher's restart), Ctrl+C in a terminal start. Are all LEDs off each time? With serialosc running (`systemctl status serialosc`) do they stay lit again? (The log line of the startup check now says why.) Does the **iii grid** go dark by itself on a quit (it is not touched by norns)?
- [ ] **Quick script changes** with the virtual grid and arc windows open, both real grids plugged in and a mapped controller playing: change the script five times in a row (also awake-rings, then sidvagn). The last script starts every time. If a load takes more than 15 s `logs/norns.log` says `### script load is taking longer than 15 s: still waiting for engine ...`: send me that line and the end of `logs/sclang.log`.
- [ ] **The crash again?** If norns crashes, `logs/crash/crash-*.txt` now has `---- functions of norns ----` with names. Send it with the `grid.lua`/`weaver:` lines just before it in `logs/norns.log` (`this grid or arc is gone` means a script kept a removed device), `dpkg -l libsdl2-2.0-0`, and `coredumpctl gdb <pid>` then `bt full` if you can.

## serialosc, grids listed twice, an action on the wrong pad (KNOWN-ISSUES 31, 32): what only your hardware can show

- [ ] **serialosc running** (`systemctl status serialosc`) with both grids plugged in, then start Verdandi: the window shows `GRID: serialosc has this grid. Stop: sudo systemctl stop serialosc.service` (also when no grid appeared in norns). **SYSTEM > DEVICES** has the entry **SERIALOSC**: the guide in short lines; K3, K3: does it stop serialosc without a password (it may not: then it shows the command)? After `sudo systemctl stop serialosc.service` and a replug the note goes by itself within a few seconds and the grids appear. `sudo systemctl start serialosc.service` brings the note back.
- [ ] **Each grid once:** SYSTEM > DEVICES > GRID lists every grid once, with serialosc running and stopped, after a replug and after Verdandi restarts. If a grid still shows twice, send me the lines of `logs/norns.log` that begin `dev_monitor:` and `dev_list_add:`.
- [ ] **MIDI actions on the wrong pad:** with ASSIGN ALL, hit a pad twice (a bounce) or hit one pad for two actions: the question names both actions. Put two actions on one note by editing `midimap.conf` (or typing a note that is used): the page says `NOTE 36 IS ON MANUAL AND MUTE` when it opens, and both rows have `!`. After learning, does the line name the action and the channel the pad sends on?

## Toast text and its border (KNOWN-ISSUES 33): what only your screen can show

- [ ] **The serialosc note** (start Verdandi with serialosc running): the pill under the buttons shows the three lines inside its border, at the default size, at the smallest window you use, maximised, and on the detached screen window (F9), in the aluminium style and in PIXEL, RETRO, 8-BIT and 16-BIT. On SYSTEM > DEVICES > SERIALOSC every line is whole (nothing cut at the right edge of the screen).
- [ ] **Other messages:** the ones you see often (a screenshot saved, a GIF saved, "MIDI actions on/off" with Ctrl+Shift+M, "copied" and "saved" in the colour picker, "restored, not saved" after leaving it, an error message) are inside their pill, also with your display scaling (100, 125, 150, 200 percent) and with a recording dot (REC GIF). If one is still cut, send me its words and the window size.


## mi-UGens shipped with the package (KNOWN-ISSUES 37): what only your machine can show

- [ ] **Emplaitress:** install the .deb, install the `emplaitress` mod from the catalog, enable it under SYSTEM > MODS, restart norns **once**. Check `logs/launcher.log` for `norns.sh: mi-UGens: seeded ...`, `logs/sclang.log` without `ELFCLASS32`, `Class ... not found` or `duplicate Class`, and `logs/norns.log` with `emplaitress found mi ugens` (not `installing mi-UGens`). Then play a script that uses its players and **hear sound** from the Plaits engines.
- [ ] **Terrarium:** install the `terrarium` script, load it: its screen must **not** ask for the download (no "K3: download + install"); if it still does, send me what the screen says and do not press K3. Hear it play. (Terrarium needs MiBeads: pull request 24 of mi-UGens.)
- [ ] **SYSTEM > CLEAN UP** shows a MI-UGENS line with the commit and the Verdandi version.
- [ ] **A collision (optional):** install `pedalboard` or `krill` and use their installer: if SuperCollider stops, the log and the window note must say which folders and what to move; CLEAN UP > ARM PLUG-INS or CLASSES moves it after one confirmation; restart and the sound works again. Tell me which script it was.
- [ ] **An update:** install a newer package over this one (when there is one): `logs/launcher.log` says `mi-UGens: updated` only if the serial grew, and a copy you edited is left alone.

## Long text on our own pages (KNOWN-ISSUES 38): what only your screen can show

- [ ] **SYSTEM > CLEAN UP:** the MI-UGENS line is short (`MI-UGENS 10f6824`); K3 shows the commit, `shipped with Verdandi <version>` over two lines and the build date; SEEDED reads `1 pack` with a size, and its list says it is copied in by Verdandi.
- [ ] **A long name:** plug in a USB MIDI device with a long name and open SYSTEM > DEVICES; save a SCREEN and a THEME preset with an 18-letter name; look at the rows: no text over another, `..` at the end of a cut name.
- [ ] **Scripts are unchanged:** a long sample name in a script's file selection is cut at the edge as before (the same on the Raspberry Pi).

## Self-healing for a Raspberry Pi mi-UGens download (KNOWN-ISSUES 37): what only your machine can show

- [ ] **At the start:** with Verdandi's own pack seeded (SYSTEM > CLEAN UP shows MI-UGENS), install `pedalboard` or `krill` (or press K3 in Terrarium once, if it still offers it) and let it download, then restart norns: the window says once `A script downloaded Raspberry Pi mi-UGens. Moved aside; Verdandi's own copy is in use.`, `logs/launcher.log` has one `mi-UGens: moved ...` line, SuperCollider starts (no SUPERCOLLIDER FAIL), and `~/Verdandi/disabled/` holds the files. Tell me which script it was and what it unpacked (the folder names).
- [ ] **While norns runs:** press the download in such a script: within about ten seconds the window shows the note with the hint to restart, and SYSTEM > CLEAN UP has an ARM PLUG-INS line; K3 K3 moves it, restart norns, the engines load.
- [ ] **Restore:** `verdandi tidy list` and `verdandi tidy restore <id>` put a moved item back; the next start moves it aside again (turn that off with `mi_ugens_heal=0` in `audio.conf`).
- [ ] **A pack of your own:** if you put a working x86-64 mi-UGens in the extension folder yourself, it is left alone (one line in the log) and SuperCollider may report duplicate classes: tell me how you want that handled.

## The virtual MIDI card and the VIRMIDI page (KNOWN-ISSUES 40): what only your machine can show

- [ ] **Reaper can open the card:** with `alsa_midi_out_to=VirMIDI` in `audio.conf`, load the module (the page, or `sudo modprobe snd-virmidi midi_devs=1`), start norns; `fuser -v /dev/snd/midiC*D0` must show **no** norns process; Reaper's MIDI input `hw:VirMIDI,0` opens without "could not be opened"; notes from a script reach the track. `logs/norns.log` has one `skipped virtual raw MIDI card VirMIDI` line.
- [ ] **Module loaded while norns runs (the old state):** load the module first, then start an older Verdandi if you still have it (or set `midi_ignore=Nothing` in `audio.conf`, start norns, see Reaper fail), then restore the default and wait 3 seconds: `released virtual raw MIDI card` is in the log, `fuser` shows nothing, Reaper opens the port without a restart of norns.
- [ ] **The page:** SYSTEM > DEVICES > VIRMIDI, K3, K3: the password dialog opens; the page says WAITING; after the password the page changes to LOADED by itself (no key) and names `hw:VirMIDI,0`; close the dialog instead: the page says in plain words that it was closed and shows the command; also try waiting two minutes (no answer) and a machine without a polkit agent if you have one.
- [ ] **Your controllers still work:** a real USB MIDI device is listed and opens as before; the virtual card is not in SYSTEM > DEVICES > MIDI, MIDI MAP's device list or the params MAP.

## NamAmp for princeton, and the heal of any wrong-architecture plug-in (KNOWN-ISSUES 41): what only your ears and your machine can show

- [ ] **NAM models:** put your `.nam` captures (an A1 WaveNet of an amp, an A2 capture, an LSTM one) into `~/Verdandi/dust/data/princeton/nam/`. Install princeton if it is not there, start Verdandi: `logs/launcher.log` has `plugin heal: moved ...` (if the script's Raspberry Pi file was in place) and `NamAmp: seeded ...`, and the window says once that it moved the Raspberry Pi plug-in aside.
- [ ] **Load princeton**, plug a guitar (or a loop) into the input, switch the amp to the NAM mode and choose a capture: **hear the amp**. Listen for crackle or dropouts (no xruns at your usual period), for the level against the analog amp (the default `namamp_gain=0` may be too loud or quiet: set `namamp_gain=<dB>` in `audio.conf` and restart norns, or choose the capture again, and tell me the value that suits), and for a capture made at another sample rate than yours (the log says so).
- [ ] **The script's own check:** princeton shows NAM as available without "restart norns"; `ls -la ~/Verdandi/.local/share/SuperCollider/Extensions/princeton/` shows `NamAmp.so` and `.verdandi-namamp` and no file of the script's was changed (`~/Verdandi/dust/code/princeton/lib/nam/NamAmp.so` is still the Raspberry Pi file); `logs/norns.log` has the two `NamAmp.so: Verdandi's own x86-64 copy is in use` lines at each load.
- [ ] **A plug-in installed while norns runs** (install a script with a Raspberry Pi plug-in, or copy any such `.so` into the extension folder): within ten seconds the window shows the note, SYSTEM > CLEAN UP has an ARM PLUG-INS line, K3 K3 moves it, a restart starts SuperCollider; and without that, the next start moves it by itself. `verdandi tidy list` and `verdandi tidy restore <id>` put it back.
- [ ] **The settings:** `namamp=0` (no seeding, the shims step aside), `plugin_heal=0` (nothing is moved; the PLUGINS note says what is wrong), `namamp_gain=-6` (quieter by 6 dB after a restart).

## Windows distribution (Releases and update-and-run): what to check

1. After the next push to `linux-port` has finished its run: the **Releases** box on the repository front page shows *Verdandi for Windows: the newest build*; its page lists the commit message, the checks, the known limits and the zip `Verdandi-windows-<version>-<hash>.zip`. If the publish step failed (red job *Publish the zip to GitHub Releases*), do the setting in `windows/README.md` ("One-time setup") and re-run the job; send the log of the failed step.
2. Download the zip from that page, unblock, extract: you get a folder `Verdandi-<version>-<hash>`. Double-click `Verdandi.exe`: the home page shows `<version> <hash>` at the bottom right; `logs\launcher.log` and `norns.log` start with the same build line.
3. Push another commit (or wait for the next build). In the old build folder double-click `update-and-run.cmd`: it says which build it holds and which is newest, downloads, unpacks next to the old one, asks about older builds (answer no the first time, check that nothing was removed), starts the new Verdandi. Your scripts and settings in `%USERPROFILE%\Verdandi` are as before. Run it once more from the **new** folder and answer yes to removing the older build.
4. Break it on purpose: switch off the internet and run it: a plain message, nothing changed, and it offers to start the build you have. If curl.exe is missing on your Windows, tell me (it then uses PowerShell: `update-and-run.ps1`, not yet run anywhere).
5. Send back: which of these steps worked, the text of the window if a step failed, the build line.

## Windows M2, second round (fixes after your first test): what to check

New zip from the newest run of the workflow windows-m1 (the program is still 0.2.0; the log's first lines name the git commit).
1. **Ten restarts:** SYSTEM > AUDIO > APPLY (or SYSTEM > RESTART) ten times in a row: every time the window comes back, there is **no "norns CRASHED"** in `logs\norns.log`, `logs\crash` stays empty, and Task Manager shows no old `norns.exe`, `sclang.exe`, `scsynth.exe` after a restart or after closing the window.
2. **Start-up:** four cold starts in a row: no SUPERCOLLIDER FAIL. If SuperCollider is slow the log says `waiting for SuperCollider` (15 s) and, if it answers late, `SuperCollider answered late ... completing the start-up`; the script then loads by itself. `audio bridge:` lines: `crone is connected` (once), no "ports were not found", no `sidecar: ... Connection refused` (at most `not listening yet, trying again` followed by success).
3. **AUDIO default:** choose another device, APPLY; then choose `default` (the first entry), APPLY: the sound is on the Windows default device again, `audio.conf` has no `output=` line, the log says `audio: output chosen: the Windows default device`, and the bottom line of the page says `playing: <name>`. Tell me if not, with `audio.conf` and the `audio:` lines.
4. **If it still crashes:** send the whole `crash-....txt`; it now holds the function names (also resolvable with `python windows\ci\resolve_crash.py norns.exe --report crash-....txt` and the exe of the same build), and it is written even if the process dies at once.

## Windows M3, round 3 (build 0.4.1: fresh start, exclusive, rate, timers): what only your PC and the RME can show

1. **Fresh start:** start Verdandi, load awake, leave BUFFER on auto: it should be as clean as after a re-apply. `logs\norns.log` line `audio: ... hold-back 4` (or more) and `u` on the status line staying near 0.
2. **Exclusive (Ableton closed):** DRIVER exclusive: if it works, listen at auto, 512, 256. If it is refused the status line scrolls the exact reason (for example `Invalid sample rate; the device runs at 44100 Hz, exclusive takes: ...`) and audio.conf is set to `exclusive=0`; send that line.
3. **Rate:** `logs\norns.log` has `audio: the device itself runs at N Hz`. Check the RME Settings: still 48000 after trying exclusive? (From this build exclusive and ASIO ask for the device's own rate.)
4. **Other OUTPUT:** change OUTPUT and read the status line: it says the pair may not be wired. Does choosing the Speakers entry again bring the sound back?
5. **Timers:** load awake, then load another script (or press the RESET/restart): is `awake.lua:124 invalid paramset index: out` gone from the log? If it still appears, send the 20 lines before the first one.
6. Not testable without your PC: all of the above.

## Windows M3, round 2 (live AUDIO page, no crackle by design, readable pages): what only your PC can show

Everything below is new in build 0.4 and was tested only with a fake sound card on Linux. Steps for you: `docs/port/phase-m3.md` section 6 and the "FOR THE OWNER" block of the report.
1. **Readable:** open SYSTEM > AUDIO and two other pages (SYSTEM, DEVICES): the unselected rows are bright and easy to read, the selected row is on a bar; nothing is cut off like `under..` (a long device name runs slowly on the selected row). The screen window (F9) behaves as before.
2. **Live:** change OUTPUT (E3), wait about a second: the status line says `applying...` then `ok`; the running script (awake) does not restart and the notes carry on after a short gap. No window closes.
3. **Crackle:** DRIVER normal, BUFFER auto: one minute of awake, then BUFFER 512, 256, 128, 64. For each: crackle yes/no, the status line (`u` and `x`), and the delay you feel. The log lines `audio:` (every 10 s) have the same numbers.
4. **Delay:** the status line says an estimate (about 35 to 40 ms in normal mode is expected: that is the Windows mixer's period). Try DRIVER exclusive with Ableton closed: how much shorter does it feel? With Ableton open: the page must say `exclusive refused: normal mode` and keep playing.
5. **A device that cannot be used:** choose OUTPUT of a device that something else holds: one plain line, the list goes back to what plays.
6. **TEST:** with no input chosen: `no input selected`; with a loop (cable or TotalMix loopback): a number in ms; without the loop: `no click heard` (and the sentence on the status line).
7. **MIC with an input chosen that did not open:** press the MIC button: the note on the window says what to do (choose it again on SYSTEM > AUDIO > INPUT, or close the program that uses it).
8. **ASIO zip:** DRIVER shows `low latency`; the output list is the ASIO drivers; with Ableton closed the delay is clearly shorter; with Ableton open you get the busy line and normal mode. Send the names of the drivers.
9. **Not testable without your PC:** the real numbers, crackle itself, MMCSS and the scsynth priority class taking effect (the log says `audio bridge: scsynth.exe ... high priority class`), exclusive mode on the RME, the ASIO build's behaviour.

## Windows M3 (ASIO, sound input, the RME Fireface UC): what only your PC can show

Download the newest build (Releases page; `windows/README.md`, "Windows M3", has the click-by-click). Two zips: the default **WASAPI-only** one and the **ASIO** one. Nothing below has been tried on Windows with sound hardware, Ableton or TotalMix by me: all of it is for you, in this order.
1. **Default zip, nothing changed:** awake plays as in M2; SYSTEM > AUDIO now shows HOST (WASAPI only), OUTPUT, OUT CH, INPUT, IN L, IN R, RATE, BUFFER, APPLY, TEST, LATENCY, MEASURED, LEVEL. The log has `audio: PortAudio ...; host APIs: ...` (no ASIO) and `audio: input is OFF at the start`.
2. **Input (WASAPI):** INPUT = your microphone or the interface's input, IN L/IN R as wanted, APPLY. After the restart the input is **OFF** (MIC button state). Press MIC: LEVEL moves with your signal, you hear it. SYS next: play a video in a browser: LEVEL moves; stop it. OFF: silent. Restart Verdandi: OFF again, no feedback howl at any time. Report what the loopback does (SYS has no input of its own: the window or the log says why if it does not work).
3. **Channels:** with an input device that has more than two channels, set IN L/IN R to another pair (for example 3 and 4): the signal of those channels is heard. Same channel twice = mono on both sides.
4. **Latency numbers:** LATENCY shows `out X in Y +Z ms`; send the numbers at BUFFER 512, 256, 128. `under` and `xrun` after one minute of awake at each size (0 is good). Which is the smallest clean size?
5. **TEST and MEASURED:** loop an output to an input (a cable, or TotalMix FX loopback), quiet script (no script or a silent one), TEST: a number in ms. Without the loop: `no signal` after two seconds. Is the number plausible next to LATENCY out + in?
6. **ASIO zip:** start it; the log's host APIs line has `ASIO(n)`; HOST can be ASIO; OUTPUT lists the ASIO drivers (send their names, in particular the RME one). Close Ableton: HOST ASIO, OUTPUT the RME driver, OUT CH 1+2, APPLY: sound with a shorter delay; LATENCY out is the driver's. OUT CH 3+4: sound on outputs 3 and 4. INPUT the same driver, IN L/IN R, MIC: the interface's input is heard.
7. **ASIO busy:** start Ableton with the RME driver, then Verdandi (ASIO zip) with HOST ASIO: it must not hang. Expected: a note `ASIO driver ... is busy: another program has it (close its audio, or use the driver's multi-client mode). Using WASAPI ... instead` and sound through WASAPI on the same hardware; or, if your RME driver is multi-client, ASIO works next to Ableton. **Tell me which happened** and the driver version.
8. **The three set-ups** (`docs/port/phase-m3.md`, section 3): (b) WASAPI next to Ableton still works; (c) TotalMix FX Loopback: does the hardware output strip of your Fireface UC have a Loopback setting, did the steps work, does the Ableton track record Verdandi; (a) ASIO alone. Say what is different from the steps (buttons, names).
9. **Fallbacks:** unplug the chosen USB device before the start: a note and the default device or silence, no hang. Choose an ASIO driver, remove it from the machine or disable it, start: the same.
10. **Logs and lists to send:** `norns.log`, `sclang.log`, `audio.conf`; the output of `set VERDANDI_AUDIO_LIST=1` + `norns.exe` (device list with host APIs, channels, latencies); the TotalMix FX version; the RME driver version; the names of the ASIO drivers.
11. **Licence:** open `licenses\ASIO-SDK-LICENSE.txt` of the ASIO zip and read it once (`docs/port/asio-licence.md`): does it offer the GPLv3 option as described? Then tell me if the ASIO zip may become the default.
12. **Cannot be shown by anything else:** WASAPI loopback (SYS) in this PortAudio build; a real ASIO driver; two clocks on a separate input device (drift: sound clean for ten minutes?); the RME and Ableton behaviour.

## Windows M2 (real audio output, WASAPI): what only your PC can show

Download the newest build from the Releases page (the link to bookmark and the updater: top of `windows/README.md`; the old way, artifact m1-zip of the workflow windows-m1, still works). Click-by-click and what to send back: `windows/README.md` ("Windows M2").
1. **Sound:** awake (SELECT) is heard through the Windows default output with no crackle at the default block (512). Note the delay you feel.
2. **SYSTEM > AUDIO:** OUTPUT lists your playback devices by their Windows names; E3 chooses; APPLY restarts Verdandi (window closes and opens, about 30 s) and the chosen device is the one you hear; the bottom line shows the rate, a latency in ms and the device name; `audio.conf` in `%USERPROFILE%\Verdandi` has `output=wasapi:<name>`, `rate=`, `period=`. INPUT says "none yet".
3. **Block sizes:** 256 and 128: the smallest that stays clean on your PC; what you hear at 64.
4. **Rate:** 44100 and 96000 (the Windows mixer converts if the device runs at 48000): sound correct pitch, no crackle; the log says the rate that really runs.
5. **Device busy or gone:** a program with exclusive access, or the chosen headset unplugged before the start: Verdandi starts (no hang) with a note on the window and the AUDIO page, scripts run silently; after fixing the cause and APPLY the sound is back. A device unplugged **while running**: tell me what happens (not handled yet).
6. **Next to other programs:** with Ableton Live (ASIO) open: does Verdandi's sound still work through WASAPI, and does Live stay unaffected? Is the Windows volume mixer entry named "Verdandi" or "norns"?
7. **Engine vs. no engine:** a script with an engine (awake: PolyPerc) AND the MIX page's levels and the tape/softcut parts of a script (e.g. record and play a loop): both are heard (engine sound goes through the bridge, softcut straight in the mixer).
8. **Logs to send:** `norns.log` lines starting `audio:` / `audio bridge:`, the `sclang.log` lines `SC_BridgeAudioDriver`, and `audio.conf`.
9. **Firewall:** no new prompt should appear in M2 (nothing new listens on the network); tell me if one does.
10. **Latency feeling:** key to sound for an engine voice at 512 and 256: not noticeable / noticeable / annoying (my estimate is 40 to 55 ms at 512).

## Windows M1 (first runnable build, no sound): what only your PC can show

Get the zip: Actions > the run **windows-m1** > Artifacts > **m1-zip** (the program) and **verdandi-windows-m1** (the report, the logs of the test run and its screenshot); steps in `windows/README.md`. Unblock the zip (right-click, Properties) and unpack the WHOLE zip into a folder of its own.
1. **Start:** double-click `Verdandi.exe`. A window with the norns screen appears within about 20 seconds (SuperCollider compiles at the first start). No administrator prompt, nothing to install. Note any Windows or antivirus warning (SmartScreen: "More info", "Run anyway").
2. **Look and feel:** the Verdandi look (device skin, screen, keys, encoders), the boxes and themes (Shift+F11, F9 detach, the THEME and SCREEN pages as on Linux). Mouse on the keys and encoders, the keyboard (letters, arrows, Ctrl combinations).
3. **Home screen and SYSTEM menus:** open the menu (F10 or the right mouse button), walk through SYSTEM, DEVICES, AUDIO, CLOCK, PARAMETERS. Things that cannot work yet (audio devices, MIDI, grids) say so in plain words or show nothing; **tell me every page that crashes, hangs or shows a wrong sentence**.
4. **A script:** load a script from the SELECT page (awake is seeded on the first start; others: copy a script folder into `%USERPROFILE%\Verdandi\dust\code`; with an empty folder SELECT says "no scripts found"), run it, watch its screen redraw and its keys and encoders react. Scripts that need an engine: the engine list in SYSTEM > ... should show the engines of norns's SuperCollider side (no sound is produced).
5. **Logs:** `%USERPROFILE%\Verdandi\logs` has `launcher.log`, `norns.log`, `sclang.log` and, after a crash, `crash\`. Send these back with any report.
6. **A second start:** double-click `Verdandi.exe` again while it runs: the window comes to the front (no second copy).
7. **A path with spaces and an accented letter:** unpack into a folder such as `C:\Verdandi test\Café` and start it there; and a Windows user name with an accented letter if you have one. Say what happens.
8. **Second round (after run 42715710150):** (a) the keyboard: letters, arrows, F10/F5 and a script that uses `keyboard.code`; (b) `logs\norns.log` has no "is not recognized", no "pthread_cancel", no "menu key handler error", and says `platform: windows`, version 0.1.0; repeated lines are collapsed; (c) SELECT lists `awake` and loads it; K3 on an empty folder shows the note; (d) the MAIDEN button shows "maiden is not in this Windows build yet" and opens no browser page; (e) metros: a script with a fast metro (awake's clock) keeps time; (f) which Firewall prompts appear (norns.exe, sclang.exe, scsynth.exe?) and what you answered.
9. **Closing:** close the window: everything ends (check in the Task Manager that `norns.exe`, `sclang.exe` and `scsynth.exe` are gone).

## Windows M3 round 6 (0.4.4)
1. Normal mode: the status line right after the start should say about 41 ms, not 49.
2. AUDIO page: E3 on BUFFER shows the new value and `K3 apply` at once; K3 shows `applying...` then `applied`; E2 to another row clears it; K2 never changes the sound.
3. The boxed help appears for the selected row only, at most three lines, nothing cut off.
4. TEST: `testing...` then a short result on the row.
5. SYS: play a video in a browser, MIC button to SYS: a script with a level meter moves (direct WASAPI loopback, never run on Windows before).

## Windows M3 round 7 (0.4.5)
1. AUDIO page: turn E3 on INPUT to a long device name: the row keeps `INPUT`, ends in `*`, the full name is readable (it runs on the selected row); the help box says `* chosen: K3 applies.`
2. MIC button with no INPUT chosen: OFF > MIC shows the note `MIC needs an INPUT...`, the next press gives SYS, the next OFF.
3. SYS in normal mode works with no INPUT and shows the feedback hint; in exclusive mode it goes back to OFF with `SYS only hears Windows sound in normal mode`.

## Windows M4 (0.5.0): MIDI, clock, Link, virtual ports, OSC, MIDI MAP
1. SYSTEM > DEVICES shows `MIDI ROUTES`. Plug a USB MIDI controller in and out: it appears and goes in a few seconds (the log says `midi: found / removed`), under the same name each time; assign it to a vport, move a control: MIDI MAP WATCH sees it.
2. The Fireface's MIDI input with the midronome: it is a device in the list; PARAMS > CLOCK source = midi shows `driving: midi from <name>, N bpm` and the log has `midi: clock in '<name>': ... jitter ... us` every 10 s. Start/stop on the midronome (or a DAW) reaches scripts.
3. With Ableton open and holding that port: DEVICES says `MIDI: 1 HELD` and names the device; after closing it in Ableton and plugging in again it works.
4. loopMIDI ports: both directions to Ableton with the click-by-click of `phase-m4.md` section 6: notes/CC both ways, clock from Ableton (Sync), clock to Ableton.
5. MIDI ROUTES tests: `TEST OSC` and `TEST <loopMIDI port>`: write the numbers down (round trip, jitter); check whether a Windows MIDI Services loopback shows up in the list on build 26200.9711 and test it the same way.
6. OSC: send `/cc 1 74 64` to 127.0.0.1:9201 from any sender (the Max for Live example): `OSC IN (n)` counts, MIDI MAP learns the device `osc`.
7. Link: with Ableton on the same machine, source = link: `driving: link, 1 peer`, tempo follows both ways; listen for the beat offset against Ableton's click (the latency is added to the beat; if it is off by the audio delay in the wrong direction, tell me).
8. Clock timing: the `clock: internal ticks woke ... us late` lines (a few hundred microseconds is expected), and `midi: clock in ... jitter` with the midronome.

## Windows M4 round 2 (0.5.1)
1. Start Ableton with the Fireface at 44100 Hz (ASIO), then start Verdandi at 48000: the AUDIO page should say `the card runs at 44100 Hz; another program set it ...` (never `device missing`) or follow it; close Ableton or set the same rate: the sound comes back by itself within a few seconds.
2. Change the theme and colours (SYSTEM > THEME, SCREEN), twice, then SYSTEM > RESTART: the last values are there. Resize the detached screen window (F9), restart: size and place kept.
3. PARAMS > CLOCK, source = link: the first line says `start/stop sync off` or `on`; with it on in both programs, Ableton's play/stop starts and stops Verdandi's clock and the other way round.
4. After a slow restart: send `launcher.log` and `norns.log` (lines with `+N s` and `stage:`).
5. After resizing the window: the `window:` line in norns.log (mean and slowest redraw).

## Windows M5 (0.6.0): monome grids
1. Plug in the 128: SYSTEM > DEVICES > GRID PORTS lists it (`monome 128`, serial, its COM port); the log has `grid: found ...` and `monome device appears to be a grid; rows=8; cols=16`. Give it a vport, run a grid script (for example `grid_test` or `awake`'s grid use): keys are seen, LEDs light with different brightness.
2. Plug in the 256 as well (two vports): same, the log says `rows=16; cols=16`. With a script that shows levels (brightness ramp): what do you see on the 2011 grid (4 steps? on/off? nothing)? The serial is `M0000163`: that is the mext family.
3. Move each grid to another USB socket: it comes back at once with the same name and serial and the same vport; pull it out while a script runs: the script goes on, the entry leaves.
4. Open serialosc or a terminal program on a grid's COM port first, then start Verdandi (or plug in): GRID PORTS names the port as held in plain words; close the other program: the grid appears within a few seconds.
5. A different FTDI device (an Arduino, a GPS) on a USB socket: it is listed as `not a monome`, not opened (no LED flicker on it).
6. SYSTEM > RESTART, SLEEP and closing the window with a lit grid: the LEDs go off. (Killing the program from Task Manager cannot.)
7. Tilt (if your grid has it) and rotation: `grid:rotation(1)` etc. as on a norns.
8. Window: resize and move the main window, restart: same size and place (an unplugged second monitor: the window opens on the first).

## Windows M6 (0.7.0): maiden, installing scripts, serialosc
1. Click MAIDEN in the window: the browser opens maiden (no Firewall question; if one appears, Cancel works). The catalog list loads (needs the internet).
2. Install a script from the catalog (a small one, then one with submodules such as an nb voice pack): it appears in SELECT and runs. Update it, then remove it.
3. The norns console (bottom left of maiden): type `print(1+1)` and Enter: `2`. The sclang console: `(1+1).postln;` gives `2`. Edit a script in the editor, save, run it from the window.
4. A script that downloads things with `wget`/`curl`/`unzip` in its own install step: it works (busybox and git are in the folder).
5. With serialosc running (as a program or a service) and a grid plugged in: GRID PORTS shows SERIALOSC; K3 twice stops it; with a service that needs administrator rights the page shows the command; AUTO STOP on: a held grid port makes Verdandi stop serialosc by itself.
6. Put a Raspberry Pi plug-in (an ELF `.scx`) into a script's folder under dust\code and restart: it is moved to `disabled` and sclang still starts.

## Windows 0.8.0 (M6 round 2 + M7), to check on a real PC
- Install a mod with maiden (for example nb): SYSTEM > MODS lists it, can be enabled, and is still there after SYSTEM > RESTART; `norns.log` says `mod found: <name> ... enabled`.
- Load a script whose engine needs a missing class: within a few seconds the norns screen says `engine <name> failed: class <X> is missing`, norns.log has the same plain line, and the next script loads.
- After the packs are in: the same script with Decimator (sc3-plugins) starts; `extensions\sc3-plugins` exists in your Verdandi folder; `norns.log` has no `SuperCollider classes missing` line.

## Windows 0.8.1 (packs with their classes, pack refresh, start-up that survives a failing extension)
- After the first start: `extensions\mi-UGens\Classes\MiPlaits.sc` and `extensions\sc3-plugins\PACK-ID.txt` exist; the old copy of the pack is in `disabled\mi-UGens-replaced` and `disabled\sc3-plugins-replaced`; your own folders in `extensions` are untouched.
- The emplaitress mod (or any script with `MiPlaits.ar`) starts; `logs\sclang.log` has no `Class 'MiPlaits' not found`, norns does not show SUPERCOLLIDER FAIL.
- `logs\sclang.log` has one line `plug-in packs: ...`; its list (and `logs\pack-check.txt`) is what is really missing.

## Windows 0.8.2 (plug-ins in the server, /home/we in sclang, stale maiden)
- A script with `MiPlaits` / `Decimator` / `MoogLadder` / `SawDPW`: `logs\sclang.log` has no "not installed"; the engine makes sound.
- Dronecaster: the drone list is not empty; picking Apparatus works (no "does not know this drone").
- `norns.log` no longer shows `find: ...\.local\share\SuperCollider\Extensions/: No such file or directory`; the folder `C:\Users\<you>\Verdandi\.local\share\SuperCollider\Extensions` exists.
- MAIDEN button opens maiden (no 404), also after you ran an older program folder before. If another program uses port 5000 the button says so on the window.

## Windows 0.8.3 (duplicate classes, restarts, SUPERCOLLIDER FAIL explained)
- Start, use the emplaitress mod, restart (SYSTEM > RESTART) several times: `logs\sclang.log` never has "duplicate Class" or "Library has not been compiled"; norns.log says "emplaitress found mi ugens" (it does not download anything).
- `C:\Users\<you>\Verdandi\.local\share\SuperCollider\Extensions\mi-UGens` holds the pack (with `PACK-ID.txt`); `extensions\mi-UGens` is gone (the old copy is in `disabled\mi-UGens-moved`).
- If you copy a folder that defines the same classes as one of yours into `extensions`: launcher.log says that nothing was moved and names both folders; the window shows a note.

## Windows 0.9.0 (ext folders)
1. Right-click the window: the menu no longer has Import files / Import folder / Copy samples / the file-dialog tick / Virtual grid, arc, keyboard; it has Ext folders, Show dust folder, Show tape folder, Screenshot, Record GIF, the Input items, Mute, MIDI actions, Open maiden, Open the manual, Quit.
2. Ext folders (or SYSTEM > EXT FOLDERS): K3 on ADD FOLDER opens the Windows folder window (an Explorer-style window). Choose a folder with samples (try one with an accented letter or a blank in its name, one on a second drive, one under OneDrive). The window comes back with "Added [ext] <name>." The window must not freeze the sound or the clock while it is open (play a script with a clock first).
3. In a script that asks for a sample (or on the TAPE page, PLAY): the browser lists `[ext] <name>` next to the dust folders; open it, play a sample from it.
4. Restart (SYSTEM > RESTART): the folder is still in the list and in the browser.
5. Unplug the drive or rename the folder: the list shows MISSING for it; nothing is deleted. Put it back: it works again (restart if it does not).
6. Try to add: the same folder again, a folder inside dust, a network share (\\server\share): each is refused with a plain sentence.
7. Remove: K3 on the entry shows the warning; K2 cancels; K3 again removes only the shortcut. Check in Explorer that the original folder and its files are all still there, and that `dust\audio` has no `[ext]` entry left.

## Windows 0.9.1 (picker, rename, GIF keys)
1. Right-click: the item is "Ext folders" and the page title is EXT FOLDERS. "Record GIF" shows Ctrl+Shift+G.
2. EXT FOLDERS > ADD FOLDER, K3: the Windows folder window opens (an Explorer-style window); navigate, choose a folder: "Added [ext] <name>." Cancel in the window says "cancelled". If it cannot open, the screen shows the step and the error code, and `logs\norns.log` has a line `windows: folder picker: ... HRESULT 0x...`; a PowerShell window may open instead (older style).
3. Press Ctrl+Shift+G (or the menu): the screen says "REC GIF - Ctrl+Shift+G stops"; press it again: "GIF saved to Pictures\Verdandi".

## Windows 0.10.0 (the script twins)
1. Install twins with maiden (or copy its folder into `dust\code`) and load it: no "Missing SuperCollider Libraries" screen. The folder `<your Verdandi folder>\.local\share\SuperCollider\Extensions\PortedPlugins` exists and holds the three `*_scsynth.scx` and the empty `*_scsynth.so` files next to them.
2. Play twins: the engine loads and makes sound; the effects AnalogChew, AnalogLoss and AnalogDegrade (the "chew", "loss" and "degrade" controls of the script) can be heard when turned up. `logs\sclang.log` has no "not installed" and no "duplicate Class".
3. Clone twins with maiden (a git clone). When the author has pushed new commits, ten seconds after the script starts the screen says "Twins Update Available": K2 skips, K3 installs; after K3 "Update Installed" (a new engine) K3 restarts Verdandi by itself within a few seconds, or the script reloads (no engine change).
4. A copy of twins that was unpacked from a zip (no `.git`) never shows the update screen: that is as designed.
5. If you edit a file of the cloned twins, the update prompt stays away (the script's own rule: local changes).

## Windows 0.10.1 (dead server, long names)
1. Load twins, give it a sample (the file of the crash if you still have it). If the server stops again: within a second or two the screen says "SuperCollider stopped (error 0x...): restarting it and the script (1 of 2)", Verdandi restarts, twins comes back; after the second restart a third stop says "SuperCollider keeps stopping ... not restarting it again". `logs\launcher.log` has the exit code of each stop (send it).
2. While a script waits for an engine and the server dies, the loading screen stops with "SuperCollider stopped" and the next script can be loaded (no waiting for ever).
3. In the file browser, a sample with a long name in an [ext] folder: E3 (preview) and K3 (choose) open the right file; `norns.log` has no "cannot open sndfile".
4. Optional, if the crash comes back: Windows can keep a crash dump of scsynth.exe (a registry setting that needs an administrator, "LocalDumps"); the dump plus `logs\launcher.log` and `logs\sclang.log` say which plug-in it was.

## Windows 0.10.2 (HOME page, sensitivity, the drawn knob)
1. HOME page, K2: the statistics appear (cpu numbers, disk) with no error note; keys and encoders work at once. The statistics change every two seconds.
2. SYSTEM > MIDI MAP: an encoder that was 2 now shows 5 and turns at the same speed as before; 9 is the same as before; 1 is somewhat slower than the old 1. A new mapping starts at 5.
3. Turn a MIDI encoder fast, then stop: the drawn knob stops when you stop (it ends where the value is).
