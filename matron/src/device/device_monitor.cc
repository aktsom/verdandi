/*
 * device_monitor.c
 */

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fnmatch.h>
#include <libudev.h>
#include <locale.h>
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "device.h"
#include "device_hid.h"
#include "device_list.h"
#include "device_monitor.h"
#include "device_midi.h"
#include "device_monome.h"
#ifdef NORNS_LINUX_DESKTOP
#include "device_dedupe.h"
#endif

#include "events.h"
#ifdef NORNS_LINUX_DESKTOP
#include "platform/linux/hid_virtual.h"
#include "platform/linux/aseq_out.h"
#include "platform/linux/jack_midi_in.h"
#include "platform/linux/midi_ignore.h"
#include <set>
#include <string>
#include <vector>
#endif

#define SUB_NAME_SIZE 32
#define NODE_NAME_SIZE 128
#define WATCH_TIMEOUT_MS 100

// enumerate unix files to watch
enum {
    DEV_FILE_TTY = 0,
    DEV_FILE_INPUT = 1,
    DEV_FILE_SOUND = 2,
    DEV_FILE_NONE = 3,
};
#define DEV_FILE_COUNT 3

struct udev_monitor *mon[DEV_FILE_COUNT];

static const char *dev_file_name[] = {"tty", "input", "sound", "none"};

//-------------------------
//----- static variables

// file descriptors to watch/poll
struct pollfd pfds[DEV_FILE_COUNT];
// thread for polling all the watched file descriptors
pthread_t watch_tid;

//--------------------------------
//--- static function declarations
static void rm_dev(struct udev_device *dev, int dev_file);
static void rm_dev_tty(struct udev_device *dev, const char *node);

static void add_dev(struct udev_device *dev, int dev_file);
static void add_dev_tty(struct udev_device *dev);
static void add_dev_input(struct udev_device *dev);
static void add_dev_sound(struct udev_device *dev);

static int is_dev_monome_grid(struct udev_device *dev);
static int is_dev_crow(struct udev_device *dev);

static void *watch_loop(void *data);
#ifdef NORNS_LINUX_DESKTOP
static void add_dev_sound(struct udev_device *dev);
#endif

// try to get MIDI device name from ALSA
// returns a newly-allocated string (may be NULL)
static const char *get_alsa_midi_node(struct udev_device *dev);

// try to get product name from udev_device or its parents
// returns a newly-allocated string (may be NULL)
static char *get_device_name(struct udev_device *dev);

static inline void print_watch_error(const char *msg, int file_idx) {
    fprintf(stderr, "error: %s on subsystem %s", msg, dev_file_name[file_idx]);
}

//--------------------------------
//---- extern function definitions
void dev_monitor_init(void) {
    struct udev *udev = NULL;
    pthread_attr_t attr;
    int s;

    udev = udev_new();
    assert(udev);

    for (int fidx = 0; fidx < DEV_FILE_COUNT; ++fidx) {
        mon[fidx] = NULL;
        struct udev_monitor *m = udev_monitor_new_from_netlink(udev, "udev");
        if (m == NULL) {
            print_watch_error("couldn't create udev monitor", fidx);
            continue;
        }
        if (udev_monitor_filter_add_match_subsystem_devtype(m, dev_file_name[fidx], NULL) < 0) {
            print_watch_error("couldn't add subsys filter", fidx);
            continue;
        }
        if (udev_monitor_enable_receiving(m) < 0) {
            print_watch_error("failed to enable monitor", fidx);
            continue;
        }
        pfds[fidx].fd = udev_monitor_get_fd(m);
        pfds[fidx].events = POLLIN;
        mon[fidx] = m;
    }

    s = pthread_attr_init(&attr);
    if (s) {
        fprintf(stderr, "error initializing thread attributes\n");
    }
    s = pthread_create(&watch_tid, &attr, watch_loop, NULL);
    if (s) {
        fprintf(stderr, "error creating thread\n");
    }
    pthread_setname_np(watch_tid, "watch_loop");
    pthread_attr_destroy(&attr);
}

void dev_monitor_deinit(void) {
    pthread_cancel(watch_tid);
    for (int fidx = 0; fidx < DEV_FILE_COUNT; ++fidx) {
        if (mon[fidx] != NULL) {
            free(mon[fidx]);
        }
    }
}

