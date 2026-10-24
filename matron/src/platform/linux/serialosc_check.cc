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
#include <unistd.h>

#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "serialosc_conflict.h"
#include "serialosc_check.h"

namespace {

struct Dev {
    std::string path;
    bool conflicted = false;
};

std::mutex mtx;
std::map<int, Dev> devs;

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

// look at every device norns has open; log a conflict once per episode. mtx held. true if any conflict
bool scan(void) {
    if (devs.empty() || !serialosc::enabled(getenv("NORNS_SERIALOSC_CHECK"))) {
        for (auto &kv : devs) {
            kv.second.conflicted = false;
        }
        return false;
    }
    std::vector<serialosc::Proc> procs = read_procs();
    bool any = false;
    for (auto &kv : devs) {
        auto c = serialosc::find(procs, kv.second.path, resolve, (int)getpid());
        if (c.found) {
            any = true;
            if (!kv.second.conflicted) {
                fprintf(stderr, "serialosc: %s\n", serialosc::message(kv.second.path, c).c_str());
            }
        }
        kv.second.conflicted = c.found;
    }
    return any;
}

} // namespace

extern "C" {

void serialosc_device_added(int id, const char *path) {
    if (path == NULL) {
        return;
    }
    std::lock_guard<std::mutex> l(mtx);
    devs[id] = Dev{path, false};
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
