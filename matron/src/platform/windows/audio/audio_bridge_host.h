/* audio_bridge_host.h (M2): norns.exe's side of the audio bridge as a JACK client of the null backend named "SuperCollider", with the ports sclang's jack_connect lines wire on Linux. */
#ifndef VERDANDI_AUDIO_BRIDGE_HOST_H
#define VERDANDI_AUDIO_BRIDGE_HOST_H
#ifdef __cplusplus
extern "C" {
#endif

/* creates the shared memory `name` and the client; a helper thread connects crone:output_5/6 -> SuperCollider:in_1/2 and SuperCollider:out_1/2 -> crone:input_5/6 as soon as crone's ports exist.
 * 0 = ok. rate and frames must be the ones of the audio (jack_null) */
int verdandi_bridge_host_start(const char *name, unsigned rate, unsigned frames);
void verdandi_bridge_host_stop(void);
/* how many blocks of scsynth's answers are held back (1 to 6): the number of engine blocks that run in one callback of the sound card. safe to call from the card's callback */
void verdandi_bridge_host_set_lag(unsigned blocks);
/* tuning (tests): blocks after scsynth's first answer during which underruns do not raise the hold-back, and quiet blocks after which a raised hold-back goes down by one. 0 = the defaults (15 s, 60 s) */
void verdandi_bridge_host_tune(unsigned grace_blocks, unsigned decay_blocks);
/* the hold-back now (it may have grown by itself) */
unsigned verdandi_bridge_host_lag(void);
/* how often the hold-back grew by itself because underruns came close together */
unsigned verdandi_bridge_host_raises(void);
/* counters: blocks handed to scsynth, blocks taken from it, underruns, drops, scsynth attached */
void verdandi_bridge_host_stats(unsigned long long *to_sc, unsigned long long *from_sc, unsigned long long *underruns, unsigned long long *drops, int *attached);

/* the underruns since the last call, one record each (the card's callback writes them, a logging thread reads them; 64 are kept: if more came since, `lost` says how many were not kept) */
typedef struct {
    unsigned long long call, tick_us, guest_blocks, drops, underruns;
    unsigned pending, answers, lag, attached;
} verdandi_bridge_event;
int verdandi_bridge_host_events(unsigned long long *cursor, verdandi_bridge_event *out, int max, unsigned long long *lost);
/* a monotonic clock in microseconds, the one the events use */
unsigned long long verdandi_bridge_now_us(void);

#ifdef __cplusplus
}
#endif
#endif
