/* redraw_throttle.h with a simulated window: a fast turning (a turn every millisecond for a second, a draw that takes 30 ms) must not leave a queue behind. the old way (one draw per turn, one after the other)
 * is simulated too, to show the lag it made. run from the repo root: cc -std=gnu11 -Wall -I matron/src/platform/common linux/tests/redraw_throttle_test.c -o /tmp/rtt && /tmp/rtt */
#include <stdio.h>
#include <string.h>
#include "redraw_throttle.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)

/* a window thread: one event queue (turns and timer events with their time of arrival), handled one at a time, a draw costs `cost` ms of its time */
typedef struct { int at; int kind; int value; } ev_t; /* kind 0 turn, 1 timer */
#define MAXEV 200000
static ev_t q[MAXEV]; static int qn;
static void push(int at, int kind, int value) { int i = qn++; while (i > 0 && q[i-1].at > at) { q[i] = q[i-1]; i--; } q[i].at = at; q[i].kind = kind; q[i].value = value; }

typedef struct { int draws, max_lag, ticks, drawn_value, end_time, backlog_after_input; } result_t;

static result_t simulate(int throttled, int turns, int gap_us_between_turns, int cost_ms) {
    result_t r; memset(&r, 0, sizeof r);
    qn = 0;
    for (int i = 0; i < turns; i++) push(i * gap_us_between_turns / 1000, 0, 1);
    int input_end = (turns - 1) * gap_us_between_turns / 1000;
    int now = 0; rt_state st; memset(&st, 0, sizeof st);
    int head = 0;
    while (head < qn) {
        ev_t e = q[head++];
        if (e.at > now) now = e.at;                 /* the window thread waits for the event */
        int lag = now - e.at;
        if (e.kind == 0 && lag > r.max_lag) r.max_lag = lag;
        if (e.kind == 0) r.ticks += e.value;
        if (!throttled) {                            /* old: draw for every turn */
            if (e.kind == 0) { now += cost_ms; r.draws++; r.drawn_value = r.ticks; }
            continue;
        }
        uint32_t delay;
        if (e.kind == 0) {
            rt_action a = rt_request(&st, (uint32_t)now, &delay);
            if (a == RT_DRAW_NOW) { now += cost_ms; rt_drawn(&st, (uint32_t)now); r.draws++; r.drawn_value = r.ticks; }
            else if (a == RT_SCHEDULE) { int at = now + (int)delay; int h = head; /* insert in order after head */ int i = qn++; while (i > h && q[i-1].at > at) { q[i] = q[i-1]; i--; } q[i].at = at; q[i].kind = 1; q[i].value = 0; }
        } else {
            rt_fired(&st); now += cost_ms; rt_drawn(&st, (uint32_t)now); r.draws++; r.drawn_value = r.ticks;
        }
    }
    r.end_time = now;
    r.backlog_after_input = now - input_end;
    return r;
}
int main(void) {
    /* 1000 turns, one a millisecond, a draw of 30 ms */
    result_t old = simulate(0, 1000, 1000, 30);
    result_t neu = simulate(1, 1000, 1000, 30);
    printf("old: %d draws, last draw ended %d ms after the last turn, the worst turn waited %d ms\n", old.draws, old.backlog_after_input, old.max_lag);
    printf("new: %d draws, last draw ended %d ms after the last turn, the worst turn waited %d ms\n", neu.draws, neu.backlog_after_input, neu.max_lag);
    CHECK(old.backlog_after_input > 5000, "the old way: the knob goes on for many seconds after the turning stopped (this is the owner's report)");
    CHECK(neu.drawn_value == 1000 && neu.ticks == 1000, "the last draw shows every turn: the knob ends where the value is");
    CHECK(neu.backlog_after_input <= 16 + 30 + 30, "the new way: the last draw is at most a gap and a draw after the last turn");
    CHECK(neu.max_lag <= 30, "no turn waits in the queue longer than one draw");
    CHECK(neu.draws < 60, "far fewer draws than turns");
    /* slow turning: every turn is drawn at once */
    result_t slow = simulate(1, 20, 100000, 30);
    CHECK(slow.draws == 20 && slow.drawn_value == 20 && slow.max_lag == 0, "slow turning: every turn is drawn at once");
    /* one turn */
    result_t one = simulate(1, 1, 1000, 30);
    CHECK(one.draws == 1 && one.drawn_value == 1, "one turn, one draw");
    /* a burst of 5 then a pause, then a burst: both end right */
    rt_state st; memset(&st, 0, sizeof st); uint32_t d;
    CHECK(rt_request(&st, 100, &d) == RT_DRAW_NOW, "the first turn draws");
    rt_drawn(&st, 110);
    CHECK(rt_request(&st, 111, &d) == RT_SCHEDULE && d == 15, "a turn right after a draw schedules the rest of the gap");
    CHECK(rt_request(&st, 112, &d) == RT_WAIT, "a turn while a timer is on its way waits");
    rt_fired(&st); rt_drawn(&st, 140);
    CHECK(rt_request(&st, 200, &d) == RT_DRAW_NOW, "after a pause the next turn draws at once");
    /* a clock that wraps (32 bit) */
    memset(&st, 0, sizeof st);
    CHECK(rt_request(&st, 0xFFFFFFF0u, &d) == RT_DRAW_NOW, "wrap: first");
    rt_drawn(&st, 0xFFFFFFF5u);
    CHECK(rt_request(&st, 0x00000003u, &d) == RT_SCHEDULE, "wrap: 14 ms later is inside the gap");
    if (fails) { printf("%d failed\n", fails); return 1; }
    printf("redraw throttle: all passed\n");
    return 0;
}
