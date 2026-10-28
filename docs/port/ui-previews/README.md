# UI previews (plan only: no product code changed)

All images are made by `make_previews.sh` (run it from anywhere; it needs a built norns, Xvfb, xdotool, ImageMagick, a C compiler and cairo's headers).
The page on the screen is the parameter list of PARAMS > EDIT, with one highlighted line (level 15) and dim lines (level 4).

| file | what it is |
|---|---|
| `layout-current-REAL-window.png` | the real window of the real norns under Xvfb, today's layout (the product, unchanged) |
| `layout-current-REAL-window-params-page.png` | the same, the PARAMS main page |
| `layout-current-rendered.png` | today's layout drawn by `device_skin.c` through the preview renderer. It differs from the real window by an RMSE of about 2 % (the LED glow and the screen's anti-aliasing), so the renderer is a fair stand-in |
| `layout-plus20.png`, `layout-plus22.png`, `layout-plus25.png` | the screen 20, 22 and 25 percent bigger (3.6, 3.66 and 3.75 device pixels per screen pixel; today 3), nearest-neighbour; box and window unchanged, the other controls nudged (`../ui-plan.md` section 1.3) |
| `layout-plus22-smooth.png`, `zoom-nearest-vs-smooth.png` | the +22 layout with a bilinear screen, and a 4x zoom of the text of both |
| `layout-plus33.png` | the screen at exactly 4 device pixels per screen pixel (+33 percent, whole pixels): box and window the same size, the cluster of K2 K3 E2 E3 re-spaced, K1 and E1 moved up (`../ui-plan.md` section 1.4) |
| `layout-plus33-wider-box.png` | the same screen with the box and window 26 units wider and the cluster's spacing kept (the alternative) |
| `zoom-letters-today-25-33.png` | the word LEVELS at 8x: today (3 px), +25 percent (3.75: uneven) and +33 percent (4: even) |
| `layout-compare.png` | the real window and the five layouts side by side (half size): today, +20, +22 / +25, +33, +33 wider box |
| `oled-edit.png` | the screen image (128 x 64) captured from the real norns; `UIPREVIEW_REUSE_CAPTURE=1 make_previews.sh` redraws everything else from it without starting norns |
| `grey-current.png`, `grey-gamma07.png`, `grey-gamma05.png`, `grey-compare.png` | the same page with today's greys and the two brighter options, current layout; `grey-levels.txt` is the exact table for all 16 levels |
| `brightness-100.png`, `brightness-70.png`, `brightness-40.png`, `brightness-compare.png` | the +22 layout with grey option gamma 0.7 at three brightness settings |

| `layout-ui-a-labels.png`, `layout-ui-a-nolabels.png`, `layout-ui-a-labels-muted.png` | round 2, arrangement A (no OUT slider, MUTE in the top row, keys and encoders 15 percent bigger, screen at 4 px; box and window as today), with and without the K and E text, and with MUTE on (`../ui-plan.md` section 1.6) |
| `layout-ui-b-labels.png`, `layout-ui-b-nolabels.png` | arrangement B (alternative: encoders and keys in two bands) |
| `layout-compare-ui.png` | today's real window against A (labels, no labels), B (labels, no labels) and A with MUTE on |
| `ui-numbers-*.txt`, `ui-checks-*.txt`, `ui-hit-check-*.txt` | the exact positions, the spacing checks and the result of the hit test (`hit_check.c`, the variant's real `skin_hit`) for each arrangement |

| `layout-margin-compare.png`, `layout-margin-*.png`, `margin-corner-compare.png`, `ui-margins.txt` | round 2b: the Mac layout as the reference, today's Linux layout and three options for the margin around the screen, with measurements (`../ui-plan.md` 1.8) |
| `resize-real-*.png`, `resize-optionA-*.png`, `resize-compare.png`, `resize-zoom-80.png`, `ui-resize-numbers.txt` | round 2b: the real window resized to 60..160 percent (today), option A simulated, and the screen scale at every size (`../ui-plan.md` 1.9) |
| `base/` | the product's `device_skin.c/.h` before the Linux layout table: the generators of rounds 1 and 2 patch these copies |

What is real code and what is not: the **screen content** comes from the real norns (menu code, fonts, the screen's own greys). Today's window is the real window. The **layouts** are drawn by the product's own `device_skin.c`
(`gen_variant.py`, `gen_variant33.py` and `gen_variant_ui.py` and `gen_variant_margin.py` make a copy with other constants; the product file is only read). **Not** product code: drawing the screen at a fractional pixel size, the grey table and the brightness (they do not exist yet).
The other files: `capture.lua` and `uipreview.lua` (what norns is told to show), `render_preview.c`, `grey_tables.py`.
