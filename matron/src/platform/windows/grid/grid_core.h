// grid_core.h: which serial ports are monome grids (Windows build, docs/port/phase-m5.md). pure, no system calls: linux/tests/grid_core_test.cpp.
// a COM number says nothing (it changes with the USB socket): a port is looked at by what Windows knows about its USB device: vendor and product id, the USB serial string, the instance id.
//   - 0xCAFE:0x1110 is the id of the current grids (the same as the Linux udev rule): a grid; libmonome then asks it who it is.
//   - 0x0403:0x6001 is the generic FTDI id of Arduino boards, GPS dongles and lab gear as well as the 2011 grids: a grid ONLY when its serial looks like a monome's ("m" or "M" and digits: the mext family; "m64-", "m128-",
//     "m256-", "mk", "m40h", "a40h-": the older series, 40h and arduinome families) or the user listed that serial (audio.conf monome_serial=). any other port is never opened.
//   - everything else is not looked at (listed once in the log as a serial port that is not a monome).
// the serial: FTDI's driver appends a letter for the channel to the serial in the instance id (FTDIBUS\VID_0403+PID_6001+M0000163A\0000 is the serial M0000163); a composite USB device (a CDC function as
// interface 0: USB\VID_CAFE&PID_1110&MI_00\6&abc&0&0000) has no serial of its own: it is the one of the parent (USB\VID_CAFE&PID_1110\M0000123).
#pragma once

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <string>
#include <vector>

