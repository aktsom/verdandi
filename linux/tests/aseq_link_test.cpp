// the optional auto-connect of "Verdandi out" (the ALSA sequencer port of the virtual MIDI device) to ALSA destination ports whose name starts with a prefix (alsa_midi_out_to in audio.conf, NORNS_ALSA_MIDI_OUT_TO), for DAWs
// that read raw MIDI only: snd-virmidi's port is the bridge to Reaper's hw:VirMIDI input (matron/src/platform/linux/aseq_link.h, with a fake sequencer: there is no kernel one in the CI containers).
//   g++ -std=c++14 -I third-party/doctest -I crone/src -I matron/src/platform/linux linux/tests/aseq_link_test.cpp
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest/doctest.h"

#include <errno.h>

#include <set>
#include <string>
#include <utility>
#include <vector>

#include "aseq_link.h"

struct FakeSeq : aseq::LinkSeq {
    std::vector<aseq::PortInfo> ports;
    std::set<std::pair<int, int>> subs; // what Verdandi out is subscribed to
    std::set<std::pair<int, int>> own_threads;
    int connect_result = 0;             // what the next connects answer
    int listed = 0, connects = 0;
    bool list_ok = true;
    bool list(std::vector<aseq::PortInfo> &out) override { listed++; out = ports; return list_ok; }
    bool connected(int c, int p) override { return subs.count({c, p}) > 0; }
    int connect(int c, int p) override {
        connects++;
        if (connect_result != 0) return connect_result;
        subs.insert({c, p});
        return 0;
    }
    void cut(int c, int p) { subs.erase({c, p}); }
    void remove_client(int c) { std::vector<aseq::PortInfo> k; for (auto &x : ports) if (x.client != c) k.push_back(x); ports = k; for (auto it = subs.begin(); it != subs.end();) it = (it->first == c) ? subs.erase(it) : std::next(it); }
};

static aseq::PortInfo P(int c, const char *cn, int p, const char *pn, bool w = true) { return aseq::PortInfo{c, p, cn, pn, w}; }

struct Logs {
    std::vector<std::string> lines;
    static void log(const char *l, void *ctx) { ((Logs *)ctx)->lines.push_back(l); }
};

static std::vector<aseq::PortInfo> world() {
    return {P(0, "System", 0, "Timer"), P(0, "System", 1, "Announce"), P(14, "Midi Through", 0, "Midi Through Port-0"), P(24, "Arturia BeatStep Pro", 0, "Arturia BeatStep Pro MIDI 1"),
            P(24, "Arturia BeatStep Pro", 1, "Arturia BeatStep Pro MIDI 2"), P(28, "VirMIDI 3-0", 0, "VirMIDI 3-0"), P(128, "Verdandi", 0, "Verdandi out", false), P(129, "norns keys", 0, "norns keys", false)};
}

TEST_CASE("off by default: no prefix, nothing is connected, the sequencer is not even asked") {
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "", 128, Logs::log, &lg);
    CHECK(l.check() == 0);
    CHECK(s.connects == 0);
    CHECK(s.listed == 0);
    CHECK(l.enabled() == false);
}

TEST_CASE("a prefix of the client name connects the matching writable port, and nothing else") {
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    CHECK(l.check() == 1);
    CHECK(s.subs == std::set<std::pair<int, int>>({{28, 0}}));
    CHECK(l.names() == "VirMIDI 3-0");
    REQUIRE(lg.lines.size() == 1);
    CHECK(lg.lines[0].find("connected") != std::string::npos);
    CHECK(lg.lines[0].find("VirMIDI 3-0") != std::string::npos);
}

TEST_CASE("the prefix may be the client and port together, the port name alone, case does not matter, several prefixes with ';'") {
    for (const char *pre : {"VirMIDI 3-0", "virmidi", "VirMIDI 3-0:VirMIDI", "VIRMIDI 3-*"}) {
        FakeSeq s; s.ports = world(); Logs lg;
        aseq::Linker l(s, pre, 128, Logs::log, &lg);
        CHECK_MESSAGE(l.check() == 1, pre);
    }
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "VirMIDI ; Arturia BeatStep Pro MIDI 2", 128, Logs::log, &lg);
    CHECK(l.check() == 2);
    CHECK(s.subs == std::set<std::pair<int, int>>({{28, 0}, {24, 1}}));
}

