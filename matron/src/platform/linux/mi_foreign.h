/*
 * mi_foreign.h: Linux desktop. mi-UGens files that are not Verdandi's own pack: a script or mod downloaded the Raspberry Pi build (32-bit ARM, cannot load on
 * x86_64: SuperCollider stops) or unpacked another copy next to ours (duplicate classes). found in the user's SuperCollider extension folder and in dust/code,
 * the two places scripts unpack into, and nowhere else. docs/port/mi-ugens.md, KNOWN-ISSUES.md 37.
 *
 * scan() only looks (it reads the first 64 bytes of each Mi plug-in and lists folders); nothing is moved, changed or deleted here. the launcher
 * (linux/mi-ugens-seed.sh heal, with linux/mi_heal.cc) moves the targets aside with `verdandi tidy disable` when Verdandi's own pack is intact; the running
 * norns only reports (mi_foreign_note.cc), the move is the one confirmation in SYSTEM > CLEAN UP.
 *
 * what is a target: a folder directly inside the extension folder whose plug-ins are all Mi plug-ins of the wrong architecture (the classes and the binaries
 * of a pack move together, so that no class is left behind to clash with ours); otherwise only the wrong Mi plug-in files and the Mi classes next to them
 * (same folder or its Classes folder) that Verdandi's own pack ships. a folder of dust/code is never a target. other plug-ins and files are never listed.
 * a copy that loads on this machine but is not ours is only reported (foreign_x86): SuperCollider's duplicate-class error and the class check say the rest.
 */

#pragma once

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <ctype.h>
#include <set>
#include <string>
#include <vector>

#include "plugin_arch.h"

namespace mi_foreign {

struct Target {
    std::string path;
    bool dir;
    std::string why;
};

struct Result {
    std::vector<Target> arm;              // what the launcher may move aside (and CLEAN UP offers)
    std::vector<std::string> foreign_x86; // copies that are not ours but load on this machine: left alone
    bool own_present = false;             // <extensions>/mi-UGens carries our stamp
};

static inline bool hasSuffix(const std::string &s, const char *suf) {
    size_t n = strlen(suf);
    return s.size() >= n && s.compare(s.size() - n, n, suf) == 0;
}
static inline bool miPrefix(const std::string &b) {
    return b.size() > 3 && b[0] == 'M' && b[1] == 'i' && isupper((unsigned char)b[2]);
}
// MiPlaits.so, MiRipples_scsynth.so, MiBeads.scx: Mi + a capital letter ("Midi.so", "Mini.so" are not mi-UGens)
static inline bool isMiPlugin(const std::string &base) {
    return miPrefix(base) && (hasSuffix(base, ".so") || hasSuffix(base, ".scx"));
}
static inline bool isMiClass(const std::string &base) {
    return miPrefix(base) && hasSuffix(base, ".sc");
}
static inline bool isPluginName(const std::string &base) {
    return hasSuffix(base, ".so") || hasSuffix(base, ".scx");
}

static inline std::string dirOf(const std::string &p) {
    size_t i = p.rfind('/');
    return i == std::string::npos ? std::string(".") : p.substr(0, i);
}
static inline std::string baseOf(const std::string &p) {
    size_t i = p.rfind('/');
    return i == std::string::npos ? p : p.substr(i + 1);
}

static inline plugin_arch::Reading readHead(const std::string &path) {
    plugin_arch::Reading r{false, {}};
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return r;
    }
    uint8_t buf[64];
    ssize_t n = read(fd, buf, sizeof buf);
    close(fd);
    if (n < 0) {
        return r;
    }
    r.readable = true;
    r.bytes.assign(buf, buf + n);
    return r;
}

// every plug-in file (.so, .scx) below dir, in any name; symlinked folders are not followed; skip: a folder not entered
static inline void walkPlugins(const std::string &dir, int depth, const std::string &skip, std::vector<std::string> &out) {
    if (depth > 8 || dir == skip) {
        return;
    }
    DIR *d = opendir(dir.c_str());
    if (d == NULL) {
        return;
    }
    while (struct dirent *e = readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        std::string path = dir + "/" + name;
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            walkPlugins(path, depth + 1, skip, out);
        } else if ((S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) && isPluginName(name)) {
            out.push_back(path);
        }
    }
    closedir(d);
}

static inline bool isDirectory(const std::string &p) {
    struct stat st;
    return lstat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}
