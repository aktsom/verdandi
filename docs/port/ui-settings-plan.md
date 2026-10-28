# SYSTEM > UI: screen brightness and screen colour (UI step 3: plan only, nothing is built)

Linux desktop build only. Written from the code of this repository; the pictures are a stand-in (the real window with the screen tinted by the mapping of section 2: `ui-previews/ui-colours.png`, `ui-previews/ui-brightness.png`; made by `ui-previews/make_ui_settings_previews.py`, the mapping itself is `ui-previews/ui_tint.py`).
**This plan replaces the "SCREEN" page of `ui-plan.md` section 2** (brightness and greys `device / bright / brighter`): the page is now called UI, its first two settings are brightness and colour, and **the grey table is not touched** (level n is grey 17 n; no gamma option in this step). The rest of section 2 (the chip's brightness/contrast/gamma do nothing on the desktop; where the colour mapping lives) still holds and is repeated below where it matters.

## 1. How it works upstream, and what the desktop build has to do

**Upstream and on the device.** The OLED is an SSD1322 and brightness is a property of the chip: `lua/core/screen.lua` reads `dust/data/system.display` (`brightness` 0-15, `contrast`, `gamma`) and on the first `screen.update()` calls `_norns.screen_brightness / screen_contrast / screen_gamma`; the page `lua/core/menu/display.lua` (SYSTEM > SETTINGS > DISPLAY) edits them with E3 and saves on every change. **There is no colour setting upstream**: the OLED's colour is the panel's (white, or yellow on the yellow panels), the software only knows 16 grey levels. On this desktop build those calls end in `hardware_null.cc` and do nothing, and `lua/core/menu/system.lua` hides SETTINGS on a computer.

**The screen path on the desktop** (all in `matron/src/platform/macos/sdl_bridge.cc`, compiled by the Mac and the Linux build):
1. the screen backend draws the 128 x 64 image in grey (level n = 17 n; text edges are anti-aliased greys in between); `present()` copies it into the cairo surface `oled` (RGB24, grey);
2. `draw_oled()` -> `skin_draw_oled()` (`device_skin.c`) draws `oled` in the window (nearest at whole multiples, enlarge + best filter in between, step 2b);
3. `save_screenshot()` (right-click menu) paints `oled` 4x with nearest and writes a PNG;
4. `gif_add_frame()` / `oled_levels()` keep **16-level frames** (max channel of `oled` rescaled to 0-15); `gif_writer.c` writes a fixed grey palette `i * 17`.
   (`_norns.screen_export_png`, used by scripts and by my tests, is written by the screen backend itself from the raw grey image, not by the bridge.)

**What has to do the work**
- **Colour mapping, one place in the bridge.** `oled` stays the raw grey image. A second surface `oled_view` (128 x 64 RGB24) is made from it through three 256-entry tables (R, G, B) in `present()` and whenever the setting changes; `draw_oled` and `save_screenshot` read `oled_view`. At white and brightness 1 the tables are the identity and `oled` is used directly (zero cost, bit-identical to today). The in-window menu, toasts and the bezel are not tinted (they are the program's, not the screen's).
- **GIF.** Frames keep the **raw levels** (`oled_levels()` unchanged); the palette becomes the 16 mapped colours (`gif_begin_palette(g, f, w, h, scale, rgb[16][3])`, new; the old `gif_begin` stays and writes the grey palette, so the Mac call is unchanged). Frames then match the window for the 16 levels; the in-between greys of anti-aliased edges are quantised to a level, as in every GIF today (the screenshot has the exact value). A setting changed during a recording: the palette of the moment the GIF is encoded is used (accepted, noted).
- **Screenshot** = the window's screen pixel for pixel, scaled 4x. `screen.export_png` (a script's own call) stays raw grey: it is the device's image, a test and script API; the tint is a property of the display. (Say if you want it tinted too.)
- **Lua: the page and the file.** One new module `lua/core/ui_settings.lua` owns the settings (defaults, parse, validate, load, save, apply); the page `lua/core/menu/ui.lua` is the screen of it. Registered like AUDIO: `m["UI"] = require 'core/menu/ui'` in `lua/core/menu.lua`, and `lua/core/menu/system.lua`'s computer list (inside the existing `NORNS_PLATFORM` block, the device's list untouched) becomes `DEVICES, AUDIO, UI, MODS, RESET, RESTART` with `pages` to match.
- **One new C function**, `_norns.ui_look(brightness, r, g, b)` (`weaver.cc`, registered under `#ifdef NORNS_LINUX_DESKTOP` next to `audio_status` and `set_warning`) -> `sdl_bridge_set_screen_look()` (like `sdl_bridge_set_warning`: posts a device event to the SDL main thread, which rebuilds the three tables, remakes `oled_view` and redraws the screen). Nothing else in C knows about settings: Lua parses, validates and decides; C only gets four numbers.
- **Where it is saved and loaded.** `ui.conf` in the norns home (Lua sees it as `/home/we/ui.conf`, the virtual home maps it, exactly like `audio.conf`). Written on every change (to `ui.conf.tmp`, then renamed: a crash never leaves half a file). Loaded and applied once at start by `ui_settings.load_and_apply()`, called from `lua/core/menu.lua` where the pages are registered (guarded by `_norns.ui_look ~= nil`, which exists only on the Linux desktop). `RESET` does not delete it (it does not delete `audio.conf` either: a look is not "system state").

