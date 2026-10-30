# Box style previews (docs/port/box-style-plan.md)

| file | what it is |
|---|---|
| `box-style-dark-vs-aluminium.png` | picture 1: the aluminium window and the pixel style (DARK), **captures of the real window** with the real SYSTEM > BOX page |
| `box-style-light-and-colour.png` | picture 2: the pixel style in LIGHT (the PRESET list with his own looks and the star) and COLOUR (SAVE and DELETE), real captures |
| `make_box_real_pictures.sh` | makes both: `./make_box_real_pictures.sh <out dir>` (a built norns, Xvfb, xdotool, ImageMagick, PIL) |
| `tint-aluminium-four.png`, `tint-aluminium-contrast.png` | stage 1 of the colour work: the aluminium style in four tints and with contrasting key and button colours, next to the pixel style. The windows are drawn by the real skin code (`render_look.c`); the text on their screens is a stand-in |
| `make_tint_pictures.py`, `render_look.c`, `make_box_pictures.py` | make the tint pictures (the last one holds the stand-in screen helper and the first, stand-in version of the pixel renderer used before the code existed) |
| `check_layout.py`, `layout-check.txt` | the pixel layout table with today's numbers, the change in percent and the clearance checks (0 failed) |
