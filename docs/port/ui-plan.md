# UI plan, step 1: a bigger screen in the box, brighter greys, a SCREEN page (preview and plan only)

Nothing in the product was changed for this note. The pictures are in `docs/port/ui-previews/` (index and how they were made: its `README.md`; reproduce with `make_previews.sh`).
The owner wants: (a) the screen about 20 to 25 percent bigger inside the box, box and window the same size, the other controls nudged; (b) brighter dim text by default and an overall brightness setting on a new SYSTEM > SCREEN page, screenshots and GIFs matching the window; (c) later a detachable resizable screen window (only noted here).

## 0. Summary and recommendation

- **Size: +25 percent (3.75 device pixels per screen pixel), or +33 percent (exactly 4) if even pixels matter more than size** (added: section 1.4: it fits **without growing the box or the window**, at the price of a tighter right cluster; the numbers for the uneven pixels of +25 are in section 1.5). Original reasoning for +25: It is the biggest of the three, it still balances (bezel 36..544 units from the left, 31 units of space to K2, 42 above to E1's label), and 3.75 = 15/4 gives the most regular pixel rhythm (4, 4, 4, 3 device pixels) when pixels are drawn crisp. +20 and +22 also work (pictures). **Finding that changes the plan:** the window draws the screen at a *whole number* of device pixels per screen pixel (today 3, `floor` of 3.04). The next whole number is 4, which is **+33 percent** and does not fit. So +20 to +25 percent means a **non-integer pixel size**: with nearest neighbour some screen pixels are one device pixel wider (crisp but slightly uneven, `zoom-nearest-vs-smooth.png`), or bilinear (even but softer). I recommend nearest neighbour and a look at it on the laptop; bilinear is a one-line switch.
- **Greys: gamma 0.7 as the new default** (level 4, the dim menu text, from grey 68 = 27 percent to **101 = 40 percent**), with **gamma 0.5** (level 4 -> 132 = 52 percent) as a second choice on the SCREEN page and "device" (today's) as a third. 0.7 makes the dim lines easy to read and keeps levels 8..15 apart (level 12 -> 218 against 15 -> 255); 0.5 starts to squeeze the bright levels together (12 -> 228), which would change how scripts that draw with levels 10 to 14 look.
- **Brightness: a percentage, 100 default, steps of 10 down to 10**, a multiplication of the mapped grey; saved in the norns home.
- Everything behind `NORNS_LINUX_DESKTOP`; the Mac keeps its layout, its greys and its code paths.

## 1. Where the box and the screen are drawn, and how every element is placed

### 1.1 Files

- **`matron/src/platform/macos/device_skin.c` / `.h`**: the box, bezel, knobs, keys, buttons, fader and MUTE, the hit testing and the screen's place. Pure cairo, shared by the Mac app and the Linux build (the folder name is historical; `matron/src/platform/common/desktop_shell.h` maps it for Linux). Tests: `macos/tests/device_skin_test.c` (hit tests, PNG renders), built by `linux/tests/run_all.sh` as `c:device_skin`.
- **`matron/src/platform/macos/sdl_bridge.cc`** (shared, with `#ifdef`s): creates the window (`SKIN_W + 2*SKIN_MARGIN` = 992 x 662 points, resizable, high-DPI), calls `skin_geom`, keeps a `static_layer` (box, bezel, labels) and draws controls and the screen on top (`redraw`, `draw_oled`); the screen's pixels arrive in `present()` into the `oled` surface (128 x 64); mouse on the screen (MIX page) uses `skin_oled_pixel`; screenshot (`save_screenshot`) and GIF (`oled_levels`, `gif_writer.c`) read the same `oled` surface.
- `matron/src/hardware/screen/sdl.cc` (the `screen:sdl` backend: the cairo surface norns draws on, in grey, level/15) and `matron/src/hardware/screen.cc` (`screen_brightness`, `screen_contrast`, `screen_gamma`, which end in `ssd1322_set_*`; on the desktop `platform/macos/hardware_null.cc` makes those no-ops).

### 1.2 How the size and position of each element are defined

Everything is in **layout units**, the box is `SKIN_W x SKIN_H = 960 x 630`, `SKIN_MARGIN 16`; `skin_geom()` fits the box plus margin into the canvas: `s = min(w/992, h/662)` device pixels per unit, origin centred. Constants in `device_skin.c` (units):

| element | position / size |
|---|---|
| box | 0,0 .. 960 x 630, corner radius 22 |
| bezel (the black recess) | x 77, y 356, 417 x 220 (outer lip 3 more) |
| screen | 128 x 64 pixels centred in the bezel; `bezel_pad = 14`; `px = floor(min((417-28)*s/128, (220-28)*s/64))` **device pixels per screen pixel, a whole number** (3.04 -> 3 at s = 1: the screen is 384 x 192 units, in the 389 x 192 interior) |
| K1 | (109, 252) radius 31 |
| K2, K3 | (594, 542), (749, 542) |
| E1 | (216, 252), washer radius 38, knob 31 |
| E2, E3 | (672, 420), (827, 420) |
| page buttons | row at y 70, 70 x 40 each, x = 77 153 229 305 (MIX TAPE HOME PARAMS), 398 474 550 626 (MIC GRID ARC KEYS), 719 795 (MAIDEN MANUAL) |
| OUT fader | x 913, travel y 196..486, cap 34 x 18 |
| MUTE | (886, 520) 54 x 34 |
| labels K1..E3 | drawn at 45 degrees below-right of each control |

`skin_hit()` tests the same constants; `skin_oled_pixel()` and the MIX-page mouse code use `oled_x/oled_y/oled_px` of `skin_geom_t` (integers); the partial redraw of the screen alone uses `128 * oled_px + 2*pad`.

### 1.3 The proposed layouts (only the screen grows; the box, the window, the sizes of all controls and the page buttons, fader and MUTE do not change)

Rule (`ui-previews/gen_variant.py`): screen size = factor x 3 device pixels per screen pixel; bezel = screen + 14 on every side; bezel left edge 36 units from the box edge (now 77), bottom edge at y 600 (now 576); K2, K3, E2, E3 move right by round((factor - 1) x 48) units.

| factor | pixels per screen pixel | screen (units) | bezel x | bezel y | K2, K3, E2, E3 move | space bezel -> K2 well | space E1 washer -> bezel |
|---|---|---|---|---|---|---|---|
| now | 3 (whole) | 384 x 192 | 77..494 | 356..576 | 0 | 69 | 66 |
| +20 | 3.60 | 461 x 230 | 36..524.8 | 341.6..600 | +10 | 48 | 52 |
| +22 | 3.66 | 468 x 234 | 36..532.5 | 337.8..600 | +11 | 42 | 48 |
| +25 | 3.75 | 480 x 240 | 36..544 | 332..600 | +12 | 31 | 42 |

Left margin of the bezel 36 (was 77), bottom margin 30 (was 54). In the pictures K1 and E1 sit above the screen's left half as before, the right cluster stays clear of the OUT fader (E3's washer ends 19 units from the fader cap at +25).
**What changes in the code for this** (inside `#ifdef NORNS_LINUX_DESKTOP`, so the Mac build compiles today's numbers): the constants above in `device_skin.c`; `skin_geom_t` gets a `double oled_unit` (device pixels per screen pixel, fractional) next to `oled_px`, used by `skin_draw_oled`, `skin_oled_pixel`, the partial-redraw rectangle and the mouse code in `sdl_bridge.cc`; `skin_draw_oled` draws with nearest neighbour at that scale (the existing `CAIRO_FILTER_NEAREST`, only the scale becomes fractional). At other window scales `s` the unit is `3.75 * s` (not floored), so the screen is always 25 percent bigger relative to today's size at that scale, rather than jumping between whole numbers.

### 1.4 The +33 percent layout: the screen at exactly 4 device pixels per screen pixel (`layout-plus33.png`, `layout-plus33-wider-box.png`)

4 device pixels per screen pixel is a whole number, so every screen pixel is a 4 x 4 block: crisp and even, no uneven blocks (`zoom-letters-today-25-33.png`). The screen becomes **512 x 256 units** (today 384 x 192, +33.3 percent in both directions; the bezel 540 x 284 against 417 x 220 is +29.5 percent wide and +29.1 percent high because the 14 unit frame stays).

**Recommended variant `layout-plus33.png`: no growth.** Box 960 x 630 units, window **992 x 662 pixels at scale 1 (unchanged: 0 percent wider, 0 percent higher)**. What moves or changes (nothing changes size: keys, encoders, buttons, fader, MUTE, labels keep their sizes):

| element | today | +33 |
|---|---|---|
| bezel | x 77..494, y 356..576 (417 x 220) | x 36..576, y 316..600 (540 x 284) |
| K1, E1 | (109, 252), (216, 252) | 30 units up: (109, 222), (216, 222) |
| K2, K3 | (594, 542), (749, 542) | (634, 542), (764, 542): K2 +40, K3 +15; spacing 155 -> 130 |
| E2, E3 | (672, 420), (827, 420) | (712, 420), (842, 420): E2 +40, E3 +15; spacing 155 -> 130 |
| page buttons, OUT fader, MUTE, box | | unchanged |

Spaces left: bezel to K2's well 27 units (now 69), E1's washer to the bezel 56 (now 66), E3's washer to the fader cap 16 (now 31), bezel to the box's left edge 36 (now 77) and its bottom edge 30 (now 54).
**What looks compromised:** (1) the right cluster is **tighter**: K2-K3 and E2-E3 are 130 units apart instead of 155 (-16 percent), so the gap between the two encoders' washers is 54 units instead of 79; E3 is close to the fader (16 units). It still reads as the same device in the picture, but it is no longer the proportions of the standard norns legend, which the layout otherwise follows. (2) The screen is now **42 percent of the box's width** and nearly touches the bottom corners' curve (bezel 30 units above the bottom, 36 from the left); the box's brushed face looks fuller on the left and emptier at the top: between the page buttons and the screen there is now a 142 unit band that K1 and E1 fill. (3) The page buttons' left edge (x 77) was aligned with the bezel's left edge; now it no longer is (the bezel starts 41 units further left). (4) K1 and E1 sit 30 units higher than on a standard norns.

**Alternative `layout-plus33-wider-box.png`: the box grows in width by 26 units only.** Box **986 x 630 units** (+2.7 percent wide, 0 percent high), window **1018 x 662 pixels** (+26 pixels = +2.6 percent wide, 0 percent high) at scale 1. K1/E1 and the bezel as above; K2, K3, E2, E3 keep their spacing (155) and move right by 38; the OUT fader and MUTE move right by 26 so the right margin stays. Spaces: bezel to K2's well 31, E3's washer to the fader cap 19. Compromised: only the left/right balance (the bezel's left margin 36 against about 47 on the right of the fader) and the same shifts of K1/E1 and the buttons' alignment; the encoder spacing stays as on the device. If the owner would rather keep the proportions of the cluster than the window size, this is the one.

At other window scales the window and screen scale together (the screen's whole number of pixels per screen pixel, 4 at scale 1, becomes `floor(4 s)` in the existing code; at scale 1.5 that is 6, which is +50 percent of 4 and still even: the **even look is lost only when 4 s is not a whole number**, as at today's 3.04 which already floors). This is the one case where today's code (whole pixels only, no `oled_unit`) would be enough for +33 percent at scale 1.

### 1.5 +25 percent (3.75): how many screen pixels come out one device pixel wider, and how it looks on a letter

3.75 = 15/4: every four screen pixels take 15 device pixels, so the pixel sizes repeat 4, 4, 4, 3. Counted by the nearest-neighbour rule that the preview and the planned code use (destination pixel d shows screen pixel floor((d + 0.5)/3.75)):
- **columns:** 96 of the 128 screen columns are **4 device pixels wide (75 percent)** and 32 are 3 wide; the screen is 480 device pixels wide;
- **rows:** 48 of 64 screen rows are 4 high and 16 are 3 high; 240 device pixels.
Against today's even 3, that is **three of every four screen pixels one device pixel wider, and one of four unchanged**, in each direction. For comparison (same rule): +20 percent (3.6): 77 of 128 columns 4 wide, 51 3 wide; +22 percent (3.66): 84 of 128 4 wide, 44 3 wide; +33 percent (4): all 128 the same, 4.
**On a letter** (`zoom-letters-today-25-33.png`, the word LEVELS at 8x): a stroke of one screen pixel is **4 or 3 device pixels thick**, in a repeating order; so the vertical stem of an L can be 4 wide while the next letter's stem is 3, and the three bars of an E are not all the same thickness (one is 3 where the others are 4). Letters stay crisp and recognisable and the unevenness is the width of one device pixel (25 percent of a stroke); at normal size it reads as slightly irregular stroke weight between letters, not as blur. With four-by-four blocks (+33) it is gone.

## 2. OLED brightness and contrast: upstream, and what the desktop build has to do

**Upstream (monome/norns, compared with this repository: the same code):** the OLED is an SSD1322 whose *chip* is set from Lua. `lua/core/screen.lua` loads `_path.display_settings` (`dust/data/system.display`, a Lua table `return {brightness=15,contrast=127,gamma=1.0}`) and on the first `screen.update()` calls `_norns.screen_brightness(0..15)` (the chip's master brightness), `_norns.screen_contrast(0..255)` (segment current) and `_norns.screen_gamma(g)` (`ssd1322.cc`: the grey-scale table of 15 entries = `round(255 * (level/14)^g)`, g from 1.0 up, so upstream can only *darken* the mid levels). The page is `lua/core/menu/display.lua` (a calibration bar of the 16 levels, BRIGHTNESS, CONTRAST, GAMMA; saves `system.display` on every change), reached through SYSTEM > SETTINGS > DISPLAY; `SYSTEM > SETTINGS > RESET` deletes the file. **On this desktop build:** the chain ends in `hardware_null.cc` (no-ops) and `lua/core/menu/system.lua` hides SETTINGS on a computer (`NORNS_PLATFORM`), so brightness, contrast and gamma exist in Lua and do nothing. The screen's pixels reach the window exactly as cairo drew them: level n is grey 17 n (15 -> 255), with anti-aliased greys between for text edges.
**Which levels the dim text uses:** the norns menus draw with **level 15** for the selected line and **level 4** for everything else (61 of the 84 fixed-level `screen.level` calls in `lua/core/menu*` use 4 (27) or 15 (34)); also 2 (11 calls), 1 (6), 3, 8 (2 each), 5, 10 (1 each). Level 4 is grey 68 (27 percent), level 2 is 34 (13 percent), level 1 is 17 (7 percent): the last two are nearly invisible on the black. Scripts use all 16.
**The grey options (exact: `ui-previews/grey-levels.txt`, the curve is evaluated for every grey 0..255, so the anti-aliased edges follow it; 0 and 15 stay):**

| level | today | gamma 0.7 | gamma 0.5 |
|---|---|---|---|
| 1 | 17 (7 %) | 38 (15 %) | 66 (26 %) |
| 2 | 34 (13 %) | 62 (24 %) | 93 (36 %) |
| 3 | 51 (20 %) | 83 (33 %) | 114 (45 %) |
| **4 (the dim text)** | **68 (27 %)** | **101 (40 %)** | **132 (52 %)** |
| 8 | 136 (53 %) | 164 (64 %) | 186 (73 %) |
| 12 | 204 (80 %) | 218 (85 %) | 228 (89 %) |
| 15 | 255 | 255 | 255 |

Mapping: out = 255 x (in/255)^gamma. The **brightness setting** multiplies the mapped grey: out = round(map(in) x percent / 100) (`brightness-*.png` use 100, 70, 40 percent with gamma 0.7).
**Why a mapping and not "change the menu to level 7":** a table affects every script and is what the device's own gamma/brightness settings do (they too act on the whole screen); changing the menu's level numbers would only help menus, would touch shared Lua (`lua/core/menu/*.lua`, also the Mac's) and would not fix scripts' own dim text. Mapping it is, with "device" (identity) as an option.

**What the Linux desktop build has to do**
1. **Colour mapping in one place in the bridge.** Keep `oled` as the raw image from the screen backend (levels), add a mapped copy `oled_view` made in `present()` through a 256-entry table and the brightness; `draw_oled` and `save_screenshot` read `oled_view`. The table is rebuilt when the setting changes (one function). On the Mac the table is the identity and not applied (the `#ifdef`).
2. **GIF.** `oled_levels()` quantises the surface to 16 levels and `gif_writer.c` writes a fixed grey palette `i * 17`. With a mapping the quantising would merge levels, so the frames keep the **raw** levels (from `oled`, as now) and the **palette is the mapped grey of each level** (a table argument to `gif_begin`, default the old palette: the Mac call is unchanged). Recorded frames then match the window; a setting changed during a recording uses the table at encode time (noted, accepted).
3. **Screenshot PNG** is written from `oled_view` (scaled 4x nearest as now), so it equals the window's screen pixel for pixel.
4. **Lua side.** A new page `SCREEN` for SYSTEM, below AUDIO: `lua/core/menu/system.lua` computer list becomes `DEVICES, AUDIO, SCREEN, MODS, RESET, RESTART` (inside the existing `NORNS_PLATFORM` block, the device's list is untouched); `lua/core/menu.lua` registers `m["SCREEN"]` the same way as AUDIO; the page (`lua/core/menu/screen_settings.lua`, new) shows the 16-level calibration bar of `display.lua`, BRIGHTNESS (E3: 100 down to 10, steps of 10) and GREYS (DEVICE, BRIGHT = gamma 0.7 (default), BRIGHTER = gamma 0.5), K2 back. It calls one new function, `_norns.screen_look(percent, grey_mode)`, registered in `weaver.cc` and implemented in the bridge only for the Linux desktop (a no-op elsewhere), so the existing `_norns.screen_brightness/contrast/gamma` chip calls and `display.lua` stay untouched.
5. **Where it is saved: `screen.conf` in the norns home**, next to `audio.conf` (`brightness=100`, `greys=bright`), read by Lua at start (before the first `screen.update`) and written on every change; RESET (`lua/core/menu/reset.lua`) deletes it on the desktop like `system.display`. Environment `NORNS_SCREEN_BRIGHTNESS` / `NORNS_SCREEN_GREYS` may override it for tests. Reason for a new file rather than `dust/data/system.display`: that file's `brightness`/`gamma` mean the *chip's* (a gamma of at least 1) and a device's file copied to a desktop must not suddenly darken it; and a norns-home file is where the other desktop settings already are.

## 3. How it is guarded so the Mac stays as it is

- Layout constants, `oled_unit`, the fractional drawing, `oled_view`, the table, `screen_look` and the SCREEN page: `#ifdef NORNS_LINUX_DESKTOP` in C; in Lua `os.getenv("NORNS_PLATFORM") ~= nil` (set only by `linux/norns.sh`; the Mac launcher does not set it) as `system.lua` already does. The Mac compiles and behaves as today; `gif_begin` keeps its signature (new optional argument) and palette default.
- `macos/` is not edited; the tests for the Mac layout (`macos/tests/device_skin_test.c`) are built without the define and keep today's expectations.

## 4. Tests I would write first (each fails before the change)

1. **Layout (pixel and geometry), `linux/tests/device_skin_linux_test.c`** built with `-DNORNS_LINUX_DESKTOP`: no control circle or button overlaps the bezel's rectangle with at least 12 units of space; the bezel is inside the box with 24 units from the edges; K1, E1, buttons, fader, MUTE unchanged; K2, K3, E2, E3 moved by exactly the nudge; the screen is 1.25 x the old size (units) and centred in the bezel; render a PNG at 992 x 662 and at one smaller and one larger size and check that the screen's pixel rectangle is black bordered, within the bezel and that its width is 480 +- 1 device pixel at s = 1. The Mac test stays as it is and still passes without the define.
2. **Hit and mouse mapping:** `skin_hit` on the moved controls; `skin_oled_pixel` maps the four corners and the centre of the screen to the pixels 0/127 and 0/63 and rejects the bezel; with the fractional unit, the pixel boundaries are monotonic (no gaps, no double pixels).
3. **Level mapping (`grey_map_test.c`):** the three tables: 0 -> 0 and 15 -> 255, monotonic, level 4 = 68, 101, 132; brightness 100 is the identity, 40 percent gives round(x * 0.4); a mapping never exceeds 255.
4. **Setting saved and applied (`linux/tests/screen_settings_test.lua` plus a headless boot):** the page's functions write `screen.conf` (`brightness=70`, `greys=bright`), a fresh start reads it and `_norns.screen_look` is called with the same values; a broken or missing file means the defaults; RESET deletes it; the SYSTEM list on a computer has SCREEN below AUDIO and on the device it does not.
5. **Screenshot and GIF match the window:** under Xvfb with `screen.conf` at brightness 40: crop the window's screen rectangle (xwd), take a screenshot through the window menu, scale it down (or the window up) and compare pixel values on a grid of sample points within 1; record a short GIF, read its palette (the 16 entries are the mapped greys) and the frame indices, and compare against the window crop the same way. With the Mac-style defaults (`greys=device`, 100) the images equal today's.
6. **Nothing else moved:** a screenshot of the window with `greys=device` and brightness 100 compared with today's window outside the screen's rectangle and the moved controls (a regression guard for the box, buttons and fader).

## 5. Risks

- **Uneven pixels:** at 3.66 and 3.75 device pixels per screen pixel, nearest neighbour makes some columns one device pixel wider. Small text may look slightly ragged; bilinear is softer. Decide from the pictures, ideally on the laptop's real screen (Cinnamon, 100 percent scaling, and a HiDPI setting if the owner uses one).
- **Window scales:** the 25 percent holds at every window size because the unit scales with `s`, but at small windows the screen pixel falls below 3 device pixels and gets blurry just as today's does.
- **The mapping changes how every script looks** (mid greys brighter). Scripts that draw faint hints with level 1 to 3 will show them more strongly; a "DEVICE" option restores the old look.
- **Gamma below 1 is outside the device's range** (upstream gamma is at least 1): a script's screenshot on a norns will not match the desktop one by design; the SCREEN page should say "desktop only".
- **GIF with a changing setting** (palette at encode time); **screenshots in existing documents** will differ from older ones.
- **Shared files** (`device_skin.c`, `sdl_bridge.cc`, `gif_writer.c`, `sdl.cc`): every edit sits behind the macro, but the Mac app compiles them too; the Mac build was not available here and cannot be run (a Mac check is on the owner's list).
- **Hit areas and labels** near the right cluster move by 10 to 12 units: trivial for the mouse, but any user-made skin or screenshot with annotated positions will differ.
- **The previews are a stand-in:** the real window with the real new code could differ slightly (for example the anti-aliasing of the screen's edge and the partial redraws).

## 6. The later detachable screen (not part of this step; only notes)

- **Easier:** the screen already is one 128 x 64 `oled` surface that is drawn by one function (`draw_oled`) and already goes to a second kind of window in the same bridge (the grid, arc and keys are separate SDL windows with their own `pane_open`, resize and close handling, `sdl_bridge.cc`); `skin_oled_pixel` and the mouse code take a geometry, so a second geometry for a free-standing window is a small step; the grey table, brightness, screenshot and GIF read `oled`/`oled_view` and do not care which window shows it.
- **Harder:** the code assumes one `the_window` (`present()` drops frames for any other window, the keyboard focus and `redraw` use it), the screen's position is part of `skin_geom_t` and `static_layer`, the in-window menu is drawn over the main window's screen, and the integer/fractional unit logic must then handle a window of any size (a free resize needs the unit to scale and the aspect to stay 2:1).
- **What the main window should show while the screen is detached:** **keep all controls where they are and show a dark placeholder where the screen was** (recommended): nothing moves, the keys and encoders still work and the box keeps its look and its size; a small label ("screen in its own window") and a click or a button to bring it back. Collapsing the box would move every control and change the window size, which makes the layout unstable for a feature that is supposed to be a convenience.

## 7. Reproducing the previews

`docs/port/ui-previews/make_previews.sh` (needs a built norns: `linux/build.sh`). It starts the real norns headless, loads `uipreview.lua`, opens PARAMS, saves the screen image and the real window, then draws the layouts and the grey and brightness variants. Files and what is real code: `docs/port/ui-previews/README.md`.
