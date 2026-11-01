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
        while (dn != NULL) {
            ev = event_data_new(EVENT_MIDI_REMOVE);
            ev->midi_remove.id = dn->d->base.id;
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
