
#pragma once

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

#include "device_common.h"
#include <monome.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DEVICE_MONOME_TYPE_GRID,
    DEVICE_MONOME_TYPE_ARC,
} device_monome_type_t;

// monome device data structure.
struct dev_monome {
    struct dev_common dev;
    device_monome_type_t type;
    monome_t *m;
    uint8_t data[4][64]; // led data by quad
    bool dirty[4];       // quad-dirty flags
    int cols;
    int rows;
    int quads;
    int quad_xoff[4];
    int quad_yoff[4];
    pthread_mutex_t io; // one writer at a time to the LEDs of this device (a script's refresh and the quit's "all off")
};

// set a single grid led
extern void dev_monome_grid_set_led(struct dev_monome *md, uint8_t x, uint8_t y, int8_t val, bool rel);
// set a single arc led
extern void dev_monome_arc_set_led(struct dev_monome *md, uint8_t n, uint8_t x, int8_t val, bool rel);
// set all led
extern void dev_monome_all_led(struct dev_monome *md, int8_t val, bool rel);
// set all data for a quad
extern void dev_monome_set_quad(struct dev_monome *md, uint8_t quad, uint8_t *data);
// transmit data for all dirty quads
extern void dev_monome_refresh(struct dev_monome *md);
extern int dev_monome_grid_rows(struct dev_monome *md);
extern int dev_monome_grid_cols(struct dev_monome *md);
// desktop: norns is ending. from now on the LED calls of Lua (set, all, refresh, intensity) change nothing, so that a script or a mod that goes on drawing cannot light a grid again after the "all off" (docs/port/phase-m17.md)
extern void dev_monome_freeze(void);
// every LED of this device off and really written out (on Windows the port's buffers are flushed); bypasses the freeze. 1 if it was sent
extern int dev_monome_leds_off(struct dev_monome *md);
// intensity
extern void dev_monome_intensity(struct dev_monome *md, uint8_t i);

// set grid rotation
extern void dev_monome_set_rotation(struct dev_monome *md, uint8_t val);

// grid tilt enable/disable
extern void dev_monome_tilt_enable(struct dev_monome *md, uint8_t val);
extern void dev_monome_tilt_disable(struct dev_monome *md, uint8_t val);

// device management
extern int dev_monome_init(void *self);
extern void dev_monome_deinit(void *self);

extern void *dev_monome_start(void *self);

#ifdef __cplusplus
}
#endif
