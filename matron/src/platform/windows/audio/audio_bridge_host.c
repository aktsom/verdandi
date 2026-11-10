/* audio_bridge_host.c (M2): see audio_bridge_host.h. portable C11 + pthreads (the unit test runs on Linux and under Wine). */
#include "audio_bridge_host.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include <jack/jack.h>

#include "verdandi_bridge.h"

extern void verdandi_jack_null_loop_breaker(jack_client_t *client);

static struct {
    vb_t b;
    int up;
    jack_client_t *client;
    jack_port_t *in[2], *out[2];
    pthread_t thread;
    atomic_int stop;
    int thread_started;
    unsigned frames;
} H;

static int process(jack_nframes_t n, void *arg) {
    (void)arg;
    if (n != H.frames) {
        return 0;
    }
    float *in1 = jack_port_get_buffer(H.in[0], n), *in2 = jack_port_get_buffer(H.in[1], n);
    float *out1 = jack_port_get_buffer(H.out[0], n), *out2 = jack_port_get_buffer(H.out[1], n);
    vb_host_exchange(&H.b, in1, in2, out1, out2);
    return 0;
}

static void *connect_thread(void *arg) {
    (void)arg;
    static const char *pairs[4][2] = {
        {"crone:output_5", "SuperCollider:in_1"},
        {"crone:output_6", "SuperCollider:in_2"},
        {"SuperCollider:out_1", "crone:input_5"},
        {"SuperCollider:out_2", "crone:input_6"},
    };
    int done[4] = {0, 0, 0, 0};
    for (int tries = 0; tries < 600 && !atomic_load(&H.stop); tries++) { /* up to 60 s: crone starts a moment after this client */
        int all = 1;
        for (int i = 0; i < 4; i++) {
            if (!done[i]) {
                if (jack_port_by_name(H.client, pairs[i][0]) && jack_port_by_name(H.client, pairs[i][1]) && jack_connect(H.client, pairs[i][0], pairs[i][1]) == 0) {
                    done[i] = 1;
                } else {
                    all = 0;
                }
            }
        }
        if (all) {
            fprintf(stderr, "audio bridge: crone is connected to the SuperCollider bridge ports\n");
            return NULL;
        }
        struct timespec ts = {0, 100000000L};
        nanosleep(&ts, NULL);
    }
    if (!atomic_load(&H.stop)) {
        fprintf(stderr, "audio bridge: crone's ports were not found, engine audio will not reach the mixer\n");
    }
    return NULL;
}

int verdandi_bridge_host_start(const char *name, unsigned rate, unsigned frames) {
    if (H.up) {
        return 0;
    }
    int rc = vb_host_create(&H.b, name, rate, frames);
    if (rc != 0) {
        fprintf(stderr, "audio bridge: cannot create '%s' (%d): scsynth will run on its own silent clock\n", name, rc);
        return -1;
    }
    H.frames = frames;
    jack_status_t st;
    H.client = jack_client_open("SuperCollider", JackNoStartServer, &st);
    if (!H.client) {
        vb_close(&H.b);
        return -1;
    }
    H.in[0] = jack_port_register(H.client, "in_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    H.in[1] = jack_port_register(H.client, "in_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    H.out[0] = jack_port_register(H.client, "out_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    H.out[1] = jack_port_register(H.client, "out_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(H.client, process, NULL);
    verdandi_jack_null_loop_breaker(H.client);
    atomic_store(&H.stop, 0);
    H.up = 1;
    if (jack_activate(H.client) != 0) {
        verdandi_bridge_host_stop();
        return -1;
    }
    H.thread_started = pthread_create(&H.thread, NULL, connect_thread, NULL) == 0;
    fprintf(stderr, "audio bridge: '%s' ready, %u Hz, %u frames per block\n", name, rate, frames);
    return 0;
}

void verdandi_bridge_host_stop(void) {
    if (!H.up) {
        return;
    }
    atomic_store(&H.stop, 1);
    if (H.thread_started) {
        pthread_join(H.thread, NULL);
        H.thread_started = 0;
    }
    if (H.client) {
        jack_deactivate(H.client);
    }
    vb_close(&H.b);
    H.up = 0;
}

void verdandi_bridge_host_stats(unsigned long long *to_sc, unsigned long long *from_sc, unsigned long long *underruns, unsigned long long *drops, int *attached) {
    unsigned long long a = 0, b = 0, u = 0, d = 0;
    int att = 0;
    if (H.up && H.b.sh) {
        a = vb_load(&H.b.sh->to_w);
        b = vb_load(&H.b.sh->from_r);
        u = vb_load(&H.b.sh->host_underruns);
        d = vb_load(&H.b.sh->host_drops);
        att = (int)vb_load(&H.b.sh->guest_attached);
    }
    if (to_sc) *to_sc = a;
    if (from_sc) *from_sc = b;
    if (underruns) *underruns = u;
    if (drops) *drops = d;
    if (attached) *attached = att;
}
