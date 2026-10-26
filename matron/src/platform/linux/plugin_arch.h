/*
 * plugin_arch.h: SuperCollider plug-ins (.so) built for another machine than this one.
 *
 * scsynth stops at the first plug-in it cannot load ("wrong ELF class: ELFCLASS32" for a Raspberry Pi build on an x86_64 machine) and
 * the whole SuperCollider server then does not start: no engines, "SUPERCOLLIDER FAIL" at every start. community scripts' installers
 * download Raspberry Pi bundles into the extension folder. this header reads ELF headers, passed in as data, and compares them with
 * uname -m. pure logic, no system calls (linux/tests/plugin_arch_test.cpp); the scanner is linux/plugin_arch_check.cc, the note for the
 * device window is serialosc-style (matron/src/platform/linux/plugin_arch_note.cc). report only: nothing is moved or changed.
 */

#pragma once

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace plugin_arch {

struct ElfInfo {
    bool elf = false;
    int bits = 0;
    int machine = 0;
    bool littleEndian = true;
};

struct Reading {
    bool readable;
    std::vector<uint8_t> bytes; // the first bytes of the file
};

enum class Verdict { Ok, NotElf, Unreadable, Mismatch };

struct Expect {
    int bits;
    int machine; // 0: unknown machine, nothing is reported
    std::string name;
};

struct Finding {
    std::string path;
    ElfInfo info;
};

inline ElfInfo parseElf(const uint8_t *b, size_t n) {
    ElfInfo i;
    if (n < 20 || b[0] != 0x7f || b[1] != 'E' || b[2] != 'L' || b[3] != 'F') {
        return i;
    }
    if ((b[4] != 1 && b[4] != 2) || (b[5] != 1 && b[5] != 2)) {
        return i;
    }
    i.elf = true;
    i.bits = b[4] == 1 ? 32 : 64;
    i.littleEndian = b[5] == 1;
    i.machine = i.littleEndian ? (b[18] | (b[19] << 8)) : ((b[18] << 8) | b[19]);
    return i;
}
inline ElfInfo parseElf(const std::vector<uint8_t> &v) {
    return parseElf(v.data(), v.size());
}

// what this machine takes, from uname -m
inline Expect expectedFor(const std::string &m) {
    if (m == "x86_64" || m == "amd64") {
        return {64, 0x3e, "x86_64"};
    }
    if (m == "aarch64" || m == "arm64") {
        return {64, 0xb7, "aarch64"};
    }
    if (m.compare(0, 3, "arm") == 0) { // armv6l, armv7l, armhf
        return {32, 0x28, m};
    }
    if (m == "i386" || m == "i486" || m == "i586" || m == "i686") {
        return {32, 0x03, m};
    }
    if (m == "riscv64") {
        return {64, 0xf3, "riscv64"};
    }
    return {0, 0, m};
}

inline Verdict check(const Reading &r, const Expect &e) {
    if (!r.readable) {
        return Verdict::Unreadable;
    }
    ElfInfo i = parseElf(r.bytes);
    if (!i.elf) {
        return Verdict::NotElf;
    }
    if (e.machine == 0) {
        return Verdict::Ok;
    }
    return (i.machine == e.machine && i.bits == e.bits) ? Verdict::Ok : Verdict::Mismatch;
}

inline std::string describe(const ElfInfo &i) {
    std::string bits = std::to_string(i.bits) + "-bit ";
    switch (i.machine) {
    case 0x3e:
        return bits + "x86_64";
    case 0x03:
        return bits + "x86";
    case 0x28:
        return bits + "ARM";
    case 0xb7:
        return bits + "ARM (aarch64)";
    case 0xf3:
        return bits + "RISC-V";
    case 0x15:
    case 0x14:
        return bits + "PowerPC";
    default: {
        char buf[32];
        snprintf(buf, sizeof buf, "machine 0x%x", i.machine);
        return bits + buf;
    }
    }
}

// the mismatching files among paths; reader gives the first bytes of a file
inline std::vector<Finding> scan(const std::vector<std::string> &paths, const std::function<Reading(const std::string &)> &reader,
                                 const std::string &uname) {
    std::vector<Finding> out;
    Expect e = expectedFor(uname);
    for (const auto &p : paths) {
        Reading r = reader(p);
        if (check(r, e) == Verdict::Mismatch) {
            out.push_back(Finding{p, parseElf(r.bytes)});
        }
    }
    return out;
}

inline bool endsWith(const std::string &s, const char *suffix) {
    size_t n = strlen(suffix);
    return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

// which files count: in the extension folders every .so and .scx; in dust/code (Lua libraries such as cjson.so live there too, which
// SuperCollider does not read) only *_scsynth.so and .scx
inline bool isPluginFile(const std::string &path, bool inDust) {
    if (endsWith(path, ".scx")) {
        return true;
    }
    if (inDust) {
        return endsWith(path, "_scsynth.so");
    }
    return endsWith(path, ".so");
}

// the bad files of one folder: one log line, one move command
struct Group {
    std::string folder;
    std::vector<Finding> items;
    std::string moveFolder; // if every plug-in in the folder is wrong (and it is a folder inside an extension folder): the folder to move instead of the files, "" = the files
};

// found: the bad files (in order); files: every plug-in file that was looked at; roots: the extension folders. one group per folder, in the order of the first bad file
inline std::vector<Group> groupFindings(const std::vector<Finding> &found, const std::vector<std::string> &files, const std::vector<std::string> &roots) {
    std::vector<Group> groups;
    for (const auto &f : found) {
        std::string parent = f.path.substr(0, f.path.rfind('/'));
        Group *g = nullptr;
        for (auto &x : groups) {
            if (x.folder == parent) {
                g = &x;
            }
        }
        if (g == nullptr) {
            groups.push_back(Group{parent, {}, ""});
            g = &groups.back();
        }
        g->items.push_back(f);
    }
    for (auto &g : groups) {
        for (const auto &r : roots) {
            if (g.folder.size() > r.size() && g.folder.compare(0, r.size() + 1, r + "/") == 0) {
                bool all = true;
                for (const auto &p : files) {
                    if (p.compare(0, g.folder.size() + 1, g.folder + "/") == 0 && p.find('/', g.folder.size() + 1) == std::string::npos) {
                        bool bad = false;
                        for (const auto &f : g.items) {
                            bad = bad || f.path == p;
                        }
                        all = all && bad;
                    }
                }
                if (all) {
                    g.moveFolder = g.folder;
                }
            }
        }
    }
    return groups;
}

// the one log line of a folder: the folder, its bad files and what each is, why SuperCollider fails, the one command that moves them, how to turn the check off
inline std::string message(const Group &g, const std::string &uname, const std::string &home) {
    std::string dir = home + "/disabled-plugins";
    bool many = g.items.size() > 1;
    std::string names;
    std::string files;
    for (const auto &f : g.items) {
        names += (names.empty() ? "" : ", ") + f.path.substr(f.path.rfind('/') + 1) + " (" + describe(f.info) + ")";
        files += "'" + f.path + "' ";
    }
    std::string src = g.moveFolder.empty() ? files : "'" + g.moveFolder + "' ";
    return std::string("SuperCollider plug-in") + (many ? "s" : "") + " in " + g.folder + ": " + names + "; this machine is " + uname +
           ": SuperCollider cannot load " + (many ? "them" : "it") +
           " and stops at the first bad file, so it will not start (no engines, SUPERCOLLIDER FAIL), and the list "
           "of bad files may be longer than the one error in sclang.log. nothing was changed. to move " + (many ? "them" : "it") +
           " out of the way (never deleted): mkdir -p '" + dir + "' && mv " + src + "'" + dir + "/' ; "
           "to turn this check off: NORNS_PLUGIN_CHECK=0 or plugin_check=0 in audio.conf";
}

// the standing note on the device window
inline const char *note(void) {
    return "PLUGINS: wrong-architecture plug-in, see log";
}

// NORNS_PLUGIN_CHECK / audio.conf plugin_check: 0, off, false, no (any case) turn the check off
inline bool enabled(const char *value) {
    if (value == nullptr || value[0] == '\0') {
        return true;
    }
    return !(strcasecmp(value, "0") == 0 || strcasecmp(value, "off") == 0 || strcasecmp(value, "false") == 0 ||
             strcasecmp(value, "no") == 0);
}

} // namespace plugin_arch
