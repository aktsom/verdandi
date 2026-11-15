# Phase M14 (Windows 0.10.5): the virtual arc, three follow-ups

Approach note, written before the code, then what was built and measured. The owner tested the virtual arc of 0.10.4 and it works. Three requests: (1) turn a ring by dragging up and down, (2) the small trail after fast turns of a mapped encoder, (3) a plain explanation of GAIN, ONE TURN and ACCEL.

## 1. Up and down drag

**What it does.** Hold the left button over a ring and move the pointer **up**: the ring turns **clockwise**; **down**: counter-clockwise. The distance decides how far. Shift = a quarter, Ctrl = four times (Windows; on Linux the "four times" key stays the Super key, as for the wheel). The wheel, the right button or Ctrl + left click (push button), the keys 5 6 / T Y / G H / B N and MIDI-mapped encoders are not touched. Only the vertical movement counts; sideways movement does nothing.

**The number chosen: 12 ticks for each pixel of height (at 1:1 size), `ARC_UD_TICKS_PER_UNIT` in `matron/src/platform/linux/arc_input.h`.**
- One lap of a real arc is 1024 ticks, so 1024 / 12 = **85.3 pixels**. The arc window is 260 pixels high (830 x 260 at 1:1), so a lap is **33 percent of the height**: a third, as asked.
- The unit is the window's own unit, not a screen pixel: the picture scales with the window (and with 125/150 percent display scaling), and so does the drag, so a bigger window is not touchier. At 200 percent scaling 170 device pixels are the same 85 units.
- With Shift one pixel is 3 ticks (a lap in 341 pixels, finer than one LED, which is 16 ticks); with Ctrl one pixel is 48 ticks (a lap in 21 pixels).
- Fractions of a tick are kept per ring, as for the wheel, so slow movement is never lost (whole ticks only go to the script).
- The old round-the-ring gear (a full turn of the pointer = 256 ticks) is unchanged.

**Capture and the window.** The mouse is captured (`SDL_CaptureMouse`) when the left button goes down on a ring and let go when it is released, so the movement and the release keep coming when the pointer leaves the ring, the window or the screen edge: the drag counts the pointer's position relative to the window, also outside it (tested: 50 pixels above the window, 2400 ticks for 200 pixels). If the release never arrives (the system took the mouse away) the first motion without the left button held ends the drag. The window does not move: the arc, grid and keys windows use the system's title bar only; there is no hit-test that turns a drag in the body into a window move (that exists only in the detached screen window, `screen_window.cc`, and only for its borderless mode). Checked in the real program: the window's geometry is the same before and after the drags.

**The setting.** MIDI MAP page, a new row **ARC DRAG** right after ARC KEYS (the two arc settings next to each other, the page's list scrolls as before). K3 toggles, E3 right = UP/DOWN, left = CIRCLE. Saved between runs in `midimap.conf` as `arc_drag=updown` or `arc_drag=circle`, and sent to the window at load and at every change (`_norns.arc_drag_config`). Defaults when nothing is saved (also for an old `midimap.conf` without the line): **Windows UP/DOWN, Linux CIRCLE**. The Linux default is unchanged; the shared code made that possible without a question: the default is one function in `midimap_settings.lua` that looks at `NORNS_PLATFORM`. Linux has the setting too (UP/DOWN can be chosen there). The preset files do not carry it (like ARC KEYS: a window setting, not a controller's).

**macOS** is unchanged: the new code is behind `NORNS_LINUX_DESKTOP` (Linux and Windows) and the Mac drag stays round the ring.

One small shared change: a motion without the left button held now ends a drag (see above). It only matters if a release was lost; the normal drag is unchanged.

