#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "events.h"
#include "hello.h"
#include "oracle.h"
#include "screen.h"
#include "weaver.h"

#define LIGHTS 32
#define GRAVITY 2048

// thread id
static pthread_t tid;
// microseconds per frame
static const int tick_us = 5000;
// frames before timeout
static const int timeout_ticks = 2400; // ~12 seconds?

struct {
    double x;
    double y;
    double dx;
    double dy;
    int range;
    int life;
} light[LIGHTS];

struct {
    double x;
    double y;
    double dx;
    double dy;
} center;

struct {
    int x;
    int y;
} black;

#ifdef NORNS_WINDOWS
// Windows: sclang starts after norns.exe and compiles its class library first, so the SuperCollider side is ready after tens of seconds, not after 12 (the Pi starts it a minute before matron).
// The wait is a time, not a number of ticks (the tick is a Windows sleep of 5 ms, in fact about 15), the default is 150 s (NORNS_STARTUP_TIMEOUT: seconds), the question to sclang is asked every
// 100 ms and not every tick, and a /crone/ready that comes after the timeout is not lost: the thread goes on asking and the start-up is completed late (the message "SUPERCOLLIDER FAIL" goes away
// when the script is resumed).
#include <time.h>
static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static long long startup_timeout_ms(void) {
    const char *e = getenv("NORNS_STARTUP_TIMEOUT");
    long v = e ? atol(e) : 0;
    return (v > 0 ? v : 150) * 1000LL;
}
#endif
static int count = 0;
static int start = 1;

static int timeout = 0;
static int ok = 0;
static volatile int thread_running = 0;

static int norns_hello(int);
static void *hello_loop(void *);
static void start_thread();

void *hello_loop(void *p) {
    (void)p;

    thread_running = true;
#ifdef NORNS_WINDOWS
    const long long began = now_ms(), limit = startup_timeout_ms();
    int told = 0;
#endif

    while (!ok && !timeout) {

        norns_hello(1);
#ifdef NORNS_WINDOWS
        if (count % 20 == 0) {
            o_query_startup();
        }
        long long waited = now_ms() - began;
        if (waited > 15000 && told == 0) {
            told = 1;
            fprintf(stderr, "waiting for SuperCollider (sclang compiles its class library at the start, this can take a while)\n");
        } else if (waited > 60000 && told == 1) {
            told = 2;
            fprintf(stderr, "still waiting for SuperCollider after %lld s (timeout %lld s)\n", waited / 1000, limit / 1000);
        }
        if (waited > limit) {
            timeout = 1;
        }
#else
        o_query_startup();

        if (count > timeout_ticks) {
            timeout = 1;
        }
#endif

        usleep(tick_us);
        count++;
    }

    // fadeout
    while (norns_hello(0)) {
        usleep(tick_us);
    }

    if (timeout) {
        event_post(event_data_new(EVENT_STARTUP_READY_TIMEOUT));
#ifdef NORNS_WINDOWS
        // a late answer completes the start-up (up to 10 more minutes, then the failure stands)
        for (int i = 0; !ok && i < 2400; i++) {
            o_query_startup();
            usleep(250000);
        }
        if (ok) {
            fprintf(stderr, "SuperCollider answered late (after %lld s): completing the start-up\n", (now_ms() - began) / 1000);
            event_post(event_data_new(EVENT_STARTUP_READY_OK));
        }
#endif
    } else {
        event_post(event_data_new(EVENT_STARTUP_READY_OK));
    }

    thread_running = false;
    return NULL;
}

void start_thread() {
    // start thread
    int res;
    pthread_attr_t attr;

    res = pthread_attr_init(&attr);
    if (res != 0) {
        fprintf(stderr, "error creating pthread attributes\n");
        return;
    }
    res = pthread_create(&tid, &attr, &hello_loop, NULL);
    if (res != 0) {
        fprintf(stderr, "error creating pthread\n");
    }
}

void norns_hello_start() {
    if (thread_running) {
        return;
    }

    srand(time(NULL));
    screen_aa(0);
    screen_line_width(1);

    for (int i = 0; i < LIGHTS; i++) {
        light[i].range = 1;
    }

    black.x = 60 + rand() % 8;
    black.y = 28 + rand() % 8;
    center.x = 60 + rand() % 8;
    center.y = 28 + rand() % 8;
    center.dx = 0;
    center.dy = 0;
    count = 0;

    timeout = 0;
    ok = 0;

    start_thread();
}

void norns_hello_ok() {
    ok = 1;
}

int norns_hello(int live) {

    if ((count & 255) == 0) {
        black.x = 60 + rand() % 8;
        black.y = 28 + rand() % 8;
    }

    screen_clear();
    // screen_line_width(1.0); // FIXME: for some reason setting this disables drawing

    center.dx = center.dx + (black.x - center.x) / GRAVITY;
    center.dy = center.dy + (black.y - center.y) / GRAVITY;
    center.x = center.x + center.dx;
    center.y = center.y + center.dy;
    int alive = 0;

    for (int i = 0; i < LIGHTS; i++) {
        if (light[i].range == 2) {
            if (start < 64)
                start++;
            light[i].range--;
        } else if (light[i].range > 2) {
            light[i].range--;
            light[i].x += light[i].dx;
            light[i].y += light[i].dy;
            alive++;
            screen_rect(light[i].x, light[i].y, 1, 1);
            screen_level(ceil(15 * light[i].range / light[i].life) * (start / 64.0));
            screen_stroke();
        } else if (live) {
            light[i].life = 64 + rand() % 64;
            light[i].range = light[i].life;
            light[i].x = center.x;
            light[i].y = center.y;
            light[i].dx = (rand() % 32 - 16) / 96.0;
            light[i].dy = (rand() % 32 - 16) / 96.0;
        }
    }
    screen_update();

    return alive;
}
