// tests for matron/src/platform/linux/midi_ignore.h: which sound cards the device monitor must not open as MIDI controllers (the kernel's virtual MIDI card snd-virmidi,
// "Virtual Raw MIDI": it is the bridge a DAW reads, and a raw port has one reader). pure string rules. built and run by linux/tests/run_all.sh:
//   g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/midi_ignore_test.cpp

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "platform/linux/midi_ignore.h"

using namespace midi_ignore;

TEST_CASE("the list: names separated by ; , blanks trimmed, empty entries dropped") {
    CHECK(parseList("VirMIDI;Virtual Raw MIDI") == std::vector<std::string>({"VirMIDI", "Virtual Raw MIDI"}));
    CHECK(parseList("  a ; b;;c  ;") == std::vector<std::string>({"a", "b", "c"}));
    CHECK(parseList("").empty());
    CHECK(parseList(nullptr).empty());
    CHECK(parseList(" ; ").empty());
}

TEST_CASE("the default is VirMIDI and Virtual Raw MIDI; a setting replaces it; the alsa_midi_out_to target is always added") {
    CHECK(entries(nullptr, nullptr) == std::vector<std::string>({"VirMIDI", "Virtual Raw MIDI"}));
    CHECK(entries("Foo;Bar", nullptr) == std::vector<std::string>({"Foo", "Bar"}));
    CHECK(entries("", nullptr).empty());                       // set but empty: nothing is ignored by name
    CHECK(entries(nullptr, "VirMIDI") == std::vector<std::string>({"VirMIDI", "Virtual Raw MIDI"})); // already there: not twice
    CHECK(entries(nullptr, "Reaper In") == std::vector<std::string>({"VirMIDI", "Virtual Raw MIDI", "Reaper In"}));
    CHECK(entries("Foo", " Bar ") == std::vector<std::string>({"Foo", "Bar"}));
    CHECK(entries("", "") .empty());
}

TEST_CASE("matching ignores case, blanks, underscores and hyphens, and looks inside the text") {
    auto d = entries(nullptr, nullptr);
    CHECK(matches(d, {"VirMIDI"}));                              // the card id
    CHECK(matches(d, {"snd_virmidi"}));                          // the driver
    CHECK(matches(d, {"snd-virmidi"}));
    CHECK(matches(d, {"Virtual Raw MIDI (16 ports)"}));          // the raw MIDI name in /proc/asound/card2/midi0
    CHECK(matches(d, {"Virtual RawMIDI"}));                      // the sequencer client name
    CHECK(matches(d, {"unknown", " 2 [VirMIDI        ]: VirMIDI - VirMIDI\\n Virtual MIDI Card 1"}));
    CHECK(matches(d, {"VIRMIDI 2-0"}));
}

TEST_CASE("real controllers and interfaces are never matched by the default list") {
    auto d = entries(nullptr, nullptr);
    CHECK_FALSE(matches(d, {"Arturia BeatStep Pro"}));
    CHECK_FALSE(matches(d, {"USB MIDI Interface", "snd-usb-audio"}));
    CHECK_FALSE(matches(d, {"monome grid", "usb"}));
    CHECK_FALSE(matches(d, {"Scarlett 2i2 USB", "Focusrite"}));
    CHECK_FALSE(matches(d, {"Virtual Piano Keyboard"}));       // not the card
    CHECK_FALSE(matches(d, {}));
    CHECK_FALSE(matches({}, {"VirMIDI"}));                     // an empty list ignores nothing
}

TEST_CASE("an entry that is only blanks or punctuation never matches everything") {
    CHECK_FALSE(matches({"  ", "-_ "}, {"VirMIDI", "Arturia"}));
}

TEST_CASE("the alsa_midi_out_to target hides the card it names") {
    auto d = entries(nullptr, "Arturia");
    CHECK(matches(d, {"Arturia BeatStep Pro"}));
}
