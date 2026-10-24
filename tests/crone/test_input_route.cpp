// tests for crone/src/InputRoute.h: what feeds crone's input on a desktop (MIC, SYS, APP, sink monitor)

#include <doctest/doctest.h>

#include "InputRoute.h"

using namespace crone::InputRoute;

static PortInfo out(const char *name, bool physical = false, bool audio = true) {
    return PortInfo{name, audio, physical, true};
}
static PortInfo in(const char *name, bool physical = false) { return PortInfo{name, true, physical, false}; }

// the laptop of the Phase 3 data plus norns itself, a browser with two streams and a media player
static std::vector<PortInfo> desktop() {
    return {out("Built-in Audio Analog Stereo:capture_FL", true),
            out("Built-in Audio Analog Stereo:capture_FR", true),
            in("Built-in Audio Analog Stereo:playback_FL", true),
            in("Built-in Audio Analog Stereo:playback_FR", true),
            out("Built-in Audio Analog Stereo:monitor_FL"),
            out("Built-in Audio Analog Stereo:monitor_FR"),
            out("Midi-Bridge:Midi Through:(capture_0)", true, false),
            out("Vivaldi:output_FL"),
            out("Vivaldi:output_FR"),
            out("Vivaldi-73:output_FL"),
            out("Vivaldi-73:output_FR"),
            out("mpv:output_1"),
            out("mpv:output_2"),
            out("crone:output_1"),
            out("crone:output_2"),
            out("softcut:output_1"),
            out("SuperCollider:out_1"),
            out("Verdandi:midi_in", false, false),
            // Reaper reading the microphone through the ALSA plugin: a capture stream, whose output ports are monitor_*
            out("PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL"),
            out("PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FR"),
            in("crone:input_1")};
}

static bool has(const std::vector<Link> &l, const char *from, const char *to) {
    for (const auto &k : l) {
        if (k.from == from && k.to == to) {
            return true;
        }
    }
    return false;
}

TEST_CASE("apps: grouped by name without the numeric suffix, own clients and cards left out") {
    auto apps = listApps(desktop());
    REQUIRE(apps.size() == 2);
    CHECK(apps[0].name == "Vivaldi");
    CHECK(apps[0].ports.size() == 4); // both streams
    CHECK(apps[1].name == "mpv");
}

TEST_CASE("apps: a card is not an application (its monitor belongs to SYS-monitor), nor is MIDI") {
    for (const auto &a : listApps(desktop())) {
        CHECK(a.name != "Built-in Audio Analog Stereo");
        CHECK(a.name != "Midi-Bridge");
    }
}

TEST_CASE("own clients are recognised, also with a suffix") {
    CHECK(isOwnClient("crone"));
    CHECK(isOwnClient("softcut"));
    CHECK(isOwnClient("SuperCollider"));
    CHECK(isOwnClient("SuperCollider-01"));
    CHECK(isOwnClient("Verdandi"));
    CHECK(isOwnClient("Verdandi ctl"));
    CHECK_FALSE(isOwnClient("Vivaldi"));
    CHECK_FALSE(isOwnClient("cronejack")); // only the name itself, not a prefix
}

TEST_CASE("SYS: every application except norns, first port to input 1, second to input 2") {
    auto l = desired("system", "", desktop(), "", "");
    CHECK(has(l, "Vivaldi:output_FL", "crone:input_1"));
    CHECK(has(l, "Vivaldi:output_FR", "crone:input_2"));
    CHECK(has(l, "Vivaldi-73:output_FL", "crone:input_1"));
    CHECK(has(l, "mpv:output_1", "crone:input_1"));
    CHECK(has(l, "mpv:output_2", "crone:input_2"));
    for (const auto &k : l) {
        CHECK(k.from.compare(0, 5, "crone") != 0);
        CHECK(k.from.compare(0, 8, "softcut:") != 0);
        CHECK(k.from.compare(0, 14, "SuperCollider:") != 0);
        CHECK(k.from.find("Built-in") == std::string::npos); // no card, so no sink monitor either
        CHECK(k.from.find("capture") == std::string::npos);
    }
    CHECK(l.size() == 6);
}

TEST_CASE("APP: the chosen application only, all its streams") {
    auto l = desired("app", "Vivaldi", desktop(), "", "");
    CHECK(l.size() == 4);
    CHECK(has(l, "Vivaldi-73:output_FR", "crone:input_2"));
    CHECK_FALSE(has(l, "mpv:output_1", "crone:input_1"));
}

TEST_CASE("APP: not running: nothing (the choice stays, links come when it appears)") {
    CHECK(desired("app", "Spotify", desktop(), "", "").empty());
}

