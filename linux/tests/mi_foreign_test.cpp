// tests for matron/src/platform/linux/mi_foreign.h: mi-UGens files that are not Verdandi's own pack (a script or mod downloaded a Raspberry Pi build), found in
// the user's SuperCollider extension folder and in dust/code, and what the launcher may move aside. the files are data: fake ELF headers in a scratch
// norns home. built and run by linux/tests/run_all.sh:  g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/mi_foreign_test.cpp

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include <fstream>
#include <set>

#include "platform/linux/mi_foreign.h"

using namespace mi_foreign;

static std::string HOME;
static std::string EXT() { return HOME + "/.local/share/SuperCollider/Extensions"; }

static void put(const std::string &path, const std::string &content) {
    std::string cmd = "mkdir -p '" + path.substr(0, path.rfind('/')) + "'";
    REQUIRE(system(cmd.c_str()) == 0);
    std::ofstream f(path, std::ios::binary);
    f << content;
}
// the first bytes of an ELF file: class, machine (little endian)
static std::string elf(int cls, int machine) {
    std::string b(64, '\0');
    b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F'; b[4] = (char)cls; b[5] = 1; b[6] = 1;
    b[18] = (char)(machine & 0xff); b[19] = (char)(machine >> 8);
    return b;
}
static std::string arm() { return elf(1, 0x28); }
static std::string x86() { return elf(2, 0x3e); }

static void fresh() {
    if (HOME.empty()) {
        char t[] = "/tmp/mi_foreign_XXXXXX";
        HOME = mkdtemp(t);
    }
    std::string cmd = "rm -rf '" + HOME + "'/* '" + HOME + "'/.local; mkdir -p '" + EXT() + "' '" + HOME + "/dust/code'";
    REQUIRE(system(cmd.c_str()) == 0);
    // Verdandi's own pack: stamp and the classes it ships
    put(EXT() + "/mi-UGens/.verdandi-stamp", "pack=mi-UGens\nserial=1\ncommit=abc\n");
    for (const char *c : {"MiPlaits", "MiRings", "MiBeads"}) {
        put(EXT() + "/mi-UGens/Classes/" + c + ".sc", "// ours");
        put(EXT() + "/mi-UGens/" + c + ".so", x86());
    }
}

static std::set<std::string> classes() { return {"MiPlaits.sc", "MiRings.sc", "MiBeads.sc"}; }

static bool has_target(const Result &r, const std::string &path) {
    for (const auto &t : r.arm) {
        if (t.path == path) {
            return true;
        }
    }
    return false;
}

TEST_CASE("which names count: Mi + a capital, .so or .scx") {
    CHECK(isMiPlugin("MiPlaits.so"));
    CHECK(isMiPlugin("MiRipples_scsynth.so"));
    CHECK(isMiPlugin("MiBeads.scx"));
    CHECK_FALSE(isMiPlugin("Midi.so"));       // Mi + a small letter: not mi-UGens
    CHECK_FALSE(isMiPlugin("Mini.so"));
    CHECK_FALSE(isMiPlugin("Mi.so"));
    CHECK_FALSE(isMiPlugin("PulsePTR_scsynth.so"));
    CHECK_FALSE(isMiPlugin("MiPlaits.sc"));
    CHECK(isMiClass("MiPlaits.sc"));
    CHECK_FALSE(isMiClass("MiPlaits.so"));
}

TEST_CASE("Verdandi's own stamped pack is never a finding") {
    fresh();
    Result r = scan(HOME, "x86_64", classes());
    CHECK(r.arm.empty());
    CHECK(r.foreign_x86.empty());
}

TEST_CASE("a folder of the extension folder that is all Raspberry Pi mi-UGens is one target: the folder (classes and binaries together)") {
    fresh();
    put(EXT() + "/MiClouds/MiClouds.so", arm());
    put(EXT() + "/MiClouds/MiRings.so", arm());
    put(EXT() + "/MiClouds/Classes/MiRings.sc", "// theirs");
    Result r = scan(HOME, "x86_64", classes());
    REQUIRE(r.arm.size() == 1);
    CHECK(r.arm[0].path == EXT() + "/MiClouds");
    CHECK(r.arm[0].dir);
    CHECK(r.arm[0].why.find("32-bit ARM") != std::string::npos);
    CHECK(r.foreign_x86.empty());
}

