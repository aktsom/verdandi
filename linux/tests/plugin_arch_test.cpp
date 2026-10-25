// tests for matron/src/platform/linux/plugin_arch.h: SuperCollider plug-ins (.so) built for another machine than this one.
// the files are data here: small fake ELF headers, no real plug-ins. built and run by linux/tests/run_all.sh:
//   g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/plugin_arch_test.cpp

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "platform/linux/plugin_arch.h"

using namespace plugin_arch;

// the first bytes of an ELF file: magic, class (1 = 32-bit, 2 = 64-bit), data (1 = little endian, 2 = big), version, then e_machine at offset 18
static std::vector<uint8_t> elf(int cls, int data, int machine) {
    std::vector<uint8_t> b(64, 0);
    b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F';
    b[4] = (uint8_t)cls;
    b[5] = (uint8_t)data;
    b[6] = 1;
    if (data == 2) { // big endian machine field
        b[18] = (uint8_t)(machine >> 8);
        b[19] = (uint8_t)(machine & 0xff);
    } else {
        b[18] = (uint8_t)(machine & 0xff);
        b[19] = (uint8_t)(machine >> 8);
    }
    return b;
}
static std::vector<uint8_t> x86_64() { return elf(2, 1, 0x3e); }
static std::vector<uint8_t> arm32() { return elf(1, 1, 0x28); }
static std::vector<uint8_t> aarch64() { return elf(2, 1, 0xb7); }
static std::vector<uint8_t> text(const char *s) { return std::vector<uint8_t>(s, s + strlen(s)); }

TEST_CASE("the header: class and machine") {
    ElfInfo a = parseElf(arm32());
    REQUIRE(a.elf);
    CHECK(a.bits == 32);
    CHECK(a.machine == 0x28);
    ElfInfo b = parseElf(x86_64());
    CHECK(b.bits == 64);
    CHECK(b.machine == 0x3e);
    ElfInfo c = parseElf(elf(2, 2, 0x15)); // big endian: the machine bytes are the other way round
    CHECK(c.machine == 0x15);
    CHECK_FALSE(c.littleEndian);
}

TEST_CASE("not ELF: a script, an empty file, a short file, a wrong class byte") {
    CHECK_FALSE(parseElf(text("#!/bin/sh\necho hi\n")).elf);
    CHECK_FALSE(parseElf(std::vector<uint8_t>()).elf);
    CHECK_FALSE(parseElf(std::vector<uint8_t>{0x7f, 'E', 'L', 'F', 2}).elf); // cut short
    CHECK_FALSE(parseElf(elf(7, 1, 0x3e)).elf);                               // class is neither 1 nor 2
}

TEST_CASE("what this machine takes, from uname -m") {
    CHECK(expectedFor("x86_64").machine == 0x3e);
    CHECK(expectedFor("x86_64").bits == 64);
    CHECK(expectedFor("aarch64").machine == 0xb7);
    CHECK(expectedFor("arm64").machine == 0xb7);
    CHECK(expectedFor("armv7l").machine == 0x28);
    CHECK(expectedFor("armv7l").bits == 32);
    CHECK(expectedFor("i686").machine == 0x03);
    CHECK(expectedFor("riscv64").machine == 0xf3);
    CHECK(expectedFor("something-new").machine == 0); // unknown: nothing is reported
}

TEST_CASE("x86_64 machine: x86_64 is fine, 32-bit ARM and aarch64 are not") {
    Expect e = expectedFor("x86_64");
    CHECK(check(Reading{true, x86_64()}, e) == Verdict::Ok);
    CHECK(check(Reading{true, arm32()}, e) == Verdict::Mismatch);
    CHECK(check(Reading{true, aarch64()}, e) == Verdict::Mismatch);
    CHECK(check(Reading{true, elf(1, 1, 0x03)}, e) == Verdict::Mismatch); // 32-bit x86 cannot load into a 64-bit process
}

TEST_CASE("a non-ELF file and an unreadable file are not mismatches") {
    Expect e = expectedFor("x86_64");
    CHECK(check(Reading{true, text("not a plugin")}, e) == Verdict::NotElf);
    CHECK(check(Reading{false, {}}, e) == Verdict::Unreadable);
}

TEST_CASE("an unknown machine reports nothing") {
    CHECK(check(Reading{true, arm32()}, expectedFor("something-new")) == Verdict::Ok);
}

TEST_CASE("a Raspberry Pi machine takes 32-bit ARM, not x86_64") {
    Expect e = expectedFor("armv7l");
    CHECK(check(Reading{true, arm32()}, e) == Verdict::Ok);
    CHECK(check(Reading{true, x86_64()}, e) == Verdict::Mismatch);
}

