# Pictures of docs/port/retro-look-plan.md

| file | what it is |
|---|---|
| `retro-today-vs-recommended.png` | left: **today's pixel style, drawn by the real code** (`../box-style-previews/render_look.c` with `box_style.c`, RENDER_STYLE=pixel); right: **the recommended retro look, a STAND-IN** (Pillow, `make_retro_pictures.py`: same layout table and five colours, the shade ramp of the plan, 4-unit blocks). DARK look |
| `retro-alternatives.png` | left: alternative A "chunky 8-bit" (stand-in, DARK); right: alternative B "dithered 16-bit" (stand-in, 3-unit blocks, COLOUR look) |
| `make_retro_pictures.py` | makes both (Pillow, cairo, freetype; builds `render_look` itself). The norns screen text is a stand-in too |
