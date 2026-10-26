// the norns screen's text placement (matron/src/hardware/screen.cc), docs/port/KNOWN-ISSUES.md item 9. the real screen.cc is compiled into this test
// (stubs for what it links to) in two variants:
//   desktop (-DNORNS_DESKTOP): the start of a text is snapped to a whole pixel, as cairo 1.16 does on the device (a newer cairo draws glyphs at
//     the fractional position it is given: an odd ink width centered is a half pixel and looks squished or blurred)
//   device (no NORNS_DESKTOP, -DSCREEN_TEXT_DEVICE): the code the Raspberry Pi build compiles: unchanged, text starts where it was asked to
// reference images are plain cairo (same surface, font, options), the text drawn at the position the device would draw it. built and run
// by linux/tests/run_all.sh. needs $HOME/norns/resources (the fonts), as norns does.

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <cairo-ft.h>
#include <cairo.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

#include "event_types.h"
#include "hardware/io.h"
#include "hardware/screen/ssd1322.h"
#include "screen_results.h"

// ---- stubs for what screen.cc links to
extern "C" {
struct io_head io_queue = TAILQ_HEAD_INITIALIZER(io_queue);
union screen_results_data *screen_results_data_new(screen_results_t) {
    static union screen_results_data d;
    return &d;
}
void screen_results_post(union screen_results_data *) {
}
}
void ssd1322_update(cairo_surface_t *, bool) {
}
void ssd1322_set_brightness(uint8_t) {
}
void ssd1322_set_contrast(uint8_t) {
}
void ssd1322_set_display_mode(ssd1322_display_mode_t) {
}
void ssd1322_set_gamma(double) {
}

// ---- the screen.cc functions used
void screen_init(void);
void screen_clear(void);
void screen_aa(int);
void screen_level(int);
void screen_font_face(int);
void screen_font_size(double);
void screen_move(double, double);
void screen_text(const char *);
void screen_text_right(const char *);
void screen_text_center(const char *);
extern void screen_export_png(const char *);

// ---- the reference: plain cairo at the position given, nothing else
static FT_Library ftlib;
static FT_Face ftface;
static cairo_font_face_t *font;

static void load_font() {
    if (font) {
        return;
    }
    FT_Init_FreeType(&ftlib);
    std::string path = std::string(getenv("HOME")) + "/norns/resources/norns.ttf";
    REQUIRE(FT_New_Face(ftlib, path.c_str(), 0, &ftface) == 0);
    font = cairo_ft_font_face_create_for_ft_face(ftface, 0);
}

static cairo_t *ref_context(cairo_surface_t **surf, int aa) {
    load_font();
    *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 128, 64);
    cairo_t *cr = cairo_create(*surf);
    cairo_font_options_t *fo = cairo_font_options_create();
    if (aa == 0) {
        cairo_set_antialias(cr, CAIRO_ANTIALIAS_NONE);
        cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_NONE);
    } else {
        cairo_set_antialias(cr, CAIRO_ANTIALIAS_DEFAULT);
        cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_GRAY);
    }
    cairo_set_font_options(cr, fo);
    cairo_font_options_destroy(fo);
    cairo_set_font_face(cr, font);
    cairo_set_font_size(cr, 8.0);
    cairo_set_source_rgb(cr, 1, 1, 1);
    return cr;
}

static double ink_width(const char *s) {
    cairo_surface_t *surf;
    cairo_t *cr = ref_context(&surf, 1);
    cairo_text_extents_t e;
    cairo_text_extents(cr, s, &e);
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    return e.width;
}

// the reference image: the text drawn with its start at (x, y), exactly
static std::vector<unsigned char> reference(const char *s, double x, double y, int aa) {
    cairo_surface_t *surf;
    cairo_t *cr = ref_context(&surf, aa);
    cairo_move_to(cr, x, y);
    cairo_show_text(cr, s);
    cairo_surface_flush(surf);
    std::vector<unsigned char> out(cairo_image_surface_get_data(surf), cairo_image_surface_get_data(surf) + 128 * 64 * 4);
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    return out;
}

// the norns screen: one text drawn with the function given
static std::vector<unsigned char> norns(const char *s, double x, double y, int aa, int how) {
    static bool inited;
    if (!inited) {
        inited = true;
        screen_init();
    }
    screen_clear();
    screen_aa(aa);
    screen_font_face(0);
    screen_font_size(8.0);
    screen_level(15);
    screen_move(x, y);
    if (how == 0) {
        screen_text(s);
    } else if (how == 1) {
        screen_text_right(s);
    } else {
        screen_text_center(s);
    }
    const char *png = "/tmp/screen_text_test.png";
    screen_export_png(png);
    cairo_surface_t *img = cairo_image_surface_create_from_png(png);
    REQUIRE(cairo_surface_status(img) == CAIRO_STATUS_SUCCESS);
    REQUIRE(cairo_image_surface_get_width(img) == 128);
    cairo_surface_flush(img);
    std::vector<unsigned char> out(cairo_image_surface_get_data(img), cairo_image_surface_get_data(img) + 128 * 64 * 4);
    cairo_surface_destroy(img);
    remove(png);
    return out;
}

