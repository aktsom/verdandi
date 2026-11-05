// the ALSA sequencer output of the virtual MIDI device (matron/src/platform/linux/aseq_pump.h): a script's bytes become sequencer events, in order, without ever blocking the sender, bounded, drops counted and said
// at most every 10 seconds. there is no kernel sequencer where this is run in CI containers, so the sink (what talks to libasound) is a fake here; the real client is aseq_out.cc, tested by aseq_dump_test.c on a machine with /dev/snd/seq.
//   g++ -std=c++14 -I third-party/doctest -I third-party/readerwriterqueue -I matron/src/platform/linux linux/tests/aseq_pump_test.cpp -lasound -lpthread
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest/doctest.h"

#include <errno.h>
#include <string.h>

#include <chrono>
#include <thread>
#include <string>
#include <vector>

#include "aseq_pump.h"

struct Got {
    snd_seq_event_type_t type;
    int channel, a, b;      // note / param / value, as the event carries them
    std::vector<uint8_t> bytes; // sysex
};

struct Fake {
    std::vector<Got> got;
    std::vector<std::string> lines;
    int result = 0;          // what output() returns
    int eagain_times = 0;    // answer -EAGAIN this many times first
    int waits = 0;
    bool room_after_wait = true;
    double now = 0;
    int calls = 0;
};

static int fake_output(void *ctx, const snd_seq_event_t *ev) {
    Fake *f = (Fake *)ctx;
    f->calls++;
    if (f->eagain_times > 0) {
        f->eagain_times--;
        return -EAGAIN;
    }
    if (f->result != 0) {
        return f->result;
    }
    Got g;
    g.type = (snd_seq_event_type_t)ev->type;
    g.channel = g.a = g.b = 0;
    switch (ev->type) {
    case SND_SEQ_EVENT_NOTEON: case SND_SEQ_EVENT_NOTEOFF: case SND_SEQ_EVENT_KEYPRESS:
        g.channel = ev->data.note.channel; g.a = ev->data.note.note; g.b = ev->data.note.velocity; break;
    case SND_SEQ_EVENT_CONTROLLER: case SND_SEQ_EVENT_PGMCHANGE: case SND_SEQ_EVENT_CHANPRESS: case SND_SEQ_EVENT_PITCHBEND:
    case SND_SEQ_EVENT_SONGPOS: case SND_SEQ_EVENT_SONGSEL: case SND_SEQ_EVENT_QFRAME:
        g.channel = ev->data.control.channel; g.a = ev->data.control.param; g.b = ev->data.control.value; break;
    case SND_SEQ_EVENT_SYSEX:
        g.bytes.assign((const uint8_t *)ev->data.ext.ptr, (const uint8_t *)ev->data.ext.ptr + ev->data.ext.len); break;
    default: break;
    }
    f->got.push_back(g);
    return 0;
}
static bool fake_wait(void *ctx, int) { Fake *f = (Fake *)ctx; f->waits++; return f->room_after_wait; }
static double fake_now(void *ctx) { return ((Fake *)ctx)->now; }
static void fake_log(const char *line, void *ctx) { ((Fake *)ctx)->lines.push_back(line); }

// a pump on a fake sequencer (the Pump is not copyable: built where it is used)
#define PUMPS(f, p, cap) aseq::Pump p(aseq::Sink{fake_output, fake_wait, &f}, cap); p.set_clock(fake_now, &f); p.set_logger(fake_log, &f)
static void send(aseq::Pump &p, std::initializer_list<uint8_t> b) { std::vector<uint8_t> v(b); p.send(v.data(), v.size()); }

TEST_CASE("nothing sent: the sequencer is not touched") {
    Fake f; PUMPS(f, p, 2048);
    p.run_once();
    CHECK(f.calls == 0);
    CHECK(p.stats().sent == 0);
}

