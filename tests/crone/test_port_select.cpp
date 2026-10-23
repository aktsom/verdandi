// tests for crone/src/PortSelect.h: choosing the sound card's JACK ports on a desktop
// (PipeWire exposes MIDI bridges, monitors and per-app streams next to the card)

#include <doctest/doctest.h>

#include "PortSelect.h"

using namespace crone::PortSelect;

static Port audio(const char *name, bool physical = true) { return Port{name, true, physical}; }
static Port midi(const char *name, bool physical = true) { return Port{name, false, physical}; }

// the laptop of the Phase 3 data (Linux Mint, PipeWire 1.0.5): capture ports are what norns reads
static std::vector<Port> laptopCapture() {
    return {audio("Built-in Audio Analog Stereo:capture_FL"),
            audio("Built-in Audio Analog Stereo:capture_FR"),
            audio("Built-in Audio Analog Stereo:monitor_FL", false),
            audio("Built-in Audio Analog Stereo:monitor_FR", false),
            midi("Midi-Bridge:Midi Through:(capture_0)")};
}

TEST_CASE("clientOf splits at the first colon") {
    CHECK(clientOf("system:capture_1") == "system");
    CHECK(clientOf("Built-in Audio Analog Stereo:capture_FL") == "Built-in Audio Analog Stereo");
    CHECK(clientOf("Midi-Bridge:Midi Through:(capture_0)") == "Midi-Bridge");
    CHECK(clientOf("noclient") == "noclient");
}

TEST_CASE("default: first physical audio client, first two ports, in order") {
    Result r = select(laptopCapture(), "", "input");
    REQUIRE(r.ports.size() == 2);
    CHECK(r.ports[0] == "Built-in Audio Analog Stereo:capture_FL");
    CHECK(r.ports[1] == "Built-in Audio Analog Stereo:capture_FR");
    CHECK(r.client == "Built-in Audio Analog Stereo");
    CHECK(r.warning.empty());
}

TEST_CASE("physical MIDI ports and non-physical monitor ports are never picked") {
    std::vector<Port> only = {midi("Midi-Bridge:Midi Through:(capture_0)"),
                              audio("Card:monitor_FL", false)};
    Result r = select(only, "", "input");
    CHECK(r.ports.empty());
    CHECK_FALSE(r.warning.empty());
}

TEST_CASE("a mono device feeds both channels") {
    Result r = select({audio("Mic:capture_MONO")}, "", "input");
    REQUIRE(r.ports.size() == 2);
    CHECK(r.ports[0] == "Mic:capture_MONO");
    CHECK(r.ports[1] == "Mic:capture_MONO");
}

TEST_CASE("two cards are never mixed") {
    std::vector<Port> two = {audio("A Card:playback_FL"), audio("B Card:playback_FL"),
                             audio("A Card:playback_FR"), audio("B Card:playback_FR")};
    Result r = select(two, "", "output");
    REQUIRE(r.ports.size() == 2);
    CHECK(r.ports[0] == "A Card:playback_FL");
    CHECK(r.ports[1] == "A Card:playback_FR");
}

TEST_CASE("prefix chooses another card") {
    std::vector<Port> two = {audio("Built-in Audio Analog Stereo:playback_FL"),
                             audio("Built-in Audio Analog Stereo:playback_FR"),
                             audio("AudioQuest DragonFly Black v1.5 Analog Stereo:playback_FL"),
                             audio("AudioQuest DragonFly Black v1.5 Analog Stereo:playback_FR")};
    Result r = select(two, "AudioQuest", "output");
    REQUIRE(r.ports.size() == 2);
    CHECK(r.client == "AudioQuest DragonFly Black v1.5 Analog Stereo");
    CHECK(r.ports[1] == "AudioQuest DragonFly Black v1.5 Analog Stereo:playback_FR");
    CHECK(r.warning.empty());
}

TEST_CASE("prefix that matches nothing: warns and falls back to the default card") {
    Result r = select(laptopCapture(), "No Such Card", "input");
    REQUIRE(r.ports.size() == 2);
    CHECK(r.client == "Built-in Audio Analog Stereo");
    CHECK(r.warning.find("No Such Card") != std::string::npos);
}

TEST_CASE("no physical ports at all: no ports, a warning that names the direction") {
    Result r = select({}, "", "output");
    CHECK(r.ports.empty());
    CHECK(r.warning.find("output") != std::string::npos);
}

TEST_CASE("prefix match is on the client name and tolerates a numeric suffix") {
    // client name with the suffix stripped, for the APP list of step 5 and for prefixes
    CHECK(baseName("Vivaldi-73") == "Vivaldi");
    CHECK(baseName("Vivaldi") == "Vivaldi");
    CHECK(baseName("Built-in Audio Analog Stereo") == "Built-in Audio Analog Stereo");
    CHECK(baseName("x-1-2") == "x-1");
    CHECK(baseName("-5") == "-5");
}
