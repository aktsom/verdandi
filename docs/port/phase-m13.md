# Phase M13 (Windows 0.10.4): the virtual arc

Approach note, written before the code. The owner wants the virtual arc of the Linux port on Windows, with the same look and controls. A virtual grid and virtual keys are not wanted now and stay switched off.

## 1. What the Linux virtual arc does (read from the code, `docs/port/arc-plan.md`, the manual)

- **How it is opened.** As its own window (titled "arc"), never a panel inside the norns window. The ARC button of the norns window, F8 from any window, the right-click menu entry "Virtual arc" (F8), a MIDI action (MIDI MAP > ACTIONS, ARC) and closing the window with its own close button all use one function (`toggle_arc` in `sdl_bridge.cc`). Opening it adds a device "monome arc virtual" to norns, closing it removes the device.
- **Size and place.** 830 x 260 points at 1:1 (four rings 190 apart), resizable (the picture scales, never smaller than a third). It is placed round the norns window (`extras_layout.c`): the norns window is never moved or resized; the arc goes below or beside it, on screen, clear of the other device windows.
- **Look.** A silver plate with four big aluminium knobs (knurled edge), each in a ring of **64 LEDs** (LED 1 at the top, clockwise). The LED levels 0 to 15 are drawn as brightness, the arc's intensity scales all of them. The knob itself turns when the ring is turned (1024 ticks = one turn of the knob); a pushed ring is drawn pressed. While MIDI MAP learns an arc encoder the ring being learned blinks.
- **Four rings.** `ARC_RINGS 4`.
- **Mouse.** Wheel over a ring: 2 ticks a notch (a trackpad scrolls in fractions; the fractions are carried, only whole ticks go out). Left drag round a ring: clockwise is up; a full turn of the pointer is 256 ticks (a quarter of the hardware's 1024, because a small knob under a mouse would be far touchier than the hardware under a hand); near the centre (under 8 units) the drag waits. Shift = a quarter as much, the GUI key (Super) = four times. Right button (or Ctrl + left button) = the ring's push button, held while the button is held.
- **Keys.** 5 and 6 = ring 1 left/right, T Y = ring 2, G H = ring 3, B N = ring 4. One press is 16 ticks (Shift 4), holding repeats (optionally speeding up: MIDI MAP > ARC KEYS ramp). Always in the arc window; in the norns window only while the arc is open, a script runs, no text entry is open and the script does not read the keyboard itself (the same rule as Q/W/A/S/Z/X); MIDI MAP > ARC KEYS can switch them off.
- **What scripts get.** The device is a real mext device for libmonome: `arc.connect()` finds it like a real arc, `a.delta(n, d)` gets the integers the window sent (1024 to a turn, small signed numbers), `a.key(n, z)` the pushes, `a:led`, `a:all`, `a:segment`, `a:refresh`, `a:intensity` draw on the 64 LEDs of each ring.
- **Saved between runs.** Only the MIDI MAP settings (`midimap.conf`: the encoders A1 to A4 with CC, device, channel, format, GAIN, ACCEL; ARC KEYS on/off and its ramp). Not saved: whether the arc window was open, its position or size.
- **With MIDI-mapped encoders.** A1 to A4 of MIDI MAP turn the **virtual** arc through `_norns.arc_turn(ring, ticks)`, which hands the turn to the window thread, which calls the same `arc_turn` the mouse uses: one path (one accumulator, one set of messages to norns, the knob in the window turns too). So a ring turned by the wheel and by a mapped encoder at the same time moves once for each, never twice. If the window is closed `arc_turn` returns false and the layer shows one toast; it never opens the window by itself. Learn by clicking a ring in the arc window (MIDI MAP armed).
- **With a real arc.** A real arc is its own device (its own vport). A mapped encoder only ever drives the virtual arc, a real arc is untouched, and its deltas reach its own port.

## 2. What Windows had before this phase

- The ARC button, F8 and the MIDI action called the shared `toggle_arc`, which called `vgrid_open_arc`: on Windows a stub that logged "the virtual arc: not yet" and returned NULL, so nothing opened (`docs/port/windows-gaps.md`).
- The right-click menu had no "Virtual grid / arc / keyboard" entries on Windows at all.
- GRID and KEYS: the same dead stubs (still so; the GRID and KEYS buttons do nothing but say so now).

## 3. What was built

The window, skin, hit test, wheel, drag, push, keys, learn-by-click, the blinking ring and the MIDI layer were already shared with Linux and compile on Windows. What was missing is the **device**: on Linux a pseudo terminal that libmonome opens like a USB arc. Windows has no ptys.

- **`matron/src/platform/windows/vgrid_device_win.c`**: the same interface as `vgrid_device.c`, with a **named pipe** `\\.\pipe\verdandi-arc-<process id>-m0000002` (`FILE_FLAG_FIRST_PIPE_INSTANCE`, no remote clients) and a thread that speaks the unchanged mext protocol of `vgrid_proto.c` (the handshake, LED messages, encoder and key messages). The virtual **grid** is not built: `vgrid_open` returns NULL with one log line.
- **`windows/libmonome/pipe-device.patch`** (on top of `serial-hook.patch`, applied when CI builds libmonome): libmonome opens a name that starts with `pipe\verdandi-` through the same `CreateFile` as a COM port but without baud rate and comm events; the wait for input looks at the pipe (`PeekNamedPipe`) and a read takes only what is there (a pipe has no read time limit, a COM port has one). Real COM ports are not touched (the code runs only for that name).
- **`grid_win.cc`**: the serial hook answers the pipe's serial (`m0000002`, the serial the Linux virtual arc has).
- **`platform/linux/arc_input.h`**: the wheel/drag/accumulator numbers moved out of `sdl_bridge.cc` into plain functions with a C test. The numbers are the same as before (Linux behaviour unchanged).
- **Menu and buttons.** The right-click menu has "Virtual arc F8" on Windows (no grid or keyboard entries). The GRID and KEYS buttons and F6/F7 say "VIRTUAL GRID: NOT ON WINDOWS YET" in a toast instead of doing nothing; a failed arc says "VIRTUAL ARC FAILED: SEE LOGS/NORNS.LOG".
- **Faster turning on Windows.** The GUI key is the Windows key, which opens the Start menu when it is let go: Ctrl is the "four times" key on Windows (a Ctrl-click is the push button, so a drag does not start with Ctrl held; Ctrl + wheel works).
- **Windowing, DPI, focus.** Unchanged shared code: the pane canvas follows the window's pixel size (`SDL_WINDOW_ALLOW_HIGHDPI`; `pane_pixels` converts points to pixels), SDL delivers the wheel to the window under the pointer, drags capture the mouse. These are the places where Windows could differ and they are on the owner's checklist.
- **Example script** `examples\arc_demo\arc_demo.lua` in the zip: four values, one per ring (turn changes it and the LEDs follow, a press resets it).

## 4. Tests

- Lua `linux/tests/arc_virtual_test.lua`: the ring and LED calls of `arc.lua` against a model of the device (1-based ring and LED, level clamp, relative, `all`, `segment` including wrap and fractions, refresh), deltas and keys arrive once, a wheel and a mapped turn on the same ring add up, a second (real) arc, remove and come back.
- C `linux/tests/arc_input_test.c`: wheel notch 2 ticks, flipped wheel, trackpad fractions, a full pointer turn 256 ticks (both directions, past the edge of the angle, two turns), Shift, Super, the carry keeps the sum exact.
- CI in the real norns.exe (`windows/ci/maiden_probe.py` VERDANDI_PROBE=arc, `smoke-m1.sh` `m13-check-arc`; hooks only with `VERDANDI_TEST_HOOKS=1`): the arc window is opened like its button does, a picture is saved with the LEDs off, a script (`windows/ci/arcprobe.lua`) draws on the rings and counts, a wheel notch, a drag round a ring, a ring press and release and mapped turns are sent through the functions the mouse events call, the script must have received exactly the numbers (52 on ring 1 = a notch + a mapped 50, about 64 on ring 2, key 3:1 and 3:0, 100 on ring 4), a second picture with the script's LEDs must differ from the first, the window is closed (the device goes) and opened again (it comes back on the same port). The pictures are in the run's output (`arc/arc_window_0.png`, `arc_window_1.png`).

## 5. Not tested without a real PC

The window on a real screen (looks, size, placement beside the norns window, 125/150 percent scaling), the real mouse wheel and trackpad feel, a drag with a real mouse, the Ctrl key, a real arc plugged in next to the virtual one, a MIDI controller mapped to A1 to A4, the arc keys with the Windows keyboard layouts. In CI the window is SDL's dummy video driver: the drawing code runs, a screen does not show it.
