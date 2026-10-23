# Phase 0 inventory: macOS-specific code and its Linux / Windows equivalents

Read-only inventory (no code changed). Sources: `readme-macos.md`, `macos/`, `macos/docs/`,
`matron/src/platform/macos/`, `wscript`, `norns/wscript`, `norns/main.cpp`, `lua/`.
Windows columns are a first pass; Phase 6 extends them.

## 1. How the macOS port is wired in (verified against code)

- `wscript`: `NORNS_MACOS = sys.platform == 'darwin'`. `configure_macos()` forces `--desktop`,
  adds a deps prefix (lua 5.3, nng, libmonome) and `-mmacosx-version-min`. On macOS it skips
  alsa/udev/evdev/gpiod/avahi/atomic. `build()` recurses into `macos/` (jack tools,
  audio_devices, auv3_bridge, app_input) instead of `watcher/`.
- `norns/wscript:150-234`: on macOS the pi hardware and linux device layer are replaced by
  `matron/src/platform/macos/*` (file list at lines 162-179), a force-included `compat.h`,
  fake `linux/input.h`, `libevdev.h`, `gpiod.h` in `platform/macos/include/`, and frameworks
  AppKit, CoreAudio, CoreFoundation, CoreMIDI, IOKit, UniformTypeIdentifiers.
- `norns/main.cpp:124`: the main thread runs `sdl_bridge_run()`, matron runs on its own thread
  (Cocoa needs windows on the main thread). Upstream hooks are `#ifdef __APPLE__` in
  `weaver.cc` (Lua functions `show_control`, `open_url`, `grid_window`, `app_input`,
  `monitor_out`, `choose_file`, `choose_file_close`; key/enc echo), `system_cmd.cc:145`
  (shutdown/reset/update commands), `hardware/screen/sdl.cc`, `hardware/io.cc`,
  `device/device_{hid,midi,serial}.{cc,h}`, `event_types.h`, `crone/src/effects/*.h`.
- Lua side is mostly platform-neutral by feature test (`if _norns.app_input`,
  `_norns.choose_file`, `_norns.open_url`), plus env `NORNS_HARDWARE_KEYS`
  (`lua/core/keyboard.lua`), `lua/core/virtual_home.lua` (virtual `/home/we`) and
  `lua/core/menu/audio.lua` (reads `audio_devices`).

**Key finding:** upstream norns already builds on desktop Linux with `--desktop`
(SDL screen `hardware/screen/sdl.cc`, keyboard input `hardware/input/sdl.cc`) and has
Linux device code (udev, ALSA rawmidi, evdev, termios). The Linux port is therefore mostly
*reusing upstream paths* plus re-hosting the macOS desktop layer on SDL2/POSIX, not
rewriting device code. Things still needing Linux attention: gpiod/ssd1322/battery/i2c/stat
on a non-Pi machine (the macOS stubs are reusable), and `NORNS_MACOS` splits in the wscripts
that must become a three-way platform switch.

## 2. Per-file inventory

Legend: **P** = already portable (plain C/POSIX/Cairo/SDL2), **R** = replace, **A** = adapt.

### 2.1 Portable as-is (shared desktop layer)

