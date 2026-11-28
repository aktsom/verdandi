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
static const char *MIDI_OUT = "Verdandi:midi_out";

static std::mutex mtx;
static std::vector<std::string> prefixes;     // midi_in_from: ports linked to Verdandi:midi_in
static std::vector<std::string> out_prefixes; // midi_out_to: ports Verdandi:midi_out is linked to
static std::atomic<bool> started(false);      // the input side is on
static std::atomic<bool> out_started(false);
static std::atomic<bool> worker_started(false);
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

// M39: the default (audio.conf has no midi_in_from=, norns.sh sets NORNS_MIDI_IN_FROM_DEFAULT=1) links one source and never the virtual MIDI card; a list the user wrote links every match, as before
static bool default_mode(void) {
    const char *d = getenv("NORNS_MIDI_IN_FROM_DEFAULT");
    return d != NULL && strcmp(d, "1") == 0;
}
static std::set<std::string> was_linked;    // ports linked by this worker that were in the port list at the last look
static std::set<std::string> said_others;   // the extra sources of the default, said once
static std::set<std::string> announce_next; // a port that was said to be gone: its next connection is said at once
static Throttle throttle_gone;
static Throttle throttle_fail;

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
    std::vector<std::string> own_clients = own_alsa_clients();
    std::vector<std::string> prefixes_now, out_prefixes_now;
    {
        std::lock_guard<std::mutex> l(mtx);
        prefixes_now = prefixes;
        out_prefixes_now = out_prefixes;
    }
    // Verdandi:midi_out to the MIDI inputs that match midi_out_to
    jack_port_t *outp = jack_port_by_name(c, MIDI_OUT);
    if (outp != NULL && !out_prefixes_now.empty()) {
        std::vector<std::string> linked_out;
        const char **oc = jack_port_get_all_connections(c, outp);
        for (int i = 0; oc != NULL && oc[i] != NULL; i++) {
            linked_out.push_back(oc[i]);
        }
        if (oc != NULL) {
            jack_free(oc);
        }
        for (const auto &w : missingFrom(wantedSinks(ports, out_prefixes_now, own_clients), linked_out)) {
            int err = jack_connect(c, MIDI_OUT, w.c_str());
            if (err != 0 && err != EEXIST) {
                continue;
            }
            std::string key = "out:" + w;
            bool again = ever_linked.count(key) > 0;
            ever_linked.insert(key);
            if (!again || throttle.allow(key, now_s())) {
                fprintf(stderr, "midi: %s %s to %s\n", again ? "reconnected" : "connected", MIDI_OUT, w.c_str());
            }
        }
    }
    std::vector<std::string> linked;
    jack_port_t *in = jack_port_by_name(c, MIDI_IN);
    if (in == NULL || prefixes_now.empty()) {
        return;
    }
    const char **conns = jack_port_get_all_connections(c, in);
    for (int i = 0; conns != NULL && conns[i] != NULL; i++) {
        linked.push_back(conns[i]);
    }
    if (conns != NULL) {
        jack_free(conns);
    }

    // a program that was linked and has gone (its port is not in the list any more): one line
    for (const auto &g : vanished(was_linked, ports)) {
        was_linked.erase(g);
        if (throttle_gone.allow(g, now_s())) {
            fprintf(stderr, "midi: %s is gone (it was linked to %s); it is linked again when it comes back\n", g.c_str(), MIDI_IN);
            announce_next.insert(g);
        }
    }
    const bool dflt = default_mode();
    std::vector<std::string> in_never = own_clients;
    {
        const char *vo = getenv("NORNS_ALSA_MIDI_OUT_TO");
        for (const auto &n : inputNever(vo != NULL ? vo : "")) {
            in_never.push_back(n);
        }
    }
    std::vector<std::string> want = wanted(ports, prefixes_now, in_never);
    if (dflt) {
        std::vector<std::string> others;
        want = chooseOne(want, linked, &others);
        for (const auto &o : others) {
            if (said_others.insert(o).second) {
                fprintf(stderr, "midi: also found %s: not linked (the default links one source; midi_in_from= in audio.conf links several)\n", o.c_str());
            }
        }
    }
    for (const auto &w : missingFrom(want, linked)) {
        int err = jack_connect(c, w.c_str(), MIDI_IN);
        if (err != 0 && err != EEXIST) {
            // M44: say it (once a minute per port): a link that the sound system makes although jack_connect said no is then told by the line below on the next look
            if (throttle_fail.allow(w, now_s())) {
                fprintf(stderr, "midi: could not link %s to %s (jack_connect said %d); it is tried again\n", w.c_str(), MIDI_IN, err);
            }
            continue;
        }
        bool again = ever_linked.count(w) > 0;
        ever_linked.insert(w);
        was_linked.insert(w);
        bool say_now = announce_next.erase(w) > 0;
        // the first link is always said, and the one after a "gone" line; a link made again at most once a minute per port (a flapping link)
        if (!again || say_now || throttle.allow(w, now_s())) {
            fprintf(stderr, "midi: %s %s to %s\n", again ? "reconnected" : "connected", w.c_str(), MIDI_IN);
        }
        linked.push_back(w);
    }
    for (const auto &w : want) {
        for (const auto &l : linked) {
            if (l == w && was_linked.insert(w).second) {
                // M44: a wanted port that is linked although this worker did not link it just now (the sound system or a person made the
                // link, or jack_connect said no and the link came all the same): its going away is said too, and so is its coming. before M44
                // this case was silent, so a returning port showed "gone" and then nothing although the link was there (laptop, PipeWire).
                bool again = ever_linked.count(w) > 0;
                ever_linked.insert(w);
                bool say_now = announce_next.erase(w) > 0;
                if (!again || say_now || throttle.allow(w, now_s())) {
                    fprintf(stderr, "midi: %s %s to %s (it was linked already when seen: the link was not made by this program's jack_connect)\n", again ? "reconnected" : "connected", w.c_str(), MIDI_IN);
                }
            }
        }
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

// the worker thread is one for both sides; it starts with the first of them
static int start_worker(void) {
    if (worker_started.load()) {
        return 1;
    }
    jack_client_t *c = input_route_client();
    if (c == NULL) {
        if (!default_mode()) { // (the default is on for everyone: no line for a start without JACK)
            fprintf(stderr, "midi: no JACK server, auto-connect is off\n");
        }
        return 0;
    }
    sem_init(&wake, 0, 0);
    worker_started = true;
    std::thread(worker, c).detach();
    return 1;
}

int midi_autoconnect_start(const char *prefix_list) {
    std::vector<std::string> p = parsePrefixes(prefix_list != NULL ? prefix_list : "");
    if (p.empty() || started.load()) {
        return started.load() ? 1 : 0;
    }
    if (!start_worker()) {
        return 0;
    }
    {
        std::lock_guard<std::mutex> l(mtx);
        prefixes = p;
    }
    started = true;
    if (default_mode()) {
        fprintf(stderr, "midi: auto-connect to %s from %s (the default: one program's virtual MIDI output; midi_in_from= in audio.conf changes it, an empty midi_in_from= turns it off)\n", MIDI_IN, prefix_list);
    } else {
        fprintf(stderr, "midi: auto-connect to %s from %s\n", MIDI_IN, prefix_list);
    }
    sem_post(&wake);
    return 1;
}

int midi_autoconnect_start_out(const char *prefix_list) {
    std::vector<std::string> p = parsePrefixes(prefix_list != NULL ? prefix_list : "");
    if (p.empty() || out_started.load()) {
        return out_started.load() ? 1 : 0;
    }
    if (!start_worker()) {
        return 0;
    }
    {
        std::lock_guard<std::mutex> l(mtx);
        out_prefixes = p;
    }
    out_started = true;
    fprintf(stderr, "midi: auto-connect from %s to %s\n", MIDI_OUT, prefix_list);
    sem_post(&wake);
    return 1;
}

void midi_autoconnect_poke(void) {
    // NORNS_MIDI_POKE=0 (tests): no wake-up by port registrations, only the 2 s re-check
    static const bool poke_on = getenv("NORNS_MIDI_POKE") == NULL || strcmp(getenv("NORNS_MIDI_POKE"), "0") != 0;
    if (poke_on && worker_started.load()) {
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
