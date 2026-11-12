// which serial ports are grids (matron/src/platform/windows/grid/grid_core.h): the owner's two grids, the generic FTDI id of other devices, composite devices, the rules of audio.conf.
//   g++ -std=c++17 -I matron/src linux/tests/grid_core_test.cpp -o /tmp/grid_core_test && /tmp/grid_core_test
#include <stdio.h>
#include "platform/windows/grid/grid_core.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

int main() {
    using namespace vgrid;
    // the serial from the instance id
    CHECK(serial_of_instance("FTDIBUS\\VID_0403+PID_6001+M0000163A\\0000") == "M0000163", "the 2011 grid 256: %s", serial_of_instance("FTDIBUS\\VID_0403+PID_6001+M0000163A\\0000").c_str());
    CHECK(serial_of_instance("FTDIBUS\\VID_0403+PID_6001+m256-021A\\0000") == "m256-021", "a hyphen in the serial is kept (libmonome cut it at the hyphen)");
    CHECK(serial_of_instance("USB\\VID_CAFE&PID_1110\\m1234567") == "m1234567", "the 2023-24 grid with a serial of its own");
    CHECK(serial_of_instance("USB\\VID_CAFE&PID_1110&MI_00\\6&2a3b&0&0000") == "", "a composite function has none: the parent is asked");
    CHECK(serial_of_instance("USB\\VID_CAFE&PID_1110\\6&2a3b&0&2") == "", "an id Windows made up is no serial");
    CHECK(serial_of_instance("ACPI\\PNP0501\\1") == "", "something else");
    int v, p;
    CHECK(vid_pid_of("USB\\VID_CAFE&PID_1110&MI_00\\x", &v, &p) && v == 0xCAFE && p == 0x1110, "vid and pid");
    CHECK(vid_pid_of("FTDIBUS\\VID_0403+PID_6001+M0000163A\\0000", &v, &p) && v == 0x403 && p == 0x6001, "vid and pid of an FTDI id");
    // monome-like serials
    for (const char *s : {"m1000123", "M0000163", "m256-021", "m128-017", "m64-001", "mk0000012", "m40h0001", "a40h-0012"}) CHECK(monome_like_serial(s), "%s is a monome serial", s);
    for (const char *s : {"", "A12345", "FTAB1234", "m", "mx12", "M12x", "GPS-0001", "mk"}) CHECK(!monome_like_serial(s), "'%s' is not", s);
    // the decisions
    Rules none;
    Port g128; g128.name = "COM6"; g128.vid = 0xCAFE; g128.pid = 0x1110; g128.serial = "m1234567"; g128.friendly = "USB Serial Device";
    Port g256; g256.name = "COM4"; g256.vid = 0x0403; g256.pid = 0x6001; g256.serial = "M0000163"; g256.friendly = "USB Serial Port";
    Port gps; gps.name = "COM9"; gps.vid = 0x0403; gps.pid = 0x6001; gps.serial = "A9B8C7"; gps.friendly = "USB Serial Port";
    Port noser; noser.name = "COM10"; noser.vid = 0x0403; noser.pid = 0x6001;
    Port bt; bt.name = "COM3"; bt.friendly = "Standard Serial over Bluetooth link";
    CHECK(classify(g128, none).v == GRID, "the 128 is a grid");
    CHECK(classify(g256, none).v == GRID, "the 256 (generic FTDI id, monome serial) is a grid");
    Result r = classify(gps, none);
    CHECK(r.v == NOT_MONOME && r.why.find("not opened") != std::string::npos && r.why.find("A9B8C7") != std::string::npos, "another FTDI device is not a grid and is not opened: %s", r.why.c_str());
    CHECK(classify(noser, none).v == NOT_MONOME, "an FTDI port without a serial is not a grid");
    CHECK(classify(bt, none).v == NOT_MONOME, "a Bluetooth serial port is not a grid");
    // the numbers do not matter
    Port moved = g256; moved.name = "COM12";
    CHECK(classify(moved, none).v == GRID, "the same grid on another COM number is the same grid");
    // audio.conf
    Rules r2; r2.extra_serials = split_list("A9B8C7; other");
    CHECK(classify(gps, r2).v == GRID && classify(gps, r2).why.find("monome_serial") != std::string::npos, "a serial listed in monome_serial= makes it a grid");
    Rules r3; r3.ignore = split_list("COM6;M0000163");
    CHECK(classify(g128, r3).v == IGNORED && classify(g256, r3).v == IGNORED, "monome_ignore= by COM name and by serial");
    Port bare = g128; bare.serial = "";
    CHECK(libmonome_serial(bare) == "m0" && libmonome_serial(g128) == "m1234567" && libmonome_serial(gps) == "A9B8C7" && libmonome_serial(noser) == "", "the serial libmonome is told");
    CHECK(speaks_mext(g128) && speaks_mext(g256) && !speaks_mext(gps), "who is asked the system query");
    Port s256 = g256; s256.serial = "m256-021"; Port s40 = g256; s40.serial = "m40h0001";
    CHECK(!speaks_mext(s256) && !speaks_mext(s40), "series and 40h grids are not asked");
    CHECK(split_list(" a ;; b;").size() == 2, "the list is split");
    CHECK(size_name(16, 16) == "grid 256" && size_name(16, 8) == "grid 128" && size_name(8, 8) == "grid 64" && size_name(0, 0) == "arc", "names of sizes");
    printf(fails == 0 ? "grid_core: all checks pass\n" : "grid_core: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