| File | What it does | Status |
|---|---|---|
| `device_skin.c/.h` (641) | Cairo drawing/hit-test of the norns device, buttons, knobs, MIC/OUT | P (tests `macos/tests/device_skin_test.c`) |
| `vgrid_skin.c`, `varc_skin.c`, `vkeys_skin.c` | Cairo drawing/hit-test for virtual grid, arc, keyboard | P |
| `vgrid_proto.c/.h` (253) | grid/arc side of the mext serial protocol | P (`vgrid_test.c` needs libmonome) |
| `vgrid_device.c/.h` (197) | pty (`posix_openpt`, `cfmakeraw`) libmonome opens as a USB grid; links `grid-m<digits>` in a private tmp dir | P/A: POSIX; check libmonome's Linux path/serial-number parsing (see 3) |
| `window_keys.c/.h` (175) | computer keyboard to K/E mapping, by HID usage | P (`window_keys_test.c`) |
| `gif_writer.c/.h` (148) | pure-C GIF encoder, 16 grey levels | P (`gif_test.c` links ImageIO but the writer itself does not; test must be adapted) |
| `dust_import.c/.h` (262) | classify dropped paths, symlink/copy into dust | A: uses `copyfile(3)` (macOS); replace with read/write or `copy_file_range` loop. Windows: copy only (no symlinks) |
| `open_url.c/.h` (48) | spawns `open` for http(s)/absolute paths, validated | A: Linux `xdg-open`; Windows `ShellExecuteW` |
| `product.h` | product name macros | P |
| `hardware_null.cc` | stubs: battery, i2c, ssd1322 | P for Linux desktop (reuse) |
| `stat_macos.cc` | CPU/temp/disk stats via mach | R: Linux `/proc/stat`, `/sys/class/thermal`, `statvfs` (upstream `hardware/stat.cc` already does this on Linux) |
| `compat.h` | Darwin POSIX gaps: pthread_setname_np, clock_nanosleep, unnamed sem, extern "C" lua | Not needed on Linux (the lua extern "C" part must be kept in mind: see 4). Windows needs its own (clock_nanosleep, sem, pty absent) |
| `include/linux/*`, `libevdev/`, `gpiod.h` | fake kernel headers so linux sources compile | Not needed on Linux (real headers). Windows would need them again |

### 2.2 macOS-API code to replace