namespace vgrid {

struct Port {
    std::string name;     // "COM6"
    int vid = 0, pid = 0; // 0 when unknown
    std::string serial;   // the USB serial after trimming, "" when none
    std::string friendly; // "USB Serial Device"
};

static inline std::string upper(std::string s) {
    for (auto &c : s) c = (char)toupper((unsigned char)c);
    return s;
}

// "USB\VID_CAFE&PID_1110\M0000123" -> vid, pid
static inline bool vid_pid_of(const std::string &instance, int *vid, int *pid) {
    std::string u = upper(instance);
    size_t v = u.find("VID_"), p = u.find("PID_");
    if (v == std::string::npos || p == std::string::npos) return false;
    *vid = (int)strtol(u.c_str() + v + 4, nullptr, 16);
    *pid = (int)strtol(u.c_str() + p + 4, nullptr, 16);
    return *vid != 0;
}

// the serial in an instance id of a device that has one of its own, trimmed; "" if the id carries none
//   FTDIBUS\VID_0403+PID_6001+M0000163A\0000  ->  M0000163   (the channel letter FTDI appends is cut; a serial that is a monome's is checked by the caller)
//   USB\VID_CAFE&PID_1110\M0000123            ->  M0000123
//   USB\VID_CAFE&PID_1110&MI_00\6&2a&0&0000   ->  ""         (a composite function: ask the parent)
//   USB\VID_CAFE&PID_1110\6&2a3b&0&2          ->  ""         (Windows made the id up: the device has no serial)
static inline std::string serial_of_instance(const std::string &instance) {
    if (strncasecmp(instance.c_str(), "FTDIBUS\\", 8) == 0) {
        size_t plus = instance.rfind('+');
        size_t slash = instance.find('\\', plus == std::string::npos ? 0 : plus);
        if (plus == std::string::npos || slash == std::string::npos || slash <= plus + 1) return "";
        std::string s = instance.substr(plus + 1, slash - plus - 1);
        if (s.size() > 1) s.pop_back();
        return s;
    }
    if (strncasecmp(instance.c_str(), "USB\\", 4) == 0) {
        if (upper(instance).find("&MI_") != std::string::npos) return "";
        size_t slash = instance.rfind('\\');
        if (slash == std::string::npos || slash + 1 >= instance.size()) return "";
        std::string s = instance.substr(slash + 1);
        if (s.find('&') != std::string::npos) return "";
        return s;
    }
    return "";
}

// does the serial look like a monome's?
static inline bool monome_like_serial(const std::string &s) {
    auto digits = [&](size_t from) {
        if (from >= s.size()) return false;
        for (size_t i = from; i < s.size(); i++) if (!isdigit((unsigned char)s[i])) return false;
        return true;
    };
    if (s.size() >= 2 && (s[0] == 'm' || s[0] == 'M') && digits(1)) return true; // mext: m1000123, M0000163
    static const char *series[] = {"m64-", "m128-", "m256-", "mk", "m40h", "a40h-"};
    for (const char *p : series) {
        size_t n = strlen(p);
        if (strncasecmp(s.c_str(), p, n) == 0 && s.size() > n) return true;
    }
    return false;
}

struct Rules {
    std::vector<std::string> extra_serials; // audio.conf monome_serial= (names separated by ;), matched without case
    std::vector<std::string> ignore;        // audio.conf monome_ignore= : serials or COM names that are left alone
};

enum Verdict { GRID, NOT_MONOME, IGNORED };
struct Result {
    Verdict v;
    std::string why; // plain words for the log and the page
};

static inline bool listed(const std::vector<std::string> &l, const std::string &x) {
    for (const auto &e : l) if (!e.empty() && strcasecmp(e.c_str(), x.c_str()) == 0) return true;
    return false;
}

static inline Result classify(const Port &p, const Rules &r) {
    if (listed(r.ignore, p.name) || (!p.serial.empty() && listed(r.ignore, p.serial))) {
        return {IGNORED, "left alone (monome_ignore in audio.conf)"};
    }
    if (p.vid == 0xCAFE && p.pid == 0x1110) {
        return {GRID, "a monome (USB id CAFE:1110)"};
    }
    if (p.vid == 0x0403 && p.pid == 0x6001) {
        if (monome_like_serial(p.serial)) return {GRID, "a monome (FTDI, serial " + p.serial + ")"};
        if (!p.serial.empty() && listed(r.extra_serials, p.serial)) return {GRID, "a monome (serial " + p.serial + " is listed in audio.conf monome_serial)"};
        return {NOT_MONOME, "a serial port with the generic FTDI id" + (p.serial.empty() ? std::string(" and no serial") : " and the serial " + p.serial) + ": not a monome, not opened (add the serial to monome_serial= in audio.conf if it is one)"};
    }
    if (p.vid != 0 && listed(r.extra_serials, p.serial) && !p.serial.empty()) return {GRID, "a monome (serial " + p.serial + " is listed in audio.conf monome_serial)"};
    return {NOT_MONOME, "a serial port that is not a monome, not opened"};
}

static inline std::vector<std::string> split_list(const std::string &s) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s + ";") {
        if (c == ';') {
            size_t a = cur.find_first_not_of(" \t"), b = cur.find_last_not_of(" \t");
            if (a != std::string::npos) out.push_back(cur.substr(a, b - a + 1));
            cur.clear();
        } else cur += c;
    }
    return out;
}

// the serial libmonome is told (it chooses the protocol from it): the port's own; a device with the id CAFE:1110 that has no serial of its own is a grid of the mext family and gets "m0"; others none
static inline std::string libmonome_serial(const Port &p) {
    if (!p.serial.empty()) return p.serial;
    return (p.vid == 0xCAFE && p.pid == 0x1110) ? "m0" : "";
}

// does the device speak the mext protocol (the system query is answered)? the current grids and the "m<digits>" serials; not the older series, 40h and arduinome families
static inline bool speaks_mext(const Port &p) {
    if (p.vid == 0xCAFE && p.pid == 0x1110) return true;
    if (p.serial.size() < 2 || (p.serial[0] != 'm' && p.serial[0] != 'M')) return false;
    for (size_t i = 1; i < p.serial.size(); i++) if (!isdigit((unsigned char)p.serial[i])) return false;
    return true;
}

// what the page and the log call a grid: "grid 128", from the columns and rows libmonome reports ("monome 128" is the friendly name)
static inline std::string size_name(int cols, int rows) {
    if (cols == 0 && rows == 0) return "arc";
    return "grid " + std::to_string(cols * rows);
}

} // namespace vgrid
