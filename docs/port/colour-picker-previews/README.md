# Pictures of docs/port/colour-picker-plan.md

| file | what it is |
|---|---|
| `picker-pixel-dark.png` | the picker panel open over the box in the pixel style, DARK look. **The box, the buttons, the keys, the encoders and the screen's bezel are drawn by the real skin code** (`../box-style-previews/render_look.c`: `device_skin.c`, `box_style.c`). **The panel is a STAND-IN** (Pillow, in `make_picker_pictures.py`): the real panel does not exist yet. The text on the norns screen is a stand-in as well |
| `picker-aluminium.png` | the same in the aluminium look (default colours); same stand-ins |
| `make_picker_pictures.py` | makes both (needs Pillow, cairo and freetype; builds `render_look` itself) |
