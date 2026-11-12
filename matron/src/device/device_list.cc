#include <search.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "device.h"
#include "device_list.h"
#include "device_midi.h"
#include "events.h"
#ifdef NORNS_LINUX_DESKTOP
#include "device_dedupe.h"
#endif

static int id = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

struct dev_node {
    struct dev_node *next;
    struct dev_node *prev;
    union dev *d;
};

struct dev_q {
    struct dev_node *head;
    struct dev_node *tail;
    size_t size;
};

struct dev_q dq;

static struct dev_node *dev_lookup_path(const char *path, struct dev_node *node_head) {
    const char *npath;

    if (path == NULL) {
        return NULL;
    }

    if (node_head == NULL) {
        node_head = dq.head;
    }

    while (node_head != NULL) {
        npath = node_head->d->base.path;
        if (npath != NULL && strcmp(path, npath) == 0) {
            return node_head;
        }
        node_head = node_head->next;
    }
    return NULL;
}

#ifdef NORNS_LINUX_DESKTOP
#include <unistd.h>

// ALSA rawmidi nodes (a USB MIDI device); the JACK "virtual" device and the keys window have other paths
static bool is_alsa_midi_path(const char *p) {
#ifdef NORNS_WINDOWS
    // Windows: the devices of the MIDI layer (platform/windows/midi): "winmm:<name>" and the OSC input "osc:..."; the list logic is the same as for the ALSA nodes
    return p != NULL && (strncmp(p, "winmm:", 6) == 0 || strncmp(p, "osc:", 4) == 0);
#else
    return p != NULL && strncmp(p, "/dev/snd/midiC", 14) == 0;
#endif
}
// is the device node there (Linux: the file; Windows: the last scan lists it)
static bool midi_node_present(const char *p) {
#ifdef NORNS_WINDOWS
    return dev_midi_node_present(p) != 0;
#else
    return access(p, F_OK) == 0;
#endif
}

// one line in the log for a node that could not be added, said once until it works (the periodic check tries again every few seconds)
static char failed_path[256];
static void midi_add_failed(const char *path, const char *why) {
    if (strncmp(failed_path, path, sizeof failed_path) != 0) {
        snprintf(failed_path, sizeof failed_path, "%s", path);
        fprintf(stderr, "midi: could not add %s: %s; it is tried again every few seconds\n", path, why);
    }
}
static void midi_add_worked(const char *path) {
    if (strncmp(failed_path, path, sizeof failed_path) == 0) {
        failed_path[0] = '\0';
    }
}
#endif

void dev_list_init(void) {
    dq.size = 0;
    dq.head = NULL;
    dq.tail = NULL;
}

extern "C" union event_data *post_add_event(union dev *d, event_t event_type) {
    if (d == NULL) {
        fprintf(stderr, "dev_list_add: error allocating device data\n");
        return NULL;
    }

    struct dev_node *dn = (dev_node *)calloc(1, sizeof(struct dev_node));

    if (dn == NULL) {
        fprintf(stderr, "dev_list_add: error allocating device queue node\n");
        free(d);
        return NULL;
    }

    d->base.id = id++;
    dn->d = d;

    pthread_mutex_lock(&lock);
    insque(dn, dq.tail);
    dq.tail = dn;
    if (dq.size == 0) {
        dq.head = dn;
    }
    dq.size++;
    pthread_mutex_unlock(&lock);

    union event_data *ev;
    ev = event_data_new(event_type);
    return ev;
}