int dev_monitor_scan(void) {
    struct udev *udev;
    struct udev_device *dev;

#ifdef NORNS_LINUX_DESKTOP
    // the computer keyboard, through the norns window (platform/linux/hid_virtual.cc)
    dev_list_add(DEV_TYPE_HID, LINUX_SDL_KEYBOARD_PATH, strdup("keyboard"), NULL);
    // MIDI from other programs through JACK (clock, notes): platform/linux/jack_midi_in.cc
    // it is the "virtual" device (in and out); without it (no JACK MIDI: NORNS_JACK_MIDI=0) the ALSA virtual port of upstream is the "virtual" device, as before
    if (jack_midi_in_start() != 0) {
        dev_list_add(DEV_TYPE_MIDI_VIRTUAL, NULL, "virtual", NULL);
    } else {
        // the same device is also a native ALSA sequencer port, "Verdandi out" (DAWs that read ALSA MIDI only): platform/linux/aseq_out.cc, NORNS_ALSA_MIDI=0 turns it off
        aseq_out_start();
    }
#endif

    udev = udev_new();
    if (udev == NULL) {
        fprintf(stderr, "dev_monitor: failed to create udev\n");
        return 1;
    }

    for (int fidx = 0; fidx < DEV_FILE_COUNT; ++fidx) {
        struct udev_enumerate *ue;
        struct udev_list_entry *devices, *dev_list_entry;

        ue = udev_enumerate_new(udev);
        udev_enumerate_add_match_subsystem(ue, dev_file_name[fidx]);
        udev_enumerate_scan_devices(ue);
        devices = udev_enumerate_get_list_entry(ue);

        udev_list_entry_foreach(dev_list_entry, devices) {
            const char *path;

            path = udev_list_entry_get_name(dev_list_entry);
            dev = udev_device_new_from_syspath(udev, path);

            if (dev != NULL) {
                if (udev_device_get_parent_with_subsystem_devtype(dev, "usb", NULL)) {
                    add_dev(dev, fidx);
                }
            }
            udev_device_unref(dev);
        }

        udev_enumerate_unref(ue);
    }
    return 0;
}

//-------------------------------
//--- static function definitions

#ifdef NORNS_LINUX_DESKTOP
// ---- the virtual MIDI card (snd-virmidi) is the bridge a DAW reads (Reaper lists raw hw: devices): a raw port has one reader, so norns must not open it as a controller.
// platform/linux/midi_ignore.h has the rules; audio.conf midi_ignore= (NORNS_MIDI_IGNORE, default "VirMIDI;Virtual Raw MIDI") and the target of alsa_midi_out_to name the cards. docs/port/KNOWN-ISSUES.md 40
static std::string read_small_file(const std::string &path) {
    std::string out;
    FILE *f = fopen(path.c_str(), "r");
    if (f == NULL) {
        return out;
    }
    char buf[1024];
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    buf[n] = '\0';
    fclose(f);
    return std::string(buf);
}

// the lines of /proc/asound/cards that belong to card N: the id line (" 2 [VirMIDI        ]: VirMIDI - VirMIDI") and the long name under it
static std::string proc_cards_entry(const std::string &cards, unsigned card) {
    std::string key = std::to_string(card) + " [";
    size_t pos = 0;
    while (pos < cards.size()) {
        size_t end = cards.find('\n', pos);
        if (end == std::string::npos) {
            end = cards.size();
        }
        size_t first = cards.find_first_not_of(' ', pos);
        if (first != std::string::npos && first < end && cards.compare(first, key.size(), key) == 0) {
            size_t end2 = end < cards.size() ? cards.find('\n', end + 1) : std::string::npos;
            return cards.substr(pos, (end2 == std::string::npos ? cards.size() : end2) - pos);
        }
        pos = end + 1;
    }
    return "";
}

