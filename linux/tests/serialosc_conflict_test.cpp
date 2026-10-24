// tests for matron/src/platform/linux/serialosc_conflict.h: is another process (serialosc's serialosc-device) reading the
// serial port of the grid that norns has opened? the process list is data here: no root, no real serialosc.
// built and run by linux/tests/run_all.sh: g++ -I third-party/doctest linux/tests/serialosc_conflict_test.cpp

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "platform/linux/serialosc_conflict.h"

using namespace serialosc;

// what readlink -f does: the by-id symlinks of the laptop, and a ttyACM number that changes between plug-ins
static std::string resolve(const std::string &p) {
    static const std::map<std::string, std::string> links = {
        {"/dev/serial/by-id/usb-monome_grid_m2623414-if00", "/dev/ttyACM0"},
        {"/dev/serial/by-id/usb-monome_arc_m0000042-if00", "/dev/ttyACM1"},
    };
    auto it = links.find(p);
    return it == links.end() ? p : it->second;
}

static Proc serialoscd() { return Proc{500, {"/usr/bin/serialoscd", "-c", "/var/lib/serialosc"}, {}}; }
static Proc detector() { return Proc{501, {"/usr/bin/serialosc-detector"}, {}}; }
// argv[0] is cut at 15 characters by the program itself, as pgrep -a shows it: "serialosc-devic"
static Proc device(const char *path, int pid = 600) {
    return Proc{pid, {"serialosc-devic", "-c", "/var/lib/serialosc", path}, {}};
}

TEST_CASE("conflict: serialosc-device holds the grid that norns opened") {
    std::vector<Proc> procs = {serialoscd(), detector(), device("/dev/ttyACM0")};
    auto c = find(procs, "/dev/ttyACM0", resolve, 1000);
    REQUIRE(c.found);
    CHECK(c.pid == 600);
    CHECK(c.name == "serialosc-devic");
}

TEST_CASE("no conflict: nobody else") {
    CHECK_FALSE(find({}, "/dev/ttyACM0", resolve, 1000).found);
    CHECK_FALSE(find({Proc{1, {"/sbin/init"}, {}}}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("serialoscd and serialosc-detector alone are not a conflict") {
    CHECK_FALSE(find({serialoscd(), detector()}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("serialosc-device for another device is not a conflict") {
    CHECK_FALSE(find({device("/dev/ttyACM1")}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("the ttyACM number changes between plug-ins: only the device that norns opened counts") {
    // the grid is ttyACM2 this time; serialosc has the arc at ttyACM0 and the grid at ttyACM2
    CHECK(find({device("/dev/ttyACM0", 601), device("/dev/ttyACM2", 602)}, "/dev/ttyACM2", resolve, 1000).pid == 602);
    // the old number is somebody else's now
    CHECK_FALSE(find({device("/dev/ttyACM2", 602)}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("a by-id symlink is resolved: norns opened the by-id name, serialosc the ttyACM name, and the other way round") {
    auto a = find({device("/dev/ttyACM0")}, "/dev/serial/by-id/usb-monome_grid_m2623414-if00", resolve, 1000);
    REQUIRE(a.found);
    CHECK(a.pid == 600);
    auto b = find({device("/dev/serial/by-id/usb-monome_grid_m2623414-if00")}, "/dev/ttyACM0", resolve, 1000);
    CHECK(b.found);
    // the arc's by-id name is another device
    CHECK_FALSE(find({device("/dev/serial/by-id/usb-monome_arc_m0000042-if00")}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("unreadable entries are tolerated: no command line, no fds") {
    std::vector<Proc> procs = {Proc{700, {}, {}},                      // cmdline unreadable (another user's process)
                               Proc{701, {"", "-c"}, {}},              // empty argv[0]
                               Proc{702, {"/usr/bin/foo"}, {"", "socket:[123]", "/dev/null"}},
                               device("/dev/ttyACM0", 703)};
    auto c = find(procs, "/dev/ttyACM0", resolve, 1000);
    REQUIRE(c.found);
    CHECK(c.pid == 703);
}

TEST_CASE("an open file counts when the command line does not say: a serialosc process holding the device") {
    Proc p{800, {"/usr/bin/serialosc-device"}, {"/dev/null", "/dev/ttyACM0"}};
    auto c = find({p}, "/dev/ttyACM0", resolve, 1000);
    REQUIRE(c.found);
    CHECK(c.pid == 800);
}

TEST_CASE("an open file of a process that is not serialosc is not reported as serialosc, and norns itself never counts") {
    CHECK_FALSE(find({Proc{801, {"/usr/bin/other"}, {"/dev/ttyACM0"}}}, "/dev/ttyACM0", resolve, 1000).found);
    CHECK_FALSE(find({Proc{1000, {"serialosc-devic", "/dev/ttyACM0"}, {"/dev/ttyACM0"}}}, "/dev/ttyACM0", resolve, 1000).found);
}

TEST_CASE("the process is recognised by its name, whichever way the path is written") {
    CHECK(isDeviceProcess(Proc{1, {"/usr/bin/serialosc-device", "x"}, {}}));
    CHECK(isDeviceProcess(Proc{1, {"serialosc-devic", "x"}, {}}));
    CHECK_FALSE(isDeviceProcess(Proc{1, {"/usr/bin/serialoscd", "x"}, {}}));
    CHECK_FALSE(isDeviceProcess(Proc{1, {"/usr/bin/serialosc-detector"}, {}}));
    CHECK_FALSE(isDeviceProcess(Proc{1, {}, {}}));
}

TEST_CASE("the log line: one line, plain words, the commands, the replug") {
    auto c = find({device("/dev/ttyACM0")}, "/dev/serial/by-id/usb-monome_grid_m2623414-if00", resolve, 1000);
    std::string m = message("/dev/serial/by-id/usb-monome_grid_m2623414-if00", c);
    CHECK(m.find('\n') == std::string::npos);
    CHECK(m.find("serialosc") != std::string::npos);
    CHECK(m.find("/dev/serial/by-id/usb-monome_grid_m2623414-if00") != std::string::npos);
    CHECK(m.find("pid 600") != std::string::npos);
    CHECK(m.find("sudo systemctl stop serialosc.service") != std::string::npos);
    CHECK(m.find("sudo systemctl start serialosc.service") != std::string::npos);
    CHECK(m.find("replug") != std::string::npos);
    CHECK(m.find("NORNS_SERIALOSC_CHECK=0") != std::string::npos); // how to turn the check off
}

TEST_CASE("the note on the device window is short") {
    CHECK(std::string(note()) == "GRID: serialosc has this grid, see log");
}

TEST_CASE("the switch: off by 0, false, off, no (any case), on otherwise") {
    CHECK(enabled(nullptr));
    CHECK(enabled(""));
    CHECK(enabled("1"));
    CHECK_FALSE(enabled("0"));
    CHECK_FALSE(enabled("off"));
    CHECK_FALSE(enabled("OFF"));
    CHECK_FALSE(enabled("false"));
    CHECK_FALSE(enabled("no"));
}
