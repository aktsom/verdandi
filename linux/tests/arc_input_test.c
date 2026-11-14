/*
 * arc_input_test.c: what the mouse does to a ring of the virtual arc window (matron/src/platform/linux/arc_input.h, the same code on Linux and Windows):
 * (the up and down drag is at the end of main) a wheel notch is 2 ticks, a full turn of the pointer round a ring 256 ticks (a quarter of the hardware's 1024), Shift a quarter of that and Super four times, the direction flag of the system
 * flips the wheel, the angle goes the short way past the left edge of the circle, fractions of a tick are kept per ring and only whole ticks go out (the sum is exact).
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "arc_input.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL " __VA_ARGS__);                                                                               \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

// a drag the way the window does it: the pointer goes round a ring in steps of 3 degrees (a wheel at a time, a click and a move per step), the angle taken with atan2 as arc_angle_at does
static int drag(double degrees, double factor, double *acc) {
    double step = (degrees < 0 ? -3.0 : 3.0) * M_PI / 180, a = -M_PI / 2, last = a;
    int sent = 0, steps = (int)(fabs(degrees) / 3 + 0.5);
    for (int i = 1; i <= steps; i++) {
        a = -M_PI / 2 + i * step;
        double now = atan2(sin(a), cos(a)); // what atan2 of the pointer's position gives: -pi to pi
        sent += arc_input_take(acc, arc_input_drag_ticks(arc_input_angle_step(now, atan2(sin(last), cos(last))), factor));
        last = a;
    }
    return sent;
}

int main(void) {
    CHECK(ARC_TICKS_PER_TURN == 1024.0, "1024 ticks to a turn, as the hardware");
    CHECK(ARC_WHEEL_TICKS == 2 && ARC_DRAG_GEAR == 0.25, "wheel 2 ticks, drag gear a quarter");

    // the wheel
    double acc = 0;
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(1, 0, 1)) == 2, "one notch up is +2");
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(-1, 0, 1)) == -2, "one notch down is -2");
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(1, 1, 1)) == -2, "a flipped wheel (the system's natural scrolling) goes the other way");
    // a trackpad scrolls in fractions: 0.3 of a notch is 0.6 tick: nothing yet, and then the carry makes it whole
    acc = 0;
    int sum = 0;
    for (int i = 0; i < 10; i++) {
        sum += arc_input_take(&acc, arc_input_wheel_ticks(0.3, 0, 1));
    }
    // (floating point may hold the last tick back by a hair: it is never lost, it comes with the next move)
    CHECK(fabs(sum + acc - 6.0) < 1e-9 && sum >= 5, "ten trackpad fractions of 0.3 notch make 6 ticks, nothing lost (sent %d, kept %g)", sum, acc);
    // Shift is a quarter, Super four times
    acc = 0;
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(1, 0, 0.25)) == 0, "Shift: one notch is half a tick, none yet");
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(1, 0, 0.25)) == 1, "Shift: two notches are one tick");
    acc = 0;
    CHECK(arc_input_take(&acc, arc_input_wheel_ticks(1, 0, 4)) == 8, "Super: one notch is 8 ticks");
    // negative fractions carry toward zero too
    acc = 0;
    sum = 0;
    for (int i = 0; i < 7; i++) {
        sum += arc_input_take(&acc, -0.5);
    }
    CHECK(sum == -3 && fabs(acc + 0.5) < 1e-9, "seven times -0.5 is -3 and -0.5 stays (sum %d, left %g)", sum, acc);

    // the angle: the short way past the edge of the atan2 range
    CHECK(fabs(arc_input_angle_step(-3.1, 3.1) - (2 * M_PI - 6.2)) < 1e-9, "from 3.1 to -3.1 is a small step forward, not a jump of 6.2 back");
    CHECK(fabs(arc_input_angle_step(3.1, -3.1) + (2 * M_PI - 6.2)) < 1e-9, "and the other way round");
    CHECK(fabs(arc_input_angle_step(0.5, 0.2) - 0.3) < 1e-9, "an ordinary step");

    // a drag: a full turn of the pointer is 256 ticks, a quarter turn 64, backwards negative
    acc = 0;
    int full = drag(360, 1, &acc);
    CHECK(abs(full - 256) <= 1, "a full turn round the ring is 256 ticks (got %d)", full);
    acc = 0;
    CHECK(abs(drag(90, 1, &acc) - 64) <= 1, "a quarter turn is 64 ticks");
    acc = 0;
    CHECK(abs(drag(-90, 1, &acc) + 64) <= 1, "a quarter turn backwards is -64");
    acc = 0;
    CHECK(abs(drag(360, 0.25, &acc) - 64) <= 1, "Shift: a full turn is 64 ticks");
    acc = 0;
    CHECK(abs(drag(90, 4, &acc) - 256) <= 1, "Super: a quarter turn is 256 ticks");
    acc = 0;
    int two = drag(720, 1, &acc);
    CHECK(abs(two - 512) <= 2, "two turns, past the edge of the angle twice, are 512 ticks (got %d)", two);
    // one degree: 256/360 of a tick: nothing for one step, but the small moves add up
    acc = 0;
    sum = 0;
    for (int i = 0; i < 360; i++) {
        sum += arc_input_take(&acc, arc_input_drag_ticks(M_PI / 180, 1));
    }
    CHECK(abs(sum - 256) <= 1, "360 steps of one degree are 256 ticks (got %d)", sum);

    CHECK(ARC_DRAG_DEAD_ZONE == 8, "the pointer near the centre waits");

    // ---- the up and down drag (ARC DRAG = UP/DOWN): the pointer moves in steps of 3 pixels, as motion events come; `unit` is the pixels of one window unit (1 at 1:1, 2 on a 200 percent screen)
    CHECK(ARC_DRAG_CIRCLE == 0 && ARC_DRAG_UPDOWN == 1 && ARC_UD_TICKS_PER_UNIT == 12.0, "drag modes and the number of ticks a unit");
    {
        double lap_units = ARC_TICKS_PER_TURN / ARC_UD_TICKS_PER_UNIT, window_h = 260;
        CHECK(fabs(lap_units / window_h - 1.0 / 3) < 0.01, "one lap of 1024 ticks is a third of the arc window's height (%.1f units of 260 = %.1f percent)", lap_units, 100 * lap_units / window_h);
    }
    // the pointer from y0 to y1 in steps of `step` pixels, each step one call; returns the whole ticks sent
    #define UD(y0, y1, step, unit, factor, accp)                                                                        \
        ({                                                                                                              \
            double last = (y0), y = (y0);                                                                               \
            int sent_ = 0, n_ = (int)(fabs((double)(y1) - (y0)) / (step) + 0.5);                                        \
            for (int i_ = 0; i_ < n_; i_++) {                                                                           \
                y += ((y1) > (y0) ? 1.0 : -1.0) * (step);                                                               \
                sent_ += arc_input_take(accp, arc_input_ud_ticks(&last, y, unit, factor));                              \
            }                                                                                                           \
            sent_;                                                                                                      \
        })
    acc = 0;
    int up = UD(200.0, 200.0 - 260.0 / 3, 1.0, 1.0, 1.0, &acc); // up by a third of the window height (86 pixels)
    CHECK(abs(up - 1032) <= 12 && up > 0, "up by a third of the height (86 px) turns clockwise by about one lap: %d ticks (1024 for 85.3 px)", up);
    acc = 0;
    int down = UD(100.0, 100.0 + 260.0 / 3, 1.0, 1.0, 1.0, &acc);
    CHECK(down == -up, "down by the same distance turns counter-clockwise by the same number: %d and %d", down, up);
    acc = 0;
    CHECK(UD(200.0, 200.0 - 85.0, 1.0, 1.0, 1.0, &acc) == 1020 && UD(200.0, 115.0, 1.0, 1.0, 1.0, &acc) == 1020, "85 pixels are 1020 ticks, whatever the carry");
    acc = 0;
    CHECK(UD(150.0, 149.0, 1.0, 1.0, 1.0, &acc) == 12, "one pixel up is 12 ticks, one pixel down -12");
    acc = 0;
    CHECK(UD(150.0, 151.0, 1.0, 1.0, 1.0, &acc) == -12, "one pixel down is -12");
    acc = 0;
    CHECK(abs(UD(200.0, 114.0, 1.0, 1.0, 0.25, &acc) - 258) <= 4, "Shift: the same drag is a quarter, about 258 ticks");
    acc = 0;
    CHECK(abs(UD(200.0, 200.0 - 20.0, 1.0, 1.0, 4.0, &acc) - 960) <= 4, "Ctrl: four times: 20 px are 960 ticks");
    acc = 0;
    CHECK(abs(UD(200.0, 200.0 - 170.0, 2.0, 2.0, 1.0, &acc) - 1020) <= 12, "a 200 percent screen (2 pixels a unit): 170 pixels are the same 85 units, 1020 ticks");
    // the size does not depend on the size of the steps (mouse speed): the same distance in 1 and in 17 pixel steps
    acc = 0;
    int a1 = UD(300.0, 214.0, 1.0, 1.0, 1.0, &acc);
    acc = 0;
    double last = 300, y = 214;
    int a2 = arc_input_take(&acc, arc_input_ud_ticks(&last, y, 1.0, 1.0));
    CHECK(a1 == a2 && a1 == 1032, "86 px in one jump or in 86 steps: the same (%d, %d)", a1, a2);
    // out of the window: y below 0 and far below the bottom still count (the drag is captured); nothing jumps when the pointer comes back
    acc = 0;
    last = 20;
    double t = 0;
    t += arc_input_ud_ticks(&last, -30, 1.0, 1.0);  // above the window: 50 pixels up
    t += arc_input_ud_ticks(&last, -400, 1.0, 1.0); // far above
    t += arc_input_ud_ticks(&last, 600, 1.0, 1.0);  // the other way, below the window
    CHECK(fabs(t - ((20 - (-30)) + (-30 - -400) + (-400 - 600)) * 12.0) < 1e-6 && last == 600, "outside the window the pointer is followed (%g ticks)", t);
    // no motion, no turn; a motion sideways is nothing (only y is looked at)
    last = 100;
    CHECK(arc_input_ud_ticks(&last, 100, 1.0, 1.0) == 0, "no move, no ticks");
    // a pointer that goes up then down by the same amount is back where it was
    acc = 0;
    last = 100;
    int s2 = arc_input_take(&acc, arc_input_ud_ticks(&last, 60, 1.0, 1.0)) + arc_input_take(&acc, arc_input_ud_ticks(&last, 100, 1.0, 1.0));
    CHECK(s2 == 0, "up 40 and down 40 is nothing");
    // a unit of 0 (no geometry yet) does not divide by zero
    last = 10;
    CHECK(isfinite(arc_input_ud_ticks(&last, 0, 0, 1.0)), "a unit of 0 is taken as 1");

    if (fails) {
        printf("arc_input_test: %d FAILED\n", fails);
        return 1;
    }
    printf("arc_input_test: ok\n");
    return 0;
}