| macOS API / file | What it does | Linux equivalent | Windows equivalent |
|---|---|---|---|
| **Cocoa window + event pump**: `sdl_bridge.cc` (2324, SDL2 wrapped in main-thread bridge; uses `dispatch/dispatch.h`, `removefile.h`, `pwd.h`) | owns SDL windows (norns, grid, arc, keys), toasts, layout, screenshot, GIF, drop events, control echo | Keep: SDL2 works on Linux. Replace `dispatch_*` with a mutex/cond or SDL user events; `removefile` with `nftw`/`unlink`; keep main-thread model (harmless on X11/Wayland) | SDL2 works; same replacements |
| **Cocoa menu bar** `mac_menu.m` (441) + `mac_menu.h` | File menu (import panel, show dust/tape folder, screenshot, GIF), Devices menu (grid/arc/keys, audio input); promised-file/pasteboard drops; adds drop methods on SDL's window class | No global menu bar on Linux. Use in-window buttons/hotkeys and right-click menu drawn with Cairo (consistent with `device_skin`), keep ids `MAC_MENU_*`. Open folders via `xdg-open`. Promised-file drops: drop (SDL_DROPFILE/TEXT) only, plus XDG DnD where SDL gives it | Win32 menu via SDL syswm, or same in-window menu; drops via SDL; folders via `ShellExecute` |
| **NSOpenPanel / UTType** (file picker, `_norns.choose_file`) | script file selection and Import | XDG Desktop Portal `org.freedesktop.portal.FileChooser` over D-Bus (sd-bus or GDBus); fallback `zenity`/`kdialog`; fallback to norns' own fileselect only | `IFileOpenDialog` |
| **Finder drop** (SDL_DROPFILE at `sdl_bridge.cc:2213` + pasteboard code in `mac_menu.m`) | drop files into dust | SDL_DROPFILE works on X11/Wayland | SDL_DROPFILE |
| **CoreMIDI**: `device_midi_coremidi.inc` (266), `device_monitor_macos.cc` (454), CoreMIDI source "norns keys" in `sdl_bridge.cc:1200` | MIDI in/out devices, virtual port "norns", virtual keyboard | Upstream `device_midi.cc` uses ALSA rawmidi and udev already (use as is for hardware). Virtual keyboard port: ALSA sequencer (`snd_seq`) virtual port named "norns keys"; it must also show up in norns' device list (needs a seq-aware path or the pty/rawmidi virtual device `snd-virmidi`; to decide in Phase 2) | WinMM/WinRT MIDI or RtMidi; virtual ports need loopMIDI/Windows MIDI Services (not built-in) |
| **IOKit serial/USB**: `device_monitor_macos.cc` | grid, arc, crow, serial discovery and hotplug | Upstream `device_monitor.cc` (libudev) + `device_serial.cc`/`device_crow.cc`/`device_monarch` via termios; libmonome with serialosc/udev. Reuse upstream | COM ports via SetupAPI/`CM_Register_Notification`; libmonome Windows support must be verified (Gate/Phase 6) |
| **IOHIDManager**: `device_hid_iohid.cc` (385) | gamepads/joysticks/keyboards translated to evdev codes | Upstream `device_hid.cc` uses libevdev: reuse | RawInput / XInput / SDL joystick, translating to evdev codes (needs a mapping table) |
| **device runloop** `device_runloop.cc` (84) | CFRunLoop thread for IOKit/CoreMIDI | Not needed (udev monitor / poll) | Message-only window thread or threadpool |
| **ImageIO** | GIF/PNG output | Not actually used in code: screenshots use `cairo_surface_write_to_png` (`sdl_bridge.cc:1537`), GIFs use `gif_writer.c`. Only `gif_test.c` links ImageIO (for verification) | Same: Cairo PNG + gif_writer |
| **Core Audio process tap** `app_audio.m` (215) + `macos/app_input.m` (418) | SYS / APP input: JACK client playing another app's audio into crone:input_1/2; spawn with `POSIX_SPAWN_CLOEXEC_DEFAULT`; parent watch | JACK / PipeWire graph: SYS = connect system monitor/sink ports (`system:monitor_*` or PipeWire `jack` monitor ports) to crone inputs; APP = connect chosen client's output ports (`pw-jack`/`jack_lsp` listing, or PipeWire node listing). No spawn needed beyond `jack_connect` calls; `_norns.app_input` can be implemented in-process with the JACK API. Needs the nonexistent-monitor case handled (plain JACK without PipeWire has none) | WASAPI loopback (system) and per-process loopback (Win 10 2004+ `ActivateAudioInterfaceAsync` with process loopback); JACK2 on Windows |
| **`macos/audio_devices.c`** (141) | enumerate CoreAudio devices; lists uid, name, channels, rates; `--default-input/--default-output` | ALSA: `snd_card_next` / `snd_ctl_*` + hw params; with PipeWire: `pw-dump`/`wpctl`; output must keep the TSV format consumed by `lua/core/menu/audio.lua` | WASAPI/ASIO enumeration; ASIO required for RME Fireface (Gate D) |
| **jackd (coreaudio driver)** in `macos/norns.sh` | launcher starts jackd with `-d coreaudio` and `audio.conf` | jackd2 `-d alsa` (or PipeWire-JACK, no jackd); `-d dummy` for headless tests | JACK2 with `-d portaudio` (ASIO) |
| `macos/jack_tools.c` (84), `jack_wait.c` (34) | busybox-style `jack_connect/disconnect/lsp`, wait-for-port | Distribution already ships `jack_connect` etc.; keep `jack_wait` (portable) | Build or bundle JACK tools |
| **`macos/auv3/`** `NornsAU.mm` (391), `auv3_bridge.c` (266), `bridge_protocol.h` (36) | AUv3 plugin client + JACK-side bridge; UDP 127.0.0.1:10200, 128-frame blocks, NB_AUDIO/NB_MIDI/NB_BYE; MIDI exposed as a CoreMIDI source | Linux has no equivalent plan in PLAN.md (no plugin). If wanted later: ALSA sequencer port instead of CoreMIDI | `bridge_protocol.h` and the JACK half of `auv3_bridge.c` are reusable for the VST3 (Phase 7); MIDI output becomes a Windows virtual MIDI port or in-process injection |
| **`system_cmd.cc:145`** | SLEEP/RESTART via `pkill -a -x 'norns|Verdandi'` and `.norns-restart` marker | Linux launcher wrapper handles `.norns-restart`; `pkill -x` works (drop `-a`); Pi `shutdown` actions must NOT run on desktop | Needs a native process-control replacement |
| **`macos/norns.sh`** (317), **`app-launcher.sh`** (31) | launcher: environment, GNU tools PATH, SC config, jackd, crone, sclang, maiden, restart logic, `pgrep` | Port to Linux bash: use system GNU tools (no gnubin), `sclang`/`scsynth` from distro, no `DYLD`, `~/norns` home | PowerShell or a small native launcher; GNU tools bundle (MSYS2/busybox) |
| **`macos/make-app.sh`, `bundle_dylibs.py`, `fetch_bottles.py`, `make-icon.py`, `licenses.py`, `setup-deps.sh`, `build.sh`** | app bundle, dmg, rpath rewriting, Homebrew bottles, license collection, dependency build | New: `linux/setup-deps.sh`, `linux/build.sh`, AppImage/Flatpak builder (Gate B); `licenses.py` can be reused (check it is not macOS-specific) | New |
| `matron/src/metro.cc`, `clocks/clock_internal.cc` `clock_nanosleep` | shimmed by `compat.h` | Native on Linux | Needs shim |
| `crone/src/effects/ZitaReverb.h`, `StereoCompressor.h` | `__APPLE__` blocks | Native Linux path (no change) | Likely needs same as macOS path |
| `maiden` patch `macos/patches/maiden-host-flag.patch` | bind maiden to 127.0.0.1 | Reuse | Reuse |
| avahi `dns_sd` (`osc.cc`) | service discovery | `avahi-compat-libdns_sd` (already in upstream wscript) | Bonjour SDK or drop |

