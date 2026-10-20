# norns on macOS

community port of norns to macOS (Apple Silicon). not affiliated with monome.
scripts from the norns catalog are meant to run unchanged: all compatibility lives here.

users: get `norns.dmg` and read the manual (`macos/manual/manual.html`, also in the dmg).
this file is for building and changing the port.

## layout

the norns home is a folder with the same layout as `/home/we` on the device; norns runs
with `HOME` set to it, so the lua core, sclang and scripts find everything where they expect.

```
<norns home>/
  norns/                 this repository
  dust/code, audio, data scripts and their data
  matronrc.lua           written on first start (desktop screen)
  Library/Application Support/SuperCollider/   sclang config, sc3-plugins
```

## build

```
macos/setup-deps.sh                      # homebrew packages + lua 5.3, nng 1.x, libmonome,
                                         # SuperCollider (jack backend), sc3-plugins, waf 2.1
python3 <deps>/bin/waf configure         # darwin is detected; always a desktop build
python3 <deps>/bin/waf
```

## app, dmg, AUv3

```
macos/make-app.sh --dmg      # dist/norns.dmg: norns.app (+ AUv3) and the manual
```

the app bundles everything (jackd, SuperCollider, sc3-plugins, GNU tools, maiden, all
dylibs rewritten to @rpath, see `macos/bundle_dylibs.py`) and is ad-hoc signed. its
launcher (`macos/app-launcher.sh`) uses `~/norns` as the norns home.

the AUv3 (`macos/auv3/`, type `aumf`, subtype `nrns`, manufacturer `Nrns`) is a sandboxed
extension inside the app. it sends the DAW's audio and MIDI over UDP on 127.0.0.1 to
`auv3_bridge`, a jack client next to norns that resamples between the two clocks (jack's
adapter) and takes over crone's main in/out while the plugin renders. check it with
`auval -v aumf nrns Nrns`.

## run

```
macos/norns.sh               # maiden: http://127.0.0.1:5000/maiden
macos/norns.sh --terminal    # matron's lua REPL and log in the terminal instead
```

starts jackd (coreaudio), norns (matron + crone + softcut), sclang and maiden. as on the
device, maiden is the editor, the REPLs (matron :5555, sclang :5556) and the script
catalog (install / update). unlike the device everything listens on 127.0.0.1 only:
the REPLs run arbitrary code, and a laptop is on networks a norns is not.

the window is the norns screen (resizable). controls:

| keys (window focused) | norns                                  |
|----------------------|----------------------------------------|
| 1 2 3                | K1 K2 K3 (held while held)             |
| Q / W                | E1 left / right                        |
| A / S                | E2 left / right (in scripts also ↑ / ↓) |
| Z / X                | E3 left / right (in scripts also ← / →) |
| ⇧ added              | 5 steps; holding a key keeps turning   |

this works wherever nothing else wants the keys: in the menu (arrows keep their menu
bindings, F1-F5 the menu pages) and in every script that does not use the keyboard itself.
text entry types as usual, and scripts with their own `keyboard.code` / `keyboard.char`
(14 of the 351 catalog scripts) get the keyboard; there:

| keys               | norns                                         |
|--------------------|-----------------------------------------------|
| ⌥ + the keys above | always K / E                                  |
| ⌥Esc               | force hardware keys on/off (title "norns · keys") |

the automatic part is `lua/core/keyboard.lua` (enabled by `NORNS_HARDWARE_KEYS=1`, which
`macos/norns.sh` sets; off on the device), tests: `NORNS_HARDWARE_KEYS=1 <lua 5.3>
macos/tests/keyboard_hardware_test.lua`.

mouse: the window draws the device (`matron/src/platform/macos/device_skin.c`, layout of
the standard norns). click a key; drag a knob (up/right = clockwise) or scroll over it; the
wheel elsewhere turns the nearest knob. keys and knobs show every key/enc event norns
receives (`sdl_bridge_show_control`, also called by the keyboard path in lua).

the key mapping is plain C (`matron/src/platform/macos/window_keys.c`) with scenario tests:
`cc -std=c11 -I matron/src/platform/macos macos/tests/window_keys_test.c matron/src/platform/macos/window_keys.c -o /tmp/wkt && /tmp/wkt`

## tests

```
cc -std=c11 -I matron/src/platform/macos macos/tests/window_keys_test.c \
   matron/src/platform/macos/window_keys.c -o /tmp/wkt && /tmp/wkt
cc -std=c11 -I matron/src/platform/macos $(pkg-config --cflags --libs cairo) \
   macos/tests/device_skin_test.c matron/src/platform/macos/device_skin.c -o /tmp/dst && /tmp/dst [png_dir]
NORNS_HARDWARE_KEYS=1 <lua 5.3> macos/tests/keyboard_hardware_test.lua
d=$(mktemp -d); HOME=$d <lua 5.3> macos/tests/virtual_home_test.lua lua/core/virtual_home.lua
macos/tests/norns_probe.sh <commands.lua>   # boot norns, drive its REPL, stop it
```

`macos/docs/` has the notes behind the port (linux inventory, catalog scan).

## what is different from the device

see `matron/src/platform/macos/` and `macos/`:

- devices: CoreMIDI (midi, plus a virtual "norns" port), IOKit (grid, arc, crow, serial),
  IOHIDManager (gamepads, joysticks), the window keyboard as hid keyboard; all translated
  to the linux device model and evdev codes the lua libraries expect
- the cocoa main thread owns the window; matron runs on its own thread
- no pi hardware: oled, gpio keys/encoders, battery, i2c are stubbed; stat via mach
- GNU coreutils/findutils/sed/grep are first on norns' PATH, as scripts expect GNU tools
- lua is built as C (C modules from scripts need the C symbols)
