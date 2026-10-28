# SYSTEM > UI: screen brightness and screen colour (UI step 3: plan only, nothing is built)

Linux desktop build only. Written from the code of this repository; the pictures are a stand-in (the real window with the screen tinted by the mapping of section 2, at the old linear greys: `ui-previews/ui-colours.png`, `ui-previews/ui-brightness.png`, **not redrawn with the grey correction**; the ramp of the 16 levels with and without it is `ui-previews/ui-grey-ramp.png`; made by `ui-previews/make_ui_settings_previews.py`, the mapping itself is `ui-previews/ui_tint.py`).
**This plan replaces the "SCREEN" page of `ui-plan.md` section 2** (brightness and greys `device / bright / brighter`): the page is now called UI, with three settings, **BRIGHTNESS, COLOUR and GREYS** (and the HEX row of the colour). **Addition (evidence from the owner's laptop): the grey correction is back and on by default** (gamma 0.7, setting GREYS): on the desktop the dim levels of some scripts (the waveform and labels of Cheat Codes 2) are almost invisible, while the same page is readable on the owner's norns. The earlier "the grey table stays as it is" is withdrawn; what stays is that the raw 16 levels (grey 17 n) come from the screen backend unchanged and the correction is a display mapping in the bridge, like the tint. The rest of section 2 of `ui-plan.md` (the chip's brightness/contrast/gamma do nothing on the desktop; where the mapping lives) still holds.

## 1. How it works upstream, and what the desktop build has to do

**Upstream and on the device.** The OLED is an SSD1322 and brightness is a property of the chip: `lua/core/screen.lua` reads `dust/data/system.display` (`brightness` 0-15, `contrast`, `gamma`) and on the first `screen.update()` calls `_norns.screen_brightness / screen_contrast / screen_gamma`; the page `lua/core/menu/display.lua` (SYSTEM > SETTINGS > DISPLAY) edits them with E3 and saves on every change. **There is no colour setting upstream**: the OLED's colour is the panel's (white, or yellow on the yellow panels), the software only knows 16 grey levels. On this desktop build those calls end in `hardware_null.cc` and do nothing, and `lua/core/menu/system.lua` hides SETTINGS on a computer.

**The screen path on the desktop** (all in `matron/src/platform/macos/sdl_bridge.cc`, compiled by the Mac and the Linux build):
1. the screen backend draws the 128 x 64 image in grey (level n = 17 n; text edges are anti-aliased greys in between); `present()` copies it into the cairo surface `oled` (RGB24, grey);
2. `draw_oled()` -> `skin_draw_oled()` (`device_skin.c`) draws `oled` in the window (nearest at whole multiples, enlarge + best filter in between, step 2b);
3. `save_screenshot()` (right-click menu) paints `oled` 4x with nearest and writes a PNG;
4. `gif_add_frame()` / `oled_levels()` keep **16-level frames** (max channel of `oled` rescaled to 0-15); `gif_writer.c` writes a fixed grey palette `i * 17`.
   (`_norns.screen_export_png`, used by scripts and by my tests, is written by the screen backend itself from the raw grey image, not by the bridge.)

**What has to do the work**
- **Grey correction, colour and brightness in one place in the bridge.** `oled` stays the raw grey image. A second surface `oled_view` (128 x 64 RGB24) is made from it through three 256-entry tables (R, G, B; each table is the grey correction, the tint and the brightness in one go, one rounding) in `present()` and whenever a setting changes; `draw_oled` and `save_screenshot` read `oled_view`. Only at white, brightness 1 **and greys 1.0** are the tables the identity and `oled` used directly (bit-identical to today); with the default (greys 0.7) the tables are always applied (8192 pixels per frame, negligible). The in-window menu, toasts and the bezel are not tinted (they are the program's, not the screen's).
- **GIF.** Frames keep the **raw levels** (`oled_levels()` unchanged); the palette becomes the 16 mapped colours (`gif_begin_palette(g, f, w, h, scale, rgb[16][3])`, new; the old `gif_begin` stays and writes the grey palette, so the Mac call is unchanged). Frames then match the window for the 16 levels; the in-between greys of anti-aliased edges are quantised to a level, as in every GIF today (the screenshot has the exact value). A setting changed during a recording: the palette of the moment the GIF is encoded is used (accepted, noted).
- **Screenshot** = the window's screen pixel for pixel (with the grey correction too), scaled 4x. `screen.export_png` (a script's own call) stays raw grey: it is the device's image, a test and script API; the tint is a property of the display. (Say if you want it tinted too.)
- **Lua: the page and the file.** One new module `lua/core/ui_settings.lua` owns the settings (defaults, parse, validate, load, save, apply); the page `lua/core/menu/ui.lua` is the screen of it. Registered like AUDIO: `m["UI"] = require 'core/menu/ui'` in `lua/core/menu.lua`, and `lua/core/menu/system.lua`'s computer list (inside the existing `NORNS_PLATFORM` block, the device's list untouched) becomes `DEVICES, AUDIO, UI, MODS, RESET, RESTART` with `pages` to match.
- **One new C function**, `_norns.ui_look(brightness, r, g, b, gamma)` (`weaver.cc`, registered under `#ifdef NORNS_LINUX_DESKTOP` next to `audio_status` and `set_warning`) -> `sdl_bridge_set_screen_look()` (like `sdl_bridge_set_warning`: posts a device event to the SDL main thread, which rebuilds the three tables, remakes `oled_view` and redraws the screen). Nothing else in C knows about settings: Lua parses, validates and decides; C only gets five numbers.
- **Where it is saved and loaded.** `ui.conf` in the norns home (Lua sees it as `/home/we/ui.conf`, the virtual home maps it, exactly like `audio.conf`). Written on every change (to `ui.conf.tmp`, then renamed: a crash never leaves half a file). Loaded and applied once at start by `ui_settings.load_and_apply()`, called from `lua/core/menu.lua` where the pages are registered (guarded by `_norns.ui_look ~= nil`, which exists only on the Linux desktop). `RESET` does not delete it (it does not delete `audio.conf` either: a look is not "system state").

