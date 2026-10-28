# UI previews (plan documents; the pictures document the owner's decisions)

Made by `make_previews.sh` (run it from anywhere; it needs a built norns, Xvfb, xdotool, ImageMagick, a C compiler and cairo's headers, and sclang: the script loads an engine).
Everything is drawn by the product's own skin code (`matron/src/platform/macos/device_skin.c`, only read) or is a capture of the real norns window; nothing in the product is changed.
`UIPREVIEW_REUSE_CAPTURE=1` reuses `oled-edit.png` instead of starting norns for it, `UIPREVIEW_SKIP_RESIZE=1` keeps the `resize-real-*.png` that are here.

## Pictures and numbers that stay

| file | what it is |
|---|---|
| `layout-ui-a-nolabels.png` | **the chosen layout** (step 2: arrangement A without labels; `../ui-plan.md` 1.6, 1.7): a render by the skin code, PARAMS > EDIT on the screen |
| `layout-current-REAL-window.png` | the **real window** of the real norns under Xvfb with that layout built (the render above matches it: RMSE printed by the script) |
| `layout-margin-compare.png` | the black margin around the screen: the Mac layout (reference), today's Linux layout and the three options `abs`, `shrink` and `grow` (step 2b, `../ui-plan.md` 1.8; the recommended one is `grow`) |
| `resize-compare.png`, `resize-real-60.png`, `-80`, `-100`, `-130`, `-160` | the real window resized to 60, 80, 100, 130 and 160 percent of 992 x 662 (the `resize-real-*` files), and the comparison sheet with option A simulated (`../ui-plan.md` 1.9) |
| `grey-levels.txt` | the grey table: the 16 levels today and with gamma 0.7 and gamma 0.5 (`../ui-plan.md` section 2) |
| `ui-numbers-a.txt`, `ui-checks-a.txt`, `ui-hit-check-a.txt` | the exact positions of the chosen layout, its spacing checks and the result of `hit_check.c` (the skin code's real `skin_hit` on 30 points) |
| `ui-margins.txt` | the margin measurements: the Mac layout and each option, calculated and measured on renders with a white screen |
| `ui-resize-numbers.txt` | what `skin_geom` does at 33 to 200 percent of the window size, for the Linux layout and the Mac layout |
| `ui-colours.png`, `ui-brightness.png` | step 3 (`../ui-settings-plan.md`): the real window (PARAMS page) with the screen tinted by the plan's mapping: white / yellow / pink at brightness 1, and white at 1, 0.7, 0.4 (a stand-in, the setting is not built; made by `make_ui_settings_previews.py` from a real capture, the mapping is `ui_tint.py`) |
| `oled-edit.png` | the 128 x 64 screen image (PARAMS > EDIT) captured from the real norns, the input of every render |

## Sources the script and the plan use

`make_previews.sh`; `capture.lua`, `resize_capture.lua` and `uipreview.lua` (what the real norns is told to show); `render_preview.c` (draws a window from the skin code, a screen image, a grey table and a screen mode); `gen_variant_ui.py` (the chosen layout from a copy of the skin code's constants, with `base/`); `gen_variant_margin.py` (the margin options); `measure_margin.py`; `geom_table.c`; `hit_check.c`; `grey_tables.py`; `base/` (the product's `device_skin.c/.h` before the Linux layout table was added: `gen_variant_ui.py` patches these copies; see `base/README.md`).

## What was removed (nothing is lost)

The pictures of the options that were not chosen, and the intermediates, were deleted from this folder in the commit that adds this paragraph; **they are in the git history** (the parent of that commit, for example `git show 25916e1:docs/port/ui-previews/layout-plus25.png`): the screen +20, +22, +25 and +33 percent layouts, the wider-box and the arrangement B layouts, the with-labels and the MUTE-on variants, the smooth and nearest zooms, the grey and brightness pictures, the single margin options and the resize pictures of option A, `gen_variant.py` and `gen_variant33.py` (they made the +20 to +33 layouts), and the ui numbers of arrangement B.
`../ui-plan.md` still names those pictures where it discusses the options; read them as "in the history".
