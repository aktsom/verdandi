/*
 * jack_midi_out_stress.cc: the JACK MIDI output of matron/src/platform/linux/jack_midi_in.cc (the real file, included here) under stress, on whatever JACK server answers (jackd, or PipeWire's JACK layer under pw-jack).
 * a crash report of the installed package (SIGSEGV in the JACK process thread of PipeWire's layer while a client received notes and clock) is what this reproduces.
 *   c++ -std=c++14 -I matron/src -I matron/src/platform/linux -I third-party/readerwriterqueue linux/tests/jack_midi_out_stress.cc -o jack_midi_out_stress $(pkg-config --cflags --libs jack) -lpthread
 *   jack_midi_out_stress [seconds, default 10] [hex mask of the kinds of sends, default 3ff] [listener 1 or 0]
 * senders (4 threads) send what a script can: single notes, a note storm, 24-tick clock bursts of 2000 messages at once, running status, sysex of 100, 500, 2000 and 20000 bytes, all in one call or in
 * pieces, garbage bytes. a client thread connects Verdandi:midi_out to its own port, listens a while, disconnects, connects again, and closes and reopens now and then. "stress: done" ends a good run, no crash
 * and no hang (a watchdog ends it with exit 3 when a send call does not return in 5 s).
 */
#include "../../matron/src/platform/linux/jack_midi_in.cc"

#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

// what jack_midi_in.cc needs from the rest of matron
extern "C" void dev_list_add(device_t, const char *, const char *, lua_State *) {}
extern "C" void clock_midi_handle_message_at(uint8_t, double) {}
extern "C" void clock_midi_handle_song_position(uint16_t) {}
extern "C" double jack_client_get_current_time() { return 0.0; }

static std::atomic<bool> run{true};
static unsigned what_mask = 0x3ff;  // which kinds of sends (bit per case below)
static bool with_listener = true;
static std::atomic<long> sent_calls{0}, got_events{0}, got_bytes{0};
static std::atomic<long> progress{0};

static int cap_process(jack_nframes_t n, void *arg) {
    jack_port_t *p = (jack_port_t *)arg;
    void *buf = jack_port_get_buffer(p, n);
    jack_nframes_t c = jack_midi_get_event_count(buf);
    for (jack_nframes_t i = 0; i < c; i++) {
        jack_midi_event_t e;
        if (jack_midi_event_get(&e, buf, i) == 0) {
            got_events.fetch_add(1, std::memory_order_relaxed);
            got_bytes.fetch_add((long)e.size, std::memory_order_relaxed);
        }
    }
    return 0;
}

static void sender(int seed) {
    unsigned r = 12345u + (unsigned)seed * 7919u;
    auto rnd = [&]() { r = r * 1664525u + 1013904223u; return r >> 8; };
    static uint8_t big[20000];
    while (run.load()) {
        int what = (int)(rnd() % 10);
        if (!(what_mask & (1u << what))) { std::this_thread::sleep_for(std::chrono::microseconds(200)); progress.fetch_add(1, std::memory_order_relaxed); continue; }
        uint8_t d[4096];
        size_t n = 0;
        switch (what) {
        case 0: d[0] = 0x90; d[1] = rnd() % 128; d[2] = 1 + rnd() % 127; n = 3; break;
        case 1: for (int i = 0; i < 400; i++) { d[0] = 0x90 + (i & 15); d[1] = i & 127; d[2] = 100; jack_midi_out_send(d, 3); } continue; // a note storm
        case 2: for (int i = 0; i < 2000; i++) { uint8_t c = 0xf8; jack_midi_out_send(&c, 1); } continue;                                    // a clock burst
        case 3: d[0] = 0xb0; d[1] = 7; d[2] = 64; d[3] = 8; n = 4; break;                                                                      // running status, a cut-off one
        case 4: n = 100; d[0] = 0xf0; for (size_t i = 1; i < n - 1; i++) d[i] = 1; d[n - 1] = 0xf7; break;
        case 5: n = 500; d[0] = 0xf0; for (size_t i = 1; i < n - 1; i++) d[i] = 2; d[n - 1] = 0xf7; break;
        case 6: n = 2000; if (n > sizeof d) n = sizeof d; d[0] = 0xf0; for (size_t i = 1; i < n - 1; i++) d[i] = 3; d[n - 1] = 0xf7; break;
        case 7: big[0] = 0xf0; for (size_t i = 1; i < sizeof big - 1; i++) big[i] = 4; big[sizeof big - 1] = 0xf7; jack_midi_out_send(big, sizeof big); continue;
        case 8: n = 1 + rnd() % 64; for (size_t i = 0; i < n; i++) d[i] = (uint8_t)rnd(); break; // garbage
        default: for (int i = 0; i < 30; i++) { d[0] = 0x80; d[1] = i; d[2] = 0; jack_midi_out_send(d, 3); } continue;
        }
        if (n) jack_midi_out_send(d, n);
        sent_calls.fetch_add(1, std::memory_order_relaxed);
        progress.fetch_add(1, std::memory_order_relaxed);
        if ((rnd() % 4) == 0) std::this_thread::sleep_for(std::chrono::microseconds(rnd() % 3000));
    }
}

static void listener() {
    int round = 0;
    while (run.load()) {
        jack_client_t *c = jack_client_open("stress_cap", JackNoStartServer, NULL);
        if (c == NULL) { std::this_thread::sleep_for(std::chrono::milliseconds(200)); continue; }
        jack_port_t *p = jack_port_register(c, "in", JACK_DEFAULT_MIDI_TYPE, JackPortIsInput, 0);
        jack_set_process_callback(c, cap_process, p);
        jack_activate(c);
        for (int k = 0; k < 4 && run.load(); k++) {
            jack_connect(c, "Verdandi:midi_out", "stress_cap:in");
            std::this_thread::sleep_for(std::chrono::milliseconds(100 + (round * 37) % 300));
            jack_disconnect(c, "Verdandi:midi_out", "stress_cap:in");
            std::this_thread::sleep_for(std::chrono::milliseconds(20 + (round * 13) % 60));
            round++;
        }
        jack_client_close(c);
    }
}

int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 10;
    if (jack_midi_in_start() != 0) {
        fprintf(stderr, "stress: no JACK MIDI (is a server running?)\n");
        return 2;
    }
    if (argc > 2) what_mask = (unsigned)strtoul(argv[2], NULL, 16);
    if (argc > 3) with_listener = atoi(argv[3]) != 0;
    std::thread l(with_listener ? listener : []() {});
    std::vector<std::thread> s;
    for (int i = 0; i < 4; i++) s.emplace_back(sender, i);
    long last = -1;
    for (int t = 0; t < seconds * 2; t++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        long p = progress.load();
        if (t % 6 == 5 && p == last) { fprintf(stderr, "stress: no progress for 3 s (a send call hangs?)\n"); _exit(3); }
        if (t % 6 == 5) last = p;
    }
    run = false;
    for (auto &t : s) t.join();
    l.join();
    printf("stress: sent %ld calls, a listener got %ld events (%ld bytes)\n", sent_calls.load(), got_events.load(), got_bytes.load());
    printf("stress: done\n");
    return 0;
}