static inline bool exists(const std::string &p) {
    struct stat st;
    return lstat(p.c_str(), &st) == 0;
}

// the stamp of Verdandi's own pack: pack=mi-UGens (linux/mi-ugens-seed.sh)
static inline bool hasOwnStamp(const std::string &dir) {
    FILE *f = fopen((dir + "/.verdandi-stamp").c_str(), "r");
    if (f == NULL) {
        return false;
    }
    bool own = false;
    char line[256];
    while (fgets(line, sizeof line, f) != NULL) {
        if (strncmp(line, "pack=mi-UGens", 13) == 0 && (line[13] == '\n' || line[13] == '\0' || line[13] == '\r')) {
            own = true;
        }
    }
    fclose(f);
    return own;
}

// packClasses: the file names of the classes Verdandi's own pack ships (MiPlaits.sc ...): only those are moved when a folder is not moved whole
static inline Result scan(const std::string &home, const std::string &machine, const std::set<std::string> &packClasses) {
    using namespace plugin_arch;
    Result res;
    Expect expect = expectedFor(machine);
    if (expect.machine == 0) {
        return res; // an unknown machine: nothing can be called wrong
    }
    std::string ext = home + "/.local/share/SuperCollider/Extensions";
    std::string own = ext + "/mi-UGens";
    res.own_present = hasOwnStamp(own);
    std::string skip = res.own_present ? own : std::string("\x01none");

    std::vector<std::string> files;
    walkPlugins(ext, 0, skip, files);
    size_t extCount = files.size();
    walkPlugins(home + "/dust/code", 0, skip, files);
    std::sort(files.begin(), files.begin() + extCount);

    struct Bad {
        std::string path;
        ElfInfo info;
        bool inExt;
    };
    std::vector<Bad> bad;
    std::set<std::string> nativeUnits;
    for (size_t i = 0; i < files.size(); i++) {
        const std::string &f = files[i];
        if (!isMiPlugin(baseOf(f))) {
            continue;
        }
        Reading r = readHead(f);
        Verdict v = check(r, expect);
        bool inExt = i < extCount;
        if (v == Verdict::Mismatch) {
            bad.push_back({f, parseElf(r.bytes), inExt});
        } else if (v == Verdict::Ok) {
            std::string unit = f;
            if (inExt) {
                std::string rel = f.substr(ext.size() + 1);
                size_t slash = rel.find('/');
                if (slash != std::string::npos) {
                    unit = ext + "/" + rel.substr(0, slash);
                }
            } else {
                unit = dirOf(f);
            }
            nativeUnits.insert(unit);
        }
    }
    res.foreign_x86.assign(nativeUnits.begin(), nativeUnits.end());

    std::set<std::string> done;
    auto add = [&](const std::string &path, bool dir, const std::string &why) {
        if (done.insert(path).second) {
            res.arm.push_back({path, dir, why});
        }
    };
    auto siblings = [&](const std::string &d, const std::string &why) {
        for (const std::string &cd : {d, d + "/Classes"}) {
            DIR *dd = opendir(cd.c_str());
            if (dd == NULL) {
                continue;
            }
            std::vector<std::string> names;
            while (struct dirent *e = readdir(dd)) {
                std::string n = e->d_name;
                if (isMiClass(n) && packClasses.count(n) > 0) {
                    names.push_back(n);
                }
            }
            closedir(dd);
            std::sort(names.begin(), names.end());
            for (const auto &n : names) {
                add(cd + "/" + n, false, why);
            }
        }
    };
    for (const auto &b : bad) {
        std::string why = "foreign mi-UGens plug-in (" + describe(b.info) + ") on " + expect.name + ": Verdandi's own pack is in use";
        std::string unitDir;
        if (b.inExt) {
            std::string rel = b.path.substr(ext.size() + 1);
            size_t slash = rel.find('/');
            if (slash != std::string::npos) {
                unitDir = ext + "/" + rel.substr(0, slash);
            }
        }
        if (!unitDir.empty() && isDirectory(unitDir)) {
            if (done.count(unitDir) > 0) {
                continue;
            }
            // the whole folder only when every plug-in in it is a Mi plug-in of the wrong architecture
            std::vector<std::string> inside;
            walkPlugins(unitDir, 0, "\\x01none", inside);
            bool all = !inside.empty();
            for (const auto &p : inside) {
                if (!isMiPlugin(baseOf(p)) || check(readHead(p), expect) != Verdict::Mismatch) {
                    all = false;
                }
            }
            if (all) {
                add(unitDir, true, why);
                continue;
            }
        }
        if (done.count(unitDir) > 0) {
            continue;
        }
        add(b.path, false, why);
        siblings(dirOf(b.path), why);
    }
    // a folder that was added whole after some of its files were added one by one: the folder wins
    std::vector<Target> out;
    for (const auto &t : res.arm) {
        bool inside = false;
        for (const auto &o : res.arm) {
            if (o.dir && t.path.size() > o.path.size() && t.path.compare(0, o.path.size() + 1, o.path + "/") == 0) {
                inside = true;
            }
        }
        if (!inside) {
            out.push_back(t);
        }
    }
    res.arm = out;
    return res;
}