**Tests.**
- C `linux/tests/arc_input_test.c` (in `run_all.sh`): direction (up positive, down negative, the same size), size (one pixel 12 ticks, 85 px 1020, 86 px 1032, a lap = a third of 260), Shift (a quarter), Ctrl/Super (four times), 200 percent scaling, the same distance in one jump or 86 steps, the pointer outside the window (negative y, far below) followed, no move = no ticks, up 40 and down 40 = 0, no division by zero. Checked against mutations (wrong number, wrong sign): 11 failures.
- Lua: settings (`midimap_settings_test.lua`: default Windows UP/DOWN, Linux CIRCLE, round trip, damaged value, old file), layer (`midimap_layer_test.lua`: the window is told 1 or 0 at load and at each change), page (`midimap_page_test.lua`: row 17, K3 and E3). The rows after ARC KEYS moved down by one (MIDI ACTIONS 18, SAVE AS 19, DELETE 20); the tests' row numbers were moved with them, no check was removed.
- **Shift in the real window is not checked with real keys here:** an `xdotool` Shift held during a drag reached SDL only part of the way through in about one run in seven (the modifier flickered under Xvfb), so such a check would be a coin toss and was left out. Shift is covered by the C numbers and, in the real program, by the Windows CI hook (`SDL_SetModState`); the real key is on the owner's checklist.
- In the real program on Linux (Xvfb, real mouse events from `xdotool`, `linux/tests/probe_arc_drag.lua`, scenario `window:arc drag with real mouse events` in `run_all.sh`; passes): circle quarter turn 62 ticks (default on Linux); UP/DOWN: 86 px up = 1032 (43 messages of 24, every one clockwise), 86 px down = -1032, 200 px up leaving the window = 2400, nothing turns after the release, ring 3 only turns ring 3 (-240), right button = key down/up and no delta, wheel notch = 2, the window's position and size unchanged, `arc_drag=` in the file.
- In the real norns.exe on Windows (CI, `windows/ci/maiden_probe.py` VERDANDI_PROBE=arc, new hook cases 5, 6, 7 of `_norns.arc_test`, same functions the mouse events call): ring 1 up 86 + up 200 (leaving the window) = 3432, ring 2 down 86 = -1032, ring 3 Shift = 258, ring 4 Ctrl = 960, and the program logs for each drag "held and capture asked until the release: yes, after the release: capture off drag off" (`smoke-m1.sh` chk_arc counts five). **Not run here** (no Windows): it is written and syntax-checked (the hook code compiles with `-DNORNS_WINDOWS`), the first CI run is its first run.
- **Not testable without the owner's PC:** a real mouse on Windows, whether the mouse capture (SDL on Windows) holds when the pointer goes off the screen's edge, Ctrl as the faster key with the real keyboard, scaling at 125/150 percent.

## 2. The lag after fast turns in the arc window

**Does the arc window have the 0.10.2 fix? No.** Read in `sdl_bridge.cc`: `arc_turn` added the angle and then called `arc_redraw()` (a full draw of the window) for every tick, and a mapped encoder's turns arrive as one event each (`SDL_BRIDGE_SHOW_ARC_TURN`). `phase-m11.md` said it itself: "Not changed: the keys, the arc and grid windows". So the same pile-up as the knobs had: the events wait in SDL's queue, one full draw each, the ring goes on after the hand stops.

**Measured first, old way** (the real program, headless on Xvfb, a draw is cheaper than on a real screen; `linux/tests/probe_arc_lag.lua`; the window logs one line per burst: `arc display: ...`; `VERDANDI_ARC_THROTTLE=0` is the old way):

| burst | old way: draws, slowest draw | the last draw ended after the last turn was sent | new way: draws | the last draw ended after the last turn |
|---|---|---|---|---|
| 4000 turns in a tight loop | 4000, 43 ms | **33 019 ms** | 2 | **31 ms** |
| 3000 turns, one a millisecond (about 650 a second: a fast hand) | 3000, 38 ms | **22 170 ms** | 104 | **29 ms** |

**Fix, the same as for the knobs** (`redraw_throttle.h`, a second `rt_state` for the arc): the drawn knob (`arc_turns`) is added at once, the whole ticks go to the script at once, and the window is drawn at most every 16 ms, counted from the end of the last draw; turns and LED changes that come while a draw is not due wait in the counters and one timer draws them: the last turn always gets its draw. The LED changes from the script (`arc_changed`) go the same way. The ring therefore always matches the value (nothing is skipped or smoothed: a draw shows the state at that moment) and it stops when the input stops (the last draw is at most one gap plus one draw after the last turn). Pushes, learn blinking and opening/closing still draw at once.

**Test:** `window:arc window after fast mapped turns` in `run_all.sh` runs 1500 turns both ways in the real window and requires: old way at least 1500 draws and the last draw more than a second after the last turn (so the test can see the trail), new way fewer than 150 draws and the last draw within 100 ms. The shared `redraw_throttle_test.c` covers the timing rule itself. macOS: unchanged (behind `NORNS_LINUX_DESKTOP`).

## 3. GAIN, ONE TURN, ACCEL: what they do (for the owner)

See the report of this phase (STATUS.md has the short form). Numbers come from `lua/core/midimap_value.lua`, `arc_step` and `gain_from_turn`, and were run with the real functions.

