/*
 * device_hid_iohid.cc
 *
 * IOHIDManager backend for the norns hid device (replaces device_hid.cc / libevdev on macOS).
 *
 * scripts and the lua hid/keyboard/gamepad libraries speak linux evdev codes, so every
 * HID element is translated into the (type, code) pair the linux hid-input driver would
 * produce for it. device guids are built from bus/vendor/product/version exactly like the
 * linux backend, so existing gamepad profiles keep matching.
 *
 * the computer keyboard is a virtual device (path MACOS_SDL_KEYBOARD_PATH) fed by the
 * norns window: no input-monitoring permission needed, and keys typed into other apps
 * never reach scripts.
 */

#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <map>
#include <mutex>
#include <set>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device_hid.h"
#include "events.h"
#include "platform/macos/device_monitor_macos.h"

namespace {

// linux/input-event-codes.h
constexpr uint16_t EV_SYN = 0x00;
constexpr uint16_t EV_KEY = 0x01;
constexpr uint16_t EV_REL = 0x02;
constexpr uint16_t EV_ABS = 0x03;
constexpr uint16_t BTN_MISC = 0x100;
constexpr uint16_t BTN_MOUSE = 0x110;
constexpr uint16_t BTN_JOYSTICK = 0x120;
constexpr uint16_t BTN_GAMEPAD = 0x130;
constexpr uint16_t BTN_DPAD_UP = 0x220;
constexpr uint16_t BTN_DPAD_DOWN = 0x221;
constexpr uint16_t BTN_DPAD_LEFT = 0x222;
constexpr uint16_t BTN_DPAD_RIGHT = 0x223;
constexpr uint16_t BTN_TRIGGER_HAPPY = 0x2c0;
constexpr uint16_t REL_HWHEEL = 0x06;
constexpr uint16_t ABS_HAT0X = 0x10;
constexpr uint16_t ABS_HAT0Y = 0x11;

// linux/input.h bus types
constexpr uint16_t BUS_USB = 0x03;
constexpr uint16_t BUS_BLUETOOTH = 0x05;
constexpr uint16_t BUS_VIRTUAL = 0x06;
constexpr uint16_t BUS_I2C = 0x18;
constexpr uint16_t BUS_SPI = 0x1c;

// USB HID keyboard usage -> linux key code (drivers/hid/hid-input.c, hid_keyboard[])
constexpr uint8_t unk = 0;
const uint8_t hid_keyboard[256] = {
    0,   0,   0,   0,   30,  48,  46,  32,  18,  33,  34,  35,  23,  36,  37,  38,  //
    50,  49,  24,  25,  16,  19,  31,  20,  22,  47,  17,  45,  21,  44,  2,   3,   //
    4,   5,   6,   7,   8,   9,   10,  11,  28,  1,   14,  15,  57,  12,  13,  26,  //
    27,  43,  43,  39,  40,  41,  51,  52,  53,  58,  59,  60,  61,  62,  63,  64,  //
    65,  66,  67,  68,  87,  88,  99,  70,  119, 110, 102, 104, 111, 107, 109, 106, //
    105, 108, 103, 69,  98,  55,  74,  78,  96,  79,  80,  81,  75,  76,  77,  71,  //
    72,  73,  82,  83,  86,  127, 116, 117, 183, 184, 185, 186, 187, 188, 189, 190, //
    191, 192, 193, 194, 134, 138, 130, 132, 128, 129, 131, 137, 133, 135, 136, 113, //
    115, 114, unk, unk, unk, 121, unk, 89,  93,  124, 92,  94,  95,  unk, unk, unk, //
    122, 123, 90,  91,  85,  unk, unk, unk, unk, unk, unk, unk, 111, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, 179, 180, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, unk, //
    unk, unk, unk, unk, unk, unk, unk, unk, 111, unk, unk, unk, unk, unk, unk, unk, //
    29,  42,  56,  125, 97,  54,  100, 126, 164, 166, 165, 163, 161, 115, 114, 113, //
    150, 158, 159, 128, 136, 177, 178, 176, 142, 152, 173, 140, unk, unk, unk, unk, //
};

struct evcode {
    uint16_t type;
    uint16_t code;
};

// translate one HID input element; returns the number of evdev codes it drives (hat: 2)
int map_element(IOHIDElementRef el, uint32_t app, evcode out[2]) {
    IOHIDElementType et = IOHIDElementGetType(el);
    if (et != kIOHIDElementTypeInput_Misc && et != kIOHIDElementTypeInput_Button &&
        et != kIOHIDElementTypeInput_Axis) {
        return 0;
    }
    uint32_t page = IOHIDElementGetUsagePage(el);
    uint32_t usage = IOHIDElementGetUsage(el);

    switch (page) {
    case kHIDPage_KeyboardOrKeypad:
        if (usage < 256 && hid_keyboard[usage] != 0) {
            out[0] = {EV_KEY, hid_keyboard[usage]};
            return 1;
        }
        return 0;

    case kHIDPage_Button: {
        if (usage == 0) {
            return 0;
        }
        uint32_t n = usage - 1;
        switch (app) {
        case kHIDUsage_GD_Mouse:
            if (n > 0xf) {
                return 0;
            }
            out[0] = {EV_KEY, (uint16_t)(BTN_MOUSE + n)};
            return 1;
        case kHIDUsage_GD_Joystick:
            out[0] = {EV_KEY, (uint16_t)(n <= 0xf ? BTN_JOYSTICK + n : BTN_TRIGGER_HAPPY + n - 0x10)};
            return 1;
        case kHIDUsage_GD_GamePad:
            out[0] = {EV_KEY, (uint16_t)(n <= 0xf ? BTN_GAMEPAD + n : BTN_TRIGGER_HAPPY + n - 0x10)};
            return 1;
        default:
            if (n > 0xf) {
                return 0;
            }
            out[0] = {EV_KEY, (uint16_t)(BTN_MISC + n)};
            return 1;
        }
    }

    case kHIDPage_GenericDesktop:
        if (usage >= kHIDUsage_GD_X && usage <= kHIDUsage_GD_Wheel) {
            // X Y Z Rx Ry Rz slider dial wheel: same low nibble order as REL_* / ABS_*
            out[0] = {IOHIDElementIsRelative(el) ? EV_REL : EV_ABS, (uint16_t)(usage & 0xf)};
            return 1;
        }
        if (usage == kHIDUsage_GD_Hatswitch) {
            out[0] = {EV_ABS, ABS_HAT0X};
            out[1] = {EV_ABS, ABS_HAT0Y};
            return 2;
        }
        switch (usage) {
        case kHIDUsage_GD_DPadUp:
            out[0] = {EV_KEY, BTN_DPAD_UP};
            return 1;
        case kHIDUsage_GD_DPadDown:
            out[0] = {EV_KEY, BTN_DPAD_DOWN};
            return 1;
        case kHIDUsage_GD_DPadRight:
            out[0] = {EV_KEY, BTN_DPAD_RIGHT};
            return 1;
        case kHIDUsage_GD_DPadLeft:
            out[0] = {EV_KEY, BTN_DPAD_LEFT};
            return 1;
        default:
            return 0;
        }

    case kHIDPage_Consumer:
        if (usage == kHIDUsage_Csmr_ACPan) {
            out[0] = {EV_REL, REL_HWHEEL};
            return 1;
        }
        return 0;

    default:
        return 0;
    }
}

int32_t int_property(IOHIDDeviceRef dev, CFStringRef key) {
    int32_t v = 0;
    CFTypeRef ref = IOHIDDeviceGetProperty(dev, key);
    if (ref != NULL && CFGetTypeID(ref) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)ref, kCFNumberSInt32Type, &v);
    }
    return v;
}

