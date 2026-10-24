#ifndef CRONE_INPUTROUTE_H
#define CRONE_INPUTROUTE_H

// what feeds crone's input on a desktop (MIC, SYS, APP, optional sink monitor), decided from the ports of a
// JACK server. pure logic, no JACK calls (the glue is matron/src/platform/linux/app_audio_linux.cc).
// applications: PipeWire gives each stream a JACK client named after the application, a numeric suffix for further
// streams ("Vivaldi", "Vivaldi-73"). norns' own clients and sound cards are not applications.

#include <algorithm>
#include <cctype>
#include <cstring>
#include <string>
#include <vector>

#include "PortSelect.h"

namespace crone {
namespace InputRoute {

struct PortInfo {
    std::string name; // "client:port"
    bool audio;
    bool physical;
    bool output; // an output port (a source of sound)
};

struct Link {
    std::string from, to;
};

struct App {
    std::string name;               // without the numeric suffix
    std::vector<std::string> ports; // all output ports of all its streams, sorted
};

inline bool isOwnClient(const std::string &client) {
    static const char *own[] = {"crone", "softcut", "SuperCollider", "Verdandi", "Verdandi ctl"};
    std::string base = PortSelect::baseName(client);
    for (const char *o : own) {
        if (base == o) {
            return true;
        }
    }
    return false;
}

inline std::string portPart(const std::string &name) {
    auto i = name.find(':');
    return i == std::string::npos ? name : name.substr(i + 1);
}

// ports SYS and APP never take, whatever the client: the name part starts with "monitor" or "capture". under PipeWire a
// capture stream (Reaper reading the microphone through the ALSA plugin) is a client whose output ports are monitor_FL/FR:
// the microphone, not an application's playback. a deny-list, not "only output*": a playback stream or a plain JACK
// application with other port names (out, audio_out_L) is still an application
inline bool isDeniedPort(const std::string &name) {
    std::string part = portPart(name);
    auto starts = [&](const char *w) {
        size_t n = strlen(w);
        if (part.size() < n) {
            return false;
        }
        for (size_t i = 0; i < n; i++) {
            if (tolower((unsigned char)part[i]) != w[i]) {
                return false;
            }
        }
        return true;
    };
    return starts("monitor") || starts("capture");
}

// the applications: clients with audio output ports, none of them physical, that are not norns and not a card
// (a client that owns any physical port, input or output, is a card)
inline std::vector<App> listApps(const std::vector<PortInfo> &ports) {
    std::vector<std::string> cards;
    for (const auto &p : ports) {
        if (p.physical) {
            cards.push_back(PortSelect::clientOf(p.name));
        }
    }
    std::vector<App> apps;
    for (const auto &p : ports) {
        if (!p.audio || !p.output || p.physical || isDeniedPort(p.name)) {
            continue;
        }
        std::string client = PortSelect::clientOf(p.name);
        if (isOwnClient(client) || std::find(cards.begin(), cards.end(), client) != cards.end()) {
            continue;
        }
        std::string base = PortSelect::baseName(client);
        auto it = std::find_if(apps.begin(), apps.end(), [&](const App &a) { return a.name == base; });
        if (it == apps.end()) {
            apps.push_back(App{base, {}});
            it = apps.end() - 1;
        }
        it->ports.push_back(p.name);
    }
    for (auto &a : apps) {
        std::sort(a.ports.begin(), a.ports.end());
    }
    return apps;
}

// the first port feeds input 1, the second input 2; one port feeds both. several streams: each its own pair
inline void pair(std::vector<Link> &out, const std::vector<std::string> &ports) {
    for (size_t i = 0; i < ports.size(); i += 2) {
        out.push_back(Link{ports[i], "crone:input_1"});
        out.push_back(Link{i + 1 < ports.size() ? ports[i + 1] : ports[i], "crone:input_2"});
    }
}

// mode: "off", "mic", "system" (every application), "app" (target = its name), "monitor" (the sink monitor of
// outClient, the chosen output card). inPrefix: the card chosen for the input ("" = the first)
inline std::vector<Link> desired(const std::string &mode, const std::string &target,
                                 const std::vector<PortInfo> &ports, const std::string &inPrefix,
                                 const std::string &outClient) {
    std::vector<Link> out;
    if (mode == "mic") {
        std::vector<PortSelect::Port> cand;
        for (const auto &p : ports) {
            if (p.output && p.physical) {
                cand.push_back(PortSelect::Port{p.name, p.audio, true});
            }
        }
        PortSelect::Result r = PortSelect::select(cand, inPrefix, "input");
        if (r.ports.size() == 2) {
            out.push_back(Link{r.ports[0], "crone:input_1"});
            out.push_back(Link{r.ports[1], "crone:input_2"});
        }
    } else if (mode == "system" || mode == "app") {
        for (const auto &a : listApps(ports)) {
            if (mode == "system" || a.name == target) {
                // a stream's ports in pairs: Vivaldi:FL,FR then Vivaldi-73:FL,FR: pair per client
                std::vector<std::string> one;
                std::string client;
                for (const auto &pn : a.ports) {
                    std::string c = PortSelect::clientOf(pn);
                    if (!one.empty() && c != client) {
                        pair(out, one);
                        one.clear();
                    }
                    client = c;
                    one.push_back(pn);
                }
                pair(out, one);
            }
        }
    } else if (mode == "monitor" && !outClient.empty()) {
        std::vector<std::string> mon;
        for (const auto &p : ports) {
            if (p.audio && p.output && !p.physical && PortSelect::clientOf(p.name) == outClient &&
                portPart(p.name).compare(0, 7, "monitor") == 0) {
                mon.push_back(p.name);
            }
        }
        std::sort(mon.begin(), mon.end());
        if (!mon.empty()) {
            pair(out, std::vector<std::string>(mon.begin(), mon.begin() + std::min<size_t>(2, mon.size())));
        }
    }
    return out;
}

inline bool contains(const std::vector<Link> &l, const Link &k) {
    for (const auto &x : l) {
        if (x.from == k.from && x.to == k.to) {
            return true;
        }
    }
    return false;
}

// wanted and not there yet
inline std::vector<Link> missing(const std::vector<Link> &want, const std::vector<Link> &have) {
    std::vector<Link> m;
    for (const auto &k : want) {
        if (!contains(have, k)) {
            m.push_back(k);
        }
    }
    return m;
}

// there (into crone:input_1/2) and not wanted
inline std::vector<Link> surplus(const std::vector<Link> &want, const std::vector<Link> &have) {
    std::vector<Link> s;
    for (const auto &k : have) {
        if ((k.to == "crone:input_1" || k.to == "crone:input_2") && !contains(want, k)) {
            s.push_back(k);
        }
    }
    return s;
}

} // namespace InputRoute
} // namespace crone

#endif