// ---- any wrong-architecture SuperCollider plug-in (the running norns, and the same files the launcher's start-up heal moves: linux/plugin-heal.sh uses
// build/linux/plugin_arch_check for those). the user's extension folder and dust/code only (the two places scripts install into); a folder directly in the extension
// folder whose plug-ins are all wrong is one target, else the files. Lua libraries in dust/code and files of this machine's architecture are never listed.
static inline void walkAny(const std::string &dir, int depth, bool inDust, const std::string &skip, std::vector<std::string> &out) {
    if (depth > 8 || dir == skip) {
        return;
    }
    DIR *d = opendir(dir.c_str());
    if (d == NULL) {
        return;
    }
    while (struct dirent *e = readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        std::string path = dir + "/" + name;
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            walkAny(path, depth + 1, inDust, skip, out);
        } else if ((S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) && plugin_arch::isPluginFile(path, inDust)) {
            out.push_back(path);
        }
    }
    closedir(d);
}

static inline Result scanAny(const std::string &home, const std::string &machine) {
    using namespace plugin_arch;
    Result res;
    Expect expect = expectedFor(machine);
    if (expect.machine == 0) {
        return res;
    }
    std::string ext = home + "/.local/share/SuperCollider/Extensions";
    std::vector<std::string> files;
    walkAny(ext, 0, false, "\x01none", files);
    walkAny(home + "/dust/code", 0, true, "\x01none", files);
    std::sort(files.begin(), files.end());
    files.erase(std::unique(files.begin(), files.end()), files.end());
    std::vector<Finding> found = plugin_arch::scan(files, [](const std::string &p) { return readHead(p); }, machine);
    for (const auto &g : groupFindings(found, files, {ext})) {
        std::string why = "wrong-architecture plug-in (" + describe(g.items.front().info) + ") on " + expect.name;
        if (!g.moveFolder.empty()) {
            res.arm.push_back({g.moveFolder, true, why});
        } else {
            for (const auto &f : g.items) {
                res.arm.push_back({f.path, false, why});
            }
        }
    }
    return res;
}

// is every file of this target a mi-UGens plug-in?
static inline bool isMiTarget(const Target &t) {
    if (!t.dir) {
        return isMiPlugin(baseOf(t.path));
    }
    std::vector<std::string> inside;
    walkPlugins(t.path, 0, "\x01none", inside);
    if (inside.empty()) {
        return false;
    }
    for (const auto &p : inside) {
        if (!isMiPlugin(baseOf(p))) {
            return false;
        }
    }
    return true;
}

// the running norns: what appeared after the first look
class Runtime {
  public:
    std::vector<Target> update(const Result &r) {
        std::vector<Target> fresh;
        if (!have_) {
            have_ = true;
            for (const auto &t : r.arm) {
                baseline_.insert(t.path);
            }
            return fresh;
        }
        for (const auto &t : r.arm) {
            if (baseline_.count(t.path) == 0) {
                fresh.push_back(t);
            }
        }
        return fresh;
    }

  private:
    bool have_ = false;
    std::set<std::string> baseline_;
};

// the file names of the classes of Verdandi's own pack
static inline std::set<std::string> ownClasses(const std::string &home) {
    std::set<std::string> out;
    std::string dir = home + "/.local/share/SuperCollider/Extensions/mi-UGens/Classes";
    DIR *d = opendir(dir.c_str());
    if (d == NULL) {
        return out;
    }
    while (struct dirent *e = readdir(d)) {
        std::string n = e->d_name;
        if (isMiClass(n)) {
            out.insert(n);
        }
    }
    closedir(d);
    return out;
}

} // namespace mi_foreign
