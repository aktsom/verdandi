#ifndef CRONE_MIDIROUTE_H
#define CRONE_MIDIROUTE_H

// the optional auto-connect of MIDI output ports to Verdandi:midi_in (midi_in_from= in audio.conf, NORNS_MIDI_IN_FROM).
// pure logic, no JACK calls (the glue is matron/src/platform/linux/midi_autoconnect.cc).

#include <map>
#include <set>
#include <string>
#include <vector>

#include "InputRoute.h"

namespace crone {
namespace MidiRoute {

struct MidiPort {
    std::string name; // "client:port"
    bool midi;        // type is MIDI
    bool output;      // an output port: a source of MIDI
};

// "a;b ; c" -> a, b, c
inline std::vector<std::string> parsePrefixes(const std::string &s) {
    std::vector<std::string> out;
    size_t i = 0;
    while (i <= s.size()) {
        size_t j = s.find(';', i);
        if (j == std::string::npos) {
            j = s.size();
        }
        std::string p = s.substr(i, j - i);
        size_t a = p.find_first_not_of(" \t");
        size_t b = p.find_last_not_of(" \t");
        if (a != std::string::npos) {
            out.push_back(p.substr(a, b - a + 1));
        }
        i = j + 1;
    }
    return out;
}

// pattern against a port name: anchored at the start, open at the end; '*' stands for any text (the number in
// "Client-20 Virtual RawMIDI" changes between runs). without a '*' it is a plain prefix
inline bool matchesPattern(const std::string &name, const std::string &pattern) {
    size_t n = 0, p = 0, star = std::string::npos, mark = 0;
    while (n < name.size()) {
        if (p < pattern.size() && pattern[p] == '*') {
            star = p++;
            mark = n;
        } else if (p < pattern.size() && pattern[p] == name[n]) {
            n++;
            p++;
        } else if (p == pattern.size()) {
            return true; // the pattern is used up: the rest of the name is the open end
        } else if (star != std::string::npos) {
            p = star + 1;
            n = ++mark;
        } else {
            return false;
        }
    }
    while (p < pattern.size() && pattern[p] == '*') {
        p++;
    }
    return p == pattern.size();
}

inline bool isWordChar(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

// does the port name contain this client name as a whole word ("Client-128" is not in "Client-1280")
inline bool containsWord(const std::string &name, const std::string &word) {
    if (word.empty()) {
        return false;
    }
    for (size_t i = name.find(word); i != std::string::npos; i = name.find(word, i + 1)) {
        bool before = i == 0 || !isWordChar(name[i - 1]);
        bool after = i + word.size() >= name.size() || !isWordChar(name[i + word.size()]);
        if (before && after) {
            return true;
        }
    }
    return false;
}

// an ALSA sequencer client as the sequencer reports it. pid: **the id of the thread that created the client** (a thread id of
// the creating process, not necessarily the process id), 0 or -1 for kernel clients
struct AlsaClient {
    int id;
    std::string name;
    int pid;
};

// norns' own clients: those whose reported id is one of norns' process ids or thread ids (own = the process, all its threads,
// and the same for the processes it started). the names to keep out: the client's name and "Client-<id>"
inline std::vector<std::string> ownAlsaNames(const std::vector<AlsaClient> &clients, const std::set<int> &own) {
    std::vector<std::string> out;
    for (const auto &c : clients) {
        if (c.pid > 0 && own.count(c.pid) > 0) {
            out.push_back(c.name);
            out.push_back("Client-" + std::to_string(c.id));
        }
    }
    return out;
}

// the process and all that descend from it (children, grandchildren ...), from a table pid -> parent pid. a loop in the
// table cannot hang it
inline std::set<int> descendants(const std::map<int, int> &parent, int root) {
    std::set<int> out = {root};
    bool grew = true;
    while (grew) {
        grew = false;
        for (const auto &kv : parent) {
            if (out.count(kv.second) > 0 && out.count(kv.first) == 0) {
                out.insert(kv.first);
                grew = true;
            }
        }
    }
    return out;
}

// ports that are never linked: norns' own ALSA MIDI clients (the virtual RawMIDI device, the keys window; own = their
// client names, found by the glue through the ALSA sequencer) and the ALSA loopback "Midi Through" (whatever is
// written to it comes out again: norns' own output would come back into its input)
inline bool neverLinked(const std::string &name, const std::vector<std::string> &own) {
    if (name.find("Midi Through") != std::string::npos) {
        return true;
    }
    for (const auto &o : own) {
        if (containsWord(name, o)) {
            return true;
        }
    }
    return false;
}

// the MIDI output ports that match a pattern (see matchesPattern); never one of norns' own JACK clients, and nothing
// that neverLinked says no to
inline std::vector<std::string> wanted(const std::vector<MidiPort> &ports, const std::vector<std::string> &prefixes,
                                       const std::vector<std::string> &own = {}) {
    std::vector<std::string> out;
    for (const auto &p : ports) {
        if (!p.midi || !p.output || InputRoute::isOwnClient(PortSelect::clientOf(p.name)) || neverLinked(p.name, own)) {
            continue;
        }
        for (const auto &pre : prefixes) {
            if (matchesPattern(p.name, pre)) {
                out.push_back(p.name);
                break;
            }
        }
    }
    return out;
}

inline std::vector<std::string> missingFrom(const std::vector<std::string> &want, const std::vector<std::string> &linked) {
    std::vector<std::string> m;
    for (const auto &w : want) {
        bool found = false;
        for (const auto &l : linked) {
            if (l == w) {
                found = true;
            }
        }
        if (!found) {
            m.push_back(w);
        }
    }
    return m;
}

// one log line per port per minute: a link that flaps cannot flood the log
struct Throttle {
    std::map<std::string, double> last;
    bool allow(const std::string &port, double now) {
        auto it = last.find(port);
        if (it != last.end() && now - it->second < 60.0) {
            return false;
        }
        last[port] = now;
        return true;
    }
};

} // namespace MidiRoute
} // namespace crone

#endif
