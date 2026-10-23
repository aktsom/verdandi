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
