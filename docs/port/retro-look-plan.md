# A more retro pixel-art look for the pixel box style (PLAN ONLY: nothing is built)

Linux desktop build only (`NORNS_LINUX_DESKTOP`, `matron/src/platform/linux/box_style.c`). `macos/` is only read. The aluminium style does not change at all. All five colours stay customizable; **no colour is removed: the ramp gets more shades, not fewer.** Pictures: section 4 (two, today's code next to stand-ins).

## 1. How the pixel style is drawn today, and where each lever changes it

**Source:** `matron/src/platform/linux/box_style.c` (+ `box_palette.c` for the shades, `box_style_font.inc`). The box is a **block image** of `BS_W x BS_H` = 496 x 331 blocks (`BS_BLOCK` = **2 layout units** per block, `BS_MARGIN` 8 blocks), ARGB, in two layers: *static* (surround, hard shadow, box, bezel; cached by the colours) and *controls* (buttons, toast, keys, encoders; cached by the control state). `place()` puts a layer in the window: crisp when `k = BS_BLOCK * s` is within 0.01 of a whole number (the layer is enlarged by that multiple), else enlarged and filtered (`BEST`); while a window is dragged `skin_set_fast` takes the cheap path (`box-style-plan.md` section 8). Positions snap to the grid with `bx()` (nearest block, so a layout position moves by at most one unit today); the hit areas are the drawn shapes plus 2 units (`BTN_SLOP`), so they follow the snap.
**Palette:** every colour gets four shades, from `box_palette.c`: `base`, `dark` (x0.60: bottom/right bevel, pressed), `darker` (x0.36: outlines, surround), `light` (+30 percent towards white: top/left bevel, hover). **Shapes:** `draw_rr` (rounded rectangle: 1 block outline, `bevel` blocks of light on top/left and dark on bottom/right; corners are quarter circles), `disc` (circle with a lit and a dark crescent), `fill_rect`; the box corner radius is 11 blocks, buttons 3, keys 5 (bevel 2), encoders 20 blocks across. Text: the norns font at 1 text pixel = 1 block (2 units).
**The screen:** 128 x 64 pixels shown 512 x 256 units: **one screen pixel = 4 units = 2 x 2 blocks today**. Its place at 100 percent is (74, 335) in the window, i.e. (58, 319) in box units: 58 is on the 2-unit grid, 319 is 1 unit off it vertically (invisible today: the bezel round it is 2 blocks wide).

| lever | what it changes in the code |
|---|---|
| 1 block size | `BS_BLOCK`, `KEY_RADIUS`, `ENC_RADIUS`, corner radii, `bx()` snapping; the image size |
| 2 dithering | a new `dither(a, b, t, x, y)` used by the box face, keys, encoders in `box_style_render_static/controls` |
| 3 outlines and bevel | `draw_rr` parameters and the outline colour per part |
| 4 stepped circles | `disc` (rim, highlight, cap) |
| 5 texture | a pass after the box face in `box_style_render_static` |
| 6 button text | `draw_button`, `label_in`, `draw_text` |
| 7 sprites | a pass in `box_style_render_static` (grille) |
All of them are inside `box_style.c`'s block renderers: the layers, the caches, `place()`, the hit tests and the bridge do not change (except lever 1, below).

## 2. The levers, each judged

**2.1 Block size (recommend: 4 units).** *What it does:* 2 -> **4 units** makes every block twice as big and, because **one screen pixel is exactly 4 units, one block = one screen pixel**: the box and the norns screen are then drawn in the same pixel size, which is the strongest single retro cue and the cheapest. 3 units gives 1.33 blocks per screen pixel: the two grids never line up (rejected as the main look; used only in alternative B to show it). *Layout consequences of 4:* the grid is 240 x 157.5 blocks: the box height 630 units becomes **632 (158 blocks), 2 units taller**; every position snaps to 4 units (the shift is at most 2 units, today's at most 1); the screen's place moves to the grid (x 58 -> 60, y 319 -> 320 box units: 2 and 1 unit); the button width 70 -> 72 units (18 blocks), so the gap between two buttons (76 pitch) falls from 6 to 4 units (visible in the picture: PARAMS and MANUAL touch their neighbours' shadows); the hit areas are the drawn shapes + 2 units as today, so they move with the shapes by at most 2 units and no control moves relative to its drawing; **this lever therefore does change the geometry by up to 2 units**, and the plan says so as the cost of the look. The aluminium style is untouched (it does not use the block grid). *Crispness:* `k = 4 s` is a whole number every **0.25 of the scale** (windows 744, 992, 1240, 1488 wide, ...; today `2 s` is whole every 0.5), so the crisp case is twice as frequent; between them the filtered placement blurs a block edge by one device pixel, which is half as visible on a block twice as large. *Screen alignment:* at every size where the screen is a whole multiple, one block = one screen pixel.
**2.2 Dithering (recommend: sparing).** Ordered 4 x 4 Bayer, a pure function of the block's (x, y): the same picture every frame, no shimmer, no animation. Use it where a smooth shade step would be: on the **encoder face** (light to dark across the rim) and in a narrow band at the **top and bottom edge of the box face** (two shades, 14 blocks) — not over the whole face (alternative B shows why: a full-face dither is busy and tiring over hours; picture 2). Not on the keys and buttons in the recommendation (flat colour reads better under text). Checkerboard (2 x 2) is the strongest and the busiest; Bayer 4 x 4 at t < 0.55 is calm.
**2.3 Outlines and bevel (recommend: yes).** A hard **1-block outline in the part's own darkest shade** (not the box's: a gold key gets a dark gold line), a **1-block light top/left and dark bottom/right bevel** on buttons and keys (today keys have 2), a **1-block hard drop shadow** under buttons and keys in the box's dark shade, and **chamfered corners** (a 1 or 3 block stair-step instead of today's quarter circle, the 8-bit button look). Outlines are part of the part's own rectangle (inside its bounds), so they cannot overlap a neighbour (tested).
**2.4 Stepped chunky circles (recommend: yes).** Encoders: radius 10 blocks (diameter 20 blocks = 80 units, as now, at 4 units per block half the blocks of today): a 1-block outline, a rim of 2 blocks with a lit top-left and dark bottom-right crescent (3 steps), a 4-block pixel highlight (two 2-block runs), a darker inner cap, a 2 x 3 block notch for the detent (today: a round dot). At 4-unit blocks the circle is visibly stepped, which is the point.
**2.5 Texture (recommend: very sparse speckle, optional).** One speckle per ~190 blocks of free face, a hash of (x, y) (deterministic), a 10 percent shade change (never the base +-30 percent of today's light/dark), never within 1 block of a control, the bezel or the screen. Scanlines were tried (alternative B, every second row at 14 percent): readable but busy; not recommended.
**2.6 Button text (limited; recommend: keep the size, add a 2-unit shadow).** The labels cannot become block-sized: `MANUAL` is 33 text pixels wide, 66 units at 2 units per text pixel in a 70-72 unit button; at 4 units per text pixel it would be 132 units. So **the text stays at 2 units per text pixel (half a block)**, which is the one fine-grained thing left in the look. What is possible: a **2-unit drop shadow** in the button's darkest shade (not on a lit button: it blurs there, seen in a first drawing) and the lit button's inverse colours as today. A custom 3 x 5 pixel font at 4 units was calculated and does not fit either (`MANUAL` 6 x 4 blocks = 96 units).
**2.7 Small sprites (recommend: one, a grille).** Corner screws were tried and **do not fit**: the box corners are 11 blocks of radius and the buttons start 9 blocks from the edge, so a 5-block screw at the corner is outside the curve or touches the MIX button. Instead: a **grille of ten short slots** (2 x 6 blocks, a 1-block light lower edge) in the empty area above the toast's place (blocks 105-135 across, 28 down; the toast sits at y 166-184 units). It is hidden by the colour picker panel while that is open and does not collide with it. Optional; off in alternative A.

## 3. The recommended look and two alternatives, with parameters

Shade ramp for **every** part (7 shades, from its base; today's four are `s1`, `s2`, `s4`, `s5`): `s0` x0.22 (deepest: outlines, the hard shadow), `s1` x0.36 (surround), `s2` x0.60, `s3` x0.80, `s4` base, `s5` +30 percent, `s6` +60 percent (highlights). The colours still come from the five customizable ones; built-in looks DARK, LIGHT, COLOUR, MAC work as before (the ramp is a formula; a very light base saturates `s5`/`s6` to white and a very dark one collapses `s0`/`s1`, which the pixel style already handles with the existing minimum steps: `box_palette.c` keeps the shades at least 6 levels apart, to be extended to the new ones and tested for the four looks).

| parameter | **Recommended: "retro"** | A: "chunky 8-bit" | B: "dithered 16-bit" |
|---|---|---|---|
| block | 4 units | 4 units | 3 units |
| outline | 1 block, part's `s0` | same | same |
| bevel (buttons / keys) | 1 / 1 | 1 / 2 | 2 / 1 |
| corner | chamfer 1 (buttons), 3 (keys), 6 (box) | same | same |
| drop shadow under buttons/keys | 1 block, box `s1` | 1 block | none |
| encoder | 10-block disc, 2-block rim, 4-block highlight, cap | no cap, 2-block highlight | 3-block rim, dithered face, cap |
| dither | Bayer on encoder faces and the box's top and bottom 14 blocks | only the box's top/bottom band | encoders, keys, box band, buttons (checker) |
| texture | speckle 1 in 190, +-10 percent | none | speckle 1 in 110 and scanline hint (14 percent) |
| button text | 2-unit pixels, 2-unit shadow | 2-unit pixels, no shadow | same as A |
| grille | yes | no | no |
**What each costs in looks:** the recommendation keeps today's calm (flat key and button faces) and adds weight (outlines, shadows, chamfers) and character (grille, encoders); A is the plainest and cheapest; B has the most colour variety (dither makes extra apparent shades from the ramp) at the price of busyness.

## 4. Pictures
1. `retro-look-previews/retro-today-vs-recommended.png`: **left today's pixel style (the real code), right the recommended retro look (stand-in)**, both in the DARK look with the same screen: look at the key and encoder size and edge (stepped, outlined, with a drop shadow), the quieter flat faces, the barely visible speckle and the small grille, and that the buttons are as readable as before.
2. `retro-look-previews/retro-alternatives.png`: **left alternative A "chunky 8-bit" in the DARK look, right alternative B "dithered 16-bit" in the COLOUR look** (both stand-ins): look at A's plainness against the recommendation, and at how B's dither adds colour variety on the box and the keys but makes the whole face busy.
Stand-ins: all retro drawings and the screen text are Pillow stand-ins written for this plan (`make_retro_pictures.py`); only today's style is the real code's output. The stand-in is not the product code; details (exact chamfer stairs, the grille position) will move when it is built. Not shown: the pressed, hover and MUTE states, the toast, the hidden top row, the picker panel.

## 5. Interaction with the other pixel-box features
- **Hidden top row:** buttons are skipped as today; the grille and the speckle do not depend on them; MUTE chip when muted: one button drawn with the same retro parameters (chamfer, outline, shadow) and its lit inverse.
- **Pressed states:** a key or button sinks 1 block and loses its drop shadow and its top/left bevel (as today's "sinks one block"); hover = the `s5` face; lit buttons = inverse colours.
- **Toast pill:** a button-style pill with the same outline and chamfer; its text stays at 2-unit pixels.
- **Colour picker panel** (`colour-picker-plan.md`): its pixel look takes the same outline, bevel and block: the strips' 8-unit blocks become 4-unit blocks (about 116 across a 465-unit strip), same marker rule.
- **Aluminium style:** untouched; selected by STYLE as now.

## 6. Performance and the caches
- The cache keys do not change: the static layer by the five colours, the controls layer by state, enlarged copies by whole multiple, `skin_set_fast`. The layers get **smaller** (4-unit blocks: 248 x 166 blocks instead of 496 x 331, a quarter of the pixels), so rendering a layer is cheaper; `place()` enlarges by `k = 4 s` instead of `2 s` (same output size, so the same cost); a dither or a speckle is a per-pixel integer test on the cheap image: tens of microseconds. The aluminium golden hashes (24 renders) are not touched.
- A new style value could be added to `box.conf` (`style=pixel` stays; a new value `style=retro` would be added: decision 1, replace the pixel look or add a third style). Not measured: the stand-in is Python; the real timings come with the build (the existing `box_frame_test.sh` budget applies unchanged). Expectation from the numbers of `box-style-plan.md` section 8: the layer render was 1-2 ms in fast mode and 65-85 ms enlarged at in-between sizes; the retro look should be no slower.

## 7. Tests to write first
1. **Palette** (`box_palette_test.c`): the 7-step ramp for the four built-in looks and 1000 random colours: monotonic in luminance, s0..s6 distinct by at least a minimum step, the four old shades unchanged (`s1`, `s2`, `s4`, `s5` = today's `darker`, `dark`, `base`, `light`), an all-white and an all-black base handled.
2. **Dither patterns deterministic** (`retro_dither_test.c`): the Bayer pattern for fixed (x, y, t) gives known values; two renders are byte-identical; no pattern depends on time or on the state.
3. **Outlines do not overlap controls**: every control's drawn rectangle (outline, shadow included) is inside its own hit rectangle and does not intersect another control's rectangle; speckles and the grille never fall in a control, the bezel or the screen (checked on the rendered block image with the controls masked).
4. **Hit areas unchanged**: today's `box_style_hit` table at fixed points is the golden for the pixel style **at 2-unit blocks**; at 4 units each control's hit rectangle equals its drawn rectangle + 2 units, and differs from today's by at most 2 units (the stated snap); the screen's rectangle moves by at most 2 units.
5. **The aluminium style byte for byte**: `box_c_test.sh`'s 24 golden renders unchanged; the Mac skin test and the Mac compile of `device_skin.c` unchanged; the guard check extended to the new identifiers.
6. **Pixel/retro both selectable**: `style=pixel` still renders today's look byte for byte if decision 1 is "add a third style" (a golden for it too).
7. **Looks**: the four built-in looks and a random colour set render without a crash, with the text readable (contrast of font and buttons unchanged by the retro changes), and two renders are identical.
8. **Frame time and final image** (`box_frame_test.sh` for the retro look: dragged under budget; the settled image equals a cold draw).
9. **Mac unchanged**: `git diff -- macos/` empty; no change in `device_skin.c` except under `NORNS_LINUX_DESKTOP` if the layout snap needs a hook.

## 8. Risks
- **Geometry moves up to 2 units** with 4-unit blocks (section 2.1); a hit area is 2 units off its old place for the pixel style; the screen's place moves 1-2 units (its black bezel hides it).
- **Gap between the buttons shrinks** from 6 to 4 units; the labels PARAMS / MANUAL are tight (visible in the picture). Alternative: keep the buttons 70 units wide and draw 17.5 blocks as 17 + a half-block gap, or use 68 units (17 blocks).
- **Dither and speckle can tire the eye over hours**: both are kept to a small area and a small contrast; the owner should judge on the laptop (section 9); B is shown so that the contrast can be compared.
- **Very light or very dark colour sets:** the extended ramp saturates; the pixel style's existing minimum step logic must cover s0, s3 and s6.
- **Stand-ins are not the product**: chamfer shapes, the highlight and the grille will change when drawn by the real code; the display scale (a block of 4 units is 4 pixels at 100 percent and 5.4 on a larger window) and the owner's display are not measured.
- **Text stays fine-grained** (2-unit pixels) next to 4-unit blocks: a mismatch of scale that cannot be removed without changing the labels or the button size.
- Not testable here: the laptop's display and eyes; Muffin; added to the hardware checklist when built.

## 9. Decisions for the owner (my recommendation first)
1. A **new third style "RETRO"** next to ALUMINIUM and PIXEL (recommended: today's pixel look stays available), or replace PIXEL.
2. The **recommended** parameters (section 3), or A (plainer), or B (dithered).
3. **4-unit blocks** with the 2-unit geometry snap (recommended), or keep 2-unit blocks and take the retro character from outlines, chamfers and circles only.
4. Grille: yes (recommended) or no; speckle: yes at 1 in 190 (recommended), or none.
5. Button width: 72 units (18 blocks, recommended for symmetry) or 68 (17 blocks, keeps the gaps wider).
