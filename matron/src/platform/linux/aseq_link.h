/*
 * aseq_link.h: the optional auto-connect of "Verdandi out" (the ALSA sequencer port of the virtual MIDI device, aseq_out.h) to ALSA destination ports whose name starts with a prefix (alsa_midi_out_to= in audio.conf,
 * NORNS_ALSA_MIDI_OUT_TO). for DAWs that read raw MIDI only: Reaper on Linux lists hw: devices and no sequencer ports, so the bridge is the kernel's snd-virmidi card: its sequencer port (client "VirMIDI 3-0")
 * is where Verdandi out is subscribed, and Reaper reads the same card as the raw device hw:VirMIDI.
 *
 * the decisions are here, pure, with the sequencer behind a small interface (LinkSeq) so that they are tested without a kernel sequencer; aseq_out.cc has the libasound side and the thread that calls check() every
 * few seconds (a port that appears later, a subscription that was cut). off unless a prefix is given. a prefix matches, without regard to case, the start of the client name, of the port name, or of "client:port";
 * ';' separates several, '*' stands for any text. never connected, whatever the prefix: norns' own clients (this one, the keys window, any client made by a thread of this process), and ports that cannot be written to.
 * System and Midi Through are only connected when a prefix names them (nothing is connected without a prefix that matches).
 */

#pragma once

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include <algorithm>
#include <functional>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "MidiRoute.h" // crone/src: parsePrefixes, matchesPattern

namespace aseq {

struct PortInfo {
    int client;
    int port;
    std::string client_name;
    std::string port_name;
    bool writable; // others may write to it and subscribe to it (CAP_WRITE and CAP_SUBS_WRITE)
    int pid = 0;   // the thread id that made the client (0 for a kernel client)
};

// the sequencer, as far as the linking goes
struct LinkSeq {
    virtual ~LinkSeq() {}
    virtual bool list(std::vector<PortInfo> &out) = 0;      // every client's ports; false if the sequencer cannot be asked
    virtual bool connected(int client, int port) = 0;       // is Verdandi out subscribed to this port?
    virtual int connect(int client, int port) = 0;          // subscribe: 0 ok, -EBUSY already, another negative number: it failed
};

inline std::string lower(std::string s) {
    for (auto &c : s) {
        c = (char)tolower((unsigned char)c);
    }
    return s;
}

// "VirMIDI 3-0" -> the name to enable in Reaper: the same (Reaper lists the raw device by its card name), and its hw form "hw:VirMIDI,0" (card name, device index), "" for any other client
inline std::string reaper_entry(const std::string &client) { return client; }
inline std::string reaper_hw(const std::string &client) {
    size_t sp = client.rfind(' ');
    if (client.compare(0, 8, "VirMIDI ") != 0 || sp == std::string::npos) {
        return "";
    }
    std::string rest = client.substr(sp + 1); // "3-0"
    size_t dash = rest.find('-');
    if (dash == std::string::npos || dash == 0 || dash + 1 >= rest.size()) {
        return "";
    }
    return "hw:VirMIDI," + rest.substr(dash + 1);
}

class Linker {
  public:
    using LogFn = void (*)(const char *line, void *ctx);

    Linker(LinkSeq &seq, const std::string &prefixes, int own_client, LogFn log = NULL, void *log_ctx = NULL)
        : seq_(seq), prefixes_(crone::MidiRoute::parsePrefixes(prefixes)), own_(own_client), log_(log), log_ctx_(log_ctx) {
        for (auto &p : prefixes_) {
            p = lower(p);
        }
    }

    bool enabled() const { return !prefixes_.empty(); }

    // tests: which thread ids are "ours" (the real one asks /proc/self/task)
    void set_own_pid_test(std::function<bool(int)> f) { own_pid_ = f; }

    // one round: subscribe to every matching port that is not subscribed. returns how many matching ports are subscribed now
    int check() {
        if (!enabled()) {
            return 0;
        }
        std::vector<PortInfo> ports;
        if (!seq_.list(ports)) {
            return count();
        }
        std::set<std::pair<int, int>> present;
        std::vector<std::string> linked_names;
        int linked = 0;
        for (const auto &p : ports) {
            if (!matches(p)) {
                continue;
            }
            std::pair<int, int> key(p.client, p.port);
            present.insert(key);
            bool ok = seq_.connected(p.client, p.port);
            if (!ok) {
                int r = seq_.connect(p.client, p.port);
                if (r == 0 || r == -EBUSY) {
                    ok = true;
                    bool again = ever_.count(key) > 0;
                    ever_.insert(key);
                    said_fail_.erase(key);
                    say(std::string("aseq_out: ") + (again ? "reconnected" : "connected") + " Verdandi out to " + p.client_name + " (" + std::to_string(p.client) + ":" + std::to_string(p.port) + ")");
                } else if (said_fail_.insert(key).second) {
                    say(std::string("aseq_out: could not connect Verdandi out to ") + p.client_name + " (" + std::to_string(p.client) + ":" + std::to_string(p.port) + "): error " + std::to_string(r) +
                        "; it is tried again every few seconds");
                }
            } else {
                ever_.insert(key);
            }
            if (ok) {
                linked++;
                if (std::find(linked_names.begin(), linked_names.end(), p.client_name) == linked_names.end()) {
                    linked_names.push_back(p.client_name);
                }
            }
        }
        std::string joined;
        for (const auto &n : linked_names) {
            joined += (joined.empty() ? "" : ", ") + n;
        }
        std::lock_guard<std::mutex> l(mtx_);
        count_ = linked;
        names_ = joined;
        return linked;
    }

    int count() const {
        std::lock_guard<std::mutex> l(mtx_);
        return count_;
    }
    std::string names() const {
        std::lock_guard<std::mutex> l(mtx_);
        return names_;
    }

  private:
    bool matches(const PortInfo &p) const {
        if (!p.writable || p.client == own_) {
            return false;
        }
        if (p.client_name == "Verdandi" || p.client_name == "norns keys") {
            return false;
        }
        if (p.pid > 0 && own_pid_ && own_pid_(p.pid)) {
            return false;
        }
        std::string cn = lower(p.client_name), pn = lower(p.port_name), both = cn + ":" + pn;
        for (const auto &pre : prefixes_) {
            if (crone::MidiRoute::matchesPattern(cn, pre) || crone::MidiRoute::matchesPattern(pn, pre) || crone::MidiRoute::matchesPattern(both, pre)) {
                return true;
            }
        }
        return false;
    }
    void say(const std::string &s) {
        if (log_) {
            log_(s.c_str(), log_ctx_);
        } else {
            fprintf(stderr, "%s\n", s.c_str());
        }
    }

    LinkSeq &seq_;
    std::vector<std::string> prefixes_;
    int own_;
    LogFn log_;
    void *log_ctx_;
    std::function<bool(int)> own_pid_;
    std::set<std::pair<int, int>> ever_, said_fail_;
    mutable std::mutex mtx_;
    int count_ = 0;
    std::string names_;
};

} // namespace aseq
