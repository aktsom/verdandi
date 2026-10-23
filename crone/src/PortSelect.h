#ifndef CRONE_PORTSELECT_H
#define CRONE_PORTSELECT_H

// choosing the sound card's JACK ports on a desktop (Linux). pure logic, no JACK calls.
// on PipeWire the JACK view holds MIDI bridges, sink monitors and per-app streams beside the card, so
// "any port flagged physical" is not enough: audio type only, one client (card) only.

#include <string>
#include <vector>

namespace crone {
namespace PortSelect {

struct Port {
    std::string name; // "client:port"
    bool audio;       // type is audio (not MIDI)
    bool physical;    // JackPortIsPhysical
};

struct Result {
    std::vector<std::string> ports; // up to two; empty if nothing usable
    std::string client;
    std::string warning; // empty if all fine
};

inline std::string clientOf(const std::string &name) {
    auto i = name.find(':');
    return i == std::string::npos ? name : name.substr(0, i);
}

// "Vivaldi-73" -> "Vivaldi": PipeWire names the JACK client of each stream after the app plus a number
inline std::string baseName(const std::string &client) {
    auto i = client.rfind('-');
    if (i == std::string::npos || i == 0 || i + 1 >= client.size()) {
        return client;
    }
    for (auto j = i + 1; j < client.size(); ++j) {
        if (client[j] < '0' || client[j] > '9') {
            return client;
        }
    }
    return client.substr(0, i);
}

// candidates: the ports of one direction in JACK's order. prefix: "" or the start of a client name.
// what: "input" or "output" (for messages).
inline Result select(const std::vector<Port> &candidates, const std::string &prefix, const std::string &what) {
    Result r;
    std::vector<Port> usable;
    for (const auto &p : candidates) {
        if (p.audio && p.physical) {
            usable.push_back(p);
        }
    }
    if (usable.empty()) {
        r.warning = "no sound card " + what + " ports found: audio " + what + " is not connected";
        return r;
    }

    std::string client;
    bool matched = false;
    if (!prefix.empty()) {
        for (const auto &p : usable) {
            std::string c = clientOf(p.name);
            if (c.compare(0, prefix.size(), prefix) == 0) {
                client = c;
                matched = true;
                break;
            }
        }
        if (!matched) {
            r.warning = "no " + what + " device matches '" + prefix + "': using the default";
        }
    }
    if (!matched) {
        client = clientOf(usable[0].name);
    }

    for (const auto &p : usable) {
        if (clientOf(p.name) == client && r.ports.size() < 2) {
            r.ports.push_back(p.name);
        }
    }
    if (r.ports.size() == 1) {
        r.ports.push_back(r.ports[0]); // mono device: both channels
    }
    r.client = client;
    return r;
}

} // namespace PortSelect
} // namespace crone

#endif