// is this sound card (its midiC<n>D<m> node) one that must not be opened? what() = the card's id for the log
static bool midi_card_ignored(struct udev_device *dev, const char *node, std::string *what) {
    unsigned card = 0, devno = 0;
    if (node == NULL || sscanf(node, "/dev/snd/midiC%uD%u", &card, &devno) != 2) {
        return false;
    }
    std::vector<std::string> ids;
    const char *id = udev_device_get_sysattr_value(dev, "id");
    if (id != NULL) {
        ids.push_back(id);
        if (what != NULL) {
            *what = id;
        }
    }
    struct udev_device *d = dev;
    for (int depth = 0; d != NULL && depth < 4; depth++, d = udev_device_get_parent(d)) {
        const char *drv = udev_device_get_driver(d);
        if (drv != NULL) {
            ids.push_back(drv);
        }
        const char *product = udev_device_get_sysattr_value(d, "product"); // a USB device's name: what alsa_midi_out_to and midi_ignore may name
        if (product != NULL) {
            ids.push_back(product);
        }
    }
    const char *proc = getenv("NORNS_PROC_ASOUND");
    std::string root = proc != NULL ? proc : "/proc/asound";
    ids.push_back(read_small_file(root + "/card" + std::to_string(card) + "/id"));
    ids.push_back(proc_cards_entry(read_small_file(root + "/cards"), card));
    ids.push_back(read_small_file(root + "/card" + std::to_string(card) + "/midi" + std::to_string(devno)));
    if (midi_ignore::matches(midi_ignore::entries(getenv("NORNS_MIDI_IGNORE"), getenv("NORNS_ALSA_MIDI_OUT_TO")), ids)) {
        if (what != NULL && what->empty()) {
            *what = node;
        }
        return true;
    }
    return false;
}

static std::set<std::string> skip_said;     // nodes whose skipping was said already (once each)
static std::set<std::string> release_said;

// a card that must not be opened: said once; if it is in the list (opened before: the setting changed, or an older run), let go of it so that a DAW can open it
static void midi_card_skip(const char *node, const std::string &what) {
    if (dev_list_midi_ports_listed(node) > 0) {
        if (release_said.insert(node).second) {
            fprintf(stderr, "dev_monitor: released virtual raw MIDI card %s (%s): it was open, a DAW can open it now\n", what.c_str(), node);
        }
        dev_list_midi_release(node);
        return;
    }
    if (skip_said.insert(node).second) {
        fprintf(stderr, "dev_monitor: skipped virtual raw MIDI card %s (%s): not opened, a DAW reads it (midi_ignore in audio.conf)\n", what.c_str(), node);
    }
}

static volatile int midi_check_poke = 0;

void dev_monitor_poke(void) {
    midi_check_poke = 1;
}

static double mono_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

void dev_monitor_midi_check(void) {
    // 1. devices that went (their read thread found them gone, or their node is not there): out of the list, Lua hears it
    dev_list_midi_sweep();
    // 2. sound cards with MIDI ports that are not (all) in the list: add them. (udev's "add" event was missed or came before the card answered, a port was busy, an earlier add failed)
    static struct udev *check_udev = NULL;
    if (check_udev == NULL) {
        check_udev = udev_new();
    }
    struct udev_enumerate *ue = udev_enumerate_new(check_udev);
    if (ue == NULL) {
        return;
    }
    udev_enumerate_add_match_subsystem(ue, "sound");
    udev_enumerate_scan_devices(ue);
    struct udev_list_entry *entry;
    for (entry = udev_enumerate_get_list_entry(ue); entry != NULL; entry = udev_list_entry_get_next(entry)) {
        const char *syspath = udev_list_entry_get_name(entry);
        if (syspath == NULL) {
            continue;
        }
        struct udev_device *dev = udev_device_new_from_syspath(check_udev, syspath);
        if (dev == NULL) {
            continue;
        }
        const char *node = get_alsa_midi_node(dev);
        if (node != NULL) {
            std::string what;
            if (midi_card_ignored(dev, node, &what)) {
                midi_card_skip(node, what);
            } else {
                int listed = dev_list_midi_ports_listed(node);
                if (listed == 0 || (unsigned int)listed < dev_midi_port_count(node)) {
                    add_dev_sound(dev);
                }
            }
            free((void *)node);
        }
        udev_device_unref(dev);
    }
    udev_enumerate_unref(ue);
}

// the watch loop calls this about every 100 ms: the MIDI check runs every 3 seconds, and at once after a poke
void dev_monitor_watch_tick(double *last) {
    double now = mono_seconds();
    if (midi_check_poke || now - *last >= 3.0) {
        midi_check_poke = 0;
        *last = now;
        dev_monitor_midi_check();
    }
}
#endif