void dev_list_add(device_t type, const char *path, const char *name, lua_State *l) {
    if (type < 0) {
        return;
    }
#ifdef NORNS_LINUX_DESKTOP
    // a device node that is already listed is not added again (a repeated event, a rescan): one grid, one entry (device_dedupe.h, docs/port/KNOWN-ISSUES.md 31). MIDI keeps its several ports per path
    if (type == DEV_TYPE_MONOME || type == DEV_TYPE_HID || type == DEV_TYPE_CROW || type == DEV_TYPE_SERIAL) {
        pthread_mutex_lock(&lock);
        bool known = false;
        for (struct dev_node *dn = dq.head; dn != NULL; dn = dn->next) {
            if (dn->d != NULL && dn->d->base.type == type && dev_same_node(path, dn->d->base.path)) {
                known = true;
                break;
            }
        }
        pthread_mutex_unlock(&lock);
        if (known) {
            fprintf(stderr, "dev_list_add: %s is listed already: not added again\n", path != NULL ? path : "?");
            return;
        }
    }
#endif

    union event_data *ev;
    union dev *d;
    unsigned int midi_port_count = 0;

    switch (type) {
    case DEV_TYPE_MIDI:
#ifdef NORNS_LINUX_DESKTOP
        if (is_alsa_midi_path(path)) {
            // a device of this node whose read thread found it gone (unplugged, powered off) is not coming back: it leaves the list first, so that Lua has removed it before the device that took its place is added
            dev_list_midi_sweep();
            midi_port_count = dev_midi_port_count(path);
            if (midi_port_count == 0) {
                midi_add_failed(path, "the card does not answer (yet)");
                free((void *)name);
                return;
            }
            bool name_used = false;
            int added = 0, failed = 0;
            for (unsigned int pidx = 0; pidx < midi_port_count; pidx++) {
                bool listed = false;
                pthread_mutex_lock(&lock);
                for (struct dev_node *dn = dq.head; dn != NULL; dn = dn->next) {
                    if (dn->d != NULL && dn->d->base.type == DEV_TYPE_MIDI && dn->d->base.path != NULL && strcmp(dn->d->base.path, path) == 0 && dn->d->midi.port_index == pidx) {
                        listed = true;
                        break;
                    }
                }
                pthread_mutex_unlock(&lock);
                if (listed) {
                    fprintf(stderr, "midi: %s port %u is listed already, not added again\n", path, pidx);
                    continue;
                }
                d = dev_new(type, path, name, midi_port_count > 1, pidx, NULL);
                if (d == NULL) {
                    failed++;
                    midi_add_failed(path, "the port could not be opened");
                    continue;
                }
                if (midi_port_count <= 1) {
                    name_used = true; // the device owns the name
                }
                ev = post_add_event(d, EVENT_MIDI_ADD);
                if (ev != NULL) {
                    fprintf(stderr, "midi: added %s (%s port %u)\n", d->base.name != NULL ? d->base.name : "?", path, pidx);
                    ev->midi_add.dev = d;
                    event_post(ev);
                    added++;
                }
            }
            if (failed == 0) {
                midi_add_worked(path);
            }
            if (!name_used) {
                free((void *)name); // every port has a name of its own, or none was added
            }
            (void)added;
            return;
        }
#endif
        midi_port_count = dev_midi_port_count(path);
        for (unsigned int pidx = 0; pidx < midi_port_count; pidx++) {
            d = dev_new(type, path, name, midi_port_count > 1, pidx, NULL);
            ev = post_add_event(d, EVENT_MIDI_ADD);
            if (ev != NULL) {
                ev->midi_add.dev = d;
                event_post(ev);
            }
        }
        return;
    case DEV_TYPE_MIDI_VIRTUAL:
        d = dev_new(DEV_TYPE_MIDI_VIRTUAL, NULL, name, false, 0, NULL);
        ev = post_add_event(d, EVENT_MIDI_ADD);
        if (ev != NULL) {
            ev->midi_add.dev = d;
            event_post(ev);
        }
        return;
    case DEV_TYPE_MONOME:
        d = dev_new(type, path, name, true, 0, NULL);
        ev = post_add_event(d, EVENT_MONOME_ADD);
        break;
    case DEV_TYPE_HID:
        d = dev_new(type, path, name, true, 0, NULL);
        ev = post_add_event(d, EVENT_HID_ADD);
        break;
    case DEV_TYPE_CROW:
        d = dev_new(type, path, name, true, 0, NULL);
        ev = post_add_event(d, EVENT_CROW_ADD);
        break;
    case DEV_TYPE_SERIAL:
        if (l == NULL) {
            fprintf(stderr, "dev_list_add(): serial device requires lua vm\n");
            return;
        }
        d = dev_new(type, path, name, true, 0, l);
        ev = post_add_event(d, EVENT_SERIAL_ADD);
        break;
    default:
        fprintf(stderr, "dev_list_add(): error posting event (unknown type)\n");
        return;
    }
    if (ev != NULL) {
        ev->monome_add.dev = d;
        event_post(ev);
    }
}

