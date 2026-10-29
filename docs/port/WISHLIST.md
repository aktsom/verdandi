# The owner's changes (after the Linux baseline)

Nothing here is implemented unless the owner says so. The Linux baseline (matching macOS behavior) comes first.

1. **Virtual arc**: the virtual arc must work in the Linux version. (Linux baseline status: works for LEDs, wheel and push; left-drag untested, see the hardware checklist.)
2. **External clock**: norns' clock must be able to follow an external or DAW clock, universally across Linux, Windows and macOS. The DAW the owner tests with is Reaper. Decided (`docs/port/clock-notes.md`):
   - **MIDI clock is the primary path.** Linux: JACK MIDI input in the baseline (Phase 3), ALSA sequencer input later; Windows: with the MIDI backend (Phase 6); macOS: works today.
   - `clock_midi` gets **SPP and MIDI continue**, with tests; continue must not reset the beat counter (Phase 3).
   - Ableton Link is secondary (already works on Linux; Reaper needs the ReaBlink extension).
   - **Plugin transport** (tempo/position/play state through the plugin bridge, AUv3 and VST3) is designed into Phase 7; a Linux VST3 is wanted in principle, decided at Gate E.

- params should be midi mappable

- font should be as close to original monome norns as possible

- **Screenshot** (decided: no change): the OLED-only screenshot (Ctrl+Shift+S, the screen at four times its size) stays as it is. A full-window screenshot is not wanted.

- **Tempo page refresh** (decided: not now): with an external clock the tempo on PARAMS > CLOCK only refreshes when the cursor
  moves. That is upstream norns behavior (`docs/port/KNOWN-ISSUES.md` item 5). If wanted later: a `refresh` function for the
  params page, or a redraw after the silent `params:set("clock_tempo", ...)` when the value changed and the page is open.

## Interface ideas (rough, to be discussed before any work)

Nothing here is designed or scheduled; each entry is a first note only.

1. **Window proportions** (idea, not designed): the OLED screen looks too small compared to the box. Make it larger relative to the box, and proportion
   and align the keys (K1 to K3) and the encoders (E1 to E3) so that they fit the screen and the box.
2. **No text labels on the keys and encoders** (idea, not designed): remove the labels next to the keys and encoders (K1 to K3, E1 to E3) for now.
3. **User-editable colors with named presets** (idea, not designed): colors can be edited, and a set of colors can be saved, loaded and deleted under a name
   (a preset). The colors cover the box and the other elements: knobs, screen levels, lit buttons, and the grid and arc windows. Presets are stored as files
   in the norns home folder, not in the repository. Some default presets will be decided later.
4. **MIDI control of the on-screen controls** (idea, not designed): MIDI control of the on-screen keys, encoders, OUT fader and MUTE button. Before designing,
   check how this relates to PARAMS > MAP and the `.pmap` files, which map a script's own parameters (these controls belong to the window, not to a script).
5. **Snap the screen window to the nearest whole scale** (decided by the owner, not built now): a hidden helper that jumps the detached screen window to the
   nearest whole multiple of 128 x 64 (for example 8x: a 1024 x 512 picture in a 1112 x 587 window with its margin) so that every screen pixel is a flat square. **It stays hidden when it is built later:
   the shortcut key is F12 (pressed in the screen window) plus one item in the in-window right-click menu, and nothing visible on the screen window itself.**
   F12 is not used by this port, and no script in the owner's `dust/code` was found to use it: **this was not checked here** (his scripts are on his laptop);
   `verdandi scan-fkeys` lists any script that names F9, F11 or F12, and its output on his laptop settles it (`docs/port/detach-plan.md` section 10).