void *watch_loop(void *p) {
    (void)p;
    struct udev_device *dev;
#ifdef NORNS_LINUX_DESKTOP
    double last_check = 0;
#endif

    while (1) {
#ifdef NORNS_LINUX_DESKTOP
        dev_monitor_watch_tick(&last_check);
#endif
        if (poll(pfds, DEV_FILE_COUNT, WATCH_TIMEOUT_MS) < 0) {
            switch (errno) {
            case EINVAL:
                perror("error in poll()");
                exit(1);
            case EINTR:
            case EAGAIN:
                continue;
            }
        }

        for (int fidx = 0; fidx < DEV_FILE_COUNT; ++fidx) {
            if (pfds[fidx].revents & POLLIN) {
                dev = udev_monitor_receive_device(mon[fidx]);
                if (dev) {
                    const char *action = udev_device_get_action(dev);
                    if (action != NULL) {
#ifdef NORNS_LINUX_DESKTOP
                        // only "add" is a new device: a "change" (serialosc's reader opening the port, ModemManager, a udev rule) or "bind" made the same grid a second device
                        // (device_dedupe.h, docs/port/KNOWN-ISSUES.md 31)
                        if (dev_action_is_remove(action)) {
                            rm_dev(dev, fidx);
                        } else if (dev_action_is_add(action)) {
                            add_dev(dev, fidx);
                        }
#else
                        if (strcmp(action, "remove") == 0) {
                            rm_dev(dev, fidx);
                        } else {
                            add_dev(dev, fidx);
                        }
#endif
                    } else {
                        fprintf(stderr, "dev_monitor error: unknown device action\n");
                    }
                    udev_device_unref(dev);
                } else {
                    fprintf(stderr, "dev_monitor error: no device data\n");
                }
            }
        }
    }
}

void rm_dev(struct udev_device *dev, int dev_file) {
    const char *node = udev_device_get_devnode(dev);
    if (node == NULL) {
        return;
    }
    switch (dev_file) {
    case DEV_FILE_TTY:
        rm_dev_tty(dev, node);
        break;
    case DEV_FILE_INPUT:
        dev_list_remove(DEV_TYPE_HID, node);
        break;
    case DEV_FILE_SOUND:
        dev_list_remove(DEV_TYPE_MIDI, node);
        break;
    case DEV_FILE_NONE:
    default:;
        ;
    }
}

void rm_dev_tty(struct udev_device *dev, const char *node) {
    // fprintf(stderr, "rm_dev_tty: %s\n", node);

    if (is_dev_monome_grid(dev)) {
        fprintf(stderr, "dev_monitor: tty appears to be monome\n");
        dev_list_remove(DEV_TYPE_MONOME, node);
        return;
    }

    if (is_dev_crow(dev)) {
        dev_list_remove(DEV_TYPE_CROW, node);
        return;
    }

    fprintf(stderr, "dev_monitor: unmatched tty device was removed from %s\n", node);
    dev_list_remove(DEV_TYPE_SERIAL, node);
}

void add_dev(struct udev_device *dev, int fidx) {
    switch (fidx) {
    case DEV_FILE_TTY:
        add_dev_tty(dev);
        break;
    case DEV_FILE_INPUT:
        add_dev_input(dev);
        break;
    case DEV_FILE_SOUND:
        add_dev_sound(dev);
        break;
    case DEV_FILE_NONE:
    default:
        break;
    }
}

void add_dev_tty(struct udev_device *dev) {
    const char *node = udev_device_get_devnode(dev);
    if (node == NULL) {
        // not a physical device. for the moment we are not concerned with input from virtual inputs
        return;
    }
    char *name = get_device_name(dev);
    if (name == NULL) {
        return;
    }
    if (is_dev_monome_grid(dev)) {
        fprintf(stderr, "dev_monitor: TTY appears to be a monome\n");
        dev_list_add(DEV_TYPE_MONOME, node, name, NULL);
    } else if (is_dev_crow(dev)) {
        fprintf(stderr, "tty is a crow\n");
        dev_list_add(DEV_TYPE_CROW, node, name, NULL);
    } else {
        fprintf(stderr, "dev_monitor: unmatched TTY device %s at %s\n", name, node);
        const char *vendor, *model, *serial, *interface;
        vendor = udev_device_get_property_value(dev, "ID_VENDOR");
        model = udev_device_get_property_value(dev, "ID_MODEL");
        serial = udev_device_get_property_value(dev, "ID_SERIAL_SHORT");
        interface = udev_device_get_property_value(dev, "ID_USB_INTERFACE_NUM");

        union event_data *ev;
        ev = event_data_new(EVENT_SERIAL_CONFIG);
        ev->serial_config.vendor = strdup(vendor != NULL ? vendor : "");
        ev->serial_config.model = strdup(model != NULL ? model : "");
        ev->serial_config.path = strdup(node);
        ev->serial_config.name = name;
        ev->serial_config.serial = strdup(serial != NULL ? serial : "");
        ev->serial_config.interface = strdup(interface != NULL ? interface : "");
        event_post(ev);
    }
}

