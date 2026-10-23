/*
 * menu_skin_test.c: platform/linux/menu_skin.c without a window
 *
 * cc -std=gnu11 -I matron/src/platform/linux $(pkg-config --cflags cairo) linux/tests/menu_skin_test.c \
 *    matron/src/platform/linux/menu_skin.c $(pkg-config --libs cairo) -lm -o /tmp/mst && /tmp/mst [png_dir]
 */

#include <stdio.h>
#include <string.h>

#include "menu_skin.h"

static int failures = 0;

#define CHECK(cond, ...)                                                                                               \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                                \
            printf(__VA_ARGS__);                                                                                       \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

static void add(menu_t *m, int id, const char *label, const char *hint, int disabled, int separator) {
    menu_item_t *it = &m->item[m->n++];
    memset(it, 0, sizeof *it);
    it->id = id;
    snprintf(it->label, sizeof it->label, "%s", label);
    snprintf(it->hint, sizeof it->hint, "%s", hint);
    it->disabled = disabled;
    it->separator = separator;
}

static void fill(menu_t *m) {
    memset(m, 0, sizeof *m);
    add(m, 1, "First", "Ctrl+1", 0, 0);
    add(m, 0, "", "", 0, 1);
    add(m, 2, "Second", "", 1, 0); // disabled
    add(m, 3, "Third", "F6", 0, 0);
    add(m, 4, "A much longer label than the others", "Ctrl+Shift+S", 0, 0);
}

int main(int argc, char **argv) {
    menu_t m;
    fill(&m);
    CHECK(!m.open, "closed at first");
    menu_skin_open(&m, 100, 100, 1.0, 800, 600);
    CHECK(m.open && m.hover == -1, "open, nothing hovered");
    CHECK(m.x == 100 && m.y == 100, "opens at the pointer (%g, %g)", m.x, m.y);
    CHECK(m.w >= 190, "at least the minimum width (%g)", m.w);

    // hit testing: rows are 26 units, a separator 9, the pad 6
    double y0 = m.y + m.pad;
    CHECK(menu_skin_hit(&m, 150, y0 + 5) == 0, "first row");
    CHECK(menu_skin_hit(&m, 150, y0 + 26 + 3) == -1, "a separator is no item");
    CHECK(menu_skin_hit(&m, 150, y0 + 26 + 9 + 5) == -1, "a disabled item is no item");
    CHECK(menu_skin_hit(&m, 150, y0 + 26 + 9 + 26 + 5) == 3, "fourth entry is item 3");
    CHECK(menu_skin_hit(&m, 50, 150) == -1 && !menu_skin_inside(&m, 50, 150), "outside");
    CHECK(menu_skin_inside(&m, m.x + 1, m.y + 1), "the corner is inside");

    // the keyboard skips the separator and the disabled item, and wraps
    menu_skin_move(&m, 1);
    CHECK(m.hover == 0, "down: first item (%d)", m.hover);
    menu_skin_move(&m, 1);
    CHECK(m.hover == 3, "down: skips separator and disabled (%d)", m.hover);
    menu_skin_move(&m, 1);
    menu_skin_move(&m, 1);
    CHECK(m.hover == 0, "down: wraps (%d)", m.hover);
    menu_skin_move(&m, -1);
    CHECK(m.hover == 4, "up from the first: the last (%d)", m.hover);

    // near the window's edge it moves back in
    menu_skin_open(&m, 790, 590, 1.0, 800, 600);
    CHECK(m.x + m.w <= 800 && m.y + m.h <= 600, "inside the window (%g+%g, %g+%g)", m.x, m.w, m.y, m.h);
    // a bigger scale makes it bigger
    menu_t big;
    fill(&big);
    menu_skin_open(&big, 10, 10, 2.0, 1600, 1200);
    menu_skin_open(&m, 10, 10, 1.0, 1600, 1200);
    CHECK(big.w > 1.8 * m.w * 0.9 && big.h > 1.9 * m.h, "scale 2 is about twice as big");
    menu_skin_close(&m);
    CHECK(!m.open && !menu_skin_inside(&m, 20, 20), "closed again");

    // draws something
    fill(&m);
    menu_skin_open(&m, 20, 20, 1.0, 400, 300);
    m.hover = 3;
    cairo_surface_t *img = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 400, 300);
    cairo_t *cr = cairo_create(img);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    menu_skin_draw(cr, &m);
    cairo_destroy(cr);
    cairo_surface_flush(img);
    const unsigned char *px = cairo_image_surface_get_data(img);
    int stride = cairo_image_surface_get_stride(img);
    // inside the panel: dark, outside: white
    CHECK(px[(30) * stride + 30 * 4] < 100, "the panel is dark");
    CHECK(px[(290) * stride + 390 * 4] > 240, "outside it stays white");
    if (argc > 1) {
        char path[512];
        snprintf(path, sizeof path, "%s/menu_skin.png", argv[1]);
        cairo_surface_write_to_png(img, path);
    }
    cairo_surface_destroy(img);
    printf("%s: %d failures\n", failures ? "FAILED" : "menu skin ok", failures);
    return failures != 0;
}
