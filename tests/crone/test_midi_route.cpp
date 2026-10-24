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

// ---- norns' own ALSA MIDI clients and loopbacks must never be linked into Verdandi:midi_in (that would be a loop)

TEST_CASE("wildcard: '*' stands for any text (the client number changes between runs); the end is open") {
    CHECK(matchesPattern("Midi-Bridge:Client-20 Virtual RawMIDI:(capture_0)", "Midi-Bridge:Client-* Virtual RawMIDI"));
    CHECK(matchesPattern("Midi-Bridge:Client-1234 Virtual RawMIDI:(capture_0)", "Midi-Bridge:Client-* Virtual RawMIDI"));
    CHECK_FALSE(matchesPattern("Midi-Bridge:Client-20 Other:(capture_0)", "Midi-Bridge:Client-* Virtual RawMIDI"));
    CHECK_FALSE(matchesPattern("Other:Client-20 Virtual RawMIDI", "Midi-Bridge:Client-* Virtual RawMIDI"));
    CHECK(matchesPattern("Fake DAW:out", "Fake DAW")); // without '*': a prefix, as before
    CHECK(matchesPattern("Fake DAW:out", "*DAW:out"));
    CHECK_FALSE(matchesPattern("Fake DAW:out", "DAW"));
}

TEST_CASE("norns' own ALSA clients are never wanted, whatever the prefix") {
    // norns' own: the virtual RawMIDI device (a client named Client-128 this run) and the keys window ("Verdandi")
    std::vector<std::string> own = {"Client-128", "Verdandi"};
    std::vector<MidiPort> ports = {out("Midi-Bridge:Client-128 Virtual RawMIDI:(capture_0)"),
                                   out("Midi-Bridge:Client-129 Virtual RawMIDI:(capture_0)"),
                                   out("Midi-Bridge:Verdandi:(capture_0) norns keys")};
    auto w = wanted(ports, parsePrefixes("Midi-Bridge:"), own);
    REQUIRE(w.size() == 1);
    CHECK(w[0] == "Midi-Bridge:Client-129 Virtual RawMIDI:(capture_0)"); // Reaper's, another number
}

TEST_CASE("own client names match whole words: Client-128 is not Client-1280, Verdandi is not Verdandi2") {
    std::vector<std::string> own = {"Client-128"};
    std::vector<MidiPort> ports = {out("Midi-Bridge:Client-1280 Virtual RawMIDI:(capture_0)")};
    CHECK(wanted(ports, parsePrefixes("Midi-Bridge"), own).size() == 1);
    CHECK(wanted({out("Midi-Bridge:Verdandi2:(capture_0)")}, parsePrefixes("Midi-Bridge"), {"Verdandi"}).size() == 1);
}

TEST_CASE("the ALSA loopback \"Midi Through\" is never wanted: what is written to it comes out again") {
    std::vector<MidiPort> ports = {out("Midi-Bridge:Midi Through:(capture_0)"), out("Midi-Bridge:Reaper:(capture_0)")};
    auto w = wanted(ports, parsePrefixes("Midi-Bridge:"));
    REQUIRE(w.size() == 1);
    CHECK(w[0] == "Midi-Bridge:Reaper:(capture_0)");
    // even if the prefix names it
    CHECK(wanted(ports, parsePrefixes("Midi-Bridge:Midi Through")).empty());
}
