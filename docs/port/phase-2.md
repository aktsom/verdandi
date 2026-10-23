# Phase 2: desktop layer for Linux (approach note, for Ken to confirm)

Status: **approach only, no Phase 2 code written.** Everything below that says "verified" was
checked by reading code or by a throwaway experiment outside the repository; nothing in the
repository changed except this file and `STATUS.md`.

Goal (PLAN.md): the SDL window with the shared skins, virtual grid/arc/keys, drop and file
picker, screenshot/GIF, menu actions, all in `matron/src/platform/linux/`, reusing the macOS
shared files where they are plain C.

## 0. Where the code goes (Gate A, option 1)

- New files go in `matron/src/platform/linux/`. The shared files (`device_skin`, `vgrid_*`,
  `varc_skin`, `vkeys_skin`, `window_keys`, `gif_writer`, `dust_import`, `open_url`,
  `hardware_null`) stay in `platform/macos/` and are referenced from there until the separate
  "move to `platform/common/`" commit, as agreed.
- Edits to shared files are limited to `#ifdef __APPLE__` seams that keep the macOS path
  byte-for-byte as it is. Each such edit is listed in section 6 so macOS can be re-verified.
- **`sdl_bridge.cc` (2324 lines) is the one big question, see section 5.**

---

## 1. libmonome cannot open the virtual grid pty

**What fails (verified).** `vgrid_device.c` makes a pty and links it as
`<tmp>/grid-m0000001`. `monome_open()` (libmonome 1.4.9, `src/libmonome.c:81`) calls
`monome_platform_get_dev_serial(path)` and gives up if it returns NULL. On Linux that function
(`src/platform/linux_libudev.c`) requires a character device that udev knows
(`udev_device_new_from_devnum`) and reads `ID_SERIAL_SHORT`. A pty is a character device, but
udev has no record of it, so the serial is NULL and the open fails. macOS's `darwin.c` instead
parses the serial from the path after the first `-`, which is why the macOS port works. The
serial then selects the protocol (`map_serial_to_device`, `m%d` → mext), so it cannot be skipped.

**Options**

