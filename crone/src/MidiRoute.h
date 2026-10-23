#ifndef CRONE_MIDIROUTE_H
#define CRONE_MIDIROUTE_H

// the optional auto-connect of MIDI output ports to Verdandi:midi_in (midi_in_from= in audio.conf, NORNS_MIDI_IN_FROM).
// pure logic, no JACK calls (the glue is matron/src/platform/linux/midi_autoconnect.cc).

#include <map>
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

// the MIDI output ports whose whole name starts with a prefix; never one of norns' own clients
inline std::vector<std::string> wanted(const std::vector<MidiPort> &ports, const std::vector<std::string> &prefixes) {
    std::vector<std::string> out;
    for (const auto &p : ports) {
        if (!p.midi || !p.output || InputRoute::isOwnClient(PortSelect::clientOf(p.name))) {
            continue;
        }
        for (const auto &pre : prefixes) {
            if (p.name.compare(0, pre.size(), pre) == 0) {
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
