# Picture of docs/port/arc-plan.md

| file | what it is |
|---|---|
| `arc-watch-standin.png` | **STAND-IN.** The WATCH view of MIDI MAP does not exist yet. The real window and box (pixel style, DARK look, headless: Xvfb, dummy jackd) with the screen drawn by a throw-away function through the **real screen API and font**; the rows and wording are the proposal (the numbers are an example of a Beatstep-style offset-binary encoder: 65 up, 63 down) |
| `standin_page.lua`, `standin_draw.lua` | what made it: `linux/tests/norns_probe.sh docs/port/arc-previews/standin_page.lua` (not part of the product or of `run_all.sh`) |
| `arc-watch-real.png` | **a capture of the real window** of the real norns built from this code (headless: Xvfb, dummy jackd; `run_all.sh`, `arc_scenario`, `probe_arc.lua`): SYSTEM > MIDI MAP > WATCH after a JACK MIDI client played 65 63 65 63 65 65 on CC 76: the source (here the JACK input; a unit behind the mio would read MIO), the last six values and the verdict LOOKS LIKE REL OFS |