**How AUDIO is built, and the UI page follows it.** A page is a table `m` with `init`, `deinit`, `key(n,z)`, `enc(n,delta)`, `redraw()`; `m.pos` is the selected row (E2), E3 changes the value, K2 goes back (`_menu.set_page("SYSTEM")`), rows are drawn by `screen.level(i == m.pos and 15 or 4); screen.move(0, 10*i); screen.text(NAME)` with the value `screen.move(127, 10*i); screen.text_right(value)`; the file is `key=value` lines read with `line:match("^([%w_]+)=(.*)$")`, unknown lines kept or ignored. The UI page uses exactly that.

### The page (what you see)
```
BRIGHTNESS            0.7      row 1 (y 10)
COLOUR              YELLOW     row 2 (y 20): WHITE, YELLOW, PINK, CUSTOM
HEX                 #FF8800    row 3 (y 30): the custom colour; K3 opens the text entry
[ 16 grey bars, in the chosen colour ]   y 44..52, as in display.lua: shows the effect at once
bad hex: 3 or 6 digits         y 62: a message (level 15 for an error, else the hint "E2 row  E3 change")
```
- **Brightness** is a plain number like the other values (AUDIO's `INPUT/RATE`, params): E3 right/left = +0.1 / -0.1, clamped to **0.1 .. 1.0**, shown as `0.7` (one decimal), default 1.0; no drawn slider. E3 is a detent encoder on the device, one step per click, on the desktop one per wheel step; shift (5 steps) is harmless since it clamps.
- **Colour** E3 cycles WHITE, YELLOW, PINK, CUSTOM (clamped at the ends like AUDIO's lists). CUSTOM is only selectable once a valid hex has been entered (before that, it shows `#------` and E3 stops at PINK).
- **Hex** row: K3 on it opens the text entry (below); a valid code becomes the custom colour and **switches COLOUR to CUSTOM at once**; a bad one keeps everything as it was and shows the message on this page (no change of colour, the page stays where it is).
- K2 = back to SYSTEM. E2 = row.

### The text entry for the hex code (found in the repository)
The entry that names a pset is `lua/lib/textentry.lua` (`require 'textentry'`): `textentry.enter(callback, default, heading, check)` (used by `lua/core/menu/params.lua` for `PSET NAME`, `PARAM`, and by wifi/settings for passwords). How the computer keyboard reaches it: the Linux window feeds the key events as a **virtual HID keyboard** (`platform/linux/hid_virtual.cc`, device "keyboard") -> `lua/core/hid.lua` -> `keyboard.process()` (`lua/core/keyboard.lua`); when `te_kbd_cb.code / .char` are set (by `textentry.enter`), the keyboard module hands every key to the entry first (and does **not** turn 1, 2, 3, Enter, Esc into K1..K3, see `hardware()`), so digits and letters can be typed; **Enter = OK, Esc = cancel, Backspace = delete**; E2 and E3 with K3 work on the device and the window as the wheel of characters. `check(text)` is called after each key; the string it returns is shown right-aligned on the entry as a warning (the entry keeps open).
The UI page calls `textentry.enter(m.hex_done, current_hex, "HEX COLOUR (3 or 6 digits):", ui_settings.hex_hint)`: the default is the current custom hex, `hex_hint` returns `""` while the text is a valid code (or a prefix that can still become one) and `"3 or 6 digits"` otherwise, so the warning shows **while typing**, and `m.hex_done(text)` (called with nil on Esc) validates once more with the same `parse_hex`, saves and applies, or shows the message on the page and keeps the previous colour. Nothing in `textentry.lua` changes (it is shared with the device).

### Adding a setting later
`ui_settings.lua` has one table `SETTINGS`: each entry has `key`, `default`, `parse(text) -> value or nil`, `format(value) -> text`, `apply(value)` (what to tell C or Lua; may be nil), and the page has one row per entry (`name`, `step(delta)` for E3, `show(value)`). Adding a setting = one entry in `SETTINGS` + one row in the page's list (+ `apply` if something has to happen). The file reader needs no change: it loops over the lines, finds the entry by key, ignores unknown keys with a log line (`ui.conf: unknown key 'foo' ignored`), fills missing keys with their defaults, and the writer writes every key of `SETTINGS` in order (plus unknown lines are kept as they were, like AUDIO keeps `in_ports=`).

### The file
```
brightness=0.7
colour=yellow
custom=FF8800
```
`colour` is `white`, `yellow`, `pink` or `custom`; `custom` is the last custom hex (6 digits, upper case, written without `#`; read with or without it, 3 or 6 digits); `color` is accepted as a spelling of `colour`. Hand editing is supported: a bad value is handled per key (below).

## 2. The exact mapping

For a grey g (0..255 of the raw screen image; level n has g = 17 n), a tint T = (Tr, Tg, Tb) and a brightness b:
1. **Normalise the tint:** divide by its largest channel and scale to 255 (hue and saturation kept, the brightest channel becomes 255). `000000` is not a colour (rejected). White, yellow and pink below are already normalised.
2. **out_c = round_half_up(g x T_c / 255 x b)** for each channel c. Linear in the pixel values (no gamma), so the anti-aliased greys between levels follow the same line and text edges stay smooth.
- **Black stays black** at every setting: g = 0 gives 0 for every channel, so the contrast (screen against its frame) is the whole range of the colour.
- **Presets:** white `FFFFFF` (as today), **yellow `FFD000`** (255, 208, 0: the amber-yellow of the yellow OLED panels; a 590 nm panel is not far from it), **pink `FF80B8`** (255, 128, 184). These are proposals; the pictures show them.
- **Custom colours are normalised, so a very dark one is not a dark screen.** The colour sets the hue; brightness is the only thing that makes the screen dimmer. A very dark code (`202020`, `010000`) becomes the full-value version of the same hue (white, red) instead of an unreadable screen, on the page that is used to set it. A very bright one (`ffffff`, `fff`) is white. A saturated dark hue such as pure blue `0000FF` stays as dim to the eye as blue is (the tint keeps the largest channel at 255, it does not equalise luminance): it is legible, but it is the owner's choice. The other design (use the code literally, so `202020` is a very dark grey screen) is simpler to explain but lets one lock the screen into a colour one cannot read; **my recommendation is the normalised one**; tell me if you prefer literal.
- **Brightness is linear in the pixel values**: 0.1 is one tenth of the value, about 1 percent of the light (the display's gamma). At the lowest settings the dim menu text (level 4 = 68) is nearly invisible: 0.4 gives 27, 0.1 gives 7. The page itself is readable at 0.1 only through its level-15 rows. This is by design of "0.1 is the lowest" but is the main risk (section 5); an alternative is a curve (out = g x b^0.6, so 0.4 acts as 0.58 and 0.1 as 0.25).

**The 16 mapped colours** (hex RGB; the custom example is `20C0A0`, normalised to `2BFFD5` at level 15; generated by `ui_tint.py table`):

| level | grey | white @ 1 | white @ 0.4 | yellow @ 1 | yellow @ 0.4 | pink @ 1 | pink @ 0.4 | custom 20C0A0 @ 1 | custom 20C0A0 @ 0.4 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 |
| 1 | 17 | 111111 | 070707 | 110E00 | 070600 | 11090C | 070305 | 03110E | 010706 |
| 2 | 34 | 222222 | 0E0E0E | 221C00 | 0E0B00 | 221119 | 0E070A | 06221C | 020E0B |
| 3 | 51 | 333333 | 141414 | 332A00 | 141100 | 331A25 | 140A0F | 09332B | 031411 |
| 4 | 68 | 444444 | 1B1B1B | 443700 | 1B1600 | 442231 | 1B0E14 | 0B4439 | 051B17 |
| 5 | 85 | 555555 | 222222 | 554500 | 221C00 | 552B3D | 221119 | 0E5547 | 06221C |
| 6 | 102 | 666666 | 292929 | 665300 | 292100 | 66334A | 29141D | 116655 | 072922 |
| 7 | 119 | 777777 | 303030 | 776100 | 302700 | 773C56 | 301822 | 147763 | 083028 |
| 8 | 136 | 888888 | 363636 | 886F00 | 362C00 | 884462 | 361B27 | 178872 | 09362D |
| 9 | 153 | 999999 | 3D3D3D | 997D00 | 3D3200 | 994D6E | 3D1F2C | 1A9980 | 0A3D33 |
| 10 | 170 | AAAAAA | 444444 | AA8B00 | 443700 | AA557B | 442231 | 1DAA8E | 0B4439 |
| 11 | 187 | BBBBBB | 4B4B4B | BB9900 | 4B3D00 | BB5E87 | 4B2636 | 20BB9C | 0D4B3E |
| 12 | 204 | CCCCCC | 525252 | CCA600 | 524300 | CC6693 | 52293B | 22CCAA | 0E5244 |
| 13 | 221 | DDDDDD | 585858 | DDB400 | 584800 | DD6F9F | 582C40 | 25DDB9 | 0F584A |
| 14 | 238 | EEEEEE | 5F5F5F | EEC200 | 5F4E00 | EE77AC | 5F3045 | 28EEC7 | 105F50 |
| 15 | 255 | FFFFFF | 666666 | FFD000 | 665300 | FF80B8 | 66334A | 2BFFD5 | 116655 |

**Edge cases** (`ui_tint.py edge`; level 15 at brightness 1, and level 4 at 0.4):
```
000000   -> rejected: black would hide the screen
010000   -> tint FF0000; level 15 at 1: FF0000, level 4 at 0.4: 1B0000
202020   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4: 1B1B1B
808080   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4: 1B1B1B
ffffff   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4: 1B1B1B
ff0000   -> tint FF0000; level 15 at 1: FF0000, level 4 at 0.4: 1B0000
0000ff   -> tint 0000FF; level 15 at 1: 0000FF, level 4 at 0.4: 00001B
00000f   -> tint 0000FF; level 15 at 1: 0000FF, level 4 at 0.4: 00001B
fff      -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4: 1B1B1B
#FFD000  -> tint FFD000; level 15 at 1: FFD000, level 4 at 0.4: 1B1600
12       -> rejected: a hex colour has 3 or 6 digits (0-9, a-f)
```
**Hex parsing** (the same in Lua and in the Python reference): optional leading `#`, then exactly 3 or 6 hex digits in either case (`fa0` = `FFAA00`), surrounding blanks ignored; anything else is rejected with "3 or 6 digits (0-9, a-f)"; `000`/`000000` is rejected with "black would hide the screen".

## 3. Instantly or not; what happens at start

- **Instantly while the page is open:** every E3 step and every accepted hex calls `_norns.ui_look` and writes `ui.conf`; the window's screen (and the bars on the page) change within a frame, and a script running behind the menu changes too (the setting is the display's, not the page's). Closing the menu changes nothing.
- **At start:** `ui_settings.load_and_apply()` reads `ui.conf` before the first script is loaded. Until then the window shows the first frame at white, brightness 1 (a pink user may see one white frame of the boot, a few hundred milliseconds; avoiding that would need the launcher to read the file; not planned).
- **Missing file:** defaults (white, brightness 1), no file written until a setting changes, log line `ui.conf: not found, using defaults`.
- **Damaged:** handled per key, each bad key falls back to its own default and logs one line (`ui.conf: brightness='abc' is not 0.1..1, using 1`, `ui.conf: colour='purple' unknown, using white`, `ui.conf: custom='12' is not a hex colour, ignored`); a brightness outside 0.1..1 is clamped if it is a number (`5` -> 1, `0` -> 0.1) and falls back to 1 if it is not; if `colour=custom` has no valid `custom`, the colour is white. A file that cannot be read at all is the same as missing. The page then shows what was applied, and the next change writes a clean file.

## 4. Guarding

- Everything new is behind `NORNS_LINUX_DESKTOP` (C) or a runtime check (Lua): `_norns.ui_look` exists only on the Linux desktop; `ui_settings.load_and_apply()` and the page registration check `_norns.ui_look ~= nil` and `os.getenv("NORNS_PLATFORM") ~= nil` (the same test as SYSTEM's computer list), so **the device (and the Mac, which has no UI page in this step) get the code but never run it**: the page is not in their lists, nothing is read, nothing is written.
- Shared C files: `sdl_bridge.cc` (the tables, `oled_view`, the new device event, the screenshot and GIF calls) and `gif_writer.c` (the new `gif_begin_palette`, the old function untouched) change only under the macro, or by adding; the Mac's `device_skin_test.c` and the GIF test are untouched and must pass. `macos/` is read, not edited.
- The Mac keeps the identity: at white and brightness 1 the Linux path is bit-identical to the old one too (`oled` drawn directly).

## 5. Tests first (each fails before the code exists)

1. **Mapping table** (C, `linux/tests/ui_look_test.c`, the mapping function that the bridge uses, separated into a small file like `window_keys.c` so it can be tested): the 16 levels for white, yellow, pink and the custom example, at 1 and 0.4, equal to the table of section 2 (generated from `ui_tint.py`, which is the second implementation: the test compares the two); every grey 0..255 monotonic per channel; level 15 at brightness 1 is the tint; the identity at white/1.
2. **Black stays black:** g = 0 gives (0,0,0) for every tint and brightness 0.1..1 (also in the window render: the pixels of the screen frame and of black screen pixels, and in a screenshot and a GIF frame).
3. **Hex parsing** (Lua, `lua/test/core/ui_settings_test.lua`, runs with the repo's Lua test runner and with `lua5.3`): `fff`, `FFF`, `#fa0`, `ff8800`, `#FF8800`, blanks around; rejected: empty, `#`, 1, 2, 4, 5, 7 digits, `ggg`, `#12345g`, `0x123456`, `000`, `000000`; the message text; and `parse_hex` of Lua equals `ui_tint.py hex` for a list of 50 random codes (same normalised colour).
4. **The text entry for the hex code** (Lua, with the real `textentry` and `keyboard` modules and the stubs of `tape_test.lua`): from the UI page K3 on HEX opens `textentry` with the current hex as its default and the heading; typing `#`, digits and letters through `keyboard.process` (not the stub) builds the text; Enter returns it, Esc returns nil; the check shows the warning while the code is bad; a valid code applies and selects CUSTOM; a bad one leaves colour and file as they were and the page shows the message; 1, 2, 3 and Enter typed in the entry do not press K1..K3.
5. **Setting saved and loaded:** change brightness and colour through the page's `enc`/`key`, the file has exactly the three keys with the expected text; a second start (new Lua state) loads them and calls `_norns.ui_look` with the same four numbers (a stub records the calls); the file is written through a temporary file (no `ui.conf.tmp` left behind); `ui.conf` is written under the norns home that the launcher uses (the headless norns test: set, restart norns, read the window).
6. **A damaged file:** each case of section 3 (empty file, binary junk, `brightness=abc`, `brightness=5`, `brightness=0`, `colour=purple`, `colour=custom` without `custom`, `custom=12`, an unknown key, a line without `=`, a missing file): the result, the log lines (the stub `print` collects them) and that nothing throws; unknown keys survive a rewrite.
7. **Brightness steps:** from 1.0 the 9th step down is 0.1 and the 10th does not go lower; up from 0.1 stops at 1; the shown text is `0.1`..`1.0` (no `0.30000000000000004`).
8. **Screenshot and GIF match the window** (C, extending `device_skin_linux_test.c` and the bridge's capture functions, which will have to be callable by the test, or a headless norns test): render the window's screen rectangle and a screenshot of the same frame for yellow/0.4, equal pixel for pixel; a GIF of the same frame decodes to the same colour at the 16 levels (the new palette); `gif_begin` (old) still writes the grey palette; white/1 screenshots equal today's bytes.
9. **The menu page is present on the desktop only:** `system.lua`'s lists are `DEVICES, AUDIO, UI, MODS, RESET, RESTART` with `NORNS_PLATFORM` set and unchanged without it; `m["UI"]` loads on the desktop; without `_norns.ui_look` `load_and_apply` does nothing and writes nothing; the Mac's and the device's tests (`macos/tests/device_skin_test.c`, the Lua tests) are unchanged.
10. **Headless norns test** (`norns_probe`): start with a `ui.conf` of yellow/0.4, read the window screenshot: the screen's brightest pixel is `665300`; open SYSTEM > UI, change values with `_norns.enc`, the window changes, `ui.conf` changes; the whole of `run_all.sh` stays green.

### Risks
- **Dim text at low brightness** (above): level 4 (the menus' dim rows, 61 of 84 fixed-level calls use 4 or 15) is 27 at 0.4 and 7 at 0.1, level 1-2 vanish. The page at 0.1 is readable only in its selected rows (level 15 = 26) and the grey bar. A floor or a curve would fix it; decision for the owner.
- **Tint accuracy:** the tint is a multiplication in the display's sRGB values; the 16 levels of a yellow or pink screen are not what a yellow panel's physical grey scale looks like; compare with a real yellow OLED if you have one.
- **Colour names are mine** (`FFD000`, `FF80B8`); the page shows the hex as well as the name.
- **GIF:** a setting changed while recording; GIF palette of 16 entries (the in-between edge greys are level-quantised as today). **Scripts' `screen.export_png`** stays raw: a script's PNG will not be tinted.
- **Text entry on the desktop** needs the window to have the keyboard focus; typed `#` and shifted characters depend on the layout (the module uses `keyboard.code_to_char`, which follows the user's layout); a hex without `#` works on every layout.
- **Shared files** (`sdl_bridge.cc`, `gif_writer.c`, `weaver.cc`) are compiled by the Mac; every edit is behind the macro or a pure addition; the Mac build is not available here (a check is on the owner's list).
- **First frame at start** is white (above).
- **Not testable here:** the colours on the laptop's real screen, the yellow panel comparison, the keyboard text entry with a real keyboard layout (a typed `#` on a non-US layout).

## Questions for the owner
1. Presets: yellow `FFD000` and pink `FF80B8` as proposed, or other values (the pictures show them)?
2. Custom colours normalised (recommended) or literal?
3. Brightness linear (as asked) or with the curve at the low end (`b^0.6`)?
4. `screen.export_png` (a script's own PNG) raw (recommended) or tinted?
5. `RESET` leaves `ui.conf` (recommended) or deletes it?
