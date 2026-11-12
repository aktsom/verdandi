// grid_monitor.cc: see grid_monitor.h
#include "grid_monitor.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include <map>
#include <set>
#include <string>
#include <vector>

#include "grid_core.h"

namespace {
const vgrid_backend *BE;
vgrid_sink SINK;
vgrid::Rules RULES;
pthread_mutex_t LK = PTHREAD_MUTEX_INITIALIZER;

struct Known {
    std::string port;       // the COM port it is on now
    std::string serial;
    std::string friendly;
    double last_try = 0;    // monotonic seconds of the last probe + add
    double added_at = 0;    // when the add was handed to the device list (0 = not yet)
};
std::map<std::string, Known> KNOWN;           // key (serial, else the port name) -> grid
std::map<std::string, std::string> NOTES;     // port -> text (problems of grids)
std::map<std::string, std::string> OTHERS;    // port -> why it is not a grid
std::set<std::string> TOLD;                   // log lines said once

double mono() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

void said_once(const std::string &key, const std::string &line) {
    if (TOLD.insert(key).second) fprintf(stderr, "grid: %s\n", line.c_str());
}

const char *HELD = "another program has this port open (serialosc? a serial terminal? another app that talks to the grid?). Close it there; Verdandi opens the grid when the port is free";
} // namespace

void vgrid_monitor_init(const vgrid_backend *be, const vgrid_sink *sink, const char *monome_serial, const char *monome_ignore) {
    BE = be;
    SINK = *sink;
    RULES.extra_serials = vgrid::split_list(monome_serial ? monome_serial : "");
    RULES.ignore = vgrid::split_list(monome_ignore ? monome_ignore : "");
}

int vgrid_monitor_scan(void) {
    if (!BE) return 0;
    static vgrid_port_info ports[64];
    int n = BE->list(ports, 64);
    int changes = 0;
    double now = mono();
    std::map<std::string, vgrid_port_info> grids; // key -> port
    std::vector<std::string> to_remove;
    pthread_mutex_lock(&LK);
    OTHERS.clear();
    for (int i = 0; i < n; i++) {
        vgrid::Port p;
        p.name = ports[i].name; p.vid = ports[i].vid; p.pid = ports[i].pid; p.serial = ports[i].serial; p.friendly = ports[i].friendly;
        vgrid::Result r = vgrid::classify(p, RULES);
        if (r.v == vgrid::GRID) {
            grids[p.serial.empty() ? p.name : p.serial] = ports[i];
        } else if (r.v == vgrid::NOT_MONOME) {
            OTHERS[p.name] = std::string(p.friendly.empty() ? "serial port" : p.friendly) + ": " + r.why;
            said_once("other:" + p.name + ":" + p.serial, "skipped " + p.name + " (" + p.friendly + "): " + r.why);
        } else {
            said_once("ignored:" + p.name + ":" + p.serial, "skipped " + p.name + ": " + r.why);
        }
    }
    // gone, or moved to another port
    std::vector<std::string> gone;
    for (auto &kv : KNOWN) {
        auto it = grids.find(kv.first);
        if (it == grids.end() || kv.second.port != it->second.name) gone.push_back(kv.first);
    }
    for (auto &k : gone) {
        bool moved = grids.count(k) != 0;
        fprintf(stderr, "grid: removed %s on %s%s\n", KNOWN[k].serial.empty() ? "a grid" : KNOWN[k].serial.c_str(), KNOWN[k].port.c_str(), moved ? " (it is on another port now)" : ": it is gone");
        NOTES.erase(KNOWN[k].port);
        if (KNOWN[k].added_at > 0) to_remove.push_back(KNOWN[k].port);
        for (auto it = TOLD.begin(); it != TOLD.end();) it = it->find("held:" + KNOWN[k].port) == 0 || it->find("unanswered:" + KNOWN[k].port) == 0 ? TOLD.erase(it) : std::next(it);
        KNOWN.erase(k);
    }
    pthread_mutex_unlock(&LK);
    for (auto &p : to_remove) {
        if (SINK.remove) SINK.remove(p.c_str());
        changes++;
    }
    for (auto &kv : grids) {
        const vgrid_port_info &pi = kv.second;
        pthread_mutex_lock(&LK);
        Known &k = KNOWN[kv.first];
        bool fresh = k.port.empty();
        if (fresh) { k.port = pi.name; k.serial = pi.serial; k.friendly = pi.friendly; }
        bool added = k.added_at > 0, wait = !fresh && now - k.last_try < 3.0;
        pthread_mutex_unlock(&LK);
        bool listed = added && SINK.listed && SINK.listed(pi.name);
        if (listed) {
            pthread_mutex_lock(&LK);
            NOTES.erase(pi.name);
            pthread_mutex_unlock(&LK);
            continue;
        }
        if (wait) continue;
        if (added) {
            // handed over, but the device list does not have it: libmonome got no answer from the grid
            pthread_mutex_lock(&LK);
            NOTES[pi.name] = std::string("a monome is on this port but did not answer (") + (pi.serial[0] ? pi.serial : "no serial") + std::string("). Unplug it and plug it in again; it is tried again every few seconds");
            said_once(std::string("unanswered:") + pi.name, std::string(pi.name) + ": " + NOTES[pi.name]);
            pthread_mutex_unlock(&LK);
        }
        char why[160] = "";
        int pr = BE->probe ? BE->probe(pi.name, why, sizeof why) : 0;
        pthread_mutex_lock(&LK);
        KNOWN[kv.first].last_try = now;
        if (pr == 1) {
            NOTES[pi.name] = HELD;
            said_once(std::string("held:") + pi.name, std::string(pi.name) + ": " + HELD);
        } else if (pr != 0) {
            NOTES[pi.name] = std::string("the port cannot be opened: ") + why;
            said_once(std::string("held:") + pi.name + ":err", std::string(pi.name) + ": " + NOTES[pi.name]);
        } else {
            if (!added) fprintf(stderr, "grid: found %s on %s (%s)\n", pi.serial[0] ? pi.serial : "a monome", pi.name, pi.friendly);
            KNOWN[kv.first].added_at = now;
            if (NOTES.count(pi.name) && NOTES[pi.name] == HELD) NOTES.erase(pi.name);
        }
        pthread_mutex_unlock(&LK);
        if (pr == 0) {
            if (SINK.add) SINK.add(pi.name, pi.friendly);
            changes++;
            if (SINK.listed && SINK.listed(pi.name)) {
                pthread_mutex_lock(&LK);
                NOTES.erase(pi.name); // it answered
                pthread_mutex_unlock(&LK);
            }
        }
    }
    return changes;
}

