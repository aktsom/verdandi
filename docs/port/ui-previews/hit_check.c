/* hit_check.c: skin_hit() of a layout variant (made by gen_variant_ui.py) against its expectations (hits.h): every key, encoder and button centre (and the
 * rim of keys and encoders) hits itself, the gaps between button groups, the screen, the old place of the fader and of MUTE and the free band hit nothing. */
#include <stdio.h>
#include "device_skin.h"
#include "hits.h"
int main(void) {
    skin_geom_t g;
    skin_geom(SKIN_W + 2 * SKIN_MARGIN, SKIN_H + 2 * SKIN_MARGIN, &g);
    int bad = 0, n = (int)(sizeof CHK / sizeof CHK[0]);
    for (int i = 0; i < n; i++) {
        int got = skin_hit(&g, g.ox + CHK[i][0] * g.s, g.oy + CHK[i][1] * g.s);
        if (got != (int)CHK[i][2]) {
            printf("FAIL point %d (%.1f,%.1f): hits %d, expected %d\n", i, CHK[i][0], CHK[i][1], got, (int)CHK[i][2]);
            bad++;
        }
    }
    printf("hit_check: %d points, %d wrong\n", n, bad);
    return bad != 0;
}