### 2.3 Tests

| Test | Needs macOS? | Linux plan |
|---|---|---|
| `window_keys_test.c`, `device_skin_test.c` (cairo), `vgrid_test.c` (libmonome), `dust_import_test.c` (after `copyfile` replaced) | No (C) | Phase 1 (after relocating or building from `platform/macos`); `dust_import_test` needs the replacement |
| `keyboard_hardware_test.lua`, `menu_pages_test.lua`, `input_modes_test.lua`, `fileselect_finder_test.lua`, `output_fader_test.lua`, `virtual_home_test.lua` | No (Lua 5.3) | Phase 1 |
| `gif_test.c` | Yes (links ImageIO) | Adapt: compare against own decoder / giflib / Python PIL |
| `drop_test.m`, `app_input_test.m` | Yes (Objective-C) | Rewrite per platform layer |
| `tests/` (upstream waf unit tests) | No | Phase 1 |
| `macos/tests/norns_probe.sh` | Calls `macos/norns.sh` | Phase 1 Linux variant |

## 3. Risks and open questions (from reading, to verify in later phases)

1. **Layout:** the shared files are in `matron/src/platform/macos/`. Gate A decides whether
   they move to `platform/common/` or stay and are referenced from `platform/linux/`.
2. **libmonome on Linux** identifies the serial from the device path after the first `-`
   (comment in `vgrid_device.h`); on Linux libmonome looks at `/dev/serial/by-id`-like
   names and udev. The pty trick may need a different symlink name or libmonome patch.
3. **Virtual MIDI keyboard on Linux:** upstream `device_midi.cc` opens `/dev/snd/midiC%dD%d`
   (rawmidi), not sequencer ports. Exposing "norns keys" may need `snd-virmidi` (kernel
   module, needs privilege) or a new seq-backed device type in the Linux layer.
4. **Lua as C vs C++:** macOS builds lua as C and wraps headers in `extern "C"` via
   `compat.h`. Distro `liblua5.3-dev` is C and its headers already carry `extern "C"` guards,
   so Ubuntu 24.04 should work; to verify in Phase 1. C modules from scripts (cjson) need
   the executable to export symbols (`-rdynamic`).
5. **SuperCollider / sc3-plugins / jackd2** versions on Ubuntu 24.04 (SC 3.13 in distro, JACK
   backend of scsynth); packaging (Gate B) must bundle or depend on them.
6. **No `jackd`, `sclang`, `lua5.3` or `Xvfb`-only tooling is installed in this sandbox**
   (`Xvfb` is present; jackd/sclang/lua5.3 were not found by `which`). Phase 1 must install
   them; if the network/apt is unavailable that blocks the boot test and goes to STATUS.
7. **Wayland vs X11:** SDL2 handles both; GIF/screenshot save to `$XDG_PICTURES_DIR`/Desktop
   to decide in Phase 2.

## 4. Already portable summary

Skins (`device_skin`, `vgrid_skin`, `varc_skin`, `vkeys_skin`), key mapping (`window_keys`),
GIF encoder (`gif_writer`), virtual grid protocol (`vgrid_proto`), pty device (`vgrid_device`,
POSIX), dust classification logic (`dust_import` apart from `copyfile`), URL validation
(`open_url`), Lua feature-detection layer, all Lua tests, UDP bridge protocol, `hardware_null`.
Roughly 2,950 of the ~7,800 lines in `platform/macos/` are directly reusable; the rest
(`sdl_bridge.cc` needs targeted edits, the Cocoa/CoreMIDI/IOKit/CoreAudio files) is replaced.
