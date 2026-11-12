// serialosc_core.h: serialosc (monome's OSC bridge for grids) holds a grid's serial port while it runs, and then Verdandi cannot open the grid. which processes and services are serialosc, what to say and what command
// to type when stopping it needs administrator rights. pure, no system calls: linux/tests/serialosc_core_test.cpp. only exact names are matched: no other program is ever touched.
#pragma once

#include <strings.h>

#include <string>
#include <vector>

namespace vso {

struct Proc {
    unsigned pid = 0;
    std::string image; // "serialoscd.exe"
};
struct Svc {
    std::string name;    // the service name
    std::string display; // the display name
    std::string path;    // the command line of the service's program
    bool running = false;
};
struct State {
    std::vector<Proc> procs;
    std::vector<Svc> services;
};

static inline bool same(const std::string &a, const char *b) { return strcasecmp(a.c_str(), b) == 0; }

// the programs of serialosc (the daemon, the detector and one process per device), by exact image name
static inline bool is_serialosc_image(const std::string &image) {
    return same(image, "serialoscd.exe") || same(image, "serialosc-detector.exe") || same(image, "serialosc-device.exe") || same(image, "serialosc.exe");
}

static inline std::string lower(std::string s) {
    for (auto &c : s) c = (char)tolower((unsigned char)c);
    return s;
}

// a service is serialosc's when its program is one of the images (the path may be quoted and have arguments) or its name is serialosc
static inline bool is_serialosc_service(const Svc &s) {
    if (same(s.name, "serialosc") || same(s.name, "serialoscd")) return true;
    std::string p = lower(s.path);
    for (const char *img : {"serialoscd.exe", "serialosc-detector.exe", "serialosc.exe"}) {
        if (p.find(img) != std::string::npos) return true;
    }
    return false;
}

static inline bool present(const State &s) { return !s.procs.empty() || !s.services.empty(); }

// what the page says about serialosc, in plain words
static inline std::string note(const State &s) {
    if (!present(s)) return "";
    std::string t = "serialosc is running";
    if (!s.services.empty()) t += " as a Windows service (" + s.services[0].name + ")";
    t += ". It keeps the grids' serial ports, so Verdandi cannot open them. K3 stops it (asks once). Verdandi needs no serialosc.";
    return t;
}

// a service that is stopped by an administrator: the commands to type in an administrator Command Prompt. the second one stops it from starting again by itself
static inline std::string admin_stop_command(const Svc &s) { return "sc stop " + s.name; }
static inline std::string admin_manual_command(const Svc &s) { return "sc config " + s.name + " start= demand"; }

// how to keep it from coming back, for the help text
static inline std::string prevent_text(const State &s) {
    std::string t = "If serialosc starts again by itself: ";
    if (!s.services.empty()) {
        t += "it is a Windows service. In an administrator Command Prompt: " + admin_stop_command(s.services[0]) + " then " + admin_manual_command(s.services[0]) + " (start type manual).";
    } else {
        t += "remove it from Windows startup (Task Manager > Startup apps), or do not start its app.";
    }
    return t;
}

struct Action {
    enum Kind { KILL_PROCESS, STOP_SERVICE } kind;
    unsigned pid = 0;
    std::string service;
};

// what stopping means: the services first (they would start the processes again), then the processes that are left
static inline std::vector<Action> plan(const State &s) {
    std::vector<Action> a;
    for (const auto &sv : s.services) {
        if (sv.running) {
            Action x{Action::STOP_SERVICE};
            x.service = sv.name;
            a.push_back(x);
        }
    }
    for (const auto &p : s.procs) {
        Action x{Action::KILL_PROCESS};
        x.pid = p.pid;
        a.push_back(x);
    }
    return a;
}

} // namespace vso
