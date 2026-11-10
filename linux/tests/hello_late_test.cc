// matron/src/hello.cc with NORNS_WINDOWS (the start-up wait of the Windows build) on Linux, with stand-ins for what it calls. what it must do: a /crone/ready after the timeout is not lost (a late OK follows the
// timeout event), a ready in time gives one OK and no timeout, the question to sclang is not asked on every 5 ms tick, and the timeout comes from NORNS_STARTUP_TIMEOUT.
#include <atomic>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vector>

#include "events.h"
#include "hello.h"

static std::atomic<int> queries(0);
static std::vector<int> posted;
extern "C" {
union event_data *event_data_new(event_t t) { union event_data *e = (union event_data *)calloc(1, sizeof(union event_data)); e->type = t; return e; }
void event_post(union event_data *e) { posted.push_back(e->type); }
void o_query_startup(void) { queries++; }
void screen_clear(void) {}
void screen_update(void) {}
void screen_rect(double, double, double, double) {}
void screen_stroke(void) {}
void screen_level(int) {}
void screen_aa(int) {}
void screen_line_width(double) {}
}

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static int count_of(int t) { int n = 0; for (int x : posted) if (x == t) n++; return n; }

int main(int argc, char **argv) {
    const char *sc = argc > 1 ? argv[1] : "late";
    setenv("NORNS_STARTUP_TIMEOUT", "2", 1);
    norns_hello_start();
    if (!strcmp(sc, "late")) {
        sleep(4);
        CHECK(count_of(EVENT_STARTUP_READY_TIMEOUT) == 1, "the timeout came after 2 s (%d)", count_of(EVENT_STARTUP_READY_TIMEOUT));
        CHECK(count_of(EVENT_STARTUP_READY_OK) == 0, "and no OK yet");
        norns_hello_ok(); /* sclang answers late */
        sleep(1);
        CHECK(count_of(EVENT_STARTUP_READY_OK) == 1, "a late /crone/ready completes the start-up (%d)", count_of(EVENT_STARTUP_READY_OK));
    } else {
        sleep(1);
        norns_hello_ok();
        sleep(3);
        CHECK(count_of(EVENT_STARTUP_READY_OK) == 1 && count_of(EVENT_STARTUP_READY_TIMEOUT) == 0, "ready in time: one OK, no timeout (%d %d)", count_of(EVENT_STARTUP_READY_OK), count_of(EVENT_STARTUP_READY_TIMEOUT));
    }
    int q = queries.load();
    CHECK(q > 5 && q < 120, "the question to sclang is asked about every 100 ms, not every tick (%d in ~5 s)", q);
    if (!fails) printf("hello_late_test %s: passed\n", sc);
    return fails ? 1 : 0;
}
