#include "clock_midi.h"
#include <clock.h>
#include <stdio.h>

static int clock_midi_counter;
static bool clock_midi_last_tick_time_set;
static double clock_midi_last_tick_time;
static clock_reference_t clock_midi_reference;

#define DURATION_BUFFER_LENGTH 24

static double duration_buf[DURATION_BUFFER_LENGTH] = {0};
static uint8_t beat_duration_buf_pos = 0;
static uint8_t beat_duration_buf_len = 0;

static double mean_scale;
static double mean_sum;

// ticks counted since clock_midi_last_tick_time was set: normally 1; more when several ticks arrive at the same
// instant (a burst: one JACK period, a USB packet) so that their interval can still be measured
static int ticks_since_time = 0;

// transport state. the beat counter is the number of clocks since the song start, minus one before the
// first tick of a run: the next tick counts it up to the position it belongs to.
static bool start_pending;    // start (0xfa) came: the first counted tick tells norns the transport started
static bool continue_pending; // continue (0xfb) came: the first counted tick tells norns it runs again, no reset
static bool spp_valid;        // a song position came and no start, continue or stop used it yet
static int spp_counter;       // the counter that position gives (position * 6 - 1)

void clock_midi_init() {
    clock_midi_counter = 0;
    start_pending = false;
    continue_pending = false;
    spp_valid = false;
    spp_counter = 0;
    clock_midi_last_tick_time_set = false;
    ticks_since_time = 0;
    mean_sum = 0;
    mean_scale = 1;
    // the smoothing buffer starts empty too (init used to leave it as it was: harmless when called once at
    // startup, but a second init, as the tests do, then started with a stale buffer)
    beat_duration_buf_pos = 0;
    beat_duration_buf_len = 0;
    for (int i = 0; i < DURATION_BUFFER_LENGTH; i++) {
        duration_buf[i] = 0;
    }
    clock_reference_init(&clock_midi_reference);
}

// one tick (0xf8) at current_time: the time the tick happened if the source knows it (JACK MIDI: the frame time of
// the event), else the time it was handled
static void clock_midi_handle_clock(double current_time) {
    double beat_duration;

    if (clock_midi_last_tick_time_set == false) {
        clock_midi_last_tick_time_set = true;
        clock_midi_last_tick_time = current_time;
        ticks_since_time = 0;
    } else {
        double dt = current_time - clock_midi_last_tick_time;
        ticks_since_time++;

        if (dt <= 1e-6 && dt >= -1e-6) {
            // ticks with the same time (a burst handled at one instant): they count, the interval is measured
            // when time has moved (an interval of 0 would make the tempo infinite)
            clock_midi_counter++;
        } else {
            beat_duration = dt * 24.0 / ticks_since_time;

            if (beat_duration > 4) { // assume clock stopped
                clock_midi_last_tick_time = current_time;
                ticks_since_time = 0;
                return;
            }
            if (beat_duration_buf_len < DURATION_BUFFER_LENGTH) {
                beat_duration_buf_len++;
                mean_scale = 1.0 / beat_duration_buf_len;
            }

            double a = beat_duration * mean_scale;
            mean_sum = mean_sum + a;
            mean_sum = mean_sum - duration_buf[beat_duration_buf_pos];
            duration_buf[beat_duration_buf_pos] = a;

            beat_duration_buf_pos = (beat_duration_buf_pos + 1) % DURATION_BUFFER_LENGTH;

            clock_midi_counter++;
            clock_midi_last_tick_time = current_time;
            ticks_since_time = 0;
        }

        // a tempo is known once a real interval was measured
        if (beat_duration_buf_len > 0) {
            double reference_beat = clock_midi_counter / 24.0;
            clock_update_source_reference(&clock_midi_reference, reference_beat, mean_sum);
        }

        if (start_pending) {
            start_pending = false;
            clock_start_from_source(CLOCK_SOURCE_MIDI);
        } else if (continue_pending) {
            continue_pending = false;
            clock_continue_from_source(CLOCK_SOURCE_MIDI);
        }
    }
}

static void clock_midi_handle_start() {
    // a song position that came before begins the run there (once); otherwise the song start
    clock_midi_counter = spp_valid ? spp_counter : -1;
    spp_valid = false;
    continue_pending = false;
    start_pending = true;
}

static void clock_midi_handle_continue() {
    // resume where it is (after a song position, there): the counter is not touched
    spp_valid = false;
    if (!start_pending) {
        continue_pending = true;
    }
}

static void clock_midi_handle_stop() {
    // a position sent before the stop is not meant for the next start
    spp_valid = false;
    start_pending = false;
    continue_pending = false;
    clock_stop_from_source(CLOCK_SOURCE_MIDI);
}

void clock_midi_handle_song_position(uint16_t midi_beats) {
    midi_beats &= 0x3fff; // 14 bits
    // the next tick is the one at this position
    spp_counter = (int)midi_beats * 6 - 1;
    spp_valid = true;
    clock_midi_counter = spp_counter;
    // with a tempo known the beat moves at once; without one the next ticks set it
    if (beat_duration_buf_len > 0) {
        clock_update_source_reference(&clock_midi_reference, (spp_counter + 1) / 24.0, mean_sum);
    }
}

void clock_midi_handle_message(uint8_t message) {
    clock_midi_handle_message_at(message, clock_get_system_time());
}

void clock_midi_handle_message_at(uint8_t message, double time) {
    switch (message) {
    case 0xfa:
        clock_midi_handle_start();
        break;
    case 0xf8:
        clock_midi_handle_clock(time);
        break;
    case 0xfb:
        clock_midi_handle_continue();
        break;
    case 0xfc:
        clock_midi_handle_stop();
        break;
    }
}

double clock_midi_get_beat() {
    return clock_get_reference_beat(&clock_midi_reference);
}

double clock_midi_get_tempo() {
    return clock_get_reference_tempo(&clock_midi_reference);
}