TEST_CASE("a pack unpacked one level deeper still moves as the top folder under the extension folder") {
    fresh();
    put(EXT() + "/mi-UGens-arm/mi-UGens/MiPlaits.so", arm());
    put(EXT() + "/mi-UGens-arm/mi-UGens/Classes/MiPlaits.sc", "// theirs");
    Result r = scan(HOME, "x86_64", classes());
    REQUIRE(r.arm.size() == 1);
    CHECK(r.arm[0].path == EXT() + "/mi-UGens-arm");
}

TEST_CASE("an unstamped folder called mi-UGens is a foreign pack, not ours") {
    fresh();
    std::string cmd = "rm -rf '" + EXT() + "/mi-UGens'";
    REQUIRE(system(cmd.c_str()) == 0);
    put(EXT() + "/mi-UGens/MiPlaits.so", arm());
    put(EXT() + "/mi-UGens/Classes/MiPlaits.sc", "// theirs");
    Result r = scan(HOME, "x86_64", classes());
    REQUIRE(r.arm.size() == 1);
    CHECK(r.arm[0].path == EXT() + "/mi-UGens");
    CHECK_FALSE(r.own_present);
}

TEST_CASE("a folder that also holds other plug-ins: only the Mi files and the Mi classes Verdandi ships move; the other plug-ins and files stay") {
    fresh();
    put(EXT() + "/mixed/MiPlaits.so", arm());
    put(EXT() + "/mixed/Other_scsynth.so", arm()); // not mi-UGens: the plug-in check reports it, heal does not touch it
    put(EXT() + "/mixed/MiPlaits.sc", "// theirs, a class Verdandi ships");
    put(EXT() + "/mixed/MiOwnThing.sc", "// theirs, not a class Verdandi ships");
    put(EXT() + "/mixed/readme.txt", "x");
    Result r = scan(HOME, "x86_64", classes());
    CHECK(has_target(r, EXT() + "/mixed/MiPlaits.so"));
    CHECK(has_target(r, EXT() + "/mixed/MiPlaits.sc"));
    CHECK_FALSE(has_target(r, EXT() + "/mixed/Other_scsynth.so"));
    CHECK_FALSE(has_target(r, EXT() + "/mixed/MiOwnThing.sc"));
    CHECK_FALSE(has_target(r, EXT() + "/mixed"));
    CHECK(r.arm.size() == 2);
}

TEST_CASE("a Mi file directly in the extension folder is a file target") {
    fresh();
    put(EXT() + "/MiBeads.so", arm());
    Result r = scan(HOME, "x86_64", classes());
    REQUIRE(r.arm.size() == 1);
    CHECK(r.arm[0].path == EXT() + "/MiBeads.so");
    CHECK_FALSE(r.arm[0].dir);
}

TEST_CASE("dust/code: the Mi files and shipped Mi classes next to them, never the script's folder") {
    fresh();
    put(HOME + "/dust/code/terrarium/lib/MiRings.so", arm());
    put(HOME + "/dust/code/terrarium/lib/MiRings.sc", "// theirs");
    put(HOME + "/dust/code/terrarium/lib/terrarium.lua", "print(1)");
    put(HOME + "/dust/code/terrarium/lib/cjson.so", arm()); // a Lua library: never touched
    Result r = scan(HOME, "x86_64", classes());
    CHECK(has_target(r, HOME + "/dust/code/terrarium/lib/MiRings.so"));
    CHECK(has_target(r, HOME + "/dust/code/terrarium/lib/MiRings.sc"));
    CHECK_FALSE(has_target(r, HOME + "/dust/code/terrarium"));
    CHECK_FALSE(has_target(r, HOME + "/dust/code/terrarium/lib"));
    CHECK_FALSE(has_target(r, HOME + "/dust/code/terrarium/lib/cjson.so"));
    CHECK(r.arm.size() == 2);
}

TEST_CASE("an x86-64 copy that is not ours is reported, never a target") {
    fresh();
    put(EXT() + "/other-mi/MiClouds.so", x86());
    put(EXT() + "/other-mi/Classes/MiClouds.sc", "// theirs");
    Result r = scan(HOME, "x86_64", classes());
    CHECK(r.arm.empty());
    REQUIRE(r.foreign_x86.size() == 1);
    CHECK(r.foreign_x86[0] == EXT() + "/other-mi");
}

