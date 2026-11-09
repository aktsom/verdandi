/* matron/src/platform/windows/jack_null: the JACK-compatible null backend that norns.exe uses on Windows (M1). portable C, so it runs here on Linux without libjack.
 * build: gcc -std=gnu11 -I matron/src/platform/windows/jack_null/include linux/tests/jack_null_test.c matron/src/platform/windows/jack_null/jack_null.c -lpthread -o t */
#include <jack/jack.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

unsigned verdandi_jack_null_ticks(void);
unsigned verdandi_jack_null_xruns(void);
unsigned verdandi_jack_null_frames(void);

static int fails;
#define CHECK(c, ...)                                                                                                                                          \
    do {                                                                                                                                                       \
        if (!(c)) {                                                                                                                                            \
            fails++;                                                                                                                                           \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                                                                        \
            printf(__VA_ARGS__);                                                                                                                               \
            printf("\n");                                                                                                                                      \
        }                                                                                                                                                      \
    } while (0)

static void msleep(int ms) {
    struct timespec ts = {ms / 1000, (long)(ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

/* client A writes a ramp into its output; client B copies its input to its output and counts blocks; client C (not connected) must see silence */
typedef struct {
    jack_port_t *in, *out;
    atomic_int blocks;
    atomic_int saw_ramp;
    atomic_int nonzero_in;
    jack_nframes_t seen_frames;
    int which;
} state_t;

static int cb(jack_nframes_t n, void *arg) {
    state_t *s = arg;
    s->seen_frames = n;
    float *out = s->out ? jack_port_get_buffer(s->out, n) : NULL;
    float *in = s->in ? jack_port_get_buffer(s->in, n) : NULL;
    if (s->which == 0 && out) {
        for (jack_nframes_t i = 0; i < n; i++) {
            out[i] = 0.5f;
        }
    } else if (s->which == 1 && in && out) {
        for (jack_nframes_t i = 0; i < n; i++) {
            out[i] = in[i];
        }
        if (in[0] == 0.5f && in[n - 1] == 0.5f) {
            atomic_store(&s->saw_ramp, 1);
        }
    } else if (s->which == 2 && in) {
        for (jack_nframes_t i = 0; i < n; i++) {
            if (in[i] != 0.f) {
                atomic_store(&s->nonzero_in, 1);
            }
        }
    }
    atomic_fetch_add(&s->blocks, 1);
    return 0;
}

static int xruns_seen;
static int xrun_cb(void *a) {
    (void)a;
    xruns_seen++;
    return 0;
}

int main(void) {
    setenv("VERDANDI_JACK_NULL_RATE", "48000", 1);
    setenv("VERDANDI_JACK_NULL_FRAMES", "128", 1);

    /* ring buffer */
    jack_ringbuffer_t *rb = jack_ringbuffer_create(100);
    CHECK(rb != NULL, "ring buffer created");
    CHECK(jack_ringbuffer_write_space(rb) >= 100, "write space %zu", jack_ringbuffer_write_space(rb));
    CHECK(jack_ringbuffer_read_space(rb) == 0, "empty");
    char msg[64], got[64];
    for (int i = 0; i < 64; i++) {
        msg[i] = (char)(i + 1);
    }
    CHECK(jack_ringbuffer_write(rb, msg, 64) == 64, "wrote 64");
    CHECK(jack_ringbuffer_read_space(rb) == 64, "64 to read");
    CHECK(jack_ringbuffer_read(rb, got, 40) == 40 && memcmp(got, msg, 40) == 0, "read 40 in order");
    CHECK(jack_ringbuffer_write(rb, msg, 64) == 64, "wrote 64 more across the end");
    CHECK(jack_ringbuffer_read_space(rb) == 88, "88 to read, got %zu", jack_ringbuffer_read_space(rb));
    CHECK(jack_ringbuffer_read(rb, got, 24) == 24 && memcmp(got, msg + 40, 24) == 0, "rest of the first write");
    CHECK(jack_ringbuffer_read(rb, got, 64) == 64 && memcmp(got, msg, 64) == 0, "second write after the wrap");
    size_t big = jack_ringbuffer_write_space(rb) + 10;
    char *junk = calloc(1, big);
    CHECK(jack_ringbuffer_write(rb, junk, big) == big - 10, "a write is cut to the free space");
    free(junk);
    jack_ringbuffer_reset(rb);
    CHECK(jack_ringbuffer_read_space(rb) == 0, "reset empties");
    jack_ringbuffer_free(rb);

    /* clients, names, ports */
    jack_status_t st = 0;
    jack_client_t *a = jack_client_open("crone-a", JackNoStartServer, &st);
    CHECK(a && st == 0, "client a, status %d", (int)st);
    jack_client_t *a2 = jack_client_open("crone-a", JackNoStartServer, &st);
    CHECK(a2 && (st & JackNameNotUnique), "second client of the same name is renamed (status %d)", (int)st);
    CHECK(a2 && strcmp(jack_get_client_name(a2), "crone-a") != 0, "unique name %s", a2 ? jack_get_client_name(a2) : "?");
    jack_client_close(a2);
    jack_client_t *b = jack_client_open("crone-b", JackNoStartServer, NULL);
    jack_client_t *c = jack_client_open("crone-c", JackNoStartServer, NULL);
    CHECK(b && c, "clients b and c");
    CHECK(jack_get_sample_rate(a) == 48000, "sample rate %u", jack_get_sample_rate(a));

    state_t sa = {0}, sb = {0}, sc = {0};
    sa.which = 0;
    sb.which = 1;
    sc.which = 2;
    sa.out = jack_port_register(a, "out", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    sb.in = jack_port_register(b, "in", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    sb.out = jack_port_register(b, "out", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    sc.in = jack_port_register(c, "in", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    CHECK(sa.out && sb.in && sb.out && sc.in, "ports registered");
    CHECK(strcmp(jack_port_name(sa.out), "crone-a:out") == 0, "port name %s", jack_port_name(sa.out));
    CHECK(strcmp(jack_port_type(sa.out), JACK_DEFAULT_AUDIO_TYPE) == 0, "port type");
    CHECK(jack_port_by_name(a, "crone-a:out") == sa.out, "port by name");
    CHECK(jack_port_by_name(a, "nope:out") == NULL, "unknown port");

    /* the sound card: physical ports exist (crone connects to them) */
    const char **phys_in = jack_get_ports(a, NULL, NULL, JackPortIsPhysical | JackPortIsOutput);
    const char **phys_out = jack_get_ports(a, NULL, NULL, JackPortIsPhysical | JackPortIsInput);
    CHECK(phys_in && phys_in[0] && phys_in[1] && !phys_in[2], "two physical capture ports");
    CHECK(phys_out && phys_out[0] && phys_out[1] && !phys_out[2], "two physical playback ports");
    CHECK(phys_in && strcmp(phys_in[0], "system:capture_1") == 0, "capture_1 first, got %s", phys_in ? phys_in[0] : "?");
    jack_free(phys_in);
    jack_free(phys_out);
    const char **all_in = jack_get_ports(a, NULL, NULL, JackPortIsInput);
    int n_in = 0;
    while (all_in && all_in[n_in]) {
        n_in++;
    }
    CHECK(n_in == 4, "input ports: system 2 + b + c = 4, got %d", n_in);
    jack_free(all_in);
    CHECK(jack_get_ports(a, "nothing-called-this", NULL, 0) == NULL, "no match gives NULL");

    /* connections */
    CHECK(jack_connect(a, "crone-a:out", "crone-b:in") == 0, "connect a -> b");
    CHECK(jack_connect(a, "crone-a:out", "crone-b:in") != 0, "connecting twice is refused");
    CHECK(jack_connect(a, "crone-b:in", "crone-a:out") != 0, "wrong direction is refused");
    CHECK(jack_connect(a, "crone-a:out", "nope:in") != 0, "unknown port is refused");
    CHECK(jack_connect(a, "crone-b:out", "system:playback_1") == 0, "connect b -> the sound card");
    const char **conns = jack_port_get_all_connections(a, sb.in);
    CHECK(conns && strcmp(conns[0], "crone-a:out") == 0 && conns[1] == NULL, "connections of b:in");
    jack_free(conns);
    CHECK(jack_port_get_all_connections(a, sc.in) == NULL, "no connections gives NULL");

    /* the graph runs: a is registered LAST in client order but feeds b, so b must see a's data in the same block */
    jack_set_process_callback(b, cb, &sb);
    jack_set_process_callback(c, cb, &sc);
    jack_set_process_callback(a, cb, &sa);
    jack_set_xrun_callback(a, xrun_cb, NULL);
    unsigned t0 = verdandi_jack_null_ticks();
    jack_nframes_t f0 = jack_frame_time(a);
    CHECK(jack_activate(b) == 0 && jack_activate(c) == 0 && jack_activate(a) == 0, "activate");
    msleep(500);
    unsigned ticks = verdandi_jack_null_ticks() - t0;
    jack_nframes_t f1 = jack_frame_time(a);
    /* 500 ms at 48000/128 = 187.5 blocks. a loaded CI machine may miss some, never gain any */
    CHECK(ticks >= 100 && ticks <= 200, "blocks in 500 ms: %u (expected about 187)", ticks);
    CHECK(atomic_load(&sa.blocks) == (int)(verdandi_jack_null_ticks() - t0) || abs(atomic_load(&sa.blocks) - (int)ticks) <= 2, "every block calls the callback once (%d vs %u)", atomic_load(&sa.blocks), ticks);
    CHECK(sa.seen_frames == 128, "block size %u", sa.seen_frames);
    CHECK(atomic_load(&sb.saw_ramp) == 1, "b saw a's data in the same block (processing order follows the connections)");
    CHECK(atomic_load(&sc.nonzero_in) == 0, "an unconnected input is silence");
    jack_nframes_t df = f1 - f0;
    CHECK(df >= 22000 && df <= 27000, "frame time advanced %u frames in about 500 ms (24000 expected)", df);
    CHECK(jack_frame_time(a) >= f1, "frame time does not go back");
    float load = jack_cpu_load(a);
    CHECK(load >= 0.f && load < 100.f, "cpu load %.2f", (double)load);

    /* deactivate stops the callback, disconnect stops the sum */
    jack_deactivate(c);
    int cb_c = atomic_load(&sc.blocks);
    msleep(60);
    CHECK(atomic_load(&sc.blocks) == cb_c, "a deactivated client is not called");
    CHECK(jack_disconnect(a, "crone-a:out", "crone-b:in") == 0, "disconnect");
    CHECK(jack_disconnect(a, "crone-a:out", "crone-b:in") != 0, "disconnecting twice fails");
    (void)xruns_seen;

    jack_deactivate(a);
    jack_deactivate(b);
    jack_client_close(c);
    jack_client_close(b);
    jack_client_close(a);
    printf(fails ? "jack_null: %d FAILED\n" : "jack_null: all checks passed\n", fails);
    return fails ? 1 : 0;
}
