# Box style previews (docs/port/box-style-plan.md)

| file | what it is |
|---|---|
| `box-style-dark-vs-aluminium.png` | picture 1: the real aluminium window (real skin code) next to the pixel style, dark matt default (**stand-in**) |
| `box-style-light-and-colour.png` | picture 2: the pixel style in the LIGHT and COLOUR sets, PRESET list and SAVE/DELETE rows on the screen (**stand-in**) |
| `make_box_pictures.py` | makes both: `python3 make_box_pictures.py <out dir>` (needs PIL, cairo's headers, a C compiler; uses `../ui-previews/render_preview.c` and `matron/src/platform/macos/device_skin.c` with `NORNS_LINUX_DESKTOP`, only read) |
| `check_layout.py`, `layout-check.txt` | the pixel layout table with today's numbers, the change in percent and the clearance checks (0 failed) |

The pixel windows and the BOX page are stand-ins: none of it exists in the product. Nothing here changes the product.