uint16_t bus_type(IOHIDDeviceRef dev) {
    CFTypeRef ref = IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDTransportKey));
    if (ref == NULL || CFGetTypeID(ref) != CFStringGetTypeID()) {
        return BUS_VIRTUAL;
    }
    CFStringRef t = (CFStringRef)ref;
    if (CFStringCompare(t, CFSTR("USB"), 0) == kCFCompareEqualTo) {
        return BUS_USB;
    }
    if (CFStringHasPrefix(t, CFSTR("Bluetooth"))) {
        return BUS_BLUETOOTH;
    }
    if (CFStringCompare(t, CFSTR("I2C"), 0) == kCFCompareEqualTo) {
        return BUS_I2C;
    }
    if (CFStringCompare(t, CFSTR("SPI"), 0) == kCFCompareEqualTo) {
        return BUS_SPI;
    }
    return BUS_VIRTUAL;
}

// same encoding as device_hid.cc: each 16-bit word, low byte first, as hex
void guid_to_string(const uint16_t *guid, char *guidstr) {
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 8; i++) {
        unsigned char c = guid[i];
        *guidstr++ = hex[c >> 4];
        *guidstr++ = hex[c & 0x0F];
        c = guid[i] >> 8;
        *guidstr++ = hex[c >> 4];
        *guidstr++ = hex[c & 0x0F];
    }
    *guidstr = '\0';
}

void post(struct dev_hid *d, uint16_t type, uint16_t code, int value) {
    union event_data *ev = event_data_new(EVENT_HID_EVENT);
    ev->hid_event.id = d->base.id;
    ev->hid_event.type = type;
    ev->hid_event.code = code;
    ev->hid_event.value = value;
    event_post(ev);
}

void input_value(void *ctx, IOReturn result, void *sender, IOHIDValueRef value) {
    (void)result;
    (void)sender;
    struct dev_hid *d = (struct dev_hid *)ctx;
    IOHIDElementRef el = IOHIDValueGetElement(value);
    evcode m[2];
    int k = map_element(el, d->app_usage, m);
    if (k == 0) {
        return;
    }
    CFIndex v = IOHIDValueGetIntegerValue(value);

    if (k == 2) {
        // hat switch: n directions clockwise from north, out-of-range = centered (hid-input.c)
        static const int hat_x[8] = {0, 1, 1, 1, 0, -1, -1, -1};
        static const int hat_y[8] = {-1, -1, 0, 1, 1, 1, 0, -1};
        CFIndex lmin = IOHIDElementGetLogicalMin(el);
        CFIndex lmax = IOHIDElementGetLogicalMax(el);
        int x = 0, y = 0;
        if (v >= lmin && v <= lmax && lmax > lmin) {
            CFIndex dir = (v - lmin) * 8 / (lmax - lmin + 1);
            x = hat_x[dir];
            y = hat_y[dir];
        }
        post(d, EV_ABS, ABS_HAT0X, x);
        post(d, EV_ABS, ABS_HAT0Y, y);
        return;
    }
    if (m[0].type == EV_REL && v == 0) {
        return;
    }
    post(d, m[0].type, m[0].code, (int)v);
}