- **GAIN** = how many ticks of the ring one unit from your encoder is worth. Whole numbers 1 to 64, default 8. The ring has 1024 ticks for one full turn (64 LEDs of 16 ticks), so one full turn of the ring needs 1024 / GAIN units: gain 8 = 128 units, gain 4 = 256 units, gain 1 = 1024, gain 64 = 16. A "unit" is one step of a relative encoder (REL formats: 1 for a nudge, 2 or 3 if the encoder bundles fast turning), or one value of change for an absolute knob (ABS). 
- **ONE TURN** (K3 on that row of the encoder's page): you turn the knob exactly once round and press K3. The page counts the units of the messages that arrive (shown as UNITS; the ring does not move meanwhile; direction does not matter; ACCEL is not applied). At K3 it sets GAIN = 1024 / units, rounded to a whole number and kept between 1 and 64, and says "GAIN n". K2 cancels. Your gain 4 means the encoder gave between 228 and 292 units for your turn (about 256). Because GAIN is a whole number the match is not exact: with 256 units it is exact; with 300 units (1024/300 = 3.41) it becomes 3 and a turn of the knob is 1.17 turns of the ring.
- **ACCEL**: OFF is linear. LOW and HIGH multiply the ticks of every message by two things: (a) by `1 + a x (units - 1)` with a = 0.25 (LOW) or 0.5 (HIGH), where units is the size of that one message (always counted as positive); (b) by 2, 3 or 4 if the previous message came less than 20, 10 or 5 ms before (the same thresholds as norns's own encoder acceleration; both LOW and HIGH use the same ones).
- **Why LOW and HIGH feel the same:** the factor (a) is 1 whatever `a` is when a message is worth 1 unit, and an endless encoder usually sends 1 per click. Then LOW and HIGH differ in nothing at all; only (b) works, and it is identical. They differ only when single messages are worth 2 or more (an encoder that bundles fast turning). Table, gain 4, 100 messages, same speed:

| each message is | gap | OFF | LOW | HIGH |
|---|---|---|---|---|
| 1 unit | 100 ms (slow) | 400 | 400 | 400 |
| 1 unit | 15 ms | 400 | 796 | 796 |
| 1 unit | 3 ms | 400 | 1588 | 1588 |
| 3 units | 100 ms | 1200 | 1800 | 2400 |
| 3 units | 3 ms | 1200 | 7146 | 9528 |
| 10 units | 100 ms | 4000 | 13000 | 22000 |

- **Which settings decide how far a ring turns:** the FORMAT (MODE: what a message means in units, and which messages count; ABS counts the change of value), the size of each message, **GAIN**, **ACCEL** (and the time between messages), the device and channel it listens to (a message from elsewhere does nothing); and the **ARC DRAG, wheel, keys** are separate inputs on the same ring and add to it. The ring's own size is fixed at 1024 ticks a turn; whether a *script* turns that into a value is up to the script.
- **Proposal, not built:** make the two choices different by what they change, e.g. LOW = at most 2x, only for messages less than 20 ms apart; HIGH = 2x, 4x, 8x at 20/10/5 ms; and drop the "units" factor (or keep it only for HIGH). Then LOW is a gentle help and HIGH is a clear boost, also for an encoder that sends 1 per click. The page could also show the maximum ("LOW 2X", "HIGH 8X"). Needs the owner's say.

## Windows CI result (run 80, commit 340f8c0)
67 checks passed, 0 failed, 1 skipped (the same skip as before). In the real norns.exe: ring 1 up 86 and up 200 points (leaving the window) = 3432, ring 2 down 86 = -1032, ring 3 with Shift = 258, ring 4 with Ctrl = 960, and all five drags logged "capture held until the release, off after it". The first run (commit f759edf) found one problem, which was in the test hook: the existing round-the-ring drag check ran with the new Windows default (up and down) and read -480 instead of 64; it now forces the circle way for its run (same numbers). The release `windows-latest` was updated to 0.10.5 / 340f8c0 by that run (zip 81 628 261 bytes, SHA-256 b9324c31f05b373f551e24e00028d94448996dc75a82e354d683e4d23e97c1b3).

## Not tested here
A real mouse and screen on Windows, DPI scaling, the mouse capture at the screen edge, a real MIDI encoder, the real cost of a draw on the owner's screen (the Xvfb numbers above are lower bounds for the old way's trail), the first Windows CI run of the new checks.