TEST_CASE("notes, cc, program change, pitch bend, pressure: the right events, channel from the status byte") {
    Fake f; PUMPS(f, p, 2048);
    send(p, {0x90, 60, 100}); send(p, {0x82, 61, 40}); send(p, {0xb1, 7, 64}); send(p, {0xc2, 5}); send(p, {0xa0, 60, 30}); send(p, {0xd3, 9});
    send(p, {0xe0, 0x00, 0x40}); send(p, {0xe0, 0x64, 0x40}); send(p, {0xe0, 0x7f, 0x7f}); send(p, {0xe0, 0x00, 0x00});
    p.run_once();
    REQUIRE(f.got.size() == 10);
    CHECK(f.got[0].type == SND_SEQ_EVENT_NOTEON); CHECK(f.got[0].channel == 0); CHECK(f.got[0].a == 60); CHECK(f.got[0].b == 100);
    CHECK(f.got[1].type == SND_SEQ_EVENT_NOTEOFF); CHECK(f.got[1].channel == 2); CHECK(f.got[1].a == 61); CHECK(f.got[1].b == 40);
    CHECK(f.got[2].type == SND_SEQ_EVENT_CONTROLLER); CHECK(f.got[2].channel == 1); CHECK(f.got[2].a == 7); CHECK(f.got[2].b == 64);
    CHECK(f.got[3].type == SND_SEQ_EVENT_PGMCHANGE); CHECK(f.got[3].channel == 2); CHECK(f.got[3].b == 5);
    CHECK(f.got[4].type == SND_SEQ_EVENT_KEYPRESS); CHECK(f.got[4].a == 60); CHECK(f.got[4].b == 30);
    CHECK(f.got[5].type == SND_SEQ_EVENT_CHANPRESS); CHECK(f.got[5].channel == 3); CHECK(f.got[5].b == 9);
    CHECK(f.got[6].type == SND_SEQ_EVENT_PITCHBEND); CHECK(f.got[6].b == 0);          // the middle, 8192
    CHECK(f.got[7].b == 100);                                                          // lsb 0x64, msb 0x40: 8292 - 8192
    CHECK(f.got[8].b == 8191);
    CHECK(f.got[9].b == -8192);
}

TEST_CASE("realtime: clock, start, continue, stop, active sensing, reset") {
    Fake f; PUMPS(f, p, 2048);
    send(p, {0xf8}); send(p, {0xfa}); send(p, {0xfb}); send(p, {0xfc}); send(p, {0xfe}); send(p, {0xff});
    p.run_once();
    REQUIRE(f.got.size() == 6);
    CHECK(f.got[0].type == SND_SEQ_EVENT_CLOCK); CHECK(f.got[1].type == SND_SEQ_EVENT_START); CHECK(f.got[2].type == SND_SEQ_EVENT_CONTINUE);
    CHECK(f.got[3].type == SND_SEQ_EVENT_STOP); CHECK(f.got[4].type == SND_SEQ_EVENT_SENSING); CHECK(f.got[5].type == SND_SEQ_EVENT_RESET);
}

TEST_CASE("system common: song position, song select, tune request, quarter frame") {
    Fake f; PUMPS(f, p, 2048);
    send(p, {0xf2, 16, 0}); send(p, {0xf2, 0x7f, 0x7f}); send(p, {0xf3, 4}); send(p, {0xf6}); send(p, {0xf1, 0x22});
    p.run_once();
    REQUIRE(f.got.size() == 5);
    CHECK(f.got[0].type == SND_SEQ_EVENT_SONGPOS); CHECK(f.got[0].b == 16);
    CHECK(f.got[1].b == 16383);
    CHECK(f.got[2].type == SND_SEQ_EVENT_SONGSEL); CHECK(f.got[2].b == 4);
    CHECK(f.got[3].type == SND_SEQ_EVENT_TUNE_REQUEST);
    CHECK(f.got[4].type == SND_SEQ_EVENT_QFRAME); CHECK(f.got[4].b == 0x22);
}

TEST_CASE("sysex: one event with every byte, F0 and F7 included; undefined bytes are dropped") {
    Fake f; PUMPS(f, p, 2048);
    send(p, {0xf0, 0x7d, 1, 2, 3, 0xf7}); send(p, {0xf9}); send(p, {0xfd});
    p.run_once();
    REQUIRE(f.got.size() == 1);
    CHECK(f.got[0].type == SND_SEQ_EVENT_SYSEX);
    CHECK(f.got[0].bytes == std::vector<uint8_t>({0xf0, 0x7d, 1, 2, 3, 0xf7}));
}

TEST_CASE("several messages in one call and running status keep their order") {
    Fake f; PUMPS(f, p, 2048);
    send(p, {0x90, 60, 100, 62, 90, 0x80, 60, 0, 0xf8});
    p.run_once();
    REQUIRE(f.got.size() == 4);
    CHECK(f.got[0].a == 60); CHECK(f.got[1].a == 62); CHECK(f.got[1].type == SND_SEQ_EVENT_NOTEON); CHECK(f.got[2].type == SND_SEQ_EVENT_NOTEOFF); CHECK(f.got[3].type == SND_SEQ_EVENT_CLOCK);
}

TEST_CASE("a thousand messages come out in the order they went in") {
    Fake f; PUMPS(f, p, 2048);
    for (int i = 0; i < 1000; i++) send(p, {0x90, (uint8_t)(i & 127), (uint8_t)(1 + (i >> 7))});
    p.run_once();
    REQUIRE(f.got.size() == 1000);
    bool ok = true;
    for (int i = 0; i < 1000; i++) ok = ok && f.got[i].a == (i & 127) && f.got[i].b == 1 + (i >> 7);
    CHECK(ok);
    CHECK(p.stats().sent == 1000);
}

