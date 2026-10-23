# Hardware checklist for Ken

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
