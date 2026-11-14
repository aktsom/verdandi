/* redraw_throttle.h: how often the window is drawn again while an encoder is turned fast (Windows 0.10.2; docs/port/phase-m11.md). pure, no SDL: linux/tests/redraw_throttle_test.c.
 * every turn of E1-E3 (a MIDI encoder can send a thousand a second) used to be one event for the window and one FULL redraw of it, one after the other. a redraw takes longer than the gap between two turns, so the
 * events piled up in the queue and the drawn knob went on turning for a long time after the turning stopped (the value and the sound were right: they do not wait for the window).
 * now the turns are added to the drawn angle at once (an integer add) and the window is drawn again at most every GAP ms, counted from the END of the last draw: while a draw is due, the turns wait in the counter;
 * the last turn always gets its draw (the timer), so the knob ends where the value is. */
#ifndef VERDANDI_REDRAW_THROTTLE_H
#define VERDANDI_REDRAW_THROTTLE_H
#include <stdint.h>

#define RT_GAP_MS 16u /* about 60 frames a second at the most */

typedef struct {
    uint32_t last_end; /* when the last draw ended */
    int has_drawn;     /* 0 until the first draw */
    int pending;       /* a timer is on its way: the turns since are drawn when it fires */
} rt_state;

typedef enum { RT_DRAW_NOW, RT_SCHEDULE, RT_WAIT } rt_action;

/* a turn arrived at `now`. RT_DRAW_NOW: draw (then call rt_drawn). RT_SCHEDULE: start a timer of *delay ms (then rt_fired when it comes). RT_WAIT: a timer is on its way already */
static inline rt_action rt_request(rt_state *s, uint32_t now, uint32_t *delay) {
    if (s->pending) return RT_WAIT;
    uint32_t since = now - s->last_end;
    if (!s->has_drawn || since >= RT_GAP_MS) return RT_DRAW_NOW;
    s->pending = 1;
    *delay = RT_GAP_MS - since;
    return RT_SCHEDULE;
}
/* the timer fired: the caller draws, then rt_drawn */
static inline void rt_fired(rt_state *s) { s->pending = 0; }
/* a draw ended at `now` */
static inline void rt_drawn(rt_state *s, uint32_t now) { s->last_end = now; s->has_drawn = 1; }
#endif
