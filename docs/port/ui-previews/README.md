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
| `layout-compare.png` | the real window and the three layouts side by side (half size) |
| `grey-current.png`, `grey-gamma07.png`, `grey-gamma05.png`, `grey-compare.png` | the same page with today's greys and the two brighter options, current layout; `grey-levels.txt` is the exact table for all 16 levels |
| `brightness-100.png`, `brightness-70.png`, `brightness-40.png`, `brightness-compare.png` | the +22 layout with grey option gamma 0.7 at three brightness settings |

What is real code and what is not: the **screen content** comes from the real norns (menu code, fonts, the screen's own greys). Today's window is the real window. The **layouts** are drawn by the product's own `device_skin.c`
(`gen_variant.py` makes a copy with other constants; the product file is only read). **Not** product code: drawing the screen at a fractional pixel size, the grey table and the brightness (they do not exist yet).
The other files: `capture.lua` and `uipreview.lua` (what norns is told to show), `render_preview.c`, `grey_tables.py`.
