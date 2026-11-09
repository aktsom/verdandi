// windows/ci/link_probe.cpp (M0a): does Ableton Link (third-party/link, GPL-2.0-or-later) compile and run with the toolchain? one peer, not enabled, no network traffic needed:
// it creates the Link object, reads the session state, commits a tempo and a start, and prints what it read. the platform macro (LINK_PLATFORM_WINDOWS, _LINUX) comes from the command line.
#include <ableton/Link.hpp>
#include <chrono>
#include <cstdio>

int main()
{
    ableton::Link link(120.0);
    link.enableStartStopSync(true);
    auto state = link.captureAppSessionState();
    const auto now = link.clock().micros();
    state.setTempo(100.0, now);
    state.setIsPlaying(true, now);
    link.commitAppSessionState(state);
    state = link.captureAppSessionState();
    const double beat = state.beatAtTime(link.clock().micros(), 4.0);
    std::printf("link probe: tempo %.1f playing %d beat >= 0: %d peers %zu\n", state.tempo(), state.isPlaying() ? 1 : 0, beat >= 0.0 ? 1 : 0, link.numPeers());
    return (state.tempo() > 99.0 && state.tempo() < 101.0 && state.isPlaying()) ? 0 : 1;
}
