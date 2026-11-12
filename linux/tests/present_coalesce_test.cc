// linux/tests/present_coalesce_test.cc: matron/src/platform/windows/present_coalesce.h. a "main thread" that is stuck (the modal loop of a window drag) must not hold up the "norns thread" that
// shows frames, and when it returns it shows the newest frame once.
#include <atomic>
#include <chrono>
#include <stdio.h>
#include <thread>
#include "../../matron/src/platform/windows/present_coalesce.h"
int main() {
    vpresent_state st;
    std::atomic<int> notes{0}, shown{0};
    std::atomic<long> lua_ticks{0};
    std::atomic<bool> stuck{true}, stop{false};
    int fails = 0;
    long frame = 0;
    // the norns thread: a clock that runs script code every 2 ms and shows a frame each time
    std::thread norns([&] {
        while (!stop) {
            lua_ticks++;
            frame++;
            if (vpresent_request(&st, (void *)1, (void *)frame)) notes++;
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
    });
    // the main thread: stuck for 400 ms (the drag), then it handles the notes
    long last_seen = 0;
    std::this_thread::sleep_for(std::chrono::milliseconds(400));
    long ticks_during_drag = lua_ticks;
    int notes_during_drag = notes;
    if (ticks_during_drag < 100) { printf("FAIL the norns thread was held up while the main thread was stuck (%ld ticks in 400 ms)\n", ticks_during_drag); fails++; }
    if (notes_during_drag != 1) { printf("FAIL %d notes were posted while the main thread was stuck, expected 1\n", notes_during_drag); fails++; }
    stuck = false;
    void *w, *s;
    vpresent_take(&st, &w, &s);
    shown++;
    last_seen = (long)s;
    if (last_seen < ticks_during_drag - 5) { printf("FAIL the frame shown is old: %ld of %ld\n", last_seen, ticks_during_drag); fails++; }
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    if (notes < 2) { printf("FAIL a frame drawn after the main thread took the note did not make a new note\n"); fails++; }
    stop = true;
    norns.join();
    printf("present_coalesce_test: %d ticks of the norns thread and %d notes while stuck; %s\n", (int)ticks_during_drag, notes_during_drag, fails ? "FAILED" : "passed");
    return fails != 0;
}
