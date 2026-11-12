// midi_monitor.cc: see midi_monitor.h
#include "midi_monitor.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "midi_core.h"

static const vmidi_backend *BE;
static vmidi_sink SINK;
static std::string IGNORE_LIST;
static bool IGNORE_ON;
static pthread_mutex_t LK = PTHREAD_MUTEX_INITIALIZER;
static std::vector<vmidi::Device> SCAN;                 // the last scan, without the ignored ones
static std::map<std::string, std::string> RAWNAMES;       // key -> the names WinMM gave, for midi_ignore
static std::vector<std::string> LISTED;                 // the keys that were added to the list
static std::map<std::string, double> LAST_TRY;
static std::map<std::string, std::string> EXTRA;        // key -> name
static std::map<std::string, std::string> NOTES;        // key -> "name: text"
static std::map<std::string, bool> IGNORE_TOLD;
static std::vector<std::string> VIRT;

static double mono(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

void vmidi_monitor_init(const vmidi_backend *be, const vmidi_sink *sink, const char *ignore_setting) {
    BE = be;
    SINK = *sink;
    IGNORE_LIST = ignore_setting ? ignore_setting : "";
    IGNORE_ON = ignore_setting != NULL;
}

void vmidi_monitor_set_extra(const char *key, const char *name) {
    pthread_mutex_lock(&LK);
    EXTRA[key] = name;
    pthread_mutex_unlock(&LK);
}

int vmidi_monitor_scan(void) {
    if (!BE) return 0;
    static char ins[64][64], outs[64][64];
    int ni = BE->list(1, ins, 64), no = BE->list(0, outs, 64);
    std::vector<std::string> vi, vo;
    for (int i = 0; i < ni; i++) vi.push_back(ins[i]);
    for (int i = 0; i < no; i++) vo.push_back(outs[i]);
    std::vector<vmidi::Device> all = vmidi::group(vi, vo);
    std::vector<vmidi::Device> scan;
    std::map<std::string, std::string> raw;
    std::vector<std::string> virt;
    for (auto &d : all) {
        std::vector<std::string> names;
        for (int k = 0; k < d.nports; k++) {
            if (d.in_idx[k] >= 0) names.push_back(vi[d.in_idx[k]]);
            if (d.out_idx[k] >= 0) names.push_back(vo[d.out_idx[k]]);
        }
        if (IGNORE_ON && vmidi::ignored(IGNORE_LIST.c_str(), d, names)) {
            if (!IGNORE_TOLD[d.key]) {
                IGNORE_TOLD[d.key] = true;
                fprintf(stderr, "midi: skipped %s: not opened (midi_ignore in audio.conf)\n", d.name.c_str());
            }
            continue;
        }
        if (vmidi::looks_virtual(d.name)) virt.push_back(d.name);
        raw[d.key] = names.empty() ? d.name : names[0];
        scan.push_back(d);
    }
    int changes = 0;
    std::vector<vmidi::Device> to_add;
    std::vector<std::string> to_remove;
    std::vector<std::pair<std::string, std::string>> extras;
    std::vector<std::string> retry;
    pthread_mutex_lock(&LK);
    SCAN = scan;
    RAWNAMES = raw;
    VIRT = virt;
    for (auto &kv : EXTRA) {
        vmidi::Device d;
        d.key = kv.first;
        d.name = kv.second;
        d.nports = 1;
        scan.push_back(d);
    }
    vmidi::Diff df = vmidi::diff(LISTED, scan);
    for (auto &k : df.remove) LISTED.erase(std::find(LISTED.begin(), LISTED.end(), k));
    for (auto &d : df.add) LISTED.push_back(d.key);
    to_add = df.add;
    to_remove = df.remove;
    double now = mono();
    for (auto &d : scan) {
        bool fresh = false;
        for (auto &a : df.add) fresh = fresh || a.key == d.key;
        if (fresh) {
            LAST_TRY[d.key] = now;
        } else if (LAST_TRY.count(d.key) && now - LAST_TRY[d.key] >= 3.0) {
            LAST_TRY[d.key] = now;
            retry.push_back(d.key);
        }
    }
    pthread_mutex_unlock(&LK);
    for (auto &k : to_remove) {
        fprintf(stderr, "midi: removed %s: it is gone\n", k.c_str());
        vmidi_note_clear(k.c_str());
        LAST_TRY.erase(k);
        if (SINK.remove) SINK.remove(k.c_str());
        changes++;
    }
    for (auto &d : to_add) {
        fprintf(stderr, "midi: found %s (%d port%s%s)\n", d.name.c_str(), d.nports, d.nports == 1 ? "" : "s", vmidi::looks_virtual(d.name) ? ", a virtual cable" : "");
        if (SINK.add) SINK.add(d.key.c_str(), d.name.c_str());
        changes++;
    }
    for (auto &k : retry) {
        // a device whose ports are not all in the list (one was held by another program, one did not answer): tried again
        int want = 1;
        std::string name;
        for (auto &d : scan) if (d.key == k) { want = d.nports; name = d.name; }
        if (SINK.ports_listed && SINK.ports_listed(k.c_str()) < want && SINK.add) {
            SINK.add(k.c_str(), name.c_str());
        }
    }
    return changes;
}

int vmidi_monitor_find(const char *key, vmidi_found *out) {
    int ok = 0;
    pthread_mutex_lock(&LK);
    for (auto &d : SCAN) {
        if (d.key == key) {
            memset(out, 0, sizeof *out);
            snprintf(out->name, sizeof out->name, "%s", d.name.c_str());
            out->nports = d.nports;
            for (int i = 0; i < 32; i++) { out->in_idx[i] = d.in_idx[i]; out->out_idx[i] = d.out_idx[i]; }
            ok = 1;
        }
    }
    if (!ok && EXTRA.count(key)) {
        memset(out, 0, sizeof *out);
        snprintf(out->name, sizeof out->name, "%s", EXTRA[key].c_str());
        out->nports = 1;
        out->extra = 1;
        for (int i = 0; i < 32; i++) out->in_idx[i] = out->out_idx[i] = -1;
        ok = 1;
    }
    pthread_mutex_unlock(&LK);
    return ok;
}

int vmidi_monitor_present(const char *key) {
    vmidi_found f;
    return vmidi_monitor_find(key, &f);
}

void vmidi_note_set(const char *key, const char *name, const char *text) {
    pthread_mutex_lock(&LK);
    std::string line = std::string(name) + ": " + text;
    bool changed = NOTES[key] != line;
    NOTES[key] = line;
    pthread_mutex_unlock(&LK);
    if (changed) fprintf(stderr, "midi: %s\n", line.c_str());
}

void vmidi_note_clear(const char *key) {
    pthread_mutex_lock(&LK);
    NOTES.erase(key);
    pthread_mutex_unlock(&LK);
}

int vmidi_notes_text(char *buf, size_t n) {
    std::string s;
    int lines = 0;
    pthread_mutex_lock(&LK);
    for (auto &kv : NOTES) {
        if (lines++) s += "\n";
        s += kv.second;
    }
    pthread_mutex_unlock(&LK);
    snprintf(buf, n, "%s", s.c_str());
    return lines;
}

void vmidi_monitor_counts(int *devices, int *cables) {
    pthread_mutex_lock(&LK);
    if (devices) *devices = (int)SCAN.size();
    if (cables) *cables = (int)VIRT.size();
    pthread_mutex_unlock(&LK);
}

int vmidi_monitor_virtual_names(char *buf, size_t n) {
    std::string s;
    pthread_mutex_lock(&LK);
    for (size_t i = 0; i < VIRT.size(); i++) s += (i ? "\n" : "") + VIRT[i];
    int c = (int)VIRT.size();
    pthread_mutex_unlock(&LK);
    snprintf(buf, n, "%s", s.c_str());
    return c;
}

// ---- the thread
static pthread_t TH;
static bool RUNNING;
static bool POKED;
static pthread_cond_t CV = PTHREAD_COND_INITIALIZER;

void vmidi_monitor_poke(void) {
    pthread_mutex_lock(&LK);
    POKED = true;
    pthread_cond_signal(&CV);
    pthread_mutex_unlock(&LK);
}

static void *run(void *) {
    while (true) {
        vmidi_monitor_scan();
        pthread_mutex_lock(&LK);
        if (!RUNNING) { pthread_mutex_unlock(&LK); break; }
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        // a device-change notice comes before the system lists the new port: wait a moment, then look (and once more at the next round)
        ts.tv_sec += 2;
        while (RUNNING && !POKED) {
            if (pthread_cond_timedwait(&CV, &LK, &ts) != 0) break;
        }
        bool poked = POKED;
        POKED = false;
        bool run_on = RUNNING;
        pthread_mutex_unlock(&LK);
        if (!run_on) break;
        if (poked) {
            struct timespec w = {0, 400 * 1000000L};
            nanosleep(&w, NULL);
        }
    }
    return NULL;
}

int vmidi_monitor_start(void) {
    if (RUNNING) return 0;
    RUNNING = true;
    return pthread_create(&TH, NULL, run, NULL);
}

void vmidi_monitor_stop(void) {
    if (!RUNNING) return;
    pthread_mutex_lock(&LK);
    RUNNING = false;
    pthread_cond_signal(&CV);
    pthread_mutex_unlock(&LK);
    pthread_join(TH, NULL);
}
