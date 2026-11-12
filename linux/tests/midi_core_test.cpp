// the names, the grouping, the list diff and the ignore rules of the Windows MIDI layer (matron/src/platform/windows/midi/midi_core.h): pure, no system calls.
#include <algorithm>
//   g++ -std=c++17 -I matron/src linux/tests/midi_core_test.cpp -o /tmp/midi_core_test && /tmp/midi_core_test
#include "platform/windows/midi/midi_core.h"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

int main() {
    using namespace vmidi;
    Parsed p = parse_name("MIDIIN2 (Arturia BeatStep Pro)");
    CHECK(p.base == "Arturia BeatStep Pro" && p.port == 2 && p.instance == 1, "MIDIIN2 wrapper: '%s' %d", p.base.c_str(), p.port);
    p = parse_name("MIDIOUT3 (Ableton Push 2)");
    CHECK(p.base == "Ableton Push 2" && p.port == 3, "MIDIOUT3 wrapper");
    p = parse_name("2- USB MIDI Interface");
    CHECK(p.base == "USB MIDI Interface" && p.instance == 2 && p.port == 1, "'2- ' prefix is the instance: '%s' %d", p.base.c_str(), p.instance);
    p = parse_name("MIDIIN2 (2- USB MIDI Interface)");
    CHECK(p.base == "USB MIDI Interface" && p.instance == 2 && p.port == 2, "both");
    p = parse_name("  loopMIDI Port  ");
    CHECK(p.base == "loopMIDI Port" && p.port == 1 && p.instance == 1, "a plain name is the name");
    p = parse_name("mio");
    CHECK(p.base == "mio", "mio");
    p = parse_name("MIDIIN (x)");
    CHECK(p.base == "MIDIIN (x)", "no number: not a wrapper");

    // one device, two ports, input and output, in whatever order WinMM lists them
    std::vector<std::string> ins = {"Arturia BeatStep Pro", "MIDIIN2 (Arturia BeatStep Pro)", "loopMIDI Port", "mio"};
    std::vector<std::string> outs = {"loopMIDI Port", "MIDIOUT2 (Arturia BeatStep Pro)", "Arturia BeatStep Pro", "mio"};
    auto g = group(ins, outs);
    CHECK(g.size() == 3, "three devices (%zu)", g.size());
    const Device *bsp = nullptr;
    for (auto &d : g) if (d.name == "Arturia BeatStep Pro") bsp = &d;
    CHECK(bsp && bsp->nports == 2 && bsp->in_idx[0] == 0 && bsp->in_idx[1] == 1 && bsp->out_idx[0] == 2 && bsp->out_idx[1] == 1, "the ports of one device are put together");
    CHECK(bsp && bsp->key == "winmm:arturia beatstep pro", "the key has no index of the system: %s", bsp ? bsp->key.c_str() : "?");

    // the same names in another order (another USB socket, a reboot): the same keys
    std::vector<std::string> ins2 = {"mio", "loopMIDI Port", "MIDIIN2 (Arturia BeatStep Pro)", "Arturia BeatStep Pro"};
    auto g2 = group(ins2, outs);
    std::vector<std::string> k1, k2;
    for (auto &d : g) k1.push_back(d.key);
    for (auto &d : g2) k2.push_back(d.key);
    std::sort(k1.begin(), k1.end());
    std::sort(k2.begin(), k2.end());
    CHECK(k1 == k2, "the keys do not depend on the order of the system");

    // two identical interfaces: the second is "name 2", with or without the driver's own numbering
    auto two = group({"USB MIDI Interface", "USB MIDI Interface"}, {"USB MIDI Interface", "USB MIDI Interface"});
    CHECK(two.size() == 2 && two[0].name == "USB MIDI Interface" && two[1].name == "USB MIDI Interface 2" && two[1].key == "winmm:usb midi interface#2", "identical devices by order: %s | %s", two[0].name.c_str(), two[1].name.c_str());
    CHECK(two[1].in_idx[0] == 1 && two[1].out_idx[0] == 1, "and each keeps its own ports");
    auto numbered = group({"USB MIDI Interface", "2- USB MIDI Interface"}, {});
    CHECK(numbered.size() == 2 && numbered[1].name == "USB MIDI Interface 2" && numbered[1].key == two[1].key, "the driver's own '2- ' gives the same key");

    // at least 16 devices at once
    std::vector<std::string> many;
    for (int i = 0; i < 20; i++) many.push_back("Controller " + std::to_string(i));
    CHECK(group(many, many).size() == 20, "20 devices");

    // replug: the list diff
    std::vector<std::string> listed;
    auto d1 = diff(listed, g);
    CHECK(d1.add.size() == 3 && d1.remove.empty(), "first scan: all added");
    for (auto &d : d1.add) listed.push_back(d.key);
    auto d2 = diff(listed, g2);
    CHECK(d2.add.empty() && d2.remove.empty(), "same devices in another order: nothing changes");
    auto gone = group({"mio"}, {"mio"});
    auto d3 = diff(listed, gone);
    CHECK(d3.add.empty() && d3.remove.size() == 2, "two devices unplugged: both removed (%zu)", d3.remove.size());
    for (auto &k : d3.remove) listed.erase(std::find(listed.begin(), listed.end(), k));
    auto d4 = diff(listed, g);
    CHECK(d4.add.size() == 2 && d4.remove.empty(), "and they come back: both added again");

    // midi_ignore
    Device dev; dev.name = "Ableton Push 2";
    CHECK(ignored("Push 2", dev, {"Ableton Push 2"}), "midi_ignore: a name part, without case or blanks");
    CHECK(ignored("push2;mio", dev, {"MIDIIN2 (Ableton Push 2)"}), "midi_ignore: normalised");
    CHECK(!ignored("", dev, {"Ableton Push 2"}), "empty: nothing is ignored");
    CHECK(!ignored(nullptr, dev, {"Ableton Push 2"}), "no setting: nothing is ignored");
    CHECK(looks_virtual("loopMIDI Port 1") && looks_virtual("MIDI Services Loopback A") && !looks_virtual("Arturia BeatStep Pro"), "virtual cables are recognised by name only to say so");

    printf(fails == 0 ? "midi_core: all checks pass\n" : "midi_core: %d failures\n", fails);
    return fails == 0 ? 0 : 1;
}
