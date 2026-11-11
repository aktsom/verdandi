/* audio_bridge_host.c (M2): see audio_bridge_host.h. portable C11 + pthreads (the unit test runs on Linux and under Wine). */
#include "audio_bridge_host.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <time.h>

#include <jack/jack.h>

#include "verdandi_bridge.h"

#ifdef _WIN32
#include <windows.h>
#include <tlhelp32.h>
/* scsynth is a program of its own that must deliver a block every few milliseconds: at the normal priority class any busy program (a browser, a DAW) can make it late, which is a crackle. once it has
 * attached to the bridge its process is raised to the HIGH class (the same user may do this to a process it started; no administrator rights). said once; tried again each second until it worked. */
static int boost_scsynth(void) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        return 0;
    }
    PROCESSENTRY32 pe;
    pe.dwSize = sizeof pe;
    int done = 0;
    for (BOOL ok = Process32First(snap, &pe); ok; ok = Process32Next(snap, &pe)) {
        if (_stricmp(pe.szExeFile, "scsynth.exe") == 0) {
            HANDLE h = OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
            if (h) {
                if (SetPriorityClass(h, HIGH_PRIORITY_CLASS)) {
                    fprintf(stderr, "audio bridge: scsynth.exe (process %lu) runs at the high priority class\n", (unsigned long)pe.th32ProcessID);
                    done = 1;
                }
                CloseHandle(h);
            }
        }
    }
    CloseHandle(snap);
    return done;
}
#endif

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
    volatile unsigned want_lag; /* set by the card's first callback, which may come before the bridge exists: kept here and put into the bridge when it is made */
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

/* crone's ports come a while after this client (crone starts with the window, on a loaded or first start up to tens of seconds later). this thread connects them as soon as they exist and then keeps
 * an eye on them: a connection that is already there (crone or a script made it) counts as done (EEXIST was once taken for a failure: "ports were not found" although engine audio flowed), a connection
 * that goes missing is made again. it says what it does once, never claims a failure before 120 s and never gives up. */
static void *connect_thread(void *arg) {
    (void)arg;
    static const char *pairs[4][2] = {
        {"crone:output_5", "SuperCollider:in_1"},
        {"crone:output_6", "SuperCollider:in_2"},
        {"SuperCollider:out_1", "crone:input_5"},
        {"SuperCollider:out_2", "crone:input_6"},
    };
    int told_wait = 0, told_late = 0, connected = 0;
    time_t t0 = time(NULL);
    while (!atomic_load(&H.stop)) {
        int all = 1;
        for (int i = 0; i < 4; i++) {
            int rc = jack_port_by_name(H.client, pairs[i][0]) && jack_port_by_name(H.client, pairs[i][1]) ? jack_connect(H.client, pairs[i][0], pairs[i][1]) : -1;
            if (rc != 0 && rc != EEXIST) {
                all = 0;
            }
        }
        long waited = (long)(time(NULL) - t0);
        if (all && !connected) {
            connected = 1;
            fprintf(stderr, "audio bridge: crone is connected to the SuperCollider bridge ports%s\n", waited > 0 ? " (after the wait)" : "");
            if (waited > 0) {
                fprintf(stderr, "audio bridge: crone's ports appeared %ld s after the bridge\n", waited);
            }
        } else if (!all && connected) {
            connected = 0; /* made again at the next round, said once more when it works */
            fprintf(stderr, "audio bridge: a connection to crone was lost, making it again\n");
        } else if (!all && !told_wait && waited >= 20) {
            told_wait = 1;
            fprintf(stderr, "audio bridge: still waiting for crone's ports (%ld s); engine audio starts when they exist\n", waited);
        } else if (!all && !told_late && waited >= 120) {
            told_late = 1;
            fprintf(stderr, "audio bridge: crone's ports have not appeared after %ld s: engine audio will not reach the mixer until they do\n", waited);
        }
#ifdef _WIN32
        {
            static int boosted, tries;
            if (!boosted && tries < 120 && H.b.sh && vb_load(&H.b.sh->guest_attached)) {
                tries++;
                boosted = boost_scsynth();
            }
        }
#endif
        struct timespec ts = {0, all ? 1000000000L : 200000000L};
        nanosleep(&ts, NULL);
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
    H.b.lag = H.want_lag; /* (vb_host_create cleared the struct) */
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

void verdandi_bridge_host_set_lag(unsigned blocks) {
    if (blocks < 1) blocks = 1;
    if (blocks > VB_RING - 2) blocks = VB_RING - 2;
    H.want_lag = blocks;
    H.b.lag = blocks;
    H.b.primed = 0; /* a new device: the hold-back is built up again */
}

unsigned verdandi_bridge_host_lag(void) { return H.up ? (H.b.lag ? H.b.lag : 1) : 0; }
unsigned verdandi_bridge_host_raises(void) { return H.up ? H.b.raises : 0; }

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