void add_dev_input(struct udev_device *dev) {
    const char *node = udev_device_get_devnode(dev);
    if (node == NULL) {
        fprintf(stderr, "dev_monitor: skipping node-less entry in /dev/input\n");
        return;
    }
    char *name = get_device_name(dev);
    if (name == NULL) {
        return;
    }
    dev_list_add(DEV_TYPE_HID, node, name, NULL);
}

void add_dev_sound(struct udev_device *dev) {
    // try to act according to
    // https://github.com/systemd/systemd/blob/master/rules/78-sound-card.rules
    const char *alsa_node = get_alsa_midi_node(dev);
#ifdef NORNS_LINUX_DESKTOP
    if (alsa_node != NULL) {
        std::string what;
        if (midi_card_ignored(dev, alsa_node, &what)) {
            midi_card_skip(alsa_node, what);
            free((void *)alsa_node);
            return;
        }
    }
#endif
    if (alsa_node != NULL) {
        char *name = get_device_name(dev);
        if (name == NULL) {
            free((void *)alsa_node);
            return;
        }
        fprintf(stderr, "dev_monitor: adding midi device %s\n", name);
        dev_list_add(DEV_TYPE_MIDI, alsa_node, name, NULL);
    }
}

// try to get midi device node from udev_device
const char *get_alsa_midi_node(struct udev_device *dev) {
    const char *subsys;
    const char *syspath;
    DIR *sysdir;
    struct dirent *sysdir_ent;
    int alsa_card, alsa_dev;
    char *result = NULL;

    subsys = udev_device_get_subsystem(dev);

    if (subsys != NULL && strcmp(subsys, "sound") == 0) {
        syspath = udev_device_get_syspath(dev);
        if (syspath == NULL || (sysdir = opendir(syspath)) == NULL) {
            fprintf(stderr, "dev_monitor: sound device without a readable syspath, skipped\n");
            return NULL;
        }

        while ((sysdir_ent = readdir(sysdir)) != NULL) {
            if (sscanf(sysdir_ent->d_name, "midiC%uD%u", &alsa_card, &alsa_dev) == 2) {
                if (asprintf(&result, "/dev/snd/%s", sysdir_ent->d_name) < 0) {
                    fprintf(stderr, "dev_monitor: failed to create alsa device path for %s\n", sysdir_ent->d_name);
                    closedir(sysdir);
                    return NULL;
                }
            }
        }
        closedir(sysdir);
    }

    return result;
}

char *get_device_name(struct udev_device *dev) {
    char *current_name = NULL;
    struct udev_device *current_dev = dev;

    while (current_name == NULL) {
        current_name = (char *)udev_device_get_sysattr_value(current_dev, "product");
        current_dev = udev_device_get_parent(current_dev);

        if (current_dev == NULL) {
            break;
        }
    }

    if (current_name == NULL) {
        // no "product" on the device or any parent (a lid switch, a speaker, a jack): never hand strdup a NULL
        const char *model = udev_device_get_property_value(dev, "ID_MODEL");
        current_name = (char *)(model != NULL ? model : "unknown");
        fprintf(stderr, "dev_monitor: device has no product name, using \"%s\"\n", current_name);
    }

    return strdup(current_name);
}

int is_dev_monome_grid(struct udev_device *dev) {
    const char *vendor, *model, *vendor_id, *model_id;

    vendor = udev_device_get_property_value(dev, "ID_VENDOR");
    model = udev_device_get_property_value(dev, "ID_MODEL");
    vendor_id = vendor != NULL ? vendor : udev_device_get_property_value(dev, "ID_VENDOR_ID");
    model_id = model != NULL ? model : udev_device_get_property_value(dev, "ID_MODEL_ID");

    fprintf(stderr, "dev_monitor: vendor=%s model=%s\n", vendor_id, model_id);

    if (vendor == NULL || model == NULL) {
        return 0;
    }

    if (strcmp(vendor, "monome") != 0) {
        return 0;
    }

    if (strcmp(model, "grid") == 0) {
        return 1;
    }
    if (strcmp(model, "arc") == 0) {
        return 1;
    }
    if (strncmp(model, "monome", 6) == 0) {
        // probably a clone or older grid (monome, monome_128)
        return 1;
    }

    return 0;
}

int is_dev_crow(struct udev_device *dev) {
    const char *device_product_string = udev_device_get_property_value(dev, "ID_MODEL");
    if (device_product_string != NULL) {
        return strcmp(device_product_string, "crow:_telephone_line") == 0;
    }
    return 0;
}