static void dev_list_remove_node(struct dev_node *dn, union event_data *event_remove) {
    event_post(event_remove);

    if (dq.head == dn) {
        dq.head = dn->next;
    }
    if (dq.tail == dn) {
        dq.tail = dn->prev;
    }
    remque(dn);
    dq.size--;

    dev_delete(dn->d);
    free(dn);
}

void dev_list_remove(device_t type, const char *node) {
    pthread_mutex_lock(&lock);
    struct dev_node *dn = dev_lookup_path(node, NULL);
    if (dn == NULL) {
        pthread_mutex_unlock(&lock);
        return;
    }
    union event_data *ev;

    switch (type) {
    case DEV_TYPE_MIDI:
#ifdef NORNS_LINUX_DESKTOP
        if (is_alsa_midi_path(node)) {
            // a remove that comes after the device was plugged in again (events are not always in order) must not take the new device away: the node is there and nothing has found the device gone.
            // if it really went, the read thread says so (-ENODEV) and the periodic check removes it
            bool gone = false;
            for (struct dev_node *x = dn; x != NULL; x = x->next) {
                if (x->d->base.type == DEV_TYPE_MIDI && x->d->base.path != NULL && strcmp(x->d->base.path, node) == 0 && x->d->midi.gone) {
                    gone = true;
                }
            }
#ifdef NORNS_WINDOWS
            gone = true; // the monitor removes a device only when the scan no longer lists it
#endif
            if (!gone && midi_node_present(node)) {
                fprintf(stderr, "midi: remove of %s ignored: the node is there and the device answers (a late event)\n", node);
                pthread_mutex_unlock(&lock);
                return;
            }
        }
#endif
        while (dn != NULL) {
            ev = event_data_new(EVENT_MIDI_REMOVE);
            ev->midi_remove.id = dn->d->base.id;
#ifdef NORNS_LINUX_DESKTOP
            fprintf(stderr, "midi: removed %s (%s): udev remove\n", dn->d->base.name != NULL ? dn->d->base.name : "?", node);
#endif
            dev_list_remove_node(dn, ev);
            dn = dev_lookup_path(node, NULL);
        }
        pthread_mutex_unlock(&lock);
        return;
    case DEV_TYPE_MONOME:
        ev = event_data_new(EVENT_MONOME_REMOVE);
        ev->monome_remove.id = dn->d->base.id;
        break;
    case DEV_TYPE_HID:
        ev = event_data_new(EVENT_HID_REMOVE);
        ev->hid_remove.id = dn->d->base.id;
        break;
    case DEV_TYPE_CROW:
        ev = event_data_new(EVENT_CROW_REMOVE);
        ev->crow_remove.id = dn->d->base.id;
        break;
    case DEV_TYPE_SERIAL:
        ev = event_data_new(EVENT_SERIAL_REMOVE);
        ev->serial_remove.id = dn->d->base.id;
        ev->serial_remove.handler_id = dn->d->serial.handler_id != NULL ? strdup(dn->d->serial.handler_id) : NULL;
        break;
    default:
        fprintf(stderr, "dev_list_remove(): error posting event (unknown type)\n");
        pthread_mutex_unlock(&lock);
        return;
    }
    dev_list_remove_node(dn, ev);
    pthread_mutex_unlock(&lock);
}

#ifdef NORNS_LINUX_DESKTOP
#include <errno.h>
#include <pthread.h>
#include <time.h>

