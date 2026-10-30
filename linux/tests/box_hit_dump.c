/*
 * box_hit_dump.c: what every point of the window hits in the pixel style (docs/port/retro-look-plan.md, test 4: the hit areas of PIXEL do not change): a point every 4 layout units over the design size
 * window with the row shown and with it hidden, one character per point, printed as lines. box_pixel_hits_golden.txt is the output of the code before the retro looks. optional argument: the pixel look
 * (0 PIXEL, 1 RETRO, 2 8-BIT, 3 16-BIT) when the build has box_style_set_variant
 */
#include <stdio.h>
#include <stdlib.h>

#include "box_style.h"
#include "device_skin.h"

int main(int argc, char **argv) {
    skin_set_look(SKIN_STYLE_PIXEL, "2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea");
#ifdef HAVE_VARIANT
    if (argc > 1) {
        skin_set_pixel_look(atoi(argv[1]));
    }
#else
    (void)argc;
    (void)argv;
#endif
    skin_geom_t g;
    skin_geom(992, 662, &g);
    for (int shown = 1; shown >= 0; shown--) {
        for (int y = 0; y < 662; y += 4) {
            for (int x = 0; x < 992; x += 4) {
                int c = box_style_hit(&g, x, y, shown, 0);
                putchar(c == SKIN_NONE ? '.' : 'A' + (c % 26));
            }
            putchar('\n');
        }
        printf("--\n");
    }
    return 0;
}
