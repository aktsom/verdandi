// midi_core.h: the MIDI layer of the Windows build (docs/port/phase-m4.md), the part that has no system calls: so that all of it can be tested on Linux (linux/tests/midi_core_test.cpp).
//   1. the names. WinMM lists every port of every device as an own device, named by the driver and cut at 31 characters: "Arturia BeatStep Pro", then "MIDIIN2 (Arturia BeatStep Pro)" for the second port, and "2- USB MIDI Interface"
//      for the second device of the same driver. norns wants ONE device with several ports, named the way the Linux build names them ("name 1", "name 2"), so that a mapping in midimap.conf survives a replug,
//      another USB socket and a reboot: the name carries no index of the system. vmidi_parse_name() takes the wrapper off, vmidi_group() puts the ports of one device together.
//   2. the list: vmidi_diff() compares the devices of one scan with the devices that are listed (what to add, what to remove).
//   3. midi_ignore= in audio.conf: the same rules as the Linux build (platform/linux/midi_ignore.h).
// nothing here knows a program or a maker: every name goes through the same rules.
#pragma once

#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>

#include <map>
#include <string>
#include <vector>

#include "platform/linux/midi_ignore.h"

namespace vmidi {

struct Parsed {
    std::string base; // the name without the wrapper
    int port = 1;     // 1 based: "MIDIIN2 (x)" is port 2 of x
    int instance = 1; // 1 based: "2- x" is the second device that has the name x
};

static inline std::string trim(const std::string &s) { return midi_ignore::trim(s); }

// "MIDIIN2 (Name)", "MIDIOUT3 (Name)", "2- Name", and both. the name is whatever is left. a name that has none of these is the name as it is
static inline Parsed parse_name(const std::string &raw) {
    Parsed p;
    std::string s = trim(raw);
    for (int pass = 0; pass < 2; pass++) {
        // MIDIIN<n> ( ... )
        if (s.size() > 8 && (strncasecmp(s.c_str(), "MIDIIN", 6) == 0 || strncasecmp(s.c_str(), "MIDIOUT", 7) == 0)) {
            size_t i = strncasecmp(s.c_str(), "MIDIIN", 6) == 0 ? 6 : 7;
            size_t d = i;
            while (d < s.size() && isdigit((unsigned char)s[d])) {
                d++;
            }
            if (d > i && d + 1 < s.size() && s[d] == ' ' && s[d + 1] == '(' && s.back() == ')') {
                p.port = atoi(s.substr(i, d - i).c_str());
                if (p.port < 1) {
                    p.port = 1;
                }
                s = trim(s.substr(d + 2, s.size() - d - 3));
                continue;
            }
        }
        // "<n>- Name" (Windows numbers a second driver instance with the same name)
        if (s.size() > 3 && isdigit((unsigned char)s[0])) {
            size_t d = 0;
            while (d < s.size() && isdigit((unsigned char)s[d])) {
                d++;
            }
            if (d < 3 && d + 1 < s.size() && s[d] == '-' && s[d + 1] == ' ') {
                p.instance = atoi(s.substr(0, d).c_str());
                if (p.instance < 1) {
                    p.instance = 1;
                }
                s = trim(s.substr(d + 2));
                continue;
            }
        }
        break;
    }
    p.base = s;
    return p;
}

// the key of a device (its path in norns' list): "winmm:" + the name in lower case, blanks collapsed, "#n" for the n-th device of that name (n > 1)
static inline std::string key_of(const std::string &base, int instance) {
    std::string k = "winmm:";
    bool sp = false;
    for (char c : base) {
        if (isspace((unsigned char)c)) {
            sp = true;
            continue;
        }
        if (sp && k.back() != ':') {
            k += ' ';
        }
        sp = false;
        k += (char)tolower((unsigned char)c);
    }
    if (instance > 1) {
        k += "#" + std::to_string(instance);
    }
    return k;
}

static const int MAX_PORTS = 32;

struct Device {
    std::string key;  // the path
    std::string name; // the name in the list: "Name", "Name 2" for the second device of that name
    int nports = 0;
    int in_idx[MAX_PORTS];  // the WinMM input index of port k+1, -1 = none
    int out_idx[MAX_PORTS]; // the WinMM output index, -1 = none
    Device() {
        for (int i = 0; i < MAX_PORTS; i++) {
            in_idx[i] = out_idx[i] = -1;
        }
    }
};

// the devices of a scan. `ins` and `outs` are the names WinMM gave, in the order of its indices. the second input of the same name and port number (two identical interfaces) is the second device
static inline std::vector<Device> group(const std::vector<std::string> &ins, const std::vector<std::string> &outs) {
    std::vector<Device> out;
    std::map<std::string, size_t> at;
    std::map<std::string, int> seen; // base|port|dir -> how many so far
    auto add = [&](const std::vector<std::string> &names, bool input) {
        for (size_t i = 0; i < names.size(); i++) {
            Parsed p = parse_name(names[i]);
            if (p.base.empty()) {
                continue;
            }
            int inst = p.instance;
            std::string sk = key_of(p.base, 1) + "|" + std::to_string(p.port) + (input ? "|i" : "|o");
            int n = ++seen[sk];
            if (inst == 1 && n > 1) {
                inst = n; // the driver did not number them: the order of the system does
            }
            std::string key = key_of(p.base, inst);
            auto f = at.find(key);
            if (f == at.end()) {
                Device d;
                d.key = key;
                d.name = inst > 1 ? p.base + " " + std::to_string(inst) : p.base;
                f = at.emplace(key, out.size()).first;
                out.push_back(d);
            }
            Device &d = out[f->second];
            if (p.port > MAX_PORTS) {
                continue;
            }
            (input ? d.in_idx : d.out_idx)[p.port - 1] = (int)i;
            if (p.port > d.nports) {
                d.nports = p.port;
            }
        }
    };
    add(ins, true);
    add(outs, false);
    return out;
}

struct Diff {
    std::vector<Device> add;
    std::vector<std::string> remove; // keys
};

// `listed`: the keys that are in the list now. `scan`: the devices of this scan (without the ignored ones)
static inline Diff diff(const std::vector<std::string> &listed, const std::vector<Device> &scan) {
    Diff d;
    for (const auto &k : listed) {
        bool there = false;
        for (const auto &s : scan) {
            there = there || s.key == k;
        }
        if (!there) {
            d.remove.push_back(k);
        }
    }
    for (const auto &s : scan) {
        bool known = false;
        for (const auto &k : listed) {
            known = known || s.key == k;
        }
        if (!known) {
            d.add.push_back(s);
        }
    }
    return d;
}

// midi_ignore= (audio.conf): the setting if it is set, else nothing on Windows (no virtual raw card to keep away from a DAW; a program that wants a port for itself is named here)
static inline bool ignored(const char *setting, const Device &d, const std::vector<std::string> &raw_names) {
    std::vector<std::string> ids = raw_names;
    ids.push_back(d.name);
    return midi_ignore::matches(midi_ignore::parseList(setting), ids);
}

// is the name one of a virtual MIDI cable (a loopback port of loopMIDI or Windows MIDI Services, another program's port)? only used to SAY so on the DEVICES page; they are ordinary devices otherwise
static inline bool looks_virtual(const std::string &name) {
    std::string n = midi_ignore::normalize(name);
    static const char *marks[] = {"loopmidi", "loopback", "virtual", "midiyoke", "rtpmidi", "midiservices"};
    for (const char *m : marks) {
        if (n.find(m) != std::string::npos) {
            return true;
        }
    }
    return false;
}

} // namespace vmidi
