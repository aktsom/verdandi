// midi_win.cc: the glue of the Windows MIDI layer to the rest of norns.exe: the device monitor (dev_monitor_*), audio.conf, the table for the DEVICES page, the route test, the log lines about the clock in.
#include "midi_win.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

#include "device/device.h"
#include "device/device_list.h"
#include "device/device_monitor.h"
#include "midi_measure.h"
#include "midi_monitor.h"
#include "midi_winmm.h"
#include "osc_in.h"

static int OSC_PORT = 9201;

int vmidi_win_osc_port(void) { return OSC_PORT; }

// the value of key= in audio.conf (the pages keep keys they do not know)
static std::string conf_value(const char *key, bool *found) {
    *found = false;
    const char *home = getenv("HOME");
    if (!home || !*home) return "";
    std::string path = std::string(home) + "/audio.conf";
    FILE *f = fopen(path.c_str(), "r");
    if (!f) return "";
    char line[512];
    std::string out;
    size_t kl = strlen(key);
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, kl) == 0 && line[kl] == '=') {
            out = line + kl + 1;
            while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();
            *found = true;
        }
    }
    fclose(f);
    return out;
}

// ---- the ports that are open, by device: for the route test and the clock log
struct Open { std::string key, name; vmidi_port *port; };
static std::vector<Open> OPEN;
static pthread_mutex_t OLK = PTHREAD_MUTEX_INITIALIZER;

extern "C" void vmidi_win_port_opened(const char *key, const char *name, void *port) {
    pthread_mutex_lock(&OLK);
    OPEN.push_back({key, name, (vmidi_port *)port});
    pthread_mutex_unlock(&OLK);
}
extern "C" void vmidi_win_port_closed(void *port) {
    pthread_mutex_lock(&OLK);
    for (size_t i = 0; i < OPEN.size(); i++) if (OPEN[i].port == port) { OPEN.erase(OPEN.begin() + i); break; }
    pthread_mutex_unlock(&OLK);
}

// ---- the sink: the monitor adds to and removes from norns' device list
static void sink_add(const char *key, const char *name) { dev_list_add(DEV_TYPE_MIDI, key, strdup(name), NULL); }
static void sink_remove(const char *key) { dev_list_remove(DEV_TYPE_MIDI, key); }
static int sink_listed(const char *key) { return dev_list_midi_ports_listed(key); }

static bool STARTED;
static pthread_t LOGTH;
static volatile bool LOG_RUN;

// every 10 seconds: the clock in of each open port that has one (the tempo and how steady the ticks are). the numbers are about the callback thread of the system, the best place to measure the jitter
static void *log_run(void *) {
    while (LOG_RUN) {
        for (int i = 0; i < 100 && LOG_RUN; i++) {
            struct timespec w = {0, 100 * 1000000L};
            nanosleep(&w, NULL);
        }
        pthread_mutex_lock(&OLK);
        for (auto &o : OPEN) {
            vmidi_stats st;
            vmidi_port_stats(o.port, &st);
            if (st.ticks > 0 && st.mean_us > 0) {
                fprintf(stderr, "midi: clock in '%s': %.1f bpm, tick interval mean %.0f us, jitter %.0f us, shortest %.0f, longest %.0f%s\n", o.name.c_str(), 60e6 / (st.mean_us * 24.0), st.mean_us, st.jitter_us, st.min_us, st.max_us,
                        st.dropped ? " (bytes were lost: norns was too slow to read)" : "");
            }
        }
        pthread_mutex_unlock(&OLK);
    }
    return NULL;
}

static void poke_all(void) {
    vmidi_monitor_poke();
    vgrid_win_poke();
}

void vmidi_win_monitor_init(void) {
    bool found;
    std::string ig = conf_value("midi_ignore", &found);
    const char *env = getenv("VERDANDI_MIDI_IGNORE");
    if (env) {
        ig = env;
        found = true;
    }
    std::string op = conf_value("osc_in_port", &found);
    if (found && !op.empty()) OSC_PORT = atoi(op.c_str());
    static vmidi_sink sink = {sink_add, sink_remove, sink_listed};
    vmidi_monitor_init(&vmidi_winmm_backend, &sink, ig.empty() && !getenv("VERDANDI_MIDI_IGNORE") ? NULL : ig.c_str());
    if (OSC_PORT > 0 && OSC_PORT < 65536) {
        char key[64];
        snprintf(key, sizeof key, "osc:127.0.0.1:%d", OSC_PORT);
        vmidi_monitor_set_extra(key, "osc");
    }
    vmidi_winmm_watch(poke_all);
    static char tmp[64][64];
    fprintf(stderr, "midi: WinMM (midiIn / midiOut): %d input and %d output ports now; a change of devices is noticed at once and every 2 seconds%s; OSC input on 127.0.0.1:%d\n", vmidi_winmm_backend.list(1, tmp, 64), vmidi_winmm_backend.list(0, tmp, 64), ig.empty() ? "" : "; midi_ignore is set", OSC_PORT);
}

void vmidi_win_monitor_deinit(void) {
    LOG_RUN = false;
    vmidi_monitor_stop();
    vmidi_winmm_watch_stop();
    vmidi_osc_stop();
    if (STARTED) pthread_join(LOGTH, NULL);
    STARTED = false;
}

