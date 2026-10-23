// tests for crone/src/MidiRoute.h: which MIDI output ports are linked to Verdandi:midi_in by the auto-connect

#include <doctest/doctest.h>

#include "MidiRoute.h"

using namespace crone::MidiRoute;

static MidiPort out(const char *name) { return MidiPort{name, true, true}; }

TEST_CASE("prefixes: split at ';', trimmed, empty ones dropped") {
    auto p = parsePrefixes(" Midi-Bridge:Client-;Midi-Bridge:Reaper ; ;");
    REQUIRE(p.size() == 2);
    CHECK(p[0] == "Midi-Bridge:Client-");
    CHECK(p[1] == "Midi-Bridge:Reaper");
    CHECK(parsePrefixes("").empty());
    CHECK(parsePrefixes("  ").empty());
}

TEST_CASE("off by default: no prefix, nothing is wanted") {
    std::vector<MidiPort> ports = {out("Midi-Bridge:Client-20:(capture_0)")};
    CHECK(wanted(ports, {}).empty());
}

TEST_CASE("a MIDI output port whose whole name starts with a prefix is wanted") {
    std::vector<MidiPort> ports = {out("Midi-Bridge:Client-20 Virtual RawMIDI:(capture_0)"),
                                   out("Midi-Bridge:Midi Through:(capture_0)"), out("Fake DAW:out")};
    auto w = wanted(ports, parsePrefixes("Midi-Bridge:Client-"));
    REQUIRE(w.size() == 1);
    CHECK(w[0] == "Midi-Bridge:Client-20 Virtual RawMIDI:(capture_0)");
    CHECK(wanted(ports, parsePrefixes("Midi-Bridge:Client-;Fake DAW")).size() == 2);
}

TEST_CASE("only MIDI outputs: audio ports and MIDI inputs never match") {
    std::vector<MidiPort> ports = {MidiPort{"Fake DAW:audio_out", false, true}, MidiPort{"Fake DAW:in", true, false},
                                   out("Fake DAW:out")};
    auto w = wanted(ports, parsePrefixes("Fake DAW"));
    REQUIRE(w.size() == 1);
    CHECK(w[0] == "Fake DAW:out");
}

TEST_CASE("norns' own MIDI ports never match, whatever the prefix") {
    std::vector<MidiPort> ports = {out("Verdandi:midi_in"), out("Verdandi ctl:x"), out("crone:y")};
    CHECK(wanted(ports, parsePrefixes("Verdandi;crone;")).empty());
    CHECK(wanted(ports, parsePrefixes("V")).empty());
}

TEST_CASE("missing links: wanted ports that are not linked yet") {
    std::vector<std::string> want = {"A:o", "B:o"};
    auto m = missingFrom(want, {"A:o"});
    REQUIRE(m.size() == 1);
    CHECK(m[0] == "B:o");
    CHECK(missingFrom(want, {"A:o", "B:o", "C:o"}).empty());
}

TEST_CASE("a log line at most once a minute per port") {
    Throttle t;
    CHECK(t.allow("A:o", 100.0));
    CHECK_FALSE(t.allow("A:o", 130.0));
    CHECK(t.allow("B:o", 130.0));
    CHECK(t.allow("A:o", 161.0));
}
