/*
 * mi_foreign_note.cc: see mi_foreign_note.h. lua asks every few seconds; the scan (the extension folder and dust/code, names and the first bytes of
 * the Mi plug-ins only) is done at most every MI_FOREIGN_INTERVAL seconds (default 5) and cached between. the first look is the baseline: what was
 * there at the start is the launcher's business (the PLUGINS note), only what appears later is new here. off with NORNS_MI_UGENS_HEAL=0.
 */

#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <time.h>

#include <string>

#include "mi_foreign.h"
#include "mi_foreign_note.h"

namespace {

bool healOff(const char *v) {
    if (v == nullptr) {
        return false;
    }
    return strcasecmp(v, "0") == 0 || strcasecmp(v, "off") == 0 || strcasecmp(v, "false") == 0 || strcasecmp(v, "no") == 0;
}

mi_foreign::Runtime runtime;
time_t lastLook = 0;
bool looked = false;
std::string noteText;
std::string fixText;
bool haveNote = false;

void refresh() {
    const char *home = getenv("HOME");
    if (home == nullptr || healOff(getenv("NORNS_PLUGIN_HEAL"))) {
        haveNote = false;
        return;
    }
    long every = 5;
    if (getenv("MI_FOREIGN_INTERVAL") != nullptr) {
        every = atol(getenv("MI_FOREIGN_INTERVAL"));
    }
    time_t now = time(nullptr);
    if (looked && now - lastLook < every) {
        return;
    }
    looked = true;
    lastLook = now;
    std::string machine;
    if (getenv("PLUGIN_ARCH_UNAME") != nullptr) {
        machine = getenv("PLUGIN_ARCH_UNAME");
    } else {
        struct utsname u;
        machine = uname(&u) == 0 ? u.machine : "";
    }
    // every wrong-architecture plug-in a script installs (mi-UGens included); mi_ugens_heal=0 silences the mi-UGens ones only
    mi_foreign::Result r = mi_foreign::scanAny(home, machine);
    std::vector<mi_foreign::Target> fresh = runtime.update(r);
    bool miOff = healOff(getenv("NORNS_MI_UGENS_HEAL"));
    std::vector<mi_foreign::Target> shown;
    bool allMi = true;
    for (const auto &t : fresh) {
        bool mi = mi_foreign::isMiTarget(t);
        if (mi && miOff) {
            continue;
        }
        allMi = allMi && mi;
        shown.push_back(t);
    }
    fixText.clear();
    for (const auto &t : shown) {
        fixText += t.path + "\t" + t.why + "\n";
    }
    haveNote = !shown.empty();
    if (allMi) {
        noteText = "A script downloaded Raspberry Pi mi-UGens. SYSTEM > CLEAN UP moves them aside, then restart norns.";
    } else {
        std::string name = shown[0].path.substr(shown[0].path.rfind('/') + 1);
        std::string more = shown.size() > 1 ? " and " + std::to_string(shown.size() - 1) + " more" : "";
        noteText = "A script installed a Raspberry Pi plug-in (" + name + more + "). SYSTEM > CLEAN UP moves it aside, then restart norns.";
    }
}

} // namespace

extern "C" const char *mi_foreign_note_text(void) {
    refresh();
    return haveNote ? noteText.c_str() : nullptr;
}

extern "C" const char *mi_foreign_fix_text(void) {
    refresh();
    return haveNote ? fixText.c_str() : nullptr;
}