| | Option | Verdict |
|---|---|---|
| A | Patch libmonome: if udev has no serial and the path is a link named `grid-<serial>` / `arc-<serial>` (or, more generally, `<name>-<serial>` pointing at `/dev/pts/*`), take the serial from the name, as `darwin.c` does | **Recommended** |
| B | Symbol interposition: define `monome_platform_get_dev_serial` in norns and rely on the dynamic linker | Fragile (depends on libmonome's symbol visibility and link flags), rejected |
| C | Make the virtual device speak libmonome's OSC protocol (`osc.udp://`) | A second protocol in `vgrid_proto.c`; much more code than A |
| D | Bypass libmonome for the virtual device in `device_monome.cc` | Changes shared device code and loses libmonome's rotation/intensity handling; rejected |
| E | Kernel/udev tricks (tty0tty, udev rules for a pty) | Needs root and kernel modules; rejected |

**Evidence for A.** I patched a scratch copy of libmonome 1.4.9 (outside the repo) with a
fallback of about 8 lines in `linux_libudev.c`; `vgrid_test.c` then passes completely
(`vgrid ok: 0 failures`, grid 64/128/256 and arc), where the unpatched build had 4 failures.

**Plan.**
1. `linux/patches/libmonome-pty-serial.patch` (same style as `macos/patches/`), applied by
   `linux/setup-deps.sh` while building libmonome 1.4.9. Ubuntu 24.04 has no `libmonome-dev`, so we
   build libmonome ourselves anyway, and a package bundle ships that build.
2. The patch only fires when udev gives no serial, so real grids, arcs and the Pi are unaffected.
   It is written so it could be offered upstream to monome/libmonome later (Ken's call).
3. `c:vgrid` moves from KNOWN to PASS in `linux/tests/run_all.sh`.
4. Side issue found on the way: with `-std=gnu11` and no `_GNU_SOURCE`, `ptsname` is implicitly
   declared and returns `int` (pointer truncation on 64-bit). The waf build defines `_GNU_SOURCE`,
   so the app is fine, but `vgrid_device.c` gets an explicit `#define _GNU_SOURCE` (harmless on
   macOS) so the standalone test compiles correctly.

Risk: the patch changes a third-party library we build ourselves; if Ken prefers not to carry a
patch, option C is the alternative at a higher price.

---

## 2. The virtual "norns keys" MIDI port

**What macOS does.** `sdl_bridge.cc:1071-1210` creates a CoreMIDI source "norns keys"; the device
monitor sees it like any app's port, so norns gets a MIDI device and other apps can connect to it.

**What upstream Linux already has (verified).** `device_midi.cc:116` `dev_midi_virtual_init` opens
alsa-lib's `"virtual"` rawmidi (an ALSA *sequencer* client). That is the "norns" virtual port, and
it is what failed at boot in Phase 1: `/dev/snd/seq` does not exist in this container. Hardware
rawmidi devices (`/dev/snd/midiC*D*`) come from udev in `device_monitor.cc`; ALSA sequencer ports
of other apps are **not** visible to matron, on Linux upstream or here.

**Options**

| | Option | Verdict |
|---|---|---|
| A | A new internal device backend: the vkeys window writes MIDI bytes into a pipe; `dev_midi` reads it with the existing byte parser (running status, sysex, clock), exactly as `device_midi_coremidi.inc` does with its pipe. Registered as `DEV_TYPE_MIDI`, path `vkeys:`, name "norns keys" | **Recommended, as the part that makes the keyboard work** |
| B | Additionally publish the same bytes on an ALSA sequencer port (client "norns", port "norns keys") so other apps/DAWs can connect | Recommended as an add-on, optional at runtime: skipped silently when `/dev/snd/seq` is missing |
| C | Use only `snd_rawmidi_open("virtual")` and rename the port | alsa-lib's virtual rawmidi does not expose naming, needs `/dev/snd/seq` always, and cannot be tested here; rejected as the only path |
| D | JACK MIDI port | Not what norns' MIDI layer or users' DAWs expect; rejected |

**Plan.**
1. `matron/src/platform/linux/device_midi_vkeys.inc` + a few lines in `device_midi.cc` /
   `device_midi.h` under `#ifdef NORNS_LINUX_DESKTOP` (the struct gets `pipe_rd`/`pipe_wr`, as the
   `__APPLE__` branch already has). `dev_midi_init` dispatches on the `vkeys:` prefix. The parser
   and everything above it stay shared.
2. `platform/linux/` registers the device with `dev_list_add(DEV_TYPE_MIDI, "vkeys:", "norns keys", NULL)`
   when the keys window is first opened (macOS: at window creation; same behavior).
3. B is a small `snd_seq` writer thread (libasound is already a dependency), fed from the same
   function that writes the pipe. It is only an output mirror; it does not change what norns hears.
4. Testing here: A is fully testable without hardware (inject bytes, check lua `midi.vports`
   and an event through `_norns.midi.event`, extend `norns_probe` to do so). B cannot be tested
   in this container (no `/dev/snd/seq`); it goes into `HARDWARE-CHECKLIST.md` with an exact
   `aconnect -l` / `aseqdump` recipe. I will not claim B works until Ken has run it.
5. Inbound ports of other apps ("norns" virtual destination, other apps' sources) are **not** in
   Phase 2's scope beyond what upstream already does; Phase 3 ("real devices via the norns Linux
   paths") covers hotplug and decides whether a seq-subscription monitor is worth building.

Open question for Ken: is publishing "norns keys" to other Linux apps (B) wanted in the first
Linux release, or is norns-internal keys enough for now?

---

## 3. dust_import replacement

**What it uses.** `copyfile(3)` in two places (`dust_import.c:198-204`) with
`COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL` (+ `COPYFILE_RECURSIVE` for folders). Everything
else in the file (classification, unique naming, link reuse, pruning, `dust_import_volatile`) is
POSIX and platform-neutral. The Linux file-manager and temp locations differ from macOS only in
`dust_import_volatile`.

**Plan.**
1. Keep the `copyfile` code **unchanged on `__APPLE__`** (so macOS behavior is untouched).
2. Add a portable `copy_path(src, dst, recursive)` for everything else: open source, create the
   destination with `O_CREAT|O_EXCL|O_WRONLY` and the source's mode (nothing is overwritten, as
   `COPYFILE_EXCL`), copy with `copy_file_range()` falling back to a read/write loop, `utimensat`
   to keep times (`COPYFILE_STAT`), recursion with `opendir`/`mkdir` (no `nftw`, so errors map
   one-to-one), symlinks in a dropped folder copied as links. On failure part way, remove the
   partial destination (a half copy must not look like an imported sample).
3. `dust_import_volatile` on Linux also treats `$XDG_RUNTIME_DIR`, `$XDG_CACHE_HOME`/`~/.cache` and
   `~/.local/share/Trash` as volatile (mirrors "Library/Caches" and ".Trash"). Same function, extra
   branch under `#ifndef __APPLE__`; macOS list unchanged.
4. The link folder name stays `dust/audio/mac` for now (lua and `readme-macos.md` refer to it;
   renaming is a user-visible compatibility question that I will not decide silently). I propose
   to keep `mac` as an internal constant and to ask Ken later whether Linux should show another
   name.
5. `dust_import_test.c` already tests behavior only; it runs unchanged on Linux. I will add cases
   for: copy of a folder tree, EXCL on an existing target, a failing copy leaves nothing behind, a
   dropped symlink.
6. Windows (Phase 6) uses the same portable copy and no links, per PLAN.md.

---

## 4. Menu and file-picker replacement

**What macOS does.** `mac_menu.m` (441 lines, AppKit) installs the menu bar (File: import,
show dust / tape, screenshot, GIF; Devices: grid, arc, keys, audio input), handles
drops that carry promised files or audio data, and the open panel for `_norns.choose_file`. The
interface is `mac_menu.h`; `sdl_bridge.cc` only calls that header.

**Linux has no global menu bar** and SDL cannot create one. Proposal:

1. **In-window menu.** A new pure-C Cairo file `menu_skin.c/.h` (same style and test approach as
   `device_skin.c` / `vgrid_skin.c`; tested by drawing to PNG and hit-testing): a popup list
   opened by a small button on the device window, F10 and right-click. Items and ids reuse the
   existing `MAC_MENU_*` enum (Import…, Show dust, Show tape, Screenshot, GIF start/stop, Grid,
   Arc, Keys, input MIC/SYS/OFF), with keyboard navigation. Accessible equivalents are plain key
   shortcuts (existing F6/F7/F8 stay; add Ctrl+Shift+S for the screenshot).
2. **Folders.** `open_url.c` gets a Linux branch that runs `xdg-open` (same argument checks as
   today, same non-blocking reap). If `xdg-open` is missing: a toast says so, nothing else
   happens.
3. **File picker** (`_norns.choose_file`, import). In this order:
   1. **XDG Desktop Portal** `org.freedesktop.portal.FileChooser.OpenFile` via **GDBus**, which is
      part of glib, already a build dependency, so **no new dependency**. Works in Flatpak
      (needed for Gate B) and on GNOME/KDE/PipeWire desktops. Asynchronous: the portal returns a
      request object and a `Response` signal with `file://` URIs; the result is converted and
      passed on exactly like the macOS `done` callback. Started in the SDL thread's glib main
      context so the SDL loop is never blocked.
   2. If the portal is not on the bus: `zenity --file-selection` or `kdialog --getopenfilename`,
      spawned without a shell, output read on a worker thread.
   3. If neither exists: `_norns.choose_file` is left unregistered. `lua/lib/fileselect.lua` already
      tests `if _norns.choose_file`, so norns' own browser (and drops on the window) keep working.
4. **Drops.** SDL `SDL_DROPFILE` (and `SDL_DROPTEXT` for `file://` lists) is enough on X11 and
   Wayland. The macOS-only "promised files / pasteboard audio" machinery has no Linux equivalent
   and is not ported. A Linux "copy instead of link" modifier is Shift held at drop time (Option on
   macOS), read with `SDL_GetModState()`.
5. Remaining small seams (no design question): `mac_menu_set_input` /
   `mac_menu_set_recording` become setters of the in-window menu state; `mac_set_app_name` and
   `mac_drop_adopt_windows` become no-ops on Linux.

Testing here: Xvfb + SDL can open the window, post synthetic SDL events (mouse, key, drop) and
read the frame; picker fallbacks can be tested with a stub `zenity` on `PATH`; the real portal
needs a desktop session (`HARDWARE-CHECKLIST.md`).

---

## 5. How the SDL window code is shared (needs your call)

`sdl_bridge.cc` is the entire window layer (all four windows, event routing, toasts, screenshots,
GIF, drops, layout). It has about a dozen macOS seams (checked by grep): `dispatch_semaphore`
(cross-thread request handoff), `removefile`, CoreMIDI keys (section 2), `mac_menu_*`,
`macos_hid_keyboard_event`, `macos_open_url`, two Mac-only SDL hints, `mac_option_held`.

| Option | Description | Verdict |
|---|---|---|
| A | Build the same `sdl_bridge.cc` on Linux; replace the seams with a small header `desktop_shell.h` (menu, picker, open_url, keyboard-as-hid, MIDI keys, option-key) implemented by `platform/macos/` (wrapping what is there now) and `platform/linux/`. `dispatch_semaphore` → `std::mutex`/`condition_variable` under `#ifndef __APPLE__` | **Recommended** |
| B | Copy `sdl_bridge.cc` into `platform/linux/` and edit | Fast, but two 2300-line files drift apart; every later fix is done twice |
| C | Split `sdl_bridge.cc` into portable window logic and platform glue first | Cleanest, but a large refactor of shared code; macOS cannot be tested here |

I recommend A: the shared file changes only at the seams, behind `#ifdef __APPLE__`, and the macOS
path stays literally what it is. CLAUDE.md lists "large refactors of shared code" as a decision;
A is not large, but it touches the file macOS depends on most, so I am asking rather than doing.
The main-thread model (`sdl_bridge_run()` on the main thread, matron on another thread) is kept on
Linux too: it is harmless on X11/Wayland and keeps one code path; `norns/main.cpp` gets
`#if defined(__APPLE__) || defined(NORNS_LINUX_DESKTOP)`.

Also in Phase 2, without design questions: the window keyboard as "hid keyboard" for
`lua/core/keyboard.lua` (Linux: a virtual evdev-style device `sdl:keyboard` fed from the window,
as `device_hid_iohid.cc` does on macOS); stubs for gpio keys/encoders, battery, i2c (already done
in Phase 1 via `hardware_null.cc`); screenshots/GIF to `$XDG_PICTURES_DIR` (falls back to
`~/Pictures`, then dust), with the filename pattern kept; proper quit handling (SDL is told not to
install signal handlers, as the macOS bridge already does at `sdl_bridge.cc:2036`).

## 6. Order of work and checks

1. libmonome patch + `c:vgrid` green (smallest, unblocks the grid).
2. `dust_import` portable copy + tests (`c:dust_import` green).
3. Window: build `sdl_bridge.cc` on Linux behind `desktop_shell.h`; render the device skin under
   Xvfb and compare a screenshot PNG; synthetic input events.
4. In-window menu, picker chain, open folders, screenshot/GIF.
5. "norns keys" (A) and the keyboard-as-hid device; B afterwards.
Each step ends with `linux/tests/run_all.sh` and a commit; `docs/port/HARDWARE-CHECKLIST.md`
collects what cannot be run here (Wayland, real portal, `aconnect`, ALSA sequencer).

## 7. Decisions I need from you

1. libmonome: carry a small patch (A), or the OSC route (C)?
2. "norns keys": internal device only first (A), or also the ALSA sequencer port (B) in the first
   Linux release?
3. `sdl_bridge.cc` sharing: A (seams behind `desktop_shell.h`), B (copy) or C (split first)?
4. In-window menu instead of a menu bar: OK? Is the dust link folder name `mac` acceptable on Linux
   for now?

---

# Shared source files changed in Phase 1 (re-verify macOS)

Phase 1 commits: `752abbc`, `e4d1216` (the rest are docs). Show the exact changes with
`git diff be64219 19286ee -- <file>`. All paths are relative to the repository root.
None of these is under `matron/src/platform/macos/` or `macos/` (nothing macOS-specific was
touched), but each is compiled or used by the macOS build.

| File | Change | Why it is neutral for macOS | What to check |
|---|---|---|---|
| `wscript` | `glib-2.0` checked with `check_cfg` inside the existing **non-macOS** branch | macOS path (`configure_macos`) untouched | `macos/build.sh` configures |
| `norns/wscript` | `import platform`; `-mfpu=neon` only on `arm*`/`aarch*`; **new** non-macOS, desktop, non-arm branch swapping `battery.cc`/`i2c.cc`/`ssd1322.cc` for `hardware_null.cc`; `GLIB-2.0` appended to `matron_use` and to the macOS `linux_only` filter list | `norns_cxxflags` is overwritten in the macOS branch (as before); the new branch needs `not NORNS_MACOS`; glib is filtered out for macOS like the other Linux libraries | `waf build` links the same sources as before; `build/norns/Verdandi` builds; diff of the link line (no `-lglib`) |
| `matron/src/hardware/screen/ssd1322.h` | `arm_neon.h` include guarded by `__ARM_NEON` / `__aarch64__` | Apple Silicon defines `__ARM_NEON` and `__aarch64__`, so the include still happens; the header declares nothing NEON-specific | `hardware_null.cc` and `weaver.cc` still compile |
| `matron/src/hardware/screen/sdl.cc` | `screen_sdl_ops` nested designated initializers `.io_ops.name = …` → `.io_ops = { .name = … }` | Same initialization; valid in clang and gcc (the old form is a clang extension) | norns window opens, `screen:sdl` registered |
| `matron/src/hardware/input/sdl.cc` | same change for `input_sdl_ops` | same | `input:sdl` still registers if configured |
| `crone/src/BufDiskWorker.h` | `#include <string>` | pure include | crone builds |
| `maiden-repl/src/page.c`, `maiden-repl/src/pages.c` | `wprintw(p->pad, "%s", txt)` and `mvwprintw(…, "%s", …)` instead of passing the text as the format string | same output (and fixes format injection) | `maiden-repl` builds (if built on macOS) |
| `tests/matron/clocks/clock_internal/test_clock_internal.cpp` | declaration `uint64_t` instead of `unsigned long long`, `#include <cstdint>` | On macOS `uint64_t` **is** `unsigned long long`: identical symbol | `waf test` (clock_internal) |
| `tests/matron/clocks/clock_scheduler/test_clock_scheduler.cpp` | `#include <cstdlib>` | pure include | `waf test` (clock_scheduler) |

Suggested macOS re-verification, in this order (from `readme-macos.md`):
1. `macos/build.sh` (whole tree builds, including the app target).
2. The macOS-independent tests listed there: `window_keys_test.c`, `device_skin_test.c`,
   `vgrid_test.c`, `dust_import_test.c`, `gif_test.c`, and the lua tests
   (`menu_pages`, `input_modes`, `fileselect_finder`, `output_fader`, `keyboard_hardware`,
   `virtual_home`).
3. `waf test` (the 16 upstream unit tests; 16/16 pass on Linux).
4. One manual start: `macos/norns.sh`, window opens, a script loads.
No source under `platform/macos/` or `macos/` changed in Phase 1, so the macOS-specific tests
(`drop_test.m`, `app_input_test.m`, `auval`) are unaffected by it.

The `linux/` folder (scripts, tests) and `docs/port/*` are new and do not touch macOS.


---

# Phase 2: changes to shared files (running list, for macOS re-verification)

Step 1 (libmonome): no repository source other than `matron/src/platform/macos/vgrid_device.c`
(`#define _GNU_SOURCE` guarded; a no-op on macOS).

Step 2 (dust_import): `matron/src/platform/macos/dust_import.c` (the `copyfile` code is unchanged
under `__APPLE__`; `dust_import_volatile` returns the same result on macOS, the extra folders are
`#ifndef __APPLE__`), `macos/tests/dust_import_test.c` (new cases, all valid on macOS too).

Step 3 (window), all behind `NORNS_SDL_BRIDGE` (= `__APPLE__` or `NORNS_LINUX_DESKTOP`), so macOS
sees the same code paths:
- `matron/src/platform/macos/sdl_bridge.cc`: includes; `dispatch_semaphore` moved into four tiny
  helpers (macOS keeps `dispatch_semaphore`); `mac_*`/`MAC_*` names replaced by `shell_*`/`SHELL_*`,
  which are macros for the same functions on macOS (`platform/common/desktop_shell.h`);
  `removefile` and the CoreMIDI keys code moved into small helper functions (`remove_taken`,
  `keys_send`, `keys_backend_open/close`, `keys_is_open`) with the original code under
  `#ifdef __APPLE__`; `ON_DEVICE_THREAD` macro around the two `device_runloop_sync` blocks; Linux
  folder for screenshots; `where()` also knows "Pictures".
- `matron/src/platform/macos/open_url.c`: `xdg-open` branch under `#else`.
- `norns/main.cpp`: the main-thread window loop is `#ifdef NORNS_SDL_BRIDGE` instead of `__APPLE__`.
- `matron/src/weaver.cc`, `matron/src/hardware/screen/sdl.cc`: `__APPLE__` -> `NORNS_SDL_BRIDGE`;
  `app_input` and `monitor_out` stay macOS-only.
- `matron/src/system_cmd.cc`: a third branch for Linux desktop; macOS and Pi branches unchanged.
- `matron/src/device/device_hid.cc`, `device_monitor.cc`: `NORNS_LINUX_DESKTOP` branches only.
- `norns/wscript`: Linux desktop source list; per-target define `NORNS_LINUX_DESKTOP`.
- new: `matron/src/platform/common/{desktop_platform,desktop_shell}.h`.
What to check on macOS: the build; `macos/norns.sh` window, menu bar, drop, virtual grid/arc/keys,
a screenshot, a GIF; `window_keys`, `device_skin`, `vgrid`, `dust_import`, `gif` tests.
