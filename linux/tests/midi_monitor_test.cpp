// the device monitor of the Windows MIDI layer (midi_monitor.cc) with a fake backend and a fake list: the first scan, replug, stale entries, devices in another order, 20 devices, midi_ignore, a device whose
// port was held by another program and is tried again, the notes for the DEVICES page, the virtual cables, the thread that scans when poked.
//   g++ -std=c++17 -I matron/src linux/tests/midi_monitor_test.cpp matron/src/platform/windows/midi/midi_monitor.cc -lpthread -o /tmp/midi_monitor_test
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <string>
#include <vector>
#include <algorithm>
#include "platform/windows/midi/midi_monitor.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static std::vector<std::string> INS, OUTS;
static int list(int input, char names[][64], int max) {
    auto &v = input ? INS : OUTS;
    int n = 0;
    for (auto &s : v) { if (n < max) snprintf(names[n++], 64, "%s", s.c_str()); }
    return n;
}
static vmidi_backend BE = {"fake", list, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
static std::vector<std::string> list_now, events;
static std::vector<std::string> names_now;
static void add(const char *k, const char *n) {
    if (std::find(list_now.begin(), list_now.end(), k) == list_now.end()) { list_now.push_back(k); }
    events.push_back(std::string("+") + n);
}
static void rem(const char *k) { list_now.erase(std::remove(list_now.begin(), list_now.end(), std::string(k)), list_now.end()); events.push_back(std::string("-") + k); }
static int listed_ports = 0;
static int ports_listed(const char *k) { return std::find(list_now.begin(), list_now.end(), k) != list_now.end() ? listed_ports : 0; }
static vmidi_sink SINK = {add, rem, ports_listed};

int main() {
    vmidi_monitor_init(&BE, &SINK, "Push 2");
    INS = {"Fireface UC MIDI", "MIDIIN2 (Arturia BeatStep Pro)", "Arturia BeatStep Pro", "loopMIDI Port", "Ableton Push 2", "MIDIIN2 (Ableton Push 2)"};
    OUTS = {"Fireface UC MIDI", "Arturia BeatStep Pro", "MIDIOUT2 (Arturia BeatStep Pro)", "loopMIDI Port", "Ableton Push 2"};
    int n = vmidi_monitor_scan();
    CHECK(n == 3 && list_now.size() == 3, "first scan: three devices, the ignored one skipped (%d)", n);
    CHECK(std::find(list_now.begin(), list_now.end(), "winmm:ableton push 2") == list_now.end(), "Push 2 is not opened (midi_ignore)");
    vmidi_found f;
    CHECK(vmidi_monitor_find("winmm:arturia beatstep pro", &f) && f.nports == 2 && f.in_idx[0] == 2 && f.in_idx[1] == 1 && f.out_idx[0] == 1 && f.out_idx[1] == 2, "find gives the ports with the system's indices");
    // the same devices, listed in another order by the system: no change
    std::reverse(INS.begin(), INS.end());
    CHECK(vmidi_monitor_scan() == 0, "another order: nothing changes");
    // unplug the Fireface, plug a second loopMIDI port
    INS.erase(std::find(INS.begin(), INS.end(), "Fireface UC MIDI"));
    OUTS.erase(std::find(OUTS.begin(), OUTS.end(), "Fireface UC MIDI"));
    INS.push_back("loopMIDI Port 1"); OUTS.push_back("loopMIDI Port 1");
    events.clear();
    n = vmidi_monitor_scan();
    CHECK(n == 2 && events.size() == 2 && events[0][0] == '-' && events[1] == "+loopMIDI Port 1", "unplugged goes, new cable comes: %zu", events.size());
    CHECK(!vmidi_monitor_present("winmm:fireface uc midi"), "a stale entry is not found any more");
    char virt[200]; int cables, devs;
    vmidi_monitor_counts(&devs, &cables);
    vmidi_monitor_virtual_names(virt, sizeof virt);
    CHECK(cables == 2 && devs == 3 && strstr(virt, "loopMIDI Port 1"), "two virtual cables are counted and named: %d '%s'", cables, virt);
    // replug of the Fireface: the same key
    INS.push_back("Fireface UC MIDI"); OUTS.push_back("Fireface UC MIDI");
    events.clear();
    vmidi_monitor_scan();
    CHECK(events.size() == 1 && events[0] == "+Fireface UC MIDI" && vmidi_monitor_present("winmm:fireface uc midi"), "replug: the same device again");
    // notes for the DEVICES page
    vmidi_note_set("winmm:fireface uc midi", "Fireface UC MIDI", "held by another program (its input)");
    char buf[300];
    CHECK(vmidi_notes_text(buf, sizeof buf) == 1 && strstr(buf, "Fireface UC MIDI: held by another program"), "a note: '%s'", buf);
    vmidi_note_clear("winmm:fireface uc midi");
    CHECK(vmidi_notes_text(buf, sizeof buf) == 0 && buf[0] == 0, "and it goes");
    // a device that is not fully in the list is tried again
    listed_ports = 1; // the sink reports 1 of 2 ports for the BeatStep
    events.clear();
    sleep(4);
    vmidi_monitor_scan();
    int retried = 0;
    for (auto &e : events) retried += e == "+Arturia BeatStep Pro";
    CHECK(retried == 1, "a device with a port missing is tried again after a few seconds (%d)", retried);
    // 20 devices
    INS.clear(); OUTS.clear();
    for (int i = 0; i < 20; i++) { INS.push_back("Ctl " + std::to_string(i)); OUTS.push_back("Ctl " + std::to_string(i)); }
    vmidi_monitor_scan();
    CHECK(list_now.size() == 20, "20 devices at once (%zu)", list_now.size());
    // extra input
    vmidi_monitor_set_extra("osc:127.0.0.1:9201", "osc");
    events.clear();
    vmidi_monitor_scan();
    CHECK(events.size() == 1 && events[0] == "+osc" && vmidi_monitor_find("osc:127.0.0.1:9201", &f) && f.extra, "an input that is not a driver's is listed like the others");
    // the thread: poke makes it scan at once
    INS = {"Late Device"}; OUTS = {"Late Device"};
    events.clear();
    vmidi_monitor_start();
    usleep(200000);
    INS.push_back("Poked"); OUTS.push_back("Poked");
    vmidi_monitor_poke();
    usleep(1200000);
    vmidi_monitor_stop();
    CHECK(std::find(events.begin(), events.end(), "+Poked") != events.end(), "the thread scans when it is poked, within a second");
    printf(fails == 0 ? "midi_monitor: all checks pass\n" : "midi_monitor: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
