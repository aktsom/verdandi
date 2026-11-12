// the grid monitor (grid_monitor.cc) with a fake list of serial ports and a fake device list: the owner's two grids at once, a replug on another COM port, a port held by another program, a grid that does not answer,
// a generic FTDI port that is NOT a monome (never probed, never opened), unplugging, the status text for the DEVICES page.
//   g++ -std=c++17 -I matron/src linux/tests/grid_monitor_test.cpp matron/src/platform/windows/grid/grid_monitor.cc -lpthread -o /tmp/grid_monitor_test
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <algorithm>
#include <string>
#include <vector>
#include "platform/windows/grid/grid_monitor.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static std::vector<vgrid_port_info> PORTS;
static std::vector<std::string> LIST, EVENTS, PROBED;
static std::string HELD_PORT, SILENT_PORT; // a port another program has; a port whose grid does not answer
static int list(vgrid_port_info *o, int max) { int n = 0; for (auto &p : PORTS) if (n < max) o[n++] = p; return n; }
static int probe(const char *port, char *why, size_t n) {
    PROBED.push_back(port);
    if (HELD_PORT == port) { snprintf(why, n, "Access is denied."); return 1; }
    return 0;
}
static void add(const char *path, const char *) {
    EVENTS.push_back(std::string("+") + path);
    if (SILENT_PORT == path) return; // libmonome got no answer: the device list does not take it
    if (std::find(LIST.begin(), LIST.end(), path) == LIST.end()) LIST.push_back(path);
}
static void rem(const char *path) { EVENTS.push_back(std::string("-") + path); LIST.erase(std::remove(LIST.begin(), LIST.end(), std::string(path)), LIST.end()); }
static int listed(const char *path) { return std::find(LIST.begin(), LIST.end(), path) != LIST.end(); }
static int info(const char *path, char *name, size_t nn, char *serial, size_t sn, int *c, int *r) {
    if (!listed(path)) return 0;
    for (auto &p : PORTS) if (!strcmp(p.name, path)) { snprintf(serial, sn, "%s", p.serial); snprintf(name, nn, "%s", p.vid == 0xCAFE ? "monome 128" : "monome 256"); *c = 16; *r = p.vid == 0xCAFE ? 8 : 16; return 1; }
    return 0;
}
static vgrid_port_info mk(const char *name, int vid, int pid, const char *serial, const char *friendly) {
    vgrid_port_info p; memset(&p, 0, sizeof p);
    snprintf(p.name, sizeof p.name, "%s", name); p.vid = vid; p.pid = pid; snprintf(p.serial, sizeof p.serial, "%s", serial); snprintf(p.friendly, sizeof p.friendly, "%s", friendly);
    return p;
}
static vgrid_backend BE = {list, probe};
static vgrid_sink SINK = {add, rem, listed, info};

int main() {
    vgrid_monitor_init(&BE, &SINK, "", "");
    PORTS = {mk("COM6", 0xCAFE, 0x1110, "m1234567", "USB Serial Device"), mk("COM4", 0x0403, 0x6001, "M0000163", "USB Serial Port"), mk("COM9", 0x0403, 0x6001, "GPS0001", "USB Serial Port"), mk("COM3", 0, 0, "", "Standard Serial over Bluetooth link")};
    int n = vgrid_monitor_scan();
    CHECK(n == 2 && LIST.size() == 2, "both grids are added at once, nothing else (%d)", n);
    CHECK(std::find(PROBED.begin(), PROBED.end(), "COM9") == PROBED.end() && std::find(PROBED.begin(), PROBED.end(), "COM3") == PROBED.end(), "the other FTDI device and the Bluetooth port are never probed, never opened");
    char buf[1000];
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(strstr(buf, "grid=COM6\tm1234567\tmonome 128\t16\t8") && strstr(buf, "grid=COM4\tM0000163\tmonome 256\t16\t16"), "the page gets both grids by name, size and serial:\n%s", buf);
    CHECK(strstr(buf, "other=COM9") && strstr(buf, "not a monome") && strstr(buf, "other=COM3"), "and the ports that were left alone, with the reason");
    // nothing changes while nothing changes
    EVENTS.clear();
    CHECK(vgrid_monitor_scan() == 0 && EVENTS.empty(), "a second scan changes nothing");
    // replug of the 256 into another USB socket: another COM number, the same serial
    for (auto &p : PORTS) if (!strcmp(p.name, "COM4")) strcpy(p.name, "COM12");
    EVENTS.clear();
    n = vgrid_monitor_scan();
    CHECK(EVENTS.size() == 2 && EVENTS[0] == "-COM4" && EVENTS[1] == "+COM12", "moved to another port: removed there, added here (%zu)", EVENTS.size());
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(strstr(buf, "grid=COM12\tM0000163\tmonome 256") && !strstr(buf, "grid=COM4"), "same serial, same name, new port");
    // unplugged
    PORTS.erase(std::remove_if(PORTS.begin(), PORTS.end(), [](const vgrid_port_info &p) { return !strcmp(p.name, "COM6"); }), PORTS.end());
    EVENTS.clear();
    vgrid_monitor_scan();
    CHECK(EVENTS.size() == 1 && EVENTS[0] == "-COM6" && LIST.size() == 1, "unplugged: removed");
    // plugged in again
    PORTS.insert(PORTS.begin(), mk("COM6", 0xCAFE, 0x1110, "m1234567", "USB Serial Device"));
    EVENTS.clear();
    vgrid_monitor_scan();
    CHECK(EVENTS.size() == 1 && EVENTS[0] == "+COM6", "and back");
    // a port another program has
    PORTS.push_back(mk("COM20", 0xCAFE, 0x1110, "m7654321", "USB Serial Device"));
    HELD_PORT = "COM20";
    EVENTS.clear();
    vgrid_monitor_scan();
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(!listed("COM20") && std::find(EVENTS.begin(), EVENTS.end(), "+COM20") == EVENTS.end(), "a held port is not handed to the device list");
    CHECK(strstr(buf, "note=COM20: another program has this port open") && strstr(buf, "serialosc"), "and the page says so in plain words: %s", buf);
    // the program lets go: tried again after a few seconds
    HELD_PORT = "";
    sleep(4);
    vgrid_monitor_scan();
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(listed("COM20") && !strstr(buf, "note=COM20"), "the port is free: the grid is added and the note goes");
    // a grid that does not answer
    PORTS.push_back(mk("COM21", 0xCAFE, 0x1110, "m1111111", "USB Serial Device"));
    SILENT_PORT = "COM21";
    vgrid_monitor_scan();
    sleep(4);
    vgrid_monitor_scan();
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(!listed("COM21") && strstr(buf, "note=COM21: a monome is on this port but did not answer") && strstr(buf, "plug it in again"), "no answer: said in plain words with what to do: %s", buf);
    // it answers after all
    SILENT_PORT = "";
    sleep(4);
    vgrid_monitor_scan();
    vgrid_monitor_status(buf, sizeof buf);
    CHECK(listed("COM21") && !strstr(buf, "note=COM21"), "it answers on the next try");
    // the thread
    vgrid_monitor_start();
    PORTS.push_back(mk("COM30", 0xCAFE, 0x1110, "m2222222", "USB Serial Device"));
    vgrid_monitor_poke();
    usleep(1500000);
    vgrid_monitor_stop();
    CHECK(listed("COM30"), "the thread scans when it is poked");
    printf(fails == 0 ? "grid_monitor: all checks pass\n" : "grid_monitor: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
