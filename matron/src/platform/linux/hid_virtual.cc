/*
 * hid_virtual.cc: see hid_virtual.h
 */

#include <linux/input.h> // EV_SYN, EV_KEY, BUS_VIRTUAL
#include <pthread.h>

#include "hid_virtual.h"

#include <mutex>
#include <set>
#include <stdint.h>
#include <stdlib.h>

#include "events.h"
#include "platform/common/desktop_shell.h"

extern "C" void guid_to_string(uint16_t *guid, char *guidstr);

namespace {

// USB HID keyboard usage -> linux key code (drivers/hid/hid-input.c, hid_keyboard[]); the same
// table as platform/macos/device_hid_iohid.cc (to be shared when the common code is moved)
constexpr uint8_t unk = 0;
const uint8_t hid_keyboard[256] = {
    0, 0, 0, 0, 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38,                     //
    50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44, 2, 3,                   //
    4, 5, 6, 7, 8, 9, 10, 11, 28, 1, 14, 15, 57, 12, 13, 26,                        //
    27, 43, 43, 39, 40, 41, 51, 52, 53, 58, 59, 60, 61, 62, 63, 64,                 //
    65, 66, 67, 68, 87, 88, 99, 70, 119, 110, 102, 104, 111, 107, 109, 106,         //
    105, 108, 103, 69, 98, 55, 74, 78, 96, 79, 80, 81, 75, 76, 77, 71,              //
    72, 73, 82, 83, 86, 127, 116, 117, 183, 184, 185, 186, 187, 188, 189, 190,      //
    191, 192, 193, 194, 134, 138, 130, 132, 128, 129, 131, 137, 133, 135, 136, 113, //
    115, 114, unk, unk, unk, 121, unk, 89, 93, 124, 92, 94, 95, unk, unk, unk,      //
    122, 123, 90, 91, 85, unk, unk, unk, unk, unk, unk, unk, 111, unk, unk, unk,    //
    unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, 179, 180, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, unk, unk, 111, unk, unk, unk, unk, unk, unk, unk, //
    29, 42, 56, 125, 97, 54, 100, 126, 164, 166, 165, 163, 161, 115, 114, 113,      //
    150, 158, 159, 128, 136, 177, 178, 176, 142, 152, 173, 140, unk, unk, unk, unk, //
};

std::mutex keyboard_lock;
struct dev_hid *keyboard = NULL;

void post(struct dev_hid *d, uint16_t type, uint16_t code, int value) {
    union event_data *ev = event_data_new(EVENT_HID_EVENT);
    ev->hid_event.id = d->base.id;
    ev->hid_event.type = type;
    ev->hid_event.code = code;
    ev->hid_event.value = value;
    event_post(ev);
}

} // namespace

int hid_virtual_init(struct dev_hid *d) {
    std::set<uint16_t> keys;
    for (int u = 0; u < 256; u++) {
        if (hid_keyboard[u] != 0) {
            keys.insert(hid_keyboard[u]);
        }
    }
    d->dev = NULL;
    d->num_types = 2;
    d->types = (uint8_t *)calloc(2, sizeof(uint8_t));
    d->num_codes = (int *)calloc(2, sizeof(int));
    d->codes = (dev_code_t **)calloc(2, sizeof(dev_code_t *));
    d->types[0] = EV_SYN;
    d->num_codes[0] = 1;
    d->codes[0] = (dev_code_t *)calloc(1, sizeof(dev_code_t));
    d->types[1] = EV_KEY;
    d->num_codes[1] = (int)keys.size();
    d->codes[1] = (dev_code_t *)calloc(keys.size(), sizeof(dev_code_t));
    int c = 0;
    for (uint16_t k : keys) {
        d->codes[1][c++] = k;
    }
    d->vid = 0;
    d->pid = 0;
    uint16_t raw_guid[8] = {BUS_VIRTUAL, 0, 0, 0, 0, 0, 0, 0};
    guid_to_string(raw_guid, d->guid);

    std::lock_guard<std::mutex> g(keyboard_lock);
    keyboard = d;
    return 0;
}

void hid_virtual_deinit(struct dev_hid *d) {
    std::lock_guard<std::mutex> g(keyboard_lock);
    if (keyboard == d) {
        keyboard = NULL;
    }
}

extern "C" void shell_hid_keyboard_event(uint16_t usage, int value) {
    std::lock_guard<std::mutex> g(keyboard_lock);
    if (keyboard != NULL && usage < 256 && hid_keyboard[usage] != 0) {
        post(keyboard, EV_KEY, hid_keyboard[usage], value);
    }
}
