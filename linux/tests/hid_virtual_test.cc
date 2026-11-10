// the computer keyboard as a HID device: a key event of the window (shell_hid_keyboard_event, usage = USB HID usage) must reach the event queue as an
// EVENT_HID_EVENT of the registered device, with the linux key code (a = 30). the Windows build once had no such device (keyboard dead). event_post is faked here.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

#include "device/device_hid.h"
#include "events.h"
#include "platform/linux/hid_virtual.h"

static std::vector<union event_data *> posted;
extern "C" union event_data *event_data_new(event_t evcode) {
    union event_data *ev = (union event_data *)calloc(1, sizeof(union event_data));
    ev->type = evcode;
    return ev;
}
extern "C" void event_post(union event_data *ev) { posted.push_back(ev); }
extern "C" void guid_to_string(uint16_t *guid, char *guidstr) { (void)guid; strcpy(guidstr, "00000000000000000000000000000000"); }
extern "C" void shell_hid_keyboard_event(uint16_t usage, int value);

static int fails = 0;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)

int main() {
    struct dev_hid d;
    memset(&d, 0, sizeof d);
    d.base.id = 7;
    shell_hid_keyboard_event(4, 1);
    CHECK(posted.empty(), "no device registered: nothing posted");
    CHECK(hid_virtual_init(&d) == 0, "init");
    CHECK(d.num_types == 2, "two event types");
    shell_hid_keyboard_event(4, 1); // HID usage 4 = a
    shell_hid_keyboard_event(4, 0);
    shell_hid_keyboard_event(0x28, 1); // enter
    shell_hid_keyboard_event(0xff, 1); // unmapped
    shell_hid_keyboard_event(300, 1);  // out of range
    CHECK(posted.size() == 3, "three mapped events posted");
    if (posted.size() == 3) {
        CHECK(posted[0]->type == EVENT_HID_EVENT && posted[0]->hid_event.id == 7, "event and device id");
        CHECK(posted[0]->hid_event.code == 30 && posted[0]->hid_event.value == 1, "a down = KEY_A (30)");
        CHECK(posted[1]->hid_event.code == 30 && posted[1]->hid_event.value == 0, "a up");
        CHECK(posted[2]->hid_event.code == 28, "enter = KEY_ENTER (28)");
    }
    hid_virtual_deinit(&d);
    size_t n = posted.size();
    shell_hid_keyboard_event(4, 1);
    CHECK(posted.size() == n, "after deinit nothing is posted");
    if (fails == 0) printf("hid_virtual_test: all passed\n");
    return fails ? 1 : 0;
}
