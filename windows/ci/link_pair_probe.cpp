// windows/ci/link_pair_probe.cpp (M4): two Ableton Link instances in one process find each other and follow a tempo change. the runner's network decides whether peers can see each other (multicast on the
// loopback or the first adapter): the program says what it saw and exits 0 when the peers were found and the tempo followed, 2 when no peer was found (a network that does not carry it, not a program fault), 1 when
// peers were found but the tempo did not follow.
#include <ableton/Link.hpp>
#include <chrono>
#include <cstdio>
#include <thread>

int main()
{
    ableton::Link a(120.0), b(100.0);
    a.enable(true);
    b.enable(true);
    for (int i = 0; i < 100 && (a.numPeers() == 0 || b.numPeers() == 0); i++)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    std::printf("link pair: a sees %zu peers, b sees %zu peers\n", a.numPeers(), b.numPeers());
    if (a.numPeers() == 0 || b.numPeers() == 0)
    {
        std::printf("link pair: no peer found within 10 s (the network of this machine did not carry the discovery)\n");
        return 2;
    }
    auto sa = a.captureAppSessionState();
    sa.setTempo(87.0, a.clock().micros());
    a.commitAppSessionState(sa);
    double seen = 0;
    for (int i = 0; i < 50; i++)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        seen = b.captureAppSessionState().tempo();
        if (seen > 86.5 && seen < 87.5) break;
    }
    std::printf("link pair: b follows a's tempo: %.2f bpm (asked 87)\n", seen);
    return (seen > 86.5 && seen < 87.5) ? 0 : 1;
}
