// linux/tests/metro_win_test.cc (built by metro_win_test.sh): matron/src/metro.cc with NORNS_WINDOWS defined (the Windows metros: detached threads that end when their "generation" moves on) against a fake
// event queue. owner's log of 0.4.0: after "# script clear" the old script's metro kept calling its handler hundreds of times. a metro that is stopped must stop, also when it is stopped right after
// its start, and when it is restarted.
#include <atomic>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include "events.h"
#include "metro.h"
static std::atomic<long> fired[40];
extern "C" union event_data *event_data_new(int) { return (union event_data *)malloc(sizeof(union event_data)); }
extern "C" void event_post(union event_data *ev) { fired[ev->metro.id]++; free(ev); }
extern "C" void norns_win_sleep_until_ns(int64_t t) {
    struct timespec ts;
    ts.tv_sec = t / 1000000000;
    ts.tv_nsec = t % 1000000000;
    clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);
}
static void ms(int n) { usleep(n * 1000); }
int main() {
    metros_init();
    int fails = 0;
    metro_start(1, 0.005, -1, 0);
    ms(60);
    metro_stop(1);
    ms(30);
    long a = fired[1];
    ms(200);
    long b = fired[1];
    printf("stop: %ld events at the stop, %ld 200 ms later\n", a, b);
    if (b > a + 1 || a < 3) {
        printf("FAIL a stopped metro keeps firing (or never ran)\n");
        fails++;
    }
    for (int i = 0; i < 400; i++) { // started and stopped at once: a thread that has not yet read its generation when the stop comes
        int id = 2 + i % 30;
        metro_start(id, 0.002, -1, 0);
        metro_stop(id);
    }
    ms(150);
    long sum1 = 0;
    for (int i = 2; i < 32; i++) sum1 += fired[i];
    ms(300);
    long sum2 = 0;
    for (int i = 2; i < 32; i++) sum2 += fired[i];
    printf("start and stop at once: %ld events, %ld 300 ms later\n", sum1, sum2);
    if (sum2 > sum1) {
        printf("FAIL metros that were stopped right after their start keep firing (%ld more events)\n", sum2 - sum1);
        fails++;
    }
    metro_start(33, 0.003, -1, 0);
    ms(10);
    metro_start(33, 0.003, -1, 0);
    ms(10);
    metro_stop(33);
    ms(30);
    long c = fired[33];
    ms(150);
    if (fired[33] > c + 1) {
        printf("FAIL a restarted metro keeps firing\n");
        fails++;
    }
    printf(fails ? "metro_win_test: %d failures\n" : "metro_win_test: passed\n", fails);
    return fails ? 1 : 0;
}