**How AUDIO is built, and the UI page follows it.** A page is a table `m` with `init`, `deinit`, `key(n,z)`, `enc(n,delta)`, `redraw()`; `m.pos` is the selected row (E2), E3 changes the value, K2 goes back (`_menu.set_page("SYSTEM")`), rows are drawn by `screen.level(i == m.pos and 15 or 4); screen.move(0, 10*i); screen.text(NAME)` with the value `screen.move(127, 10*i); screen.text_right(value)`; the file is `key=value` lines read with `line:match("^([%w_]+)=(.*)$")`, unknown lines kept or ignored. The UI page uses exactly that.

### The page (what you see)
```
BRIGHTNESS            0.7      row 1 (y 10)
COLOUR              YELLOW     row 2 (y 20): WHITE, YELLOW, PINK, CUSTOM
GREYS                 0.7      row 3 (y 30): 1.0 = linear (as before), 0.7 default, 0.5 brighter
HEX                 #FF8800    row 4 (y 40): the custom colour; K3 opens the text entry
[ 16 grey bars, in the chosen colour ]   y 45..50, as in display.lua: shows the effect at once
bad hex: 3 or 6 digits         y 62: a message (level 15 for an error, else the hint "E2 row  E3 change; GREYS lower = brighter")
```
- **Brightness** is a plain number like the other values (AUDIO's `INPUT/RATE`, params): E3 right/left = +0.1 / -0.1, clamped to **0.1 .. 1.0**, shown as `0.7` (one decimal), default 1.0; no drawn slider. E3 is a detent encoder on the device, one step per click, on the desktop one per wheel step; shift (5 steps) is harmless since it clamps.
- **Greys** is a plain number, like BRIGHTNESS: E3 steps of 0.1, clamped to **0.4 .. 1.0**, shown with one decimal; **1.0 is linear (the desktop as it was), 0.7 is the default, 0.5 and 0.4 brighten the mid greys more**. (The name is GREYS, not CONTRAST: upstream's CONTRAST is the chip's segment current, a different thing.) The 16 bars on the page show the effect while it is changed. It is the gamma of the mapping, so a *lower* number is a *brighter* mid grey; the hint line says so.
- **Colour** E3 cycles WHITE, YELLOW, PINK, CUSTOM (clamped at the ends like AUDIO's lists). CUSTOM is only selectable once a valid hex has been entered (before that, it shows `#------` and E3 stops at PINK).
- **Hex** row (the last, the sub-row of COLOUR): K3 on it opens the text entry (below); a valid code becomes the custom colour and **switches COLOUR to CUSTOM at once**; a bad one keeps everything as it was and shows the message on this page (no change of colour, the page stays where it is).
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
greys=0.7
```
`colour` is `white`, `yellow`, `pink` or `custom`; `custom` is the last custom hex (6 digits, upper case, written without `#`; read with or without it, 3 or 6 digits); `greys` is the gamma, 0.4 to 1.0, default 0.7; `color` is accepted as a spelling of `colour`. Hand editing is supported: a bad value is handled per key (below).

## 2. The exact mapping

For a grey g (0..255 of the raw screen image; level n has g = 17 n), a grey correction gamma G (default 0.7), a tint T = (Tr, Tg, Tb) and a brightness b, **in this order**:
1. **Grey correction (GREYS):** g' = 255 x (g / 255)^G. G = 1.0 is the identity (the desktop as it was). It is evaluated for every grey 0..255, so the anti-aliased edges of text follow the same curve; **0 stays 0 and 255 stays 255** at every G.
2. **Normalise the tint:** divide by its largest channel and scale to 255 (hue and saturation kept, the brightest channel becomes 255). `000000` is not a colour (rejected). White, yellow and pink below are already normalised.
3. **out_c = round_half_up(g' x T_c / 255 x b)** for each channel c: **one rounding, at the end** (so the table below is exact, and a test can compare it with the reference).
- **Black stays black** at every setting: g = 0 gives 0 for every channel whatever G, T and b, so the contrast (screen against its frame) is the whole range of the colour.
- **Presets:** white `FFFFFF` (as today), **yellow `FFD000`** (255, 208, 0: the amber-yellow of the yellow OLED panels; a 590 nm panel is not far from it), **pink `FF80B8`** (255, 128, 184). These are proposals; the pictures show them (at the old linear greys).
- **Custom colours are normalised, so a very dark one is not a dark screen.** The colour sets the hue; brightness is the only thing that makes the screen dimmer. A very dark code (`202020`, `010000`) becomes the full-value version of the same hue (white, red) instead of an unreadable screen, on the page that is used to set it. A very bright one (`ffffff`, `fff`) is white. A saturated dark hue such as pure blue `0000FF` stays as dim to the eye as blue is (the tint keeps the largest channel at 255, it does not equalise luminance): it is legible, but it is the owner's choice. The other design (use the code literally, so `202020` is a very dark grey screen) is simpler to explain but lets one lock the screen into a colour one cannot read; **my recommendation is the normalised one**; tell me if you prefer literal.
- **Brightness is linear in the pixel values, after the grey correction**: 0.1 is one tenth of the value, about 1 percent of the light (the display's gamma). With the default greys 0.7 the dim menu text (level 4 = 101) is 40 at brightness 0.4 and 10 at 0.1 (without the correction it was 27 and 7): readable at 0.4, still very dark at 0.1, where the page is readable only through its level-15 rows. An alternative is a curve for brightness (out = g' x b^0.6, so 0.4 acts as 0.58 and 0.1 as 0.25).

### 2.1 The grey correction: the evidence and the numbers

**What the owner saw.** The waveform of a sample and some dim labels in Cheat Codes 2 are almost black in the window; on the norns the same page is readable.

**What Cheat Codes 2 draws** (I could check: the catalog scan's clone of the script is available here, commit `7134bd5`, `cheat_codes_2.lua` and `lib/main_menu.lua`; nothing was run, I read the source):
- the sample page (`loops`, `lib/main_menu.lua` line 96) has `screen_levels = {frame2 and 15 or 3, frame2 and 4 or 1, frame2 and 10 or 2, frame2 and 3 or 15}`; **the waveform is drawn with `screen_levels[2]`: level 1 in the overview, level 4 in the editing frame**; the start and end markers use `[1]`: level 3 in the overview, 15 when editing; the page title and many labels are `screen.level(3)`;
- over the whole script: 200 `screen.level` calls; the literal ones are level 15 (32 times), **level 3 (37)**, 0 (6), 6 (2), 10 (1), the rest are computed from the same pairs (`... and 15 or 3`). So **its dim parts are level 3, and its waveform is level 1 or 4**: today level 1 is grey 17 (7 percent), level 3 grey 51 (20 percent), level 4 grey 68 (27 percent), on a monitor those emit about 0.3, 2.5 and 5 percent of full light. With the default mapping they are 38, 83 and 101.
- I cannot tell which of the two frames the owner looked at.

**What the device does** (read from `matron/src/hardware/screen/ssd1322.cc`, `screen.cc`, `lua/core/screen.lua`; not run, no device here): the screen backend hands the chip the 4-bit level (the upper nibble of the grey); the chip's grey scale table is written by `ssd1322_set_gamma(g)` as **`gs[level+1] = round((level/14)^g x 112)` for level 0..14, g from `system.display` (default 1.0, set on the first `screen.update()`)**. At g = 1.0 pixel value k (1..15) is driven with GS value 8 x (k-1) of 112: **linear in drive time, so linear in the light the panel emits; pixel value 1 has GS 0 ("GS1 has no current drive", the code's own comment) and is as dark as 0**, level 2 gives 7 percent of the light, 3 gives 14, 4 gives 21, 8 gives 50, 15 gives 100. A monitor does the opposite: code value c gives about (c/255)^2.2 of the light. So the same level 4 is **21 percent light on the panel and about 5 percent on the desktop**, level 3 14 vs 2.5, level 2 7 vs 0.7. That agrees with the owner's observation and is the likely cause. Upstream knows the export has the same mismatch: `screen.cc` (the PNG export) carries `// FIXME: needs some sort of gamma correction?`.

**The mapped levels against the device** (grey code values and percent of full white; `ui_tint.py greys` makes the table; "device-like" is *my estimate*: the code value whose light on a monitor with gamma 2.2 equals the panel's light at gs[k] = 8 (k-1), i.e. 255 x ((k-1)/14)^(1/2.2); the values for gamma 0.7 and 0.5 are the exact table of `docs/port/ui-previews/grey-levels.txt`, which is still there, up to a one-point rounding of the percent column):

| level | today (gamma 1.0) | gamma 0.7 (default) | gamma 0.5 | device-like (estimate) |
|---|---|---|---|---|
| 0 | 0 (0%) | 0 (0%) | 0 (0%) | 0 (0%) |
| 1 | 17 (7%) | 38 (15%) | 66 (26%) | 0 (0%) |
| 2 | 34 (13%) | 62 (24%) | 93 (37%) | 77 (30%) |
| 3 | 51 (20%) | 83 (32%) | 114 (45%) | 105 (41%) |
| 4 | 68 (27%) | 101 (40%) | 132 (52%) | 127 (50%) |
| 5 | 85 (33%) | 118 (46%) | 147 (58%) | 144 (56%) |
| 6 | 102 (40%) | 134 (53%) | 161 (63%) | 160 (63%) |
| 7 | 119 (47%) | 150 (59%) | 174 (68%) | 173 (68%) |
| 8 | 136 (53%) | 164 (64%) | 186 (73%) | 186 (73%) |
| 9 | 153 (60%) | 178 (70%) | 198 (77%) | 198 (78%) |
| 10 | 170 (67%) | 192 (75%) | 208 (82%) | 209 (82%) |
| 11 | 187 (73%) | 205 (80%) | 218 (86%) | 219 (86%) |
| 12 | 204 (80%) | 218 (86%) | 228 (89%) | 229 (90%) |
| 13 | 221 (87%) | 231 (90%) | 237 (93%) | 238 (93%) |
| 14 | 238 (93%) | 243 (95%) | 246 (97%) | 247 (97%) |
| 15 | 255 (100%) | 255 (100%) | 255 (100%) | 255 (100%) |

What this says: **gamma 0.5 is within 5 code values of the device-like curve from level 2 up; gamma 0.7 (the default asked for) is milder** (level 4: 101 against 127, level 2: 62 against 77) but already brings level 4 from 27 to 40 percent and level 1 from 7 to 15 percent. Differences: the device shows level 1 as black (the same as 0) where every mapping here keeps level 1 visible. **I could not verify any of this on a real panel**: it rests on (a) the code's grey-scale table and its comment, (b) the assumption that the panel's light is linear in the GS value, (c) a 2.2 monitor, (d) the default gamma 1.0 (the owner's `system.display` could differ; contrast and brightness do not change the relative levels). **It does not explain by itself why the overview waveform at level 1 is clearly readable on the owner's norns**: by the table level 1 is dark on the panel too; either the owner looked at the editing frame (level 4), or the panel shows level 1 faintly (pre-charge), or the settings differ. Worth a look at the real page before the default is final.

**What GREYS does to every script.** It is a display mapping of the whole screen, for every script and every menu: the mid greys get brighter everywhere (levels 1 to 14), only black (0) and full white (level 15) are unchanged. Scripts that draw faint hints in level 1 to 3 will show them more strongly, a screen full of level 5 to 10 looks lighter and flatter, and **a desktop screenshot or GIF (which follow the window) will not match what a device shows pixel for pixel**; at 1.0 they are as before. `screen.export_png` (a script's own PNG) stays the raw levels, so it differs from the window by this mapping.

**The 16 mapped colours** (hex RGB; gamma 0.7, the default; the custom example is `20C0A0`, normalised to `2BFFD5` at level 15; generated by `ui_tint.py table`):

| level | grey | white @ 1 | white @ 0.4 | yellow @ 1 | yellow @ 0.4 | pink @ 1 | pink @ 0.4 | custom 20C0A0 @ 1 | custom 20C0A0 @ 0.4 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 | 000000 |
| 1 | 17 | 262626 | 0F0F0F | 261F00 | 0F0C00 | 26131C | 0F080B | 062620 | 030F0D |
| 2 | 34 | 3E3E3E | 191919 | 3E3300 | 191400 | 3E1F2D | 190C12 | 0A3E34 | 041915 |
| 3 | 51 | 535353 | 212121 | 534300 | 211B00 | 53293C | 211118 | 0E5345 | 06211C |
| 4 | 68 | 656565 | 282828 | 655200 | 282100 | 653349 | 28141D | 116554 | 072822 |
| 5 | 85 | 767676 | 2F2F2F | 766000 | 2F2700 | 763B55 | 2F1822 | 147663 | 082F27 |
| 6 | 102 | 868686 | 363636 | 866E00 | 362C00 | 864361 | 361B27 | 178670 | 09362D |
| 7 | 119 | 969696 | 3C3C3C | 967A00 | 3C3100 | 964B6C | 3C1E2B | 19967D | 0A3C32 |
| 8 | 136 | A4A4A4 | 424242 | A48600 | 423600 | A45276 | 42212F | 1CA489 | 0B4237 |
| 9 | 153 | B2B2B2 | 474747 | B29100 | 473A00 | B25A81 | 472433 | 1EB295 | 0C473C |
| 10 | 170 | C0C0C0 | 4D4D4D | C09D00 | 4D3F00 | C0608B | 4D2737 | 20C0A0 | 0D4D40 |
| 11 | 187 | CDCDCD | 525252 | CDA700 | 524300 | CD6794 | 52293B | 23CDAB | 0E5245 |
| 12 | 204 | DADADA | 575757 | DAB200 | 574700 | DA6D9D | 572C3F | 25DAB6 | 0F5749 |
| 13 | 221 | E7E7E7 | 5C5C5C | E7BC00 | 5C4B00 | E774A6 | 5C2E43 | 27E7C1 | 105C4D |
| 14 | 238 | F3F3F3 | 616161 | F3C600 | 614F00 | F37AAF | 613146 | 29F3CB | 106151 |
| 15 | 255 | FFFFFF | 666666 | FFD000 | 665300 | FF80B8 | 66334A | 2BFFD5 | 116655 |

**Edge cases** (`ui_tint.py edge`; level 15 at brightness 1, and level 4 at 0.4, gamma 0.7):
```
000000   -> rejected: black would hide the screen
010000   -> tint FF0000; level 15 at 1: FF0000, level 4 at 0.4 (gamma 0.7): 280000
202020   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4 (gamma 0.7): 282828
808080   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4 (gamma 0.7): 282828
ffffff   -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4 (gamma 0.7): 282828
ff0000   -> tint FF0000; level 15 at 1: FF0000, level 4 at 0.4 (gamma 0.7): 280000
0000ff   -> tint 0000FF; level 15 at 1: 0000FF, level 4 at 0.4 (gamma 0.7): 000028
00000f   -> tint 0000FF; level 15 at 1: 0000FF, level 4 at 0.4 (gamma 0.7): 000028
fff      -> tint FFFFFF; level 15 at 1: FFFFFF, level 4 at 0.4 (gamma 0.7): 282828
#FFD000  -> tint FFD000; level 15 at 1: FFD000, level 4 at 0.4 (gamma 0.7): 282100
12       -> rejected: a hex colour has 3 or 6 digits (0-9, a-f)
```
**Hex parsing** (the same in Lua and in the Python reference): optional leading `#`, then exactly 3 or 6 hex digits in either case (`fa0` = `FFAA00`), surrounding blanks ignored; anything else is rejected with "3 or 6 digits (0-9, a-f)"; `000`/`000000` is rejected with "black would hide the screen".

## 3. Instantly or not; what happens at start

- **Instantly while the page is open:** every E3 step and every accepted hex calls `_norns.ui_look` and writes `ui.conf`; the window's screen (and the bars on the page) change within a frame, and a script running behind the menu changes too (the setting is the display's, not the page's). Closing the menu changes nothing.
- **At start:** `ui_settings.load_and_apply()` reads `ui.conf` before the first script is loaded. Until then the window shows the first frame at white, brightness 1 and linear greys (a pink user may see one white frame of the boot, a few hundred milliseconds; avoiding that would need the launcher to read the file; not planned).
- **Missing file:** defaults (white, brightness 1, greys 0.7), no file written until a setting changes, log line `ui.conf: not found, using defaults`.
- **Damaged:** handled per key, each bad key falls back to its own default and logs one line (`ui.conf: brightness='abc' is not 0.1..1, using 1`, `ui.conf: colour='purple' unknown, using white`, `ui.conf: custom='12' is not a hex colour, ignored`, `ui.conf: greys='x' is not 0.4..1.0, using 0.7`); **greys** falls back to its own default 0.7 (a number outside 0.4..1.0 is clamped, anything else uses 0.7), brightness to 1, the colour to white; a brightness outside 0.1..1 is clamped if it is a number (`5` -> 1, `0` -> 0.1) and falls back to 1 if it is not; if `colour=custom` has no valid `custom`, the colour is white. A file that cannot be read at all is the same as missing. The page then shows what was applied, and the next change writes a clean file.

## 4. Guarding

- Everything new is behind `NORNS_LINUX_DESKTOP` (C) or a runtime check (Lua): `_norns.ui_look` exists only on the Linux desktop; `ui_settings.load_and_apply()` and the page registration check `_norns.ui_look ~= nil` and `os.getenv("NORNS_PLATFORM") ~= nil` (the same test as SYSTEM's computer list), so **the device (and the Mac, which has no UI page in this step) get the code but never run it**: the page is not in their lists, nothing is read, nothing is written.
- Shared C files: `sdl_bridge.cc` (the tables, `oled_view`, the new device event, the screenshot and GIF calls) and `gif_writer.c` (the new `gif_begin_palette`, the old function untouched) change only under the macro, or by adding; the Mac's `device_skin_test.c` and the GIF test are untouched and must pass. `macos/` is read, not edited.
- The Mac keeps the identity: at white and brightness 1 the Linux path is bit-identical to the old one too (`oled` drawn directly).

## 5. Tests first (each fails before the code exists)

1. **Mapping table** (C, now with the grey correction first, `linux/tests/ui_look_test.c`, the mapping function that the bridge uses, separated into a small file like `window_keys.c` so it can be tested): the 16 levels for white, yellow, pink and the custom example, at brightness 1 and 0.4 (gamma 0.7), equal to the table of section 2 (generated from `ui_tint.py`, which is the second implementation: the test compares the two); every grey 0..255 monotonic per channel; level 15 at brightness 1 is the tint at every gamma; **the 16-level gamma table equals `grey-levels.txt` for gamma 1.0, 0.7 and 0.5 (the device-like column of 2.1 is only documentation, not tested)**; the identity at white, brightness 1, greys 1.0 (and only then `oled` is used directly).
2. **Black stays black and white stays white:** g = 0 gives (0,0,0) and g = 255 gives the tint times the brightness for every tint, every gamma 0.4..1.0 and brightness 0.1..1 (also in the window render: the pixels of the screen frame and of black screen pixels, and in a screenshot and a GIF frame).
3. **Hex parsing** (Lua, `lua/test/core/ui_settings_test.lua`, runs with the repo's Lua test runner and with `lua5.3`): `fff`, `FFF`, `#fa0`, `ff8800`, `#FF8800`, blanks around; rejected: empty, `#`, 1, 2, 4, 5, 7 digits, `ggg`, `#12345g`, `0x123456`, `000`, `000000`; the message text; and `parse_hex` of Lua equals `ui_tint.py hex` for a list of 50 random codes (same normalised colour).
4. **The text entry for the hex code** (Lua, with the real `textentry` and `keyboard` modules and the stubs of `tape_test.lua`): from the UI page K3 on HEX opens `textentry` with the current hex as its default and the heading; typing `#`, digits and letters through `keyboard.process` (not the stub) builds the text; Enter returns it, Esc returns nil; the check shows the warning while the code is bad; a valid code applies and selects CUSTOM; a bad one leaves colour and file as they were and the page shows the message; 1, 2, 3 and Enter typed in the entry do not press K1..K3.
5. **Setting saved and loaded:** change brightness, colour and **greys** through the page's `enc`/`key`, the file has exactly the four keys with the expected text (`greys=0.7` by default, `1.0` after the steps up, no float noise like `0.7000000000000001`); a second start (new Lua state) loads them and calls `_norns.ui_look` with the same five numbers (a stub records the calls); the file is written through a temporary file (no `ui.conf.tmp` left behind); `ui.conf` is written under the norns home that the launcher uses (the headless norns test: set, restart norns, read the window).
6. **A damaged file:** each case of section 3 (empty file, binary junk, `brightness=abc`, `brightness=5`, `brightness=0`, `colour=purple`, `colour=custom` without `custom`, `custom=12`, `greys=abc`, `greys=0`, `greys=3`, a missing `greys`, an unknown key, a line without `=`, a missing file): the result, the log lines (the stub `print` collects them) and that nothing throws; unknown keys survive a rewrite.
7. **Brightness and greys steps:** greys from the default 0.7: three steps up reach 1.0 and stop, three down reach 0.4 and stop, shown `0.4`..`1.0`; brightness from 1.0 the 9th step down is 0.1 and the 10th does not go lower; up from 0.1 stops at 1; the shown text is `0.1`..`1.0` (no `0.30000000000000004`).
8. **Screenshot and GIF match the window** (C, extending `device_skin_linux_test.c` and the bridge's capture functions, which will have to be callable by the test, or a headless norns test): render the window's screen rectangle and a screenshot of the same frame for yellow/0.4, equal pixel for pixel; a GIF of the same frame decodes to the same colour at the 16 levels (the new palette); `gif_begin` (old) still writes the grey palette; white/1 screenshots equal today's bytes.
9. **The menu page is present on the desktop only:** `system.lua`'s lists are `DEVICES, AUDIO, UI, MODS, RESET, RESTART` with `NORNS_PLATFORM` set and unchanged without it; `m["UI"]` loads on the desktop; without `_norns.ui_look` `load_and_apply` does nothing and writes nothing; the Mac's and the device's tests (`macos/tests/device_skin_test.c`, the Lua tests) are unchanged.
10. **Headless norns test** (`norns_probe`): start with a `ui.conf` of yellow/0.4, read the window screenshot: the screen's brightest pixel is `665300` (level 15 is unchanged by the grey correction) and a level-4 pixel is `282100` (gamma 0.7: 101 x 0.4 on the yellow); open SYSTEM > UI, change values with `_norns.enc`, the window changes, `ui.conf` changes; the whole of `run_all.sh` stays green.

### Risks
- **Dim text at low brightness:** with the default greys the menus' dim rows (level 4) are 40 at brightness 0.4 and 10 at 0.1 (27 and 7 at linear greys); levels 1-2 are nearly invisible below 0.4. The page at 0.1 is readable only in its selected rows (level 15 = 26) and the grey bar. A floor or a curve would fix it; decision for the owner.
- **The grey correction changes how every script looks** (mid greys brighter, flatter): faint hints in levels 1 to 3 show more, screens that use levels 5 to 10 for shading look lighter; and **desktop screenshots and GIFs no longer match a device exactly** (at GREYS 1.0 they do again). A script author who tunes levels on the desktop sees a different picture than on the device unless GREYS is at the device-like value.
- **Which gamma matches the device is an estimate** (2.1): 0.5 is nearer to the computed panel curve than 0.7; the level-1 puzzle (panel dark by the table, readable for the owner) is open; the default may need to move after a look at the real page on both.
- **The earlier pictures** (`ui-colours.png`, `ui-brightness.png`) are at linear greys and show dimmer text than the default will; only the ramp picture shows the correction. Re-make them (with `ui_tint.py`'s gamma) when the plan is accepted.
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
   (new) **Default greys 0.7 as asked, or 0.5**, which is closer to my estimate of the panel? And the range 0.4 to 1.0 in 0.1 steps?
3. Brightness linear (as asked) or with the curve at the low end (`b^0.6`)?
4. `screen.export_png` (a script's own PNG) raw (recommended) or tinted?
5. `RESET` leaves `ui.conf` (recommended) or deletes it?