int vgrid_monitor_status(char *buf, size_t n) {
    std::string s;
    std::vector<std::pair<std::string, std::string>> listed;
    pthread_mutex_lock(&LK);
    for (auto &kv : KNOWN) if (kv.second.added_at > 0) listed.push_back({kv.second.port, kv.second.serial});
    std::map<std::string, std::string> notes = NOTES, others = OTHERS;
    pthread_mutex_unlock(&LK);
    for (auto &l : listed) {
        char name[96] = "", serial[64] = "";
        int cols = 0, rows = 0;
        if (SINK.info && SINK.info(l.first.c_str(), name, sizeof name, serial, sizeof serial, &cols, &rows)) {
            s += "grid=" + l.first + "\t" + serial + "\t" + name + "\t" + std::to_string(cols) + "\t" + std::to_string(rows) + "\n";
        }
    }
    for (auto &kv : notes) s += "note=" + kv.first + ": " + kv.second + "\n";
    for (auto &kv : others) s += "other=" + kv.first + ": " + kv.second + "\n";
    snprintf(buf, n, "%s", s.c_str());
    return (int)s.size();
}

// ---- the thread
static pthread_t TH;
static bool RUNNING, POKED;
static pthread_cond_t CV = PTHREAD_COND_INITIALIZER;

void vgrid_monitor_poke(void) {
    pthread_mutex_lock(&LK);
    POKED = true;
    pthread_cond_signal(&CV);
    pthread_mutex_unlock(&LK);
}

static void *run(void *) {
    while (true) {
        vgrid_monitor_scan();
        pthread_mutex_lock(&LK);
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += 2;
        while (RUNNING && !POKED) {
            if (pthread_cond_timedwait(&CV, &LK, &ts) != 0) break;
        }
        bool poked = POKED, go = RUNNING;
        POKED = false;
        pthread_mutex_unlock(&LK);
        if (!go) break;
        if (poked) {
            struct timespec w = {0, 500 * 1000000L}; // the port is listed a moment after the notice
            nanosleep(&w, NULL);
        }
    }
    return NULL;
}

int vgrid_monitor_start(void) {
    if (RUNNING) return 0;
    RUNNING = true;
    return pthread_create(&TH, NULL, run, NULL);
}

void vgrid_monitor_stop(void) {
    if (!RUNNING) return;
    pthread_mutex_lock(&LK);
    RUNNING = false;
    pthread_cond_signal(&CV);
    pthread_mutex_unlock(&LK);
    pthread_join(TH, NULL);
}
