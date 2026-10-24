# Phase 1: headless Linux build and boot (approach, written before code changes)

Gate A decided: option 1, platform folders in this fork (`matron/src/platform/linux/` later;
shared files stay in `platform/macos/` until a separate move commit once Linux works).

## Approach
1. `linux/setup-deps.sh` (Ubuntu 24.04, apt + libmonome 1.4.9 from source + waf 2.1.9 built from
   the GitLab tag, because the bundled waf 2.0.14 imports `imp`, removed in python 3.12, and
   waf.io is not reachable from the sandbox) and `linux/build.sh` (submodules, waf configure
   `--desktop`, build).
2. Build the unmodified upstream desktop path first; fix only what breaks, with the smallest
   change that keeps macOS and the Pi build unchanged (guards, not rewrites).
3. `linux/norns.sh` (headless boot: Xvfb, `jackd -d dummy`, crone, matron) and
   `linux/tests/norns_probe.sh` in the style of `macos/tests/norns_probe.sh`.
4. Run the tests that do not need macOS frameworks; record results and failures below.

Not in scope: SDL desktop layer, skins in the window, packaging (Phases 2-4).

## Results (2026-10-23, Ubuntu 24.04.5, x86_64, python 3.13 default, gcc 13)

Build: `linux/setup-deps.sh` then `linux/build.sh` give `build/norns/norns`. From a wiped
`build/` the second script takes about 20 s with the dependencies in place. Not run on a
truly fresh container: I re-ran both scripts here, and tested the waf-building step in a
separate directory, but not the libmonome step from scratch with the script itself (it ran
by hand with the same commands). A fresh-container run belongs in Phase 4.

Boot: `linux/tests/norns_probe.sh linux/tests/probe_boot.lua` starts Xvfb, jackd (dummy),
norns (matron + crone + softcut) and sclang, loads a script (`PolyPerc` engine), sends a key and
an encoder event and shuts everything down. Passes; crone is `/crone/ready`, engines
PolySub, SimplePassThru, PolyPerc, TestSine, None.

`linux/tests/run_all.sh` (28 s): 6 lua tests, window_keys, device_skin, waf unit tests (16 of
16), headless boot: pass. Two known failures (below). Skipped: `gif_test.c` (ImageIO),
`drop_test.m`, `app_input_test.m` (Objective-C).

### What had to change in upstream sources (all small, none changes macOS or the Pi)
| Where | Problem on Linux x86_64 / gcc 13 | Change |
|---|---|---|
| bundled `waf` 2.0.14 | needs python's removed `imp` (also on the system python 3.12) | waf 2.1.9, built from the GitLab tag by `linux/setup-deps.sh` (waf.io is not reachable from the sandbox) |
| `maiden-repl/src/page.c`, `pages.c` | `-Werror=format-security` | `"%s"` format |
| `norns/wscript` | `-mfpu=neon` rejected by x86 g++ | only on arm |
| `norns/wscript` | oled driver is arm NEON; no battery/i2c | on desktop x86: `platform/macos/hardware_null.cc` stubs replace `ssd1322.cc`, `battery.cc`, `i2c.cc` |
| `hardware/screen/ssd1322.h` | `#include <arm_neon.h>` | guarded by `__ARM_NEON` / `__aarch64__` |
| `hardware/screen/sdl.cc`, `input/sdl.cc` | `.io_ops.name = ...` nested designators are rejected by g++ | `.io_ops = { .name = ... }` |
| `crone/src/BufDiskWorker.h` | missing `#include <string>` | added |
| `wscript`, `norns/wscript` | `device_hid.cc` needs glib | `glib-2.0` found by pkg-config, used on Linux only |
| tests `test_clock_scheduler.cpp`, `test_clock_internal.cpp` | missing `<cstdlib>`; `unsigned long long` vs `uint64_t` link mismatch | include `<cstdlib>`; use `uint64_t` |

### Findings for later phases
1. **libmonome cannot open the virtual grid pty on Linux** (`vgrid_test.c`: 4 failures). On macOS
   it takes the serial from the path; on Linux `linux_libudev.c` asks udev for `ID_SERIAL_SHORT`
   and a pty has none. Phase 2 needs a libmonome patch (the same family as the macOS patch), a
   udev rule is not possible for a pty, or a different transport.
2. **`dust_import.c`** needs `copyfile(3)` (macOS); Phase 2.
3. **No `/dev/snd/seq` in this container**: `failed to open alsa virtual device` and
   `dev_list_add: error allocating device data` at boot. Matron continues. Phase 2's "norns keys"
   ALSA sequencer port cannot be tested here; goes to the hardware checklist.
4. `error loading keyboard layout, using old value: us` appears (also in the lua keyboard test); it
   needs `setxkbmap`/X data. Harmless here.
5. **SIGTERM does not stop norns**: SDL installs its own handler and nothing reads the quit
   event. `linux/norns.sh` sets `SDL_NO_SIGNAL_HANDLERS=1`. Phase 2's window code must handle
   quit properly.
6. **sclang as root** (containers) needs `QTWEBENGINE_DISABLE_SANDBOX=1` and
   `QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox`, and `QT_QPA_PLATFORM=offscreen`; `linux/norns.sh`
   sets them (the sandbox flags only when root).
7. Ubuntu's `liblua5.3-dev` (C build) works with matron; `pkg-config lua53` is found. The macOS-style
   `extern "C"` wrapper was not needed.
8. This build is the upstream `--desktop` window (`screen:sdl`), which the headless run drives
   under Xvfb; it is not yet the Verdandi window with device skin (Phase 2).
9. Unverified: that the macOS build still works after these edits (no macOS here). The changes
   are guarded or syntax-neutral, but the owner should run the macOS build and tests once
   (`docs/port/HARDWARE-CHECKLIST.md`).
10. Audio goes through jackd's dummy driver only; real devices are Phase 3.
