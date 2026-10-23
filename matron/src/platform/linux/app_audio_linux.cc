/*
 * app_audio_linux.cc: see platform/macos/app_audio.h
 *
 * what feeds crone:input_1/2 on a desktop with JACK or PipeWire's JACK: the sound card's capture ports (MIC), every
 * application's output ports except norns' own (SYS), one application's (APP), or, as an option, the monitor of the
 * chosen output card (it hears norns too). done with JACK connections from a small client "Verdandi ctl"; the
 * decisions are crone/src/InputRoute.h (tested). while SYS / APP / the monitor is on, a port registration callback
 * wakes a thread that connects new streams (a browser starting to play) without a poll.
 */

#include <jack/jack.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <chrono>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../macos/app_audio.h"
#include "InputRoute.h"
#include "crone_main.h"
#include "input_route.h"

using namespace crone::InputRoute;

static std::mutex mtx;
static jack_client_t *client = NULL;
static sem_t wake;
static bool mic_live = true; // crone connected the card itself
static std::string tap;      // "" none, APP_AUDIO_SYSTEM, an application's name, APP_AUDIO_SINK_MONITOR
static std::string tap_mode; // for desired(): system, app, monitor

static void on_registration(jack_port_id_t port, int reg, void *arg) {
    (void)port;
    (void)reg;
    (void)arg;
    sem_post(&wake); // only this: no jack calls in a jack callback
}

static void on_client_registration(const char *name, int reg, void *arg) {
    (void)name;
    (void)reg;
    (void)arg;
    sem_post(&wake);
}

static std::vector<PortInfo> snapshot(void) {
    std::vector<PortInfo> out;
    const char **names = jack_get_ports(client, NULL, NULL, 0);
    for (int i = 0; names != NULL && names[i] != NULL; i++) {
        jack_port_t *p = jack_port_by_name(client, names[i]);
        if (p == NULL) {
            continue;
        }
        int flags = jack_port_flags(p);
        out.push_back(PortInfo{names[i], strcmp(jack_port_type(p), JACK_DEFAULT_AUDIO_TYPE) == 0,
                               (flags & JackPortIsPhysical) != 0, (flags & JackPortIsOutput) != 0});
    }
    if (names != NULL) {
        jack_free(names);
    }
    return out;
}

static std::vector<Link> current(void) {
    std::vector<Link> out;
    for (const char *dst : {"crone:input_1", "crone:input_2"}) {
        jack_port_t *p = jack_port_by_name(client, dst);
        const char **c = p != NULL ? jack_port_get_all_connections(client, p) : NULL;
        for (int i = 0; c != NULL && c[i] != NULL; i++) {
            out.push_back(Link{c[i], dst});
        }
        if (c != NULL) {
            jack_free(c);
        }
    }
    return out;
}

// full: also take away what is there and not wanted (a change of mode); else only connect what is missing
// (a new stream). mtx held
static void apply(bool full) {
    if (client == NULL) {
        return;
    }
    std::string mode = mic_live ? "mic" : (tap.empty() ? "off" : tap_mode);
    const char *pre = getenv("NORNS_IN_PORTS");
    char outc[256];
    crone_audio_status(2, outc, sizeof outc);
    std::vector<Link> want = desired(mode, tap, snapshot(), pre != NULL ? pre : "", outc);
    std::vector<Link> have = current();
    if (full) {
        for (const auto &k : surplus(want, have)) {
            jack_disconnect(client, k.from.c_str(), k.to.c_str());
        }
    }
    for (const auto &k : missing(want, have)) {
        int err = jack_connect(client, k.from.c_str(), k.to.c_str());
        if (err != 0 && err != EEXIST) {
            fprintf(stderr, "app_audio: could not connect %s to %s\n", k.from.c_str(), k.to.c_str());
        }
    }
}

static void worker(void) {
    for (;;) {
        sem_wait(&wake);
        // a stream registers its ports one by one: let them settle, then look once
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        while (sem_trywait(&wake) == 0) {
        }
        std::lock_guard<std::mutex> l(mtx);
        if (!mic_live && !tap.empty()) {
            apply(false);
        }
    }
}

static int ensure_client(void) {
    std::lock_guard<std::mutex> l(mtx);
    if (client != NULL) {
        return 1;
    }
    jack_client_t *c = jack_client_open("Verdandi ctl", JackNoStartServer, NULL);
    if (c == NULL) {
        return 0;
    }
    sem_init(&wake, 0, 0);
    jack_set_port_registration_callback(c, on_registration, NULL);
    jack_set_client_registration_callback(c, on_client_registration, NULL);
    jack_activate(c);
    client = c;
    std::thread(worker).detach();
    return 1;
}

extern "C" {

int app_audio_available(void) {
    return ensure_client();
}

int app_audio_list(app_audio_app_t *out, int max) {
    if (!ensure_client()) {
        return 0;
    }
    std::lock_guard<std::mutex> l(mtx);
    int n = 0;
    for (const auto &a : listApps(snapshot())) {
        if (n >= max) {
            break;
        }
        memset(&out[n], 0, sizeof out[n]);
        snprintf(out[n].name, sizeof out[n].name, "%s", a.name.c_str());
        snprintf(out[n].bundle, sizeof out[n].bundle, "%s", a.name.c_str());
        out[n].playing = 0;
        n++;
    }
    return n;
}

int app_audio_select(const char *bundle) {
    if (bundle == NULL) {
        std::lock_guard<std::mutex> l(mtx);
        tap.clear();
        apply(true);
        return 1;
    }
    if (!ensure_client()) {
        return 0;
    }
    std::lock_guard<std::mutex> l(mtx);
    tap = bundle;
    tap_mode = tap == APP_AUDIO_SYSTEM ? "system" : tap == APP_AUDIO_SINK_MONITOR ? "monitor" : "app";
    apply(true);
    return 1; // an application that is not running yet is picked up when it appears
}

const char *app_audio_current(void) {
    static char buf[256];
    std::lock_guard<std::mutex> l(mtx);
    if (tap.empty()) {
        return NULL;
    }
    snprintf(buf, sizeof buf, "%s", tap.c_str());
    return buf;
}

void input_route_mic(int live) {
    if (!ensure_client()) {
        return;
    }
    std::lock_guard<std::mutex> l(mtx);
    mic_live = live != 0;
    apply(true);
}

int input_route_monitor_enabled(void) {
    const char *e = getenv("NORNS_SYS_MONITOR");
    return e != NULL && strcmp(e, "1") == 0;
}

} // extern "C"