TEST_CASE("the description") {
    CHECK(describe(parseElf(arm32())) == "32-bit ARM");
    CHECK(describe(parseElf(aarch64())) == "64-bit ARM (aarch64)");
    CHECK(describe(parseElf(x86_64())) == "64-bit x86_64");
    CHECK(describe(parseElf(elf(1, 1, 0x03))) == "32-bit x86");
    CHECK(describe(parseElf(elf(2, 1, 0x1234))).find("machine 0x1234") != std::string::npos);
}

TEST_CASE("the scan: the files are read through a function; mismatches only, in order") {
    std::map<std::string, Reading> files = {{"/h/Extensions/ok_scsynth.so", {true, x86_64()}},
                                            {"/h/Extensions/pl/AnalogChew_scsynth.so", {true, arm32()}},
                                            {"/h/Extensions/pl/AnalogLoss_scsynth.so", {true, arm32()}},
                                            {"/h/Extensions/notelf.so", {true, text("x")}},
                                            {"/h/Extensions/locked.so", {false, {}}},
                                            {"/h/dust/code/s/aarch_scsynth.so", {true, aarch64()}}};
    std::vector<std::string> paths;
    for (auto &kv : files) {
        paths.push_back(kv.first);
    }
    auto reader = [&](const std::string &p) { return files[p]; };
    auto found = scan(paths, reader, "x86_64");
    REQUIRE(found.size() == 3);
    CHECK(found[0].path == "/h/Extensions/pl/AnalogChew_scsynth.so");
    CHECK(found[1].path == "/h/Extensions/pl/AnalogLoss_scsynth.so");
    CHECK(found[2].path == "/h/dust/code/s/aarch_scsynth.so");
    CHECK(scan(paths, reader, "something-new").empty());
}

TEST_CASE("which files count: .so and .scx in the extension folders, only *_scsynth.so and .scx in dust/code") {
    CHECK(isPluginFile("/h/Extensions/pl/AnalogChew_scsynth.so", false));
    CHECK(isPluginFile("/h/Extensions/pl/Thing.so", false));
    CHECK(isPluginFile("/h/Extensions/pl/Thing.scx", false));
    CHECK_FALSE(isPluginFile("/h/Extensions/pl/Thing.sc", false));
    CHECK_FALSE(isPluginFile("/h/Extensions/pl/libfoo.so.1", false));
    // dust/code holds Lua libraries too (cjson.so ...): SuperCollider does not read those
    CHECK(isPluginFile("/h/dust/code/s/ignore/PulsePTR_scsynth.so", true));
    CHECK(isPluginFile("/h/dust/code/s/Thing.scx", true));
    CHECK_FALSE(isPluginFile("/h/dust/code/s/lib/cjson.so", true));
}

TEST_CASE("the log line: one line, the path, what it is, why it fails, the command, never a delete") {
    Finding f{"/home/n/.local/share/SuperCollider/Extensions/supercollider-plugins/AnalogChew_scsynth.so", parseElf(arm32())};
    std::string m = message(f, "x86_64", "/home/n", "");
    CHECK(m.find('\n') == std::string::npos);
    CHECK(m.find(f.path) != std::string::npos);
    CHECK(m.find("32-bit ARM, this machine is x86_64") != std::string::npos);
    CHECK(m.find("SuperCollider") != std::string::npos);
    CHECK(m.find("stops at the first") != std::string::npos);
    CHECK(m.find("mkdir -p '/home/n/disabled-plugins' && mv '" + f.path + "' '/home/n/disabled-plugins/'") != std::string::npos);
    CHECK(m.find("rm ") == std::string::npos);
    CHECK(m.find("NORNS_PLUGIN_CHECK=0") != std::string::npos);
    // when the whole folder is bad, the command moves the folder
    std::string m2 = message(f, "x86_64", "/home/n", "/home/n/.local/share/SuperCollider/Extensions/supercollider-plugins");
    CHECK(m2.find("mv '/home/n/.local/share/SuperCollider/Extensions/supercollider-plugins' '/home/n/disabled-plugins/'") != std::string::npos);
}

TEST_CASE("the note on the device window is short") {
    CHECK(std::string(note()) == "PLUGINS: wrong-architecture plug-in, see log");
}

TEST_CASE("the switch") {
    CHECK(enabled(nullptr));
    CHECK(enabled("1"));
    CHECK_FALSE(enabled("0"));
    CHECK_FALSE(enabled("off"));
    CHECK_FALSE(enabled("No"));
}