TEST_CASE("never itself, never the keys window, never System or Midi Through unless the prefix names them") {
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "Verd", 128, Logs::log, &lg); // would match the client Verdandi
    CHECK(l.check() == 0);
    aseq::Linker k(s, "norns", 128, Logs::log, &lg);
    CHECK(k.check() == 0);
    aseq::Linker t(s, "Midi", 128, Logs::log, &lg);  // a prefix that only starts like Midi Through
    CHECK(t.check() == 1);                           // named by the prefix: connected
    CHECK(s.subs == std::set<std::pair<int, int>>({{14, 0}}));
    FakeSeq s2; s2.ports = world();
    aseq::Linker v(s2, "VirMIDI", 128, Logs::log, &lg);
    v.check();
    CHECK(s2.subs.count({14, 0}) == 0); CHECK(s2.subs.count({0, 0}) == 0); CHECK(s2.subs.count({24, 0}) == 0); CHECK(s2.subs.count({24, 1}) == 0);
}

TEST_CASE("a client of norns' own (a thread of this process made it) is never connected, whatever its name") {
    FakeSeq s; s.ports = world();
    s.ports.push_back(P(130, "VirMIDI own", 0, "VirMIDI own"));
    s.ports.back().pid = 4242;
    Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    l.set_own_pid_test([](int pid) { return pid == 4242; });
    CHECK(l.check() == 1);
    CHECK(s.subs.count({130, 0}) == 0);
}

TEST_CASE("a port that cannot be written to (an output only port) is not connected") {
    FakeSeq s; s.ports = {P(40, "VirMIDI 4-0", 0, "VirMIDI 4-0", false)}; Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    CHECK(l.check() == 0);
    CHECK(s.connects == 0);
}

TEST_CASE("a port that appears later is connected at the next check; one that is cut is connected again (said as reconnected); a client that goes is dropped from the status") {
    FakeSeq s; s.ports = {P(0, "System", 0, "Timer")}; Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    CHECK(l.check() == 0);
    CHECK(l.names() == "");
    s.ports = world();
    CHECK(l.check() == 1);
    s.cut(28, 0);
    CHECK(l.check() == 1);
    CHECK(s.subs.count({28, 0}) == 1);
    REQUIRE(lg.lines.size() == 2);
    CHECK(lg.lines[1].find("reconnected") != std::string::npos);
    s.remove_client(28);
    CHECK(l.check() == 0);
    CHECK(l.names() == "");
    s.ports = world();
    CHECK(l.check() == 1); // it comes back (the module was loaded again)
}

TEST_CASE("already connected is not connected twice and says nothing; the number of checks does not grow the log") {
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    for (int i = 0; i < 20; i++) l.check();
    CHECK(s.connects == 1);
    CHECK(lg.lines.size() == 1);
}

TEST_CASE("-EBUSY (the subscription is there already) counts as connected; another error is said once per port until it works") {
    FakeSeq s; s.ports = world(); Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    s.connect_result = -EBUSY;
    CHECK(l.check() == 1);
    FakeSeq t; t.ports = world(); Logs lg2;
    aseq::Linker m(t, "VirMIDI", 128, Logs::log, &lg2);
    t.connect_result = -EPERM;
    CHECK(m.check() == 0);
    CHECK(m.check() == 0);
    CHECK(m.check() == 0);
    REQUIRE(lg2.lines.size() == 1);
    CHECK(lg2.lines[0].find("could not") != std::string::npos);
    t.connect_result = 0;
    CHECK(m.check() == 1);
}

TEST_CASE("the sequencer cannot be asked: nothing happens, nothing crashes") {
    FakeSeq s; s.ports = world(); s.list_ok = false; Logs lg;
    aseq::Linker l(s, "VirMIDI", 128, Logs::log, &lg);
    CHECK(l.check() == 0);
    s.list_ok = true;
    CHECK(l.check() == 1);
}

TEST_CASE("the Reaper entry: the name to enable follows the client that was connected") {
    CHECK(aseq::reaper_entry("VirMIDI 3-0") == "VirMIDI 3-0");
    CHECK(aseq::reaper_entry("VirMIDI 7-2") == "VirMIDI 7-2");
    CHECK(aseq::reaper_entry("Some Synth") == "Some Synth");
    CHECK(aseq::reaper_hw("VirMIDI 3-0") == "hw:VirMIDI,0");
    CHECK(aseq::reaper_hw("VirMIDI 7-2") == "hw:VirMIDI,2");
    CHECK(aseq::reaper_hw("Some Synth") == "");
}
