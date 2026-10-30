/*
 * midimap_hit_test.c: the window's hit test for the six controls that MIDI MAP learns by mouse (docs/port/midi-map-plan.md 2.4, test 3.6). for every style and pixel look (aluminium, PIXEL, RETRO, 8-BIT,
 * 16-BIT), at three window sizes: K1-K3 and E1-E3 are each hit somewhere, and the points that hit them are exactly the same with the row of page buttons shown or hidden, muted or not (only the buttons
 * depend on the row): a hidden top row or a changed style never changes which control a click picks. exit 0 = ok
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "box_style.h"
#include "device_skin.h"

static char *map_of(int w, int h, int shown, int muted) {
    skin_geom_t g;
    skin_geom(w, h, &g);
    skin_set_buttons_shown(shown);
    skin_note_muted(muted);
    char *m = malloc((size_t)(w / 4 + 1) * (h / 4 + 1) + 16);
    size_t n = 0;
    for (int y = 0; y < h; y += 4) {
        for (int x = 0; x < w; x += 4) {
            int c = skin_hit(&g, x, y);
            m[n++] = (c >= SKIN_K1 && c <= SKIN_E3) ? (char)('0' + c) : '.';
        }
    }
    m[n] = 0;
    return m;
}

int main(void) {
    int sizes[3][2] = {{992, 662}, {700, 470}, {1400, 930}};
    int fails = 0;
    for (int style = 0; style < 2; style++) {
        for (int look = 0; look < (style ? 4 : 1); look++) {
            skin_set_look(style ? SKIN_STYLE_PIXEL : SKIN_STYLE_ALUMINIUM, "2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea");
            if (style) {
                skin_set_pixel_look(look);
            }
            for (int s = 0; s < 3; s++) {
                int w = sizes[s][0], h = sizes[s][1];
                char *ref = map_of(w, h, 1, 0);
                for (int c = 1; c <= 6; c++) {
                    if (strchr(ref, '0' + c) == NULL) {
                        printf("FAIL style %d look %d %dx%d: control %d is never hit\n", style, look, w, h, c);
                        fails++;
                    }
                }
                for (int shown = 0; shown <= 1; shown++) {
                    for (int muted = 0; muted <= 1; muted++) {
                        char *m = map_of(w, h, shown, muted);
                        if (strcmp(m, ref) != 0) {
                            printf("FAIL style %d look %d %dx%d shown %d muted %d: the six controls' hit areas changed\n", style, look, w, h, shown, muted);
                            fails++;
                        }
                        free(m);
                    }
                }
                free(ref);
            }
        }
    }
    skin_set_buttons_shown(1);
    skin_note_muted(0);
    if (fails == 0) {
        printf("midimap hit: K1-K3 and E1-E3 hit alike in aluminium, PIXEL, RETRO, 8-BIT, 16-BIT, row shown or hidden, muted or not, 3 sizes\n");
    }
    return fails == 0 ? 0 : 1;
}
