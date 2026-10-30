# Picture of docs/port/midi-map-plan.md

| file | what it is |
|---|---|
| `midi-map-learn-standin.png` | **STAND-IN.** The MIDI MAP page does not exist yet. The real window and box (pixel style, DARK look, headless: Xvfb, dummy jackd) with the screen drawn by a throw-away function through the **real screen API and font**; the rows, wording and learn banner are the proposal. The knob E2 in the window is not ringed here: the ring is part of the proposal (plan section 2.5) and is not drawn |
| `standin_page.lua`, `standin_draw.lua` | what made it: `linux/tests/norns_probe.sh docs/port/midi-map-previews/standin_page.lua` (not part of the product or of `run_all.sh`) |
| `midimap-learn-real.png` | **a capture of the real window** of the real norns built from this code (headless: Xvfb, dummy jackd; `linux/tests/run_all.sh`, `midimap_scenario`, `probe_midimap.lua`): SYSTEM > MIDI MAP after K3 on LEARN and a click on E2 in the window: the inverted banner `LEARN E2`, the target row `MOVE A KNOB`, the seconds left, and the toast beside E1. (The blinking light on E2 is off in this frame.) |
