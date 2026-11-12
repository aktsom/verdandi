/* present_coalesce.h (Windows build): the norns thread must never wait for the SDL (main) thread. Windows runs a modal loop inside the thread of a window while the user drags or resizes it, and the SDL
 * event loop does not run meanwhile: a synchronous "show this frame" call from the norns thread (which also runs the Lua event loop, the metros' handlers and the clock) then stood still until the mouse
 * was released, and the script went silent. now showing a frame is a note to the main thread: at most ONE note is outstanding, later frames only update what it will show; nothing waits.
 * header only, no SDL: linux/tests/present_coalesce_test.cc runs it with threads. */
#ifndef VERDANDI_PRESENT_COALESCE_H
#define VERDANDI_PRESENT_COALESCE_H
#include <atomic>

struct vpresent_state {
    std::atomic<int> queued{0};
    void *window = nullptr;
    void *src = nullptr;
};

/* the norns thread: remember what to show. returns true when the caller must post the note to the main thread (none is outstanding), false when one already is (it will show the newest frame) */
inline bool vpresent_request(vpresent_state *s, void *window, void *src) {
    s->window = window;
    s->src = src;
    return s->queued.exchange(1) == 0;
}

/* the main thread, when it handles the note: the flag goes down BEFORE the frame is read, so a frame drawn meanwhile makes a new note */
inline void vpresent_take(vpresent_state *s, void **window, void **src) {
    s->queued.store(0);
    *window = s->window;
    *src = s->src;
}
#endif
