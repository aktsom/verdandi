/*
 * box_render_dump.c: the window as the skin code draws it in a set of states and sizes, one raw RGB24 file per case in the folder given (docs/port/box-style-plan.md, test 7: the aluminium style
 * with its default colours must give the same bytes as the code did before the box styles existed; box_aluminium_test.sh compares the sha256 of every file with
 * linux/tests/box_aluminium_golden.txt, which was made from the committed device_skin.c of the step before). built with -DNORNS_LINUX_DESKTOP against either version of device_skin.c: the
 * look is only set when BOX_LOOK=1 is in the environment (the old source has no skin_set_look).
 *   box_render_dump OUT_DIR
 */
#include <cairo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device_skin.h"

static cairo_surface_t *mkoled(void) {
    cairo_surface_t *o = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 128, 64);
    uint32_t *d = (uint32_t *)cairo_image_surface_get_data(o);
    int stride = cairo_image_surface_get_stride(o) / 4;
    for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 128; x++) {
            int v = ((x / 8 + y / 8) % 2) ? 200 : (x * 2) & 0xff; // a pattern with edges, so that a shifted screen shows
            d[y * stride + x] = 0xff000000u | (v << 16) | (v << 8) | v;
        }
    }
    cairo_surface_mark_dirty(o);
    return o;
}

static void dump(const char *dir, const char *name, int w, int h, void (*setup)(skin_state_t *, int *), int hover_variant) {
    cairo_surface_t *canvas = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    cairo_t *cr = cairo_create(canvas);
    skin_geom_t g;
    skin_geom(w, h, &g);
    skin_state_t st;
    memset(&st, 0, sizeof st);
    st.page = 4;
    st.input = SKIN_INPUT_MIC;
    int placeholder = 0;
    (void)hover_variant;
    setup(&st, &placeholder);
    cairo_surface_t *oled = mkoled();
    skin_draw_static(cr, &g);
    if (placeholder) {
        skin_draw_placeholder(cr, &g, 0);
    } else {
        skin_draw_oled(cr, &g, oled);
    }
    skin_draw_controls(cr, &g, &st);
    cairo_surface_flush(canvas);
    char path[512];
    snprintf(path, sizeof path, "%s/%s.rgb", dir, name);
    FILE *f = fopen(path, "wb");
    unsigned char *data = cairo_image_surface_get_data(canvas);
    int stride = cairo_image_surface_get_stride(canvas);
    for (int y = 0; y < h; y++) {
        fwrite(data + (size_t)y * stride, 4, (size_t)w, f);
    }
    fclose(f);
    cairo_surface_destroy(oled);
    cairo_destroy(cr);
    cairo_surface_destroy(canvas);
}

static void s_idle(skin_state_t *s, int *p) { (void)s; (void)p; }
static void s_keys(skin_state_t *s, int *p) { (void)p; s->key_down[0] = 1; s->enc_ticks[1] = 7; s->hover = (SKIN_E1 + 1); s->page = 2; s->grid_open = 1; s->input = SKIN_INPUT_SYSTEM; }
static void s_button(skin_state_t *s, int *p) { (void)p; s->button_down = SKIN_MAIDEN; s->hover = SKIN_MIC; s->arc_open = 1; s->keys_open = 1; }
static void s_toast(skin_state_t *s, int *p) { (void)p; s->toast = "Imported 3 files"; s->recording = 1; s->key_down[2] = 1; s->enc_ticks[0] = -5; }
static void s_muted(skin_state_t *s, int *p) { (void)p; s->out_muted = 1; s->hover = SKIN_MUTE; }
static void s_detached(skin_state_t *s, int *p) { *p = 1; s->screen_out = 1; s->hover = (SKIN_K1 + 1); }

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: box_render_dump OUT_DIR\n");
        return 2;
    }
    const char *dir = argv[1];
    static const int sizes[][2] = {{992, 662}, {600, 400}, {1488, 993}, {1200, 662}};
    static const struct {
        const char *name;
        void (*fn)(skin_state_t *, int *);
    } cases[] = {{"idle", s_idle}, {"keys", s_keys}, {"button", s_button}, {"toast", s_toast}, {"muted", s_muted}, {"detached", s_detached}};
    for (unsigned c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        for (unsigned z = 0; z < sizeof sizes / sizeof sizes[0]; z++) {
            char name[64];
            snprintf(name, sizeof name, "%s-%dx%d", cases[c].name, sizes[z][0], sizes[z][1]);
            dump(dir, name, sizes[z][0], sizes[z][1], cases[c].fn, 0);
        }
    }
    return 0;
}
