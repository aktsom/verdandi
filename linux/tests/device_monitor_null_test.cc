// the udev device monitor (matron/src/device/device_monitor.cc) with devices that lack properties: no "product" in the device or any
// parent, no vendor/model, no node, no subsystem, a syspath that cannot be opened. a laptop crashed with strdup(NULL) in the
// watch_loop thread (get_device_name). the udev layer is faked here, the real file is included so its static functions can be called.
// every case runs in a child process: a crash is a failure of that case, not of the test.
#include <string>
#include <map>
#include <vector>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

#include "device_monitor.cc"

// ---- the fake udev layer: a device is a node, a subsystem, a syspath, properties, sysattrs and a parent ----
struct udev_device {
    const char *node, *subsystem, *syspath;
    std::map<std::string, std::string> props, attrs;
    struct udev_device *parent;
};
extern "C" {
struct udev *udev_new(void) { return NULL; }
struct udev_monitor *udev_monitor_new_from_netlink(struct udev *, const char *) { return NULL; }
int udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *, const char *, const char *) { return -1; }
int udev_monitor_enable_receiving(struct udev_monitor *) { return -1; }
int udev_monitor_get_fd(struct udev_monitor *) { return -1; }
struct udev_device *udev_monitor_receive_device(struct udev_monitor *) { return NULL; }
struct udev_enumerate *udev_enumerate_new(struct udev *) { return NULL; }
int udev_enumerate_add_match_subsystem(struct udev_enumerate *, const char *) { return 0; }
int udev_enumerate_scan_devices(struct udev_enumerate *) { return 0; }
struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *) { return NULL; }
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *) { return NULL; }
const char *udev_list_entry_get_name(struct udev_list_entry *) { return NULL; }
struct udev_enumerate *udev_enumerate_unref(struct udev_enumerate *) { return NULL; }
struct udev_device *udev_device_new_from_syspath(struct udev *, const char *) { return NULL; }
struct udev_device *udev_device_unref(struct udev_device *) { return NULL; }
struct udev_device *udev_device_get_parent_with_subsystem_devtype(struct udev_device *, const char *, const char *) { return NULL; }
const char *udev_device_get_action(struct udev_device *) { return "add"; }
const char *udev_device_get_devnode(struct udev_device *d) { return d->node; }
const char *udev_device_get_subsystem(struct udev_device *d) { return d->subsystem; }
const char *udev_device_get_syspath(struct udev_device *d) { return d->syspath; }
struct udev_device *udev_device_get_parent(struct udev_device *d) { return d->parent; }
const char *udev_device_get_property_value(struct udev_device *d, const char *k) {
    auto i = d->props.find(k);
    return i == d->props.end() ? NULL : i->second.c_str();
}
const char *udev_device_get_sysattr_value(struct udev_device *d, const char *k) {
    auto i = d->attrs.find(k);
    return i == d->attrs.end() ? NULL : i->second.c_str();
}
}

// ---- what the monitor hands on ----
static std::vector<std::string> added; // "type:node:name"
static bool name_null;
static bool serial_name_null;
void dev_list_add(device_t type, const char *node, const char *name, lua_State *) {
    if (name == NULL) name_null = true;
    added.push_back(std::to_string((int)type) + ":" + (node ? node : "(null)") + ":" + (name ? name : "(null)"));
}
void dev_list_remove(device_t, const char *) {}
static union event_data fake_ev;
union event_data *event_data_new(event_t) { memset(&fake_ev, 0, sizeof fake_ev); return &fake_ev; }
void event_post(union event_data *ev) { if (ev->serial_config.name == NULL) serial_name_null = true; }
int jack_midi_in_start(void) { return -1; }

static int failures;
#define CASE(name, ...)                                                                        \
    do {                                                                                          \
        fflush(stdout);                                                                           \
        pid_t pid = fork();                                                                       \
        if (pid == 0) {                                                                           \
            __VA_ARGS__;                                                                               \
            _exit(0);                                                                             \
        }                                                                                         \
        int st = 0;                                                                               \
        waitpid(pid, &st, 0);                                                                     \
        if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {                                             \
            printf("FAIL: %s (%s %d)\n", name, WIFSIGNALED(st) ? "signal" : "exit", WIFSIGNALED(st) ? WTERMSIG(st) : WEXITSTATUS(st)); \
            failures++;                                                                           \
        } else {                                                                                  \
            printf("ok:   %s\n", name);                                                           \
        }                                                                                         \
    } while (0)

int main(void) {
    // a /dev/input node whose device and parents have no "product" (a lid switch, a PC speaker, a headphone jack)
    CASE("input node, no product anywhere: no crash, a name is given", {
        udev_device top = {NULL, "platform", "/nonexistent", {}, {}, NULL};
        udev_device d = {"/dev/input/event9", "input", "/nonexistent", {}, {}, &top};
        add_dev(&d, DEV_FILE_INPUT);
        if (added.size() != 1 || name_null) _exit(2);
    });
    CASE("input node, product on a parent: that name", {
        udev_device top = {NULL, "usb", "/nonexistent", {}, {{"product", "mio"}}, NULL};
        udev_device d = {"/dev/input/event9", "input", "/nonexistent", {}, {}, &top};
        add_dev(&d, DEV_FILE_INPUT);
        if (added.size() != 1 || added[0] != "1:/dev/input/event9:mio") _exit(2);
    });
    CASE("input entry without node: skipped", {
        udev_device d = {NULL, "input", "/nonexistent", {}, {}, NULL};
        add_dev(&d, DEV_FILE_INPUT);
        if (!added.empty()) _exit(2);
    });
    CASE("tty, no vendor, model, serial, product: an event with a name", {
        udev_device d = {"/dev/ttyACM3", "tty", "/nonexistent", {}, {}, NULL};
        add_dev(&d, DEV_FILE_TTY);
        if (serial_name_null) _exit(2);
    });
    CASE("monome grid tty without a product name: a name is given", {
        udev_device d = {"/dev/ttyACM0", "tty", "/nonexistent", {{"ID_VENDOR", "monome"}, {"ID_MODEL", "grid"}}, {}, NULL};
        add_dev(&d, DEV_FILE_TTY);
        if (added.size() != 1 || name_null) _exit(2);
    });
    CASE("crow tty without a product name: a name is given", {
        udev_device d = {"/dev/ttyACM1", "tty", "/nonexistent", {{"ID_VENDOR", "crow"}, {"ID_MODEL", "crow"}}, {}, NULL};
        add_dev(&d, DEV_FILE_TTY);
        if (name_null) _exit(2);
    });
    CASE("sound device without a subsystem or syspath: no crash, nothing added", {
        udev_device d = {NULL, NULL, NULL, {}, {}, NULL};
        add_dev(&d, DEV_FILE_SOUND);
        if (!added.empty()) _exit(2);
    });
    CASE("sound device whose syspath cannot be opened: no crash, nothing added", {
        udev_device d = {NULL, "sound", "/nonexistent/path", {}, {}, NULL};
        add_dev(&d, DEV_FILE_SOUND);
        if (!added.empty()) _exit(2);
    });
    CASE("remove of a tty and an input without a property: no crash", {
        udev_device d = {"/dev/ttyACM5", "tty", "/nonexistent", {}, {}, NULL};
        rm_dev(&d, DEV_FILE_TTY);
        rm_dev(&d, DEV_FILE_INPUT);
    });
    if (failures) {
        printf("device_monitor_null_test: %d failed\n", failures);
        return 1;
    }
    printf("device_monitor_null_test: all passed\n");
    return 0;
}
