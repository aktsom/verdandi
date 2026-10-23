# Ken's changes (after the Linux baseline)

Nothing here is implemented unless Ken says so. The Linux baseline (matching macOS behavior) comes first.

1. **Virtual arc**: the virtual arc must work in the Linux version. (Linux baseline status: works for LEDs, wheel and push; left-drag untested, see the hardware checklist.)
2. **External clock**: norns' clock must be able to follow an external or DAW clock, universally across Linux, Windows and macOS. The DAW Ken tests with is Reaper. Decided (`docs/port/clock-notes.md`):
   - **MIDI clock is the primary path.** Linux: JACK MIDI input in the baseline (Phase 3), ALSA sequencer input later; Windows: with the MIDI backend (Phase 6); macOS: works today.
   - `clock_midi` gets **SPP and MIDI continue**, with tests; continue must not reset the beat counter (Phase 3).
   - Ableton Link is secondary (already works on Linux; Reaper needs the ReaBlink extension).
   - **Plugin transport** (tempo/position/play state through the plugin bridge, AUv3 and VST3) is designed into Phase 7; a Linux VST3 is wanted in principle, decided at Gate E.

- params should be midi mappable

- font should be as close to original monome norns as possible

- **Full-window screenshot**: an option to save the whole norns window (device skin, knobs, buttons) as a picture.
  Ctrl+Shift+S currently saves only the OLED, four times its size.