TEST_CASE("non-ELF Mi files, other names, and files outside the two places are not findings") {
    fresh();
    put(EXT() + "/x/MiPlaits.so", "not an elf file at all");
    put(EXT() + "/x/Midi.so", arm());
    put(HOME + "/dust/audio/MiSample.so", arm()); // not a place scripts unpack plug-ins
    put(HOME + "/elsewhere/MiPlaits.so", arm());
    Result r = scan(HOME, "x86_64", classes());
    CHECK(r.arm.empty());
    CHECK(r.foreign_x86.empty());
}

TEST_CASE("an unknown machine reports nothing; an aarch64 machine takes aarch64 only") {
    fresh();
    put(EXT() + "/p/MiPlaits.so", arm());
    CHECK(scan(HOME, "weirdmachine", classes()).arm.empty());
    Result r = scan(HOME, "aarch64", classes());
    REQUIRE(r.arm.size() == 1);
}

TEST_CASE("scanning changes nothing") {
    fresh();
    put(EXT() + "/MiClouds/MiClouds.so", arm());
    std::string before = "find '" + HOME + "' -type f -exec sha1sum {} + | sort > /tmp/mi_foreign_before.txt";
    std::string after = "find '" + HOME + "' -type f -exec sha1sum {} + | sort > /tmp/mi_foreign_after.txt";
    REQUIRE(system(before.c_str()) == 0);
    scan(HOME, "x86_64", classes());
    REQUIRE(system(after.c_str()) == 0);
    CHECK(system("cmp -s /tmp/mi_foreign_before.txt /tmp/mi_foreign_after.txt") == 0);
}

TEST_CASE("runtime: what was there at the first look is the baseline; only what appears later is new, and it goes when the file goes") {
    fresh();
    put(EXT() + "/early/MiPlaits.so", arm());
    Runtime rt;
    CHECK(rt.update(scan(HOME, "x86_64", classes())).empty()); // the first look: the baseline (the launcher's plug-in check reports these)
    CHECK(rt.update(scan(HOME, "x86_64", classes())).empty());
    put(EXT() + "/late/MiRings.so", arm());
    std::vector<Target> n = rt.update(scan(HOME, "x86_64", classes()));
    REQUIRE(n.size() == 1);
    CHECK(n[0].path == EXT() + "/late");
    CHECK(rt.update(scan(HOME, "x86_64", classes())).size() == 1); // still there: still new
    REQUIRE(system(("rm -rf '" + EXT() + "/late'").c_str()) == 0);
    CHECK(rt.update(scan(HOME, "x86_64", classes())).empty());
}

// ---- the running norns: matron/src/platform/linux/mi_foreign_note.cc (built into this test)
extern "C" const char *mi_foreign_note_text(void);
extern "C" const char *mi_foreign_fix_text(void);

TEST_CASE("the note and the CLEAN UP list while norns runs: baseline first, then what a script downloads, gone when the files are gone, off with the setting") {
    fresh();
    setenv("HOME", HOME.c_str(), 1);
    setenv("MI_FOREIGN_INTERVAL", "0", 1);
    setenv("PLUGIN_ARCH_UNAME", "x86_64", 1);
    unsetenv("NORNS_MI_UGENS_HEAL");
    put(EXT() + "/early/MiPlaits.so", arm()); // there at the start: the launcher's plug-in check reports it, not this note
    CHECK(mi_foreign_note_text() == nullptr);
    CHECK(mi_foreign_fix_text() == nullptr);
    put(EXT() + "/late/MiRings.so", arm()); // a script's K3 download while norns runs
    put(EXT() + "/late/Classes/MiRings.sc", "// theirs");
    const char *n = mi_foreign_note_text();
    REQUIRE(n != nullptr);
    CHECK(std::string(n).find("A script downloaded Raspberry Pi mi-UGens") == 0);
    CHECK(std::string(n).find("restart") != std::string::npos);
    CHECK(std::string(n).find("CLEAN UP") != std::string::npos);
    std::string fix = mi_foreign_fix_text() ? mi_foreign_fix_text() : "";
    CHECK(fix.find(EXT() + "/late\t") == 0);
    CHECK(fix.find("32-bit ARM") != std::string::npos);
    CHECK(fix.find("early") == std::string::npos);
    setenv("NORNS_MI_UGENS_HEAL", "0", 1);
    CHECK(mi_foreign_note_text() == nullptr);
    CHECK(mi_foreign_fix_text() == nullptr);
    unsetenv("NORNS_MI_UGENS_HEAL");
    REQUIRE(system(("rm -rf '" + EXT() + "/late'").c_str()) == 0);
    CHECK(mi_foreign_note_text() == nullptr);
    CHECK(mi_foreign_fix_text() == nullptr);
}

