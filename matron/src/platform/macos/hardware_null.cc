/*
 * hardware_null.cc
 *
 * macOS stand-ins for the norns pi hardware: battery gauge, i2c (headphone amp, adc)
 * and the ssd1322 oled. the desktop screen is screen:sdl, so the oled calls are no-ops.
 */

#include <cairo.h>
#include <stdbool.h>
#include <stdint.h>

#include "hardware/battery.h"
#include "hardware/i2c.h"
#include "hardware/screen/ssd1322.h"

void battery_init(void) {
}
void battery_deinit(void) {
}

void i2c_init(void) {
}
void i2c_deinit(void) {
}
void i2c_hp(int level) {
    (void)level;
}
int adc_rev(void) {
    return 0;
}

void ssd1322_init() {
}
void ssd1322_deinit() {
}
void ssd1322_refresh() {
}
void ssd1322_update(cairo_surface_t *surface, bool should_translate_color) {
    (void)surface;
    (void)should_translate_color;
}
void ssd1322_set_brightness(uint8_t b) {
    (void)b;
}
void ssd1322_set_contrast(uint8_t c) {
    (void)c;
}
void ssd1322_set_display_mode(ssd1322_display_mode_t m) {
    (void)m;
}
void ssd1322_set_gamma(double g) {
    (void)g;
}
void ssd1322_set_refresh_rate(uint8_t hz) {
    (void)hz;
}
