// linux/tests/font_widths_dump.c <font file> <size>: the text metrics of the norns screen font, for the page width test (page_width_test.lua), measured by cairo
// the way matron's screen.cc sets it up (FreeType face, size, no hinting options changed). prints
//   C <code> <x_advance> <x_bearing> <ink width>     for the printable ASCII characters
//   S <ink width of the whole string> <string>       a few whole strings, so the test can check its own arithmetic against cairo
#include <cairo-ft.h>
#include <cairo.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s font size\n", argv[0]);
        return 2;
    }
    FT_Library lib;
    FT_Face face;
    if (FT_Init_FreeType(&lib) || FT_New_Face(lib, argv[1], 0, &face)) {
        fprintf(stderr, "cannot open %s\n", argv[1]);
        return 1;
    }
    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 128, 64);
    cairo_t *cr = cairo_create(surf);
    cairo_set_font_face(cr, cairo_ft_font_face_create_for_ft_face(face, 0));
    cairo_set_font_size(cr, atof(argv[2]));
    for (int c = 32; c < 127; c++) {
        char s[2] = {(char)c, 0};
        cairo_text_extents_t e;
        cairo_text_extents(cr, s, &e);
        printf("C %d %.6f %.6f %.6f\n", c, e.x_advance, e.x_bearing, e.width);
    }
    const char *strs[] = {"SEEDED", "Hello World 0123", "mi-UGens: 10f6824, shipped with Verdandi 0.1~git20261106.3393.230f7ba8", "..", "W i l"};
    for (int i = 0; i < 5; i++) {
        cairo_text_extents_t e;
        cairo_text_extents(cr, strs[i], &e);
        printf("S %.6f %s\n", e.width, strs[i]);
    }
    return 0;
}
