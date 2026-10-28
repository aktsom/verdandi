/* geom_table.c: what skin_geom() of the real device_skin.c does at window sizes from 33 to 200 percent of the design size (992 x 662): the scale s, the
 * whole number of device pixels per screen pixel (oled_px), the screen's size, what it would be if it scaled with the window (px per screen pixel x s, no
 * flooring), and the difference. built with and without -DNORNS_LINUX_DESKTOP: the Linux layout and the Mac layout. */
#include <stdio.h>
#include "device_skin.h"
int main(void) {
    static const int pct[] = {33, 50, 60, 75, 80, 100, 125, 130, 150, 160, 200};
    printf("%6s %8s %8s %6s %10s %10s %9s\n", "window", "w x h", "scale s", "px", "screen w", "ideal w", "smaller");
    for (unsigned i = 0; i < sizeof pct / sizeof pct[0]; i++) {
        int w = (SKIN_W + 2 * SKIN_MARGIN) * pct[i] / 100, h = (SKIN_H + 2 * SKIN_MARGIN) * pct[i] / 100;
        skin_geom_t g;
        skin_geom(w, h, &g);
        // ideal: the screen of the design size (px 4 on Linux, 3.04 on the Mac: the bezel's interior over 128) scaled with the window
#ifdef NORNS_LINUX_DESKTOP
        double design = 4.0;
#else
        double design = 389.0 / 128;
#endif
        double ideal = 128 * design * g.s, got = 128.0 * g.oled_px;
        printf("%5d%% %4dx%-4d %8.3f %6d %10.0f %10.1f %8.1f%%\n", pct[i], w, h, g.s, g.oled_px, got, ideal, 100 * (1 - got / ideal));
    }
    return 0;
}