static void *monome_off_thread(void *arg) {
    struct dev_monome *md = (struct dev_monome *)arg;
    if (md->m == NULL) {
        return NULL;
    }
    dev_monome_all_led(md, 0, false);
    dev_monome_refresh(md);
    if (md->type == DEVICE_MONOME_TYPE_GRID) {
        monome_led_all(md->m, 0); // a grid without levels takes this one
    }
    return NULL;
}

int dev_list_midi_sweep(void) {
    int removed = 0;
    pthread_mutex_lock(&lock);
    for (struct dev_node *dn = dq.head; dn != NULL;) {
        struct dev_node *next = dn->next;
        if (dn->d != NULL && dn->d->base.type == DEV_TYPE_MIDI && is_alsa_midi_path(dn->d->base.path)) {
            bool node_missing = !midi_node_present(dn->d->base.path);
            if (dn->d->midi.gone || node_missing) {
                union event_data *ev = event_data_new(EVENT_MIDI_REMOVE);
                ev->midi_remove.id = dn->d->base.id;
                fprintf(stderr, "midi: removed %s (%s): %s, no udev remove came\n", dn->d->base.name != NULL ? dn->d->base.name : "?", dn->d->base.path,
                        dn->d->midi.gone ? "the device vanished" : "the node is gone");
                dev_list_remove_node(dn, ev);
                removed++;
            }
        }
        dn = next;
    }
    pthread_mutex_unlock(&lock);
    return removed;
}

int dev_list_midi_release(const char *node) {
    int n = 0;
    pthread_mutex_lock(&lock);
    for (struct dev_node *dn = dev_lookup_path(node, NULL); dn != NULL; dn = dev_lookup_path(node, NULL)) {
        union event_data *ev = event_data_new(EVENT_MIDI_REMOVE);
        ev->midi_remove.id = dn->d->base.id;
        fprintf(stderr, "midi: released %s (%s)\n", dn->d->base.name != NULL ? dn->d->base.name : "?", node);
        dev_list_remove_node(dn, ev);
        n++;
    }
    pthread_mutex_unlock(&lock);
    return n;
}

int dev_list_midi_ports_listed(const char *node) {
    int n = 0;
    pthread_mutex_lock(&lock);
    for (struct dev_node *dn = dq.head; dn != NULL; dn = dn->next) {
        if (dn->d != NULL && dn->d->base.type == DEV_TYPE_MIDI && dn->d->base.path != NULL && node != NULL && strcmp(dn->d->base.path, node) == 0) {
            n++;
        }
    }
    pthread_mutex_unlock(&lock);
    return n;
}

bool dev_list_has_monome(struct dev_monome *md) {
    pthread_mutex_lock(&lock);
    bool found = false;
    for (struct dev_node *dn = dq.head; dn != NULL; dn = dn->next) {
        if (dn->d != NULL && &dn->d->monome == md) {
            found = true;
            break;
        }
    }
    pthread_mutex_unlock(&lock);
    return found;
}

void dev_list_monome_all_off(int timeout_ms) {
    pthread_t th[16];
    int n = 0;
    struct timespec dl;
    clock_gettime(CLOCK_REALTIME, &dl);
    dl.tv_sec += timeout_ms / 1000;
    dl.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (dl.tv_nsec >= 1000000000L) {
        dl.tv_sec++;
        dl.tv_nsec -= 1000000000L;
    }
    for (struct dev_node *dn = dq.head; dn != NULL && n < 16; dn = dn->next) {
        if (dn->d != NULL && dn->d->base.type == DEV_TYPE_MONOME && dn->d->monome.m != NULL) {
            if (pthread_create(&th[n], NULL, monome_off_thread, &dn->d->monome) == 0) {
                n++;
            }
        }
    }
    for (int i = 0; i < n; i++) {
        if (pthread_timedjoin_np(th[i], NULL, &dl) != 0) {
            pthread_detach(th[i]); // a device that does not answer: go on without it
        }
    }
}
#endif