// nothing is added before the scan (as on the other platforms): the scan starts the thread that looks again
void vmidi_win_monitor_start(void) {
    if (STARTED) return;
    STARTED = true;
    LOG_RUN = true;
    pthread_create(&LOGTH, NULL, log_run, NULL);
    vmidi_monitor_start();
}

// ---- the table for the DEVICES page
int vmidi_win_status(char *buf, size_t n) {
    std::string s;
    int dev = 0, cab = 0;
    vmidi_monitor_counts(&dev, &cab);
    char t[1024];
    s += "backend=WinMM\n";
    snprintf(t, sizeof t, "devices=%d\ncables=%d\nosc_port=%d\n", dev, cab, OSC_PORT);
    s += t;
    char names[1024];
    vmidi_monitor_virtual_names(names, sizeof names);
    for (char *p = strtok(names, "\n"); p; p = strtok(NULL, "\n")) s += std::string("cable=") + p + "\n";
    char notes[2048];
    vmidi_notes_text(notes, sizeof notes);
    std::string nn = notes;
    size_t pos = 0;
    while (pos < nn.size()) {
        size_t e = nn.find('\n', pos);
        if (e == std::string::npos) e = nn.size();
        s += "note=" + nn.substr(pos, e - pos) + "\n";
        pos = e + 1;
    }
    unsigned long long used = 0, ign = 0;
    vmidi_osc_counts(&used, &ign);
    snprintf(t, sizeof t, "osc_used=%llu\nosc_ignored=%llu\n", used, ign);
    s += t;
    pthread_mutex_lock(&OLK);
    for (auto &o : OPEN) {
        s += "open=" + o.name + "\n";
        double age = vmidi_port_tick_age_us(o.port);
        if (age >= 0 && age < 1.5e6) s += "clock_in=" + o.name + "\n"; // ticks came in within the last 1.5 s: this device drives (or could drive) the MIDI clock
    }
    pthread_mutex_unlock(&OLK);
    extern std::string vmidi_route_state_text();
    s += vmidi_route_state_text();
    snprintf(buf, n, "%s", s.c_str());
    return (int)s.size();
}

// ---- the route test
static pthread_mutex_t RLK = PTHREAD_MUTEX_INITIALIZER;
static std::string ROUTE_STATE = "route_state=idle\n";
static bool ROUTE_BUSY;
struct RouteArg { std::string kind, device; };

std::string vmidi_route_state_text() {
    pthread_mutex_lock(&RLK);
    std::string s = ROUTE_STATE;
    pthread_mutex_unlock(&RLK);
    return s;
}

static void route_set(const std::string &st, const std::string &line) {
    pthread_mutex_lock(&RLK);
    ROUTE_STATE = "route_state=" + st + "\nroute=" + line + "\n";
    pthread_mutex_unlock(&RLK);
}

static void *route_run(void *a) {
    RouteArg *ra = (RouteArg *)a;
    vmidi_route_result r;
    char err[200] = "", line[300];
    int rc;
    std::string label;
    if (ra->kind == "osc") {
        label = "OSC (127.0.0.1)";
        rc = vmidi_measure_udp(200, 10, &r, err, sizeof err);
    } else {
        label = ra->device;
        vmidi_port *p = NULL;
        pthread_mutex_lock(&OLK);
        for (auto &o : OPEN) {
            if (o.name == ra->device || o.key.find(ra->device) != std::string::npos) {
                if (vmidi_port_has_input(o.port) && vmidi_port_has_output(o.port)) { p = o.port; break; }
            }
        }
        pthread_mutex_unlock(&OLK);
        if (!p) {
            route_set("failed", ra->device + ": not open here with an input and an output (is it in midi_ignore, held by another program, or not a cable?)");
            rc = -2;
        } else {
            rc = vmidi_measure_port(p, 200, 10, &r, err, sizeof err);
        }
    }
    if (rc == 0) {
        vmidi_route_format(&r, label.c_str(), line, sizeof line);
        fprintf(stderr, "midi: route test: %s\n", line);
        route_set("done", line);
    } else if (rc == -1) {
        route_set("failed", label + ": " + err);
        fprintf(stderr, "midi: route test: %s: %s\n", label.c_str(), err);
    }
    pthread_mutex_lock(&RLK);
    ROUTE_BUSY = false;
    pthread_mutex_unlock(&RLK);
    delete ra;
    return NULL;
}

int vmidi_win_route_test(const char *kind, const char *device, char *msg, size_t n) {
    pthread_mutex_lock(&RLK);
    if (ROUTE_BUSY) {
        pthread_mutex_unlock(&RLK);
        snprintf(msg, n, "a test is running");
        return 1;
    }
    ROUTE_BUSY = true;
    pthread_mutex_unlock(&RLK);
    route_set("running", "");
    pthread_t th;
    if (pthread_create(&th, NULL, route_run, new RouteArg{kind ? kind : "midi", device ? device : ""}) != 0) {
        ROUTE_BUSY = false;
        snprintf(msg, n, "no thread");
        return -1;
    }
    pthread_detach(th);
    msg[0] = 0;
    return 0;
}
