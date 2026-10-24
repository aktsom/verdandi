/*
 * serialosc_conflict.h: is another process reading the serial port of a monome grid or arc that norns has opened?
 *
 * serialosc (serialoscd, started at boot by serialosc.service) starts one serialosc-device process per grid it finds
 * (command line: serialosc-device -c /var/lib/serialosc /dev/ttyACM0). two readers on one serial stream steal each other's bytes:
 * grid events lag, arrive out of order, or invalid (a row 33 on an 8-row grid). pure logic, no system calls: the process list
 * and the path resolution are passed in, so it is tested without root and without serialosc (linux/tests/serialosc_conflict_test.cpp).
 * the glue that reads /proc is serialosc_check.cc. only a process that has this grid's device counts: serialoscd and
 * serialosc-detector alone do not.
 */

#pragma once

#include <functional>
#include <map>
#include <string>
#include <vector>

#include <stdlib.h>
#include <strings.h>

namespace serialosc {

struct Proc {
    int pid;
    std::vector<std::string> args; // argv from /proc/<pid>/cmdline; empty if unreadable
    std::vector<std::string> fds;  // targets of /proc/<pid>/fd/*, as read; empty if unreadable
};

struct Conflict {
    bool found;
    int pid;
    std::string name; // argv[0] as the process shows it
    std::string how;  // "command line" or "open file"
};

inline std::string baseName(const std::string &path) {
    size_t i = path.rfind('/');
    return i == std::string::npos ? path : path.substr(i + 1);
}

// serialosc's per-device process. it shows as "serialosc-device", or "serialosc-devic" when the name was cut at 15 characters
inline bool isDeviceProcess(const Proc &p) {
    if (p.args.empty()) {
        return false;
    }
    return baseName(p.args[0]).compare(0, 15, "serialosc-devic") == 0;
}

inline bool isSerialoscName(const Proc &p) {
    return !p.args.empty() && baseName(p.args[0]).compare(0, 9, "serialosc") == 0;
}

// the process that has the grid at `device` (any spelling: by-id symlink or ttyACM name; resolve = readlink -f), or none.
// self: norns' own pid, never reported
inline Conflict find(const std::vector<Proc> &procs, const std::string &device,
                                    const std::function<std::string(const std::string &)> &resolve, int self) {
    std::string want = resolve(device);
    for (const auto &p : procs) {
        if (p.pid == self) {
            continue;
        }
        // 1. serialosc-device's last argument is the device it was started for
        if (isDeviceProcess(p)) {
            for (size_t i = p.args.size(); i-- > 1;) {
                if (p.args[i].empty()) {
                    continue; // a trailing empty argument
                }
                if (resolve(p.args[i]) == want) {
                    return Conflict{true, p.pid, p.args[0], "command line"};
                }
                break; // only the last real argument is the device
            }
        }
        // 2. a serialosc process that has the device open (where /proc/<pid>/fd can be read)
        if (isSerialoscName(p)) {
            for (const auto &fd : p.fds) {
                if (!fd.empty() && fd[0] == '/' && resolve(fd) == want) {
                    return Conflict{true, p.pid, p.args[0], "open file"};
                }
            }
        }
    }
    return Conflict{false, 0, "", ""};
}

// the line for the log: one line, plain words
inline std::string message(const std::string &device, const Conflict &c) {
    return "serialosc has this monome device open as well as norns (" + c.name + ", pid " + std::to_string(c.pid) + ", on " +
           device + "): two programs reading one serial port steal each other's bytes, so grid events lag, arrive out of order "
           "or invalid. to stop serialosc for this session: sudo systemctl stop serialosc.service ; to start it again later: "
           "sudo systemctl start serialosc.service . after stopping it, unplug and replug the grid (a replug is needed). "
           "to turn this check off: NORNS_SERIALOSC_CHECK=0 or serialosc_check=0 in audio.conf";
}

// the standing note on the device window
inline const char *note(void) {
    return "GRID: serialosc has this grid, see log";
}

// NORNS_SERIALOSC_CHECK / audio.conf serialosc_check: 0, off, false, no (any case) turn the check off
inline bool enabled(const char *value) {
    if (value == nullptr || value[0] == '\0') {
        return true;
    }
    return !(strcasecmp(value, "0") == 0 || strcasecmp(value, "off") == 0 || strcasecmp(value, "false") == 0 ||
             strcasecmp(value, "no") == 0);
}

} // namespace serialosc