// ---- the running norns, any plug-in (not only mi-UGens): what a script installs while norns runs
TEST_CASE("runtime, any wrong-architecture plug-in: the note names it, the CLEAN UP list has it, non-plug-in files and right-architecture plug-ins are ignored") {
    fresh();
    setenv("HOME", HOME.c_str(), 1);
    setenv("MI_FOREIGN_INTERVAL", "0", 1);
    setenv("PLUGIN_ARCH_UNAME", "x86_64", 1);
    unsetenv("NORNS_MI_UGENS_HEAL");
    unsetenv("NORNS_PLUGIN_HEAL");
    // a fresh process state is needed for the baseline: a plug-in that is there at the first look belongs to the launcher
    CHECK(mi_foreign_note_text() == nullptr);
    put(EXT() + "/synthpack/Thing_scsynth.so", arm());       // a script's installer, while norns runs
    put(HOME + "/dust/code/s/lib/Other_scsynth.so", arm());  // a script that unpacks into its own folder
    put(HOME + "/dust/code/s/lib/cjson.so", arm());          // a Lua library: never
    put(EXT() + "/fine/Fine_scsynth.so", x86());             // this machine's own architecture: never
    put(EXT() + "/readme/notes.txt", "x");
    const char *n = mi_foreign_note_text();
    REQUIRE(n != nullptr);
    std::string note = n;
    CHECK(note.find("A script installed a Raspberry Pi plug-in") == 0);
    CHECK(note.find("restart") != std::string::npos);
    CHECK(note.find("CLEAN UP") != std::string::npos);
    CHECK(note.find("mi-UGens") == std::string::npos);   // not mi-UGens: the general wording
    std::string fix = mi_foreign_fix_text() ? mi_foreign_fix_text() : "";
    CHECK(fix.find(EXT() + "/synthpack\t") != std::string::npos);
    CHECK(fix.find(HOME + "/dust/code/s/lib/Other_scsynth.so\t") != std::string::npos);
    CHECK(fix.find("cjson") == std::string::npos);
    CHECK(fix.find("/fine") == std::string::npos);
    CHECK(fix.find("32-bit ARM") != std::string::npos);
    // the setting
    setenv("NORNS_PLUGIN_HEAL", "0", 1);
    CHECK(mi_foreign_note_text() == nullptr);
    CHECK(mi_foreign_fix_text() == nullptr);
    unsetenv("NORNS_PLUGIN_HEAL");
    // gone when moved
    REQUIRE(system(("rm -rf '" + EXT() + "/synthpack' '" + HOME + "/dust/code/s/lib/Other_scsynth.so'").c_str()) == 0);
    CHECK(mi_foreign_note_text() == nullptr);
}

TEST_CASE("runtime: the mi-UGens wording stays for mi-UGens only, and mi_ugens_heal=0 silences only those") {
    fresh();
    setenv("HOME", HOME.c_str(), 1);
    setenv("MI_FOREIGN_INTERVAL", "0", 1);
    setenv("PLUGIN_ARCH_UNAME", "x86_64", 1);
    unsetenv("NORNS_PLUGIN_HEAL");
    setenv("NORNS_MI_UGENS_HEAL", "0", 1);
    CHECK(mi_foreign_note_text() == nullptr);
    put(EXT() + "/late-mi/MiRings.so", arm());
    CHECK(mi_foreign_note_text() == nullptr);              // a mi-UGens download with mi_ugens_heal=0: said by nobody here
    put(EXT() + "/late-other/Late_scsynth.so", arm());
    const char *n = mi_foreign_note_text();
    REQUIRE(n != nullptr);                                  // another plug-in still is
    CHECK(std::string(n).find("A script installed a Raspberry Pi plug-in") == 0);
    CHECK(std::string(mi_foreign_fix_text()).find("late-mi") == std::string::npos);
    unsetenv("NORNS_MI_UGENS_HEAL");
    n = mi_foreign_note_text();
    REQUIRE(n != nullptr);                                  // both again
    REQUIRE(system(("rm -rf '" + EXT() + "/late-other'").c_str()) == 0);
    n = mi_foreign_note_text();
    REQUIRE(n != nullptr);
    CHECK(std::string(n).find("A script downloaded Raspberry Pi mi-UGens") == 0); // only the mi-UGens one is left: the specific wording
}
