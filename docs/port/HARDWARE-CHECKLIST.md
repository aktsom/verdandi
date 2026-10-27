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
      "Verdandi JACK in".
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
      ALSA cards, APPLY restarts jackd with them (`jackd.log`); a setting that does not start falls back to the defaults
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
- [ ] A second click while it runs: nothing breaks. (Known: it says "norns is already running" in a dialog; bringing the first window forward is not built.)
- [ ] Break something on purpose (stop PipeWire and jackd): a dialog says what is wrong instead of nothing happening.
- [ ] **Shared home:** with your developer checkout's home (`NORNS_HOME=… ` or `echo /path/to/home > ~/.config/verdandi/home`), start the package: your scripts and data are there; the `norns` link of that home now leads to `/opt/verdandi`; start the checkout (`linux/norns.sh`) and the link leads back. A real folder called `norns` in the home makes the launcher refuse with a message (it is never replaced).
- [ ] Your usual scripts and the engines Orgn and Eterna with real audio (the headless check only measured the output level of a dummy driver).
- [ ] **A real grid and a real arc**, plugged in after the package is installed: they work as with the checkout. **This also tests the libmonome fix** (the package carries its own libmonome with its protocol modules in `/opt/verdandi/lib/monome`). Then try `lsusb` and `udevadm info` on the serial port to see the numbers and the manufacturer string, and `getfacl /dev/ttyUSB0` (or `ttyACM0`): your user should have an ACL entry without being in `dialout`. Note the IDs of **every** grid and arc you own: the udev rule's numbers are not verified.
- [ ] `sudo apt remove verdandi`: `/opt/verdandi`, the menu entry and the udev rule go; `~/Verdandi` stays.
- [ ] Engines/UGens of scripts you use that needed the distribution's sc3-plugins: they should run on the bundled 3.14.1 (`docs/port/supercollider-3.14.md` lists what is known). Note any script that fails on SuperCollider classes (a Qt GUI class is not in the bundled build).
- [ ] **Browser (found on your laptop):** with Vivaldi as the default browser, click MAIDEN and MANUAL in the window, started from the menu entry and from a terminal with `verdandi`: both open Vivaldi, as `xdg-open http://127.0.0.1:5000/maiden` in a terminal does. If one still opens Firefox, send `echo $BROWSER` and `xdg-settings get default-web-browser` from the terminal you start it in. (Changing the default in Cinnamon's settings while Verdandi runs: close and start it again.)
- [ ] **Name:** the window title and the application menu entry read "Verdandi Linux"; `apt show verdandi` starts its description with it; the JACK/PipeWire graph still shows the client "Verdandi" and your MIDI setup still finds "Verdandi keys".
- [ ] **Panel icon:** after installing the new `.deb`, the running window shows Verdandi's icon (not a gear) in Cinnamon's panel and window list, started from the menu and from `verdandi` in a terminal; `xprop WM_CLASS` on the window still prints `"norns", "norns"`; a pinned launcher groups with the window.