TEST_CASE("a mono application feeds both inputs") {
    std::vector<PortInfo> p = {out("Tuner:out")};
    auto l = desired("system", "", p, "", "");
    CHECK(has(l, "Tuner:out", "crone:input_1"));
    CHECK(has(l, "Tuner:out", "crone:input_2"));
}

TEST_CASE("MIC: the capture ports of the card by flag, never the MIDI port") {
    auto l = desired("mic", "", desktop(), "", "");
    CHECK(l.size() == 2);
    CHECK(has(l, "Built-in Audio Analog Stereo:capture_FL", "crone:input_1"));
    CHECK(has(l, "Built-in Audio Analog Stereo:capture_FR", "crone:input_2"));
}

TEST_CASE("MIC: the input prefix picks another card") {
    auto p = desktop();
    p.push_back(out("USB Mic:capture_MONO", true));
    auto l = desired("mic", "", p, "USB", "");
    CHECK(l.size() == 2);
    CHECK(has(l, "USB Mic:capture_MONO", "crone:input_1"));
    CHECK(has(l, "USB Mic:capture_MONO", "crone:input_2"));
}

TEST_CASE("OFF: nothing") { CHECK(desired("off", "", desktop(), "", "").empty()); }

TEST_CASE("sink monitor (optional): the monitor ports of the chosen output, nothing of the applications") {
    auto l = desired("monitor", "", desktop(), "", "Built-in Audio Analog Stereo");
    CHECK(l.size() == 2);
    CHECK(has(l, "Built-in Audio Analog Stereo:monitor_FL", "crone:input_1"));
    CHECK(has(l, "Built-in Audio Analog Stereo:monitor_FR", "crone:input_2"));
}

TEST_CASE("sink monitor: no chosen output, nothing") {
    CHECK(desired("monitor", "", desktop(), "", "").empty());
}

TEST_CASE("missing links: what is wanted and not there yet") {
    std::vector<Link> want = {{"A:o1", "crone:input_1"}, {"A:o2", "crone:input_2"}};
    std::vector<Link> have = {{"A:o1", "crone:input_1"}};
    auto m = missing(want, have);
    REQUIRE(m.size() == 1);
    CHECK(m[0].from == "A:o2");
}

TEST_CASE("surplus links: what feeds crone's inputs 1 and 2 and is not wanted") {
    std::vector<Link> want = {{"A:o1", "crone:input_1"}};
    std::vector<Link> have = {{"A:o1", "crone:input_1"},
                              {"Built-in Audio Analog Stereo:capture_FL", "crone:input_1"},
                              {"X:o", "crone:input_2"}};
    auto s = surplus(want, have);
    CHECK(s.size() == 2);
}

TEST_CASE("a capture stream (monitor_* ports) is not an application: not listed, not linked by SYS or APP") {
    for (const auto &a : listApps(desktop())) {
        CHECK(a.name.find("Capture") == std::string::npos);
        CHECK(a.name.find("reaper") == std::string::npos);
    }
    for (const char *mode : {"system", "app"}) {
        auto l = desired(mode, "PipeWire ALSA [reaper]/ALSA Capture [reaper]", desktop(), "", "");
        for (const auto &k : l) {
            CHECK(k.from.find("ALSA Capture") == std::string::npos);
        }
    }
}

TEST_CASE("the deny-list: monitor* and capture* ports are skipped, any other name still counts") {
    CHECK(isDeniedPort("PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL"));
    CHECK(isDeniedPort("X:monitor_1"));
    CHECK(isDeniedPort("X:capture_FL"));
    CHECK(isDeniedPort("X:capture_MONO"));
    CHECK_FALSE(isDeniedPort("Vivaldi:output_FL"));
    CHECK_FALSE(isDeniedPort("mpv:output_1"));
    CHECK_FALSE(isDeniedPort("Tuner:out"));          // a plain JACK application
    CHECK_FALSE(isDeniedPort("Synth:audio_out_L"));  // not named output*: still an application
}

TEST_CASE("a client with both output and monitor ports: only the output ports are taken") {
    std::vector<PortInfo> p = {out("Player:output_FL"), out("Player:output_FR"), out("Player:monitor_FL"),
                               out("Player:monitor_FR")};
    auto l = desired("system", "", p, "", "");
    CHECK(l.size() == 2);
    CHECK(has(l, "Player:output_FL", "crone:input_1"));
    CHECK(has(l, "Player:output_FR", "crone:input_2"));
}

TEST_CASE("a client that only has monitor ports is no application at all") {
    std::vector<PortInfo> p = {out("Rec:monitor_FL"), out("Rec:monitor_FR")};
    CHECK(listApps(p).empty());
    CHECK(desired("system", "", p, "", "").empty());
}
