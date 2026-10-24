/*
 * midi_autoconnect.cc: see input_route.h
 *
 * the optional auto-connect of MIDI output ports (a DAW's, a Midi-Bridge port) to Verdandi:midi_in. off unless a prefix
 * list is given (NORNS_MIDI_IN_FROM, from audio.conf midi_in_from=). a thread looks every 2 seconds and whenever a port is
 * registered: a link that PipeWire's Midi-Bridge dropped without any port disappearing is made again. decisions:
 * crone/src/MidiRoute.h (tested).
 */

#include <alsa/asoundlib.h>
#include <dirent.h>
#include <jack/jack.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <atomic>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "MidiRoute.h"
#include "input_route.h"

using namespace crone::MidiRoute;

static const char *MIDI_IN = "Verdandi:midi_in";

static std::mutex mtx;
static std::vector<std::string> prefixes;
static std::atomic<bool> started(false);
static sem_t wake;
static std::set<std::string> ever_linked;
static Throttle throttle;
static int linked_count = 0;
static std::string linked_names;

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

// the process ids and thread ids that are norns': the process, all its threads, and the same for every process it started
// (a child may create ALSA clients too). ALSA reports, for a client, the id of the thread that created it, so the process id alone
// does not find norns' own clients. read from /proc each time (threads come and go)
static std::set<int> own_ids(void) {
    std::map<int, int> parent;
    DIR *d = opendir("/proc");
    while (d != NULL) {
        struct dirent *e = readdir(d);
        if (e == NULL) {
            break;
        }
        int pid = atoi(e->d_name);
        if (pid <= 0) {
            continue;
        }
        char path[64], line[512];
        snprintf(path, sizeof path, "/proc/%d/stat", pid);
        FILE *f = fopen(path, "r");
        if (f != NULL) {
            if (fgets(line, sizeof line, f) != NULL) {
                // "pid (comm) S ppid ...": the command may hold spaces and parentheses, so look after the last ')'
                char *rp = strrchr(line, ')');
                int ppid = 0;
                if (rp != NULL && sscanf(rp + 1, " %*c %d", &ppid) == 1) {
                    parent[pid] = ppid;
                }
            }
            fclose(f);
        }
    }
    if (d != NULL) {
        closedir(d);
    }
    std::set<int> own;
    for (int pid : descendants(parent, (int)getpid())) {
        own.insert(pid);
        char path[64];
        snprintf(path, sizeof path, "/proc/%d/task", pid);
        DIR *t = opendir(path);
        while (t != NULL) {
            struct dirent *e = readdir(t);
            if (e == NULL) {
                break;
            }
            int tid = atoi(e->d_name);
            if (tid > 0) {
                own.insert(tid);
            }
        }
        if (t != NULL) {
            closedir(t);
        }
    }
    return own;
}

// the names of norns' own ALSA sequencer clients (the virtual RawMIDI device, the keys window, ...): they show up in JACK as
// Midi-Bridge ports and must never be linked back into Verdandi:midi_in
static std::vector<std::string> own_alsa_clients(void) {
    static snd_seq_t *seq = NULL;
    static bool tried = false;
    if (!tried) {
        tried = true;
        if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_INPUT, 0) < 0) {
            seq = NULL; // no ALSA sequencer here: norns has no ALSA MIDI clients either
        }
    }
    if (seq == NULL) {
        return {};
    }
    std::vector<AlsaClient> clients;
    snd_seq_client_info_t *info;
    snd_seq_client_info_alloca(&info);
    snd_seq_client_info_set_client(info, -1);
    while (snd_seq_query_next_client(seq, info) >= 0) {
        clients.push_back(AlsaClient{snd_seq_client_info_get_client(info), snd_seq_client_info_get_name(info),
                                     snd_seq_client_info_get_pid(info)});
    }
    return ownAlsaNames(clients, own_ids());
}

static void apply(jack_client_t *c) {
    std::vector<MidiPort> ports;
    const char **names = jack_get_ports(c, NULL, JACK_DEFAULT_MIDI_TYPE, 0);
    for (int i = 0; names != NULL && names[i] != NULL; i++) {
        jack_port_t *p = jack_port_by_name(c, names[i]);
        if (p != NULL) {
            ports.push_back(MidiPort{names[i], true, (jack_port_flags(p) & JackPortIsOutput) != 0});
        }
    }
    if (names != NULL) {
        jack_free(names);
    }
    std::vector<std::string> linked;
    jack_port_t *in = jack_port_by_name(c, MIDI_IN);
    if (in == NULL) {
        return;
    }
    const char **conns = jack_port_get_all_connections(c, in);
    for (int i = 0; conns != NULL && conns[i] != NULL; i++) {
        linked.push_back(conns[i]);
    }
    if (conns != NULL) {
        jack_free(conns);
    }

    std::vector<std::string> want = wanted(ports, prefixes, own_alsa_clients());
    for (const auto &w : missingFrom(want, linked)) {
        int err = jack_connect(c, w.c_str(), MIDI_IN);
        if (err != 0 && err != EEXIST) {
            continue;
        }
        bool again = ever_linked.count(w) > 0;
        ever_linked.insert(w);
        // the first link is always said; a link made again at most once a minute per port (a flapping link)
        if (!again || throttle.allow(w, now_s())) {
            fprintf(stderr, "midi: %s %s to %s\n", again ? "reconnected" : "connected", w.c_str(), MIDI_IN);
        }
        linked.push_back(w);
    }
    std::string names_out;
    int n = 0;
    for (const auto &w : want) {
        for (const auto &l : linked) {
            if (l == w) {
                names_out += (n++ ? ", " : "") + w;
                break;
            }
        }
    }
    std::lock_guard<std::mutex> l(mtx);
    linked_count = n;
    linked_names = names_out;
}

static void worker(jack_client_t *c) {
    for (;;) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += 2; // the re-check: dropped links come without any registration
        sem_timedwait(&wake, &ts);
        while (sem_trywait(&wake) == 0) {
        }
        apply(c);
    }
}

extern "C" {

int midi_autoconnect_start(const char *prefix_list) {
    std::vector<std::string> p = parsePrefixes(prefix_list != NULL ? prefix_list : "");
    if (p.empty() || started.load()) {
        return started.load() ? 1 : 0;
    }
    jack_client_t *c = input_route_client();
    if (c == NULL) {
        fprintf(stderr, "midi: no JACK server, auto-connect is off\n");
        return 0;
    }
    {
        std::lock_guard<std::mutex> l(mtx);
        prefixes = p;
    }
    sem_init(&wake, 0, 0);
    started = true;
    fprintf(stderr, "midi: auto-connect to %s from %s\n", MIDI_IN, prefix_list);
    std::thread(worker, c).detach();
    return 1;
}

void midi_autoconnect_poke(void) {
    // NORNS_MIDI_POKE=0 (tests): no wake-up by port registrations, only the 2 s re-check
    static const bool poke_on = getenv("NORNS_MIDI_POKE") == NULL || strcmp(getenv("NORNS_MIDI_POKE"), "0") != 0;
    if (poke_on && started.load()) {
        sem_post(&wake);
    }
}

int midi_autoconnect_status(int *count, char *names, size_t n) {
    std::lock_guard<std::mutex> l(mtx);
    *count = linked_count;
    snprintf(names, n, "%s", linked_names.c_str());
    return started.load() ? 1 : 0;
}

} // extern "C"