static int partial_pixels(const std::vector<unsigned char> &img) {
    int n = 0;
    for (size_t i = 3; i < img.size(); i += 4) {
        if (img[i] != 0 && img[i] != 255) {
            n++;
        }
    }
    return n;
}

static const char *ODD[] = {"modulation", "track 6 options", "track 1 filter", "link"}; // ink widths 43, 65, 53, 13
static const char *EVEN[] = {"midi clock out", "tempo"};                                  // 56, 24

#ifndef SCREEN_TEXT_DEVICE
// ============================== desktop: the start is a whole pixel, as on the device

TEST_CASE("centered text with an odd ink width starts on a whole pixel (round half up, as cairo 1.16 draws it)") {
    for (const char *s : ODD) {
        double w = ink_width(s);
        REQUIRE(fmod(w, 2.0) == 1.0); // the test strings are odd
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            CAPTURE(aa);
            auto got = norns(s, 64, 10, aa, 2);
            auto want = reference(s, floor(64 - w * 0.5 + 0.5), 10, aa);
            CHECK(got == want);
            CHECK(partial_pixels(got) == 0);
        }
    }
}

TEST_CASE("centered text with an even ink width is as it was") {
    for (const char *s : EVEN) {
        double w = ink_width(s);
        REQUIRE(fmod(w, 2.0) == 0.0);
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            auto got = norns(s, 64, 10, aa, 2);
            CHECK(got == reference(s, 64 - w * 0.5, 10, aa));
            CHECK(got == reference(s, floor(64 - w * 0.5 + 0.5), 10, aa)); // the same thing
        }
    }
}

TEST_CASE("left-aligned text at a whole pixel is as it was") {
    for (const char *s : ODD) {
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            CHECK(norns(s, 10, 20, aa, 0) == reference(s, 10, 20, aa));
        }
    }
    for (const char *s : EVEN) {
        CHECK(norns(s, 3, 9, 1, 0) == reference(s, 3, 9, 1));
    }
}

TEST_CASE("right-aligned text at a whole pixel is as it was") {
    for (const char *s : ODD) {
        double w = ink_width(s);
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            CHECK(norns(s, 126, 30, aa, 1) == reference(s, 126 - w, 30, aa));
        }
    }
    for (const char *s : EVEN) {
        CHECK(norns(s, 126, 30, 0, 1) == reference(s, 126 - ink_width(s), 30, 0));
    }
}

TEST_CASE("a fractional start given by a script is snapped too (x and y, round half up), as cairo 1.16 did") {
    for (const char *s : ODD) {
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            CHECK(norns(s, 10.5, 20.5, aa, 0) == reference(s, 11, 21, aa));
            CHECK(norns(s, 10.4, 20.4, aa, 0) == reference(s, 10, 20, aa));
        }
    }
    // right-aligned with a fractional x: start = x - width, rounded
    double w = ink_width("modulation");
    CHECK(norns("modulation", 100.5, 30, 1, 1) == reference("modulation", floor(100.5 - w + 0.5), 30, 1));
}

TEST_CASE("the snap does not move the text by more than half a pixel in any direction") {
    // the leftmost lit column of "modulation" centered at 64: 43 (start 42.5 rounded up); the glyph "m" starts at its origin
    auto img = norns("modulation", 64, 10, 0, 2);
    int left = -1;
    for (int x = 0; x < 128 && left < 0; x++) {
        for (int y = 0; y < 64; y++) {
            if (img[(y * 128 + x) * 4 + 3] != 0) {
                left = x;
                break;
            }
        }
    }
    CHECK(left == 43);
}

#else
// ============================== device build (no NORNS_DESKTOP): the code is as it was, nothing is snapped

TEST_CASE("device build: centered text starts where it was asked to (fractional x stays fractional)") {
    for (const char *s : ODD) {
        double w = ink_width(s);
        for (int aa = 0; aa <= 1; aa++) {
            CAPTURE(s);
            CHECK(norns(s, 64, 10, aa, 2) == reference(s, 64 - w * 0.5, 10, aa));
        }
    }
}

TEST_CASE("device build: left- and right-aligned text with fractional positions is not snapped") {
    for (const char *s : ODD) {
        CHECK(norns(s, 10.5, 20.5, 1, 0) == reference(s, 10.5, 20.5, 1));
        double w = ink_width(s);
        CHECK(norns(s, 100.5, 30.5, 1, 1) == reference(s, 100.5 - w, 30.5, 1));
    }
}
#endif
