/*
 * midi_ignore.h: Linux desktop. which sound cards the device monitor must not open as MIDI controllers. the kernel's virtual MIDI card (snd-virmidi, "Virtual Raw MIDI",
 * card id "VirMIDI") is the bridge a DAW reads (Reaper lists raw hw: devices only); a raw MIDI port has ONE reader, so a norns that opens it as a controller makes the DAW
 * report "the following MIDI inputs could not be opened". Verdandi's own ALSA output ("Verdandi out") reaches that card through the sequencer, not through the raw port.
 *
 * the list: audio.conf midi_ignore= (NORNS_MIDI_IGNORE), names separated by ";", default "VirMIDI;Virtual Raw MIDI". a card is ignored when any of its identities (card id, driver, the
 * names in /proc/asound) contains an entry, compared without case, blanks, "_" and "-". the target of alsa_midi_out_to (NORNS_ALSA_MIDI_OUT_TO) is always an entry: the card
 * Verdandi out is connected to is one a DAW reads. pure string rules: tests in linux/tests/midi_ignore_test.cpp, the monitor in matron/src/device/device_monitor.cc.
 */

#pragma once

#include <ctype.h>

#include <string>
#include <vector>

namespace midi_ignore {

static inline std::string trim(const std::string &s) {
    size_t a = 0, b = s.size();
    while (a < b && isspace((unsigned char)s[a])) {
        a++;
    }
    while (b > a && isspace((unsigned char)s[b - 1])) {
        b--;
    }
    return s.substr(a, b - a);
}

// "a; b;;c" -> a, b, c
static inline std::vector<std::string> parseList(const char *s) {
    std::vector<std::string> out;
    if (s == nullptr) {
        return out;
    }
    std::string cur;
    for (const char *p = s;; p++) {
        if (*p == ';' || *p == '\0') {
            std::string t = trim(cur);
            if (!t.empty()) {
                out.push_back(t);
            }
            cur.clear();
            if (*p == '\0') {
                break;
            }
        } else {
            cur += *p;
        }
    }
    return out;
}

// the entries: the setting if it is set (empty = no names), else the default; then the alsa_midi_out_to target, once
static inline std::vector<std::string> entries(const char *setting, const char *alsaOutTo) {
    std::vector<std::string> out = setting != nullptr ? parseList(setting) : std::vector<std::string>{"VirMIDI", "Virtual Raw MIDI"};
    if (alsaOutTo != nullptr) {
        std::string t = trim(alsaOutTo);
        bool have = false;
        for (const auto &e : out) {
            have = have || e == t;
        }
        if (!t.empty() && !have) {
            out.push_back(t);
        }
    }
    return out;
}

// lower case letters and digits only
static inline std::string normalize(const std::string &s) {
    std::string out;
    for (char c : s) {
        if (isalnum((unsigned char)c)) {
            out += (char)tolower((unsigned char)c);
        }
    }
    return out;
}

static inline bool matches(const std::vector<std::string> &list, const std::vector<std::string> &identities) {
    for (const auto &e : list) {
        std::string ne = normalize(e);
        if (ne.empty()) {
            continue; // an entry of blanks or punctuation matches nothing (never everything)
        }
        for (const auto &id : identities) {
            if (normalize(id).find(ne) != std::string::npos) {
                return true;
            }
        }
    }
    return false;
}

} // namespace midi_ignore
