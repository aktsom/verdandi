# norns on macOS

community port of norns to macOS (Apple Silicon). not affiliated with monome.
scripts from the norns catalog are meant to run unchanged: all compatibility lives here.

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

mouse: the left / middle / right third of the window is K1+E1 / K2+E2 / K3+E3; click =
key, scroll = encoder.

the key mapping is plain C (`matron/src/platform/macos/window_keys.c`) with scenario tests:
`cc -std=c11 -I matron/src/platform/macos macos/tests/window_keys_test.c matron/src/platform/macos/window_keys.c -o /tmp/wkt && /tmp/wkt`

## what is different from the device

see `matron/src/platform/macos/` and `macos/`:

- devices: CoreMIDI (midi, plus a virtual "norns" port), IOKit (grid, arc, crow, serial),
  IOHIDManager (gamepads, joysticks), the window keyboard as hid keyboard; all translated
  to the linux device model and evdev codes the lua libraries expect
- the cocoa main thread owns the window; matron runs on its own thread
- no pi hardware: oled, gpio keys/encoders, battery, i2c are stubbed; stat via mach
- GNU coreutils/findutils/sed/grep are first on norns' PATH, as scripts expect GNU tools
- lua is built as C (C modules from scripts need the C symbols)