std::mutex keyboard_lock;
struct dev_hid *keyboard = NULL;

int keyboard_init(struct dev_hid *d) {
    std::set<uint16_t> keys;
    for (int u = 0; u < 256; u++) {
        if (hid_keyboard[u] != 0) {
            keys.insert(hid_keyboard[u]);
        }
    }
    d->dev = NULL;
    d->app_usage = kHIDUsage_GD_Keyboard;
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

} // namespace

extern "C" void macos_hid_keyboard_event(uint16_t usage, int value) {
    std::lock_guard<std::mutex> g(keyboard_lock);
    if (keyboard != NULL && usage < 256 && hid_keyboard[usage] != 0) {
        post(keyboard, EV_KEY, hid_keyboard[usage], value);
    }
}

int dev_hid_init(void *self) {
    struct dev_hid *d = (struct dev_hid *)self;
    struct dev_common *base = (struct dev_common *)self;

    if (base->path != NULL && strcmp(base->path, MACOS_SDL_KEYBOARD_PATH) == 0) {
        base->start = NULL;
        base->deinit = &dev_hid_deinit;
        return keyboard_init(d);
    }

    IOHIDDeviceRef dev = (IOHIDDeviceRef)macos_hid_lookup(base->path);
    if (dev == NULL) {
        fprintf(stderr, "failed to open hid device: %s\n", base->path);
        return -1;
    }
    d->dev = dev;
    d->app_usage = (uint32_t)int_property(dev, CFSTR(kIOHIDPrimaryUsageKey));

    // capabilities, in the shape weaver reports to lua (sorted types, sorted codes per type)
    std::map<uint16_t, std::set<uint16_t>> caps;
    caps[EV_SYN].insert(0);
    CFArrayRef els = IOHIDDeviceCopyMatchingElements(dev, NULL, kIOHIDOptionsTypeNone);
    if (els != NULL) {
        for (CFIndex i = 0; i < CFArrayGetCount(els); i++) {
            evcode m[2];
            int k = map_element((IOHIDElementRef)CFArrayGetValueAtIndex(els, i), d->app_usage, m);
            for (int j = 0; j < k; j++) {
                caps[m[j].type].insert(m[j].code);
            }
        }
        CFRelease(els);
    }
    d->num_types = (int)caps.size();
    d->types = (uint8_t *)calloc(d->num_types, sizeof(uint8_t));
    d->num_codes = (int *)calloc(d->num_types, sizeof(int));
    d->codes = (dev_code_t **)calloc(d->num_types, sizeof(dev_code_t *));
    int t = 0;
    for (auto &kv : caps) {
        d->types[t] = (uint8_t)kv.first;
        d->num_codes[t] = (int)kv.second.size();
        d->codes[t] = (dev_code_t *)calloc(kv.second.size(), sizeof(dev_code_t));
        int c = 0;
        for (uint16_t code : kv.second) {
            d->codes[t][c++] = code;
        }
        t++;
    }

    uint16_t vendor = (uint16_t)int_property(dev, CFSTR(kIOHIDVendorIDKey));
    uint16_t product = (uint16_t)int_property(dev, CFSTR(kIOHIDProductIDKey));
    uint16_t version = (uint16_t)int_property(dev, CFSTR(kIOHIDVersionNumberKey));
    d->vid = (dev_vid_t)vendor;
    d->pid = (dev_pid_t)product;
    uint16_t raw_guid[8] = {bus_type(dev), 0, vendor, 0, product, 0, version, 0};
    guid_to_string(raw_guid, d->guid);

    IOHIDDeviceRegisterInputValueCallback(dev, input_value, d);

    // input arrives through the device runloop callback, no reader thread
    base->start = NULL;
    base->deinit = &dev_hid_deinit;
    return 0;
}

void *dev_hid_start(void *self) {
    (void)self;
    return NULL;
}

void dev_hid_deinit(void *self) {
    struct dev_hid *d = (struct dev_hid *)self;
    {
        std::lock_guard<std::mutex> g(keyboard_lock);
        if (keyboard == d) {
            keyboard = NULL;
        }
    }
    if (d->dev != NULL) {
        IOHIDDeviceRegisterInputValueCallback((IOHIDDeviceRef)d->dev, NULL, NULL);
    }
    for (int i = 0; i < d->num_types; i++) {
        free(d->codes[i]);
    }
    free(d->codes);
    free(d->num_codes);
    free(d->types);
}
