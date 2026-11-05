// the real client of the ALSA sequencer output (matron/src/platform/linux/aseq_out.cc, libasound): it starts when there is a sequencer and says so when there is none, NORNS_ALSA_MIDI=0 switches it off, a send never fails
// the caller (nothing connected is not an error), and it does not crash without a sequencer. where /dev/snd/seq exists (a laptop) the client is really made and found by name.
//   g++ -std=c++14 -I third-party/doctest -I third-party/readerwriterqueue -I matron/src -I matron/src/platform/linux linux/tests/aseq_out_test.cpp matron/src/platform/linux/aseq_out.cc -lasound -lpthread
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest/doctest.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "aseq_out.h"

static bool have_sequencer() { return access("/dev/snd/seq", F_OK) == 0; }

TEST_CASE("switched off by NORNS_ALSA_MIDI=0: no client, sends are -1, nothing is tried") {
    setenv("NORNS_ALSA_MIDI", "0", 1);
    CHECK(aseq_out_start() == -1);
    uint8_t d[3] = {0x90, 60, 100};
    CHECK(aseq_out_send(d, 3) == -1);
    CHECK(aseq_out_client_id() < 0);
    unsetenv("NORNS_ALSA_MIDI");
}

TEST_CASE("before the start a send is -1 and harmless") {
    uint8_t d[1] = {0xf8};
    CHECK(aseq_out_send(d, 1) == -1);
    CHECK(aseq_out_send(NULL, 0) == -1);
}

TEST_CASE("without a kernel sequencer the start says no (the log has the reason) and sends stay -1") {
    if (have_sequencer()) return; // the other case below
    CHECK(aseq_out_start() == -1);
    uint8_t d[3] = {0x90, 60, 100};
    CHECK(aseq_out_send(d, 3) == -1);
    CHECK(aseq_out_start() == -1); // twice is fine, the reason is said once
}

TEST_CASE("with a kernel sequencer the client exists, the send takes the bytes with nobody subscribed, and it can be stopped") {
    if (!have_sequencer()) return;
    CHECK(aseq_out_start() == 0);
    CHECK(aseq_out_client_id() >= 0);
    uint8_t d[3] = {0x90, 60, 100};
    CHECK(aseq_out_send(d, 3) == 3);
    uint8_t clk[1] = {0xf8};
    for (int i = 0; i < 5000; i++) aseq_out_send(clk, 1); // many, nobody listening: no block, no crash
    CHECK(aseq_out_start() == 0); // again: still up, no second client
    aseq_out_stop();
    CHECK(aseq_out_send(d, 3) == -1);
}