TEST_CASE("no subscribers is not an error: the sequencer answers 0 and the events count as sent") {
    Fake f; f.result = 0; PUMPS(f, p, 2048);
    send(p, {0x90, 60, 100});
    p.run_once();
    CHECK(p.stats().sent == 1); CHECK(p.stats().dropped_error == 0);
}

TEST_CASE("the sender never blocks, also when the sequencer does not take anything: the queue is bounded, the rest is dropped and counted") {
    Fake f; f.result = -EAGAIN; f.room_after_wait = false; PUMPS(f, p, 256);
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < 5000; i++) send(p, {0x90, 60, 100}); // no worker runs: nothing is taken
    double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    CHECK(ms < 500);
    CHECK(p.stats().dropped_full >= 5000 - 600); // the queue holds a few hundred (its size is rounded up to a power of two)
    CHECK(p.stats().dropped_full < 5000);
    CHECK(f.calls == 0); // the sender did not touch the sequencer
}

TEST_CASE("a full destination (-EAGAIN) is waited for a little and tried again; when it stays full the event is dropped and counted, the next one still goes") {
    Fake f; f.eagain_times = 1; f.room_after_wait = true; PUMPS(f, p, 2048);
    send(p, {0x90, 60, 100});
    p.run_once();
    CHECK(f.got.size() == 1); CHECK(f.waits >= 1); CHECK(p.stats().dropped_error == 0);
    Fake g; g.eagain_times = 1000; g.room_after_wait = false; PUMPS(g, q, 2048);
    send(q, {0x90, 60, 100});
    q.run_once();
    CHECK(g.got.empty()); CHECK(q.stats().dropped_error == 1);
    CHECK(g.calls <= 4); // bounded retries
    g.eagain_times = 0;
    send(q, {0x90, 61, 100});
    q.run_once();
    REQUIRE(g.got.size() == 1); CHECK(g.got[0].a == 61);
}

TEST_CASE("an error of the sequencer is counted, nothing crashes, the next events go") {
    for (int err : {-ENXIO, -EPIPE, -ENOMEM, -EINVAL, -ENOENT}) {
        Fake f; f.result = err; PUMPS(f, p, 2048);
        send(p, {0x90, 60, 100}); send(p, {0xf8});
        p.run_once();
        CHECK(p.stats().dropped_error == 2);
        f.result = 0;
        send(p, {0x90, 61, 100});
        p.run_once();
        REQUIRE(f.got.size() == 1);
    }
}

TEST_CASE("drops are said at most every 10 seconds, with the totals since the last line, from outside the delivery") {
    Fake f; f.result = -EPIPE; PUMPS(f, p, 2048); f.now = 100;
    send(p, {0x90, 60, 100}); p.run_once();
    REQUIRE(f.lines.size() == 1);
    CHECK(f.lines[0].find("dropped") != std::string::npos);
    f.now = 105; send(p, {0x90, 60, 100}); send(p, {0x90, 60, 100}); p.run_once();
    CHECK(f.lines.size() == 1);
    f.now = 110.5; send(p, {0x90, 60, 100}); p.run_once();
    REQUIRE(f.lines.size() == 2);
    CHECK(f.lines[1].find("2 message") != std::string::npos); // the two dropped at 105, sent as soon as ten seconds had passed (the third waits for the next line)
    f.now = 200; f.result = 0; send(p, {0x90, 60, 100}); p.run_once();
    REQUIRE(f.lines.size() == 3);
    CHECK(f.lines[2].find("1 message") != std::string::npos); // what was dropped after the last line is said at the next chance
    f.now = 400; send(p, {0x90, 60, 100}); p.run_once();
    CHECK(f.lines.size() == 3); // nothing dropped since: nothing said
}

TEST_CASE("a long sysex is cut into events of at most MIDI_FRAME_MAX bytes, none lost (as the JACK output does)") {
    Fake f; PUMPS(f, p, 2048);
    std::vector<uint8_t> d(MIDI_FRAME_MAX * 2 + 10, 1); d[0] = 0xf0; d.back() = 0xf7;
    p.send(d.data(), d.size());
    p.run_once();
    size_t total = 0; bool small = true;
    for (auto &g : f.got) { total += g.bytes.size(); small = small && g.bytes.size() <= MIDI_FRAME_MAX; }
    CHECK(f.got.size() >= 3); CHECK(small); CHECK(total == d.size());
}

TEST_CASE("the worker thread delivers what was sent and stops cleanly, also with work left and without any") {
    Fake f; PUMPS(f, p, 2048);
    p.start();
    for (int i = 0; i < 200; i++) send(p, {0x90, (uint8_t)(i & 127), 100});
    for (int k = 0; k < 200 && p.stats().sent < 200; k++) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    p.stop();
    CHECK(p.stats().sent == 200);
    { PUMPS(f, q, 2048); q.start(); q.stop(); } // no work
    { PUMPS(f, r, 2048); send(r, {0x90, 60, 100}); } // never started, destroyed with work queued
}
