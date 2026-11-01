/*
 * serialosc_check.cc: see serialosc_conflict.h
 *
 * when norns has opened a monome grid or arc, look through /proc for serialosc's serialosc-device process for the same device
 * (command line, and the open files where they can be read). one log line per episode, a standing note on the device window
 * (lua asks for it: serialosc_conflict_text, now and every few seconds), gone when the conflict is. reads only: it never
 * stops or changes anything. no root: unreadable entries are skipped. off with NORNS_SERIALOSC_CHECK=0.
 */

#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include <algorithm>
#include <iterator>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "serialosc_conflict.h"
#include "serialosc_check.h"

namespace {

struct Dev {
    std::string path;
    std::string serial;
};

std::mutex mtx;
std::map<int, Dev> devs;
bool shown = false; // the note is on (one log line per episode)

std::string resolve(const std::string &p) {
    char buf[PATH_MAX];
    return realpath(p.c_str(), buf) != NULL ? std::string(buf) : p;
}

std::vector<serialosc::Proc> read_procs(void) {
    std::vector<serialosc::Proc> out;
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
        serialosc::Proc p{pid, {}, {}};
        char path[64];
        snprintf(path, sizeof path, "/proc/%d/cmdline", pid);
        FILE *f = fopen(path, "r");
        if (f != NULL) {
            char buf[4096];
            size_t n = fread(buf, 1, sizeof buf, f);
            fclose(f);
            size_t i = 0;
            while (i < n) {
                size_t j = i;
                while (j < n && buf[j] != '\0') {
                    j++;
                }
                p.args.emplace_back(buf + i, j - i);
                i = j + 1;
            }
        }
        // the open files, only of processes that look like serialosc (cheap; and what we cannot read we skip)
        if (!p.args.empty() && serialosc::isSerialoscName(p)) {
            snprintf(path, sizeof path, "/proc/%d/fd", pid);
            DIR *fd = opendir(path);
            while (fd != NULL) {
                struct dirent *fe = readdir(fd);
                if (fe == NULL) {
                    break;
                }
                char link[PATH_MAX], target[PATH_MAX];
                snprintf(link, sizeof link, "/proc/%d/fd/%s", pid, fe->d_name);
                ssize_t n = readlink(link, target, sizeof target - 1);
                if (n > 0) {
                    p.fds.emplace_back(target, (size_t)n);
                }
            }
            if (fd != NULL) {
                closedir(fd);
            }
        }
        out.push_back(p);
    }
    if (d != NULL) {
        closedir(d);
    }
    return out;
}

// is serialosc.service running? a cgroup that has processes: where systemd keeps them (v2, then v1). NORNS_SERIALOSC_UNIT_FILE names another file (the tests): non-empty = active
bool unit_active(void) {
    const char *over = getenv("NORNS_SERIALOSC_UNIT_FILE");
    const char *files[] = {"/sys/fs/cgroup/system.slice/serialosc.service/cgroup.procs", "/sys/fs/cgroup/systemd/system.slice/serialosc.service/cgroup.procs"};
    for (int i = 0; i < 3; i++) {
        const char *f = i == 0 ? over : files[i - 1];
        if (f == NULL) {
            continue;
        }
        FILE *fp = fopen(f, "r");
        if (fp != NULL) {
            int c = fgetc(fp);
            fclose(fp);
            if (c != EOF && c != '\n') {
                return true;
            }
        }
    }
    return false;
}

// is a monome grid or arc plugged in, whether or not norns could open it? udev's by-id names (usb-monome_*); NORNS_SERIALOSC_BYID_DIR names another folder (the tests)
bool monome_nodes(void) {
    const char *dir = getenv("NORNS_SERIALOSC_BYID_DIR");
    DIR *d = opendir(dir != NULL ? dir : "/dev/serial/by-id");
    bool found = false;
    while (d != NULL) {
        struct dirent *e = readdir(d);
        if (e == NULL) {
            break;
        }
        if (strncasecmp(e->d_name, "usb-monome", 10) == 0) {
            found = true;
            break;
        }
    }
    if (d != NULL) {
        closedir(d);
    }
    return found;
}

// the same grid listed twice (the same node, or the same serial): then the note is due too
bool duplicates(void) {
    for (auto a = devs.begin(); a != devs.end(); ++a) {
        for (auto b = std::next(a); b != devs.end(); ++b) {
            if (serialosc::same_device(resolve, a->second.path, b->second.path) || (!a->second.serial.empty() && a->second.serial == b->second.serial)) {
                return true;
            }
        }
    }
    return false;
}

// is the note due now? looked at from the processes, the unit and the devices every time (a grid plugged in later, serialosc started or stopped: no state to go stale). one log line per
// episode. mtx held
bool scan(void) {
    if (!serialosc::enabled(getenv("NORNS_SERIALOSC_CHECK"))) {
        shown = false;
        return false;
    }
    std::vector<serialosc::Proc> procs = read_procs();
    serialosc::Status st = serialosc::assess(procs, unit_active(), !devs.empty(), monome_nodes(), duplicates());
    if (st.show && !shown) {
        std::string held;
        for (const auto &p : procs) {
            if (serialosc::isDeviceProcess(p) && !p.args.empty()) {
                held += " " + p.args.back() + " (pid " + std::to_string(p.pid) + ")";
            }
        }
        serialosc::Conflict c{false, 0, "", ""};
        for (const auto &kv : devs) {
            auto f = serialosc::find(procs, kv.second.path, resolve, (int)getpid());
            if (f.found) {
                c = f;
                break;
            }
        }
        if (c.found) {
            fprintf(stderr, "serialosc: %s\n", serialosc::message(devs.empty() ? "a grid" : devs.begin()->second.path, c).c_str());
        } else {
            std::string h = held.empty() ? "" : "serialosc-device has:" + held;
            fprintf(stderr, "serialosc: %s\n", serialosc::message_running(h).c_str());
        }
    }
    shown = st.show;
    return st.show;
}

} // namespace

extern "C" {

void serialosc_device_added(int id, const char *path, const char *serial) {
    if (path == NULL) {
        return;
    }
    std::lock_guard<std::mutex> l(mtx);
    devs[id] = Dev{path, serial != NULL ? serial : ""};
    scan();
}

void serialosc_device_removed(int id) {
    std::lock_guard<std::mutex> l(mtx);
    devs.erase(id);
}

const char *serialosc_conflict_text(void) {
    std::lock_guard<std::mutex> l(mtx);
    return scan() ? serialosc::note() : NULL;
}

} // extern "C"
