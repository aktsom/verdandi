/*
 * jack_null.c: a JACK-compatible NULL backend for Windows (M1). see include/jack/jack.h. no audio device: a timer thread runs the process callbacks of the
 * activated clients once per block, so crone's mixer and softcut run for real, on silence. portable C11 + pthreads; on Linux it is only used by its unit test
 * (linux/tests/jack_null_test.c), on Windows it is compiled into norns.exe in place of libjack.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <jack/jack.h>

#ifdef _WIN32
#include <windows.h>

#include <mmsystem.h> /* timeBeginPeriod (link winmm) */
#endif

#define MAX_FRAMES 4096
#define MAX_CLIENTS 64
#define MAX_PORTS 512
#define MAX_CONNS 2048

struct _jack_port {
    char name[192]; /* "client:port" */
    char type[40];
    int flags;
    int is_audio;
    struct _jack_client *owner;
    float buf[MAX_FRAMES];
};

struct _jack_client {
    char name[64];
    int active;
    int depth;
    JackProcessCallback process;
    void *process_arg;
    JackShutdownCallback shutdown_cb;
    void *shutdown_arg;
    JackXRunCallback xrun_cb;
    void *xrun_arg;
    JackPortRegistrationCallback portreg_cb;
    void *portreg_arg;
    JackClientRegistrationCallback clientreg_cb;
    void *clientreg_arg;
    int loop_breaker; /* its output is read one block late: the connections it feeds do not count for the processing order (a feedback loop) */
};

struct conn {
    struct _jack_port *src, *dst;
};

static struct {
    pthread_mutex_t lock;
    struct _jack_client *clients[MAX_CLIENTS];
    int nclients;
    struct _jack_port *ports[MAX_PORTS];
    int nports;
    struct conn conns[MAX_CONNS];
    int nconns;
    int inited;
    unsigned rate;
    unsigned frames;
    int64_t start_ns;
    pthread_t thread;
    int thread_running;
    atomic_int stop;
    atomic_uint last_frame; /* frame time at the start of the last block */
    _Atomic double cpu;     /* percent of the block period spent in the callbacks, smoothed */
    atomic_uint ticks;
    atomic_uint xruns;
    int external;          /* M2: a sound card callback runs the blocks (verdandi_jack_null_process), there is no clock thread */
    unsigned pre_rate;     /* verdandi_jack_null_configure, used by init_locked instead of the environment */
    unsigned pre_frames;
} G = {.lock = PTHREAD_MUTEX_INITIALIZER};

static int64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void sleep_until_ns(int64_t target) {
#ifdef _WIN32
    static HANDLE timer;
    static int tried;
    if (!tried) {
        tried = 1;
        /* CREATE_WAITABLE_TIMER_HIGH_RESOLUTION (0x2): Windows 10 1803 and later. otherwise a normal timer with a 1 ms system resolution */
        timer = CreateWaitableTimerExW(NULL, NULL, 0x2, TIMER_ALL_ACCESS);
        if (!timer) {
            timeBeginPeriod(1);
            timer = CreateWaitableTimerW(NULL, FALSE, NULL);
        }
    }
    int64_t d = target - now_ns();
    if (d <= 0) {
        return;
    }
    if (timer) {
        LARGE_INTEGER due;
        due.QuadPart = -(d / 100);
        if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
            WaitForSingleObject(timer, INFINITE);
            return;
        }
    }
    Sleep((DWORD)(d / 1000000));
#else
    struct timespec ts;
    ts.tv_sec = target / 1000000000LL;
    ts.tv_nsec = target % 1000000000LL;
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR) {
    }
#endif
}

static unsigned env_uint(const char *name, unsigned def, unsigned lo, unsigned hi) {
    const char *e = getenv(name);
    if (e && *e) {
        long v = strtol(e, NULL, 10);
        if (v >= (long)lo && v <= (long)hi) {
            return (unsigned)v;
        }
    }
    return def;
}

static struct _jack_port *new_port_locked(struct _jack_client *c, const char *short_name, const char *type, int flags) {
    if (G.nports >= MAX_PORTS) {
        return NULL;
    }
    struct _jack_port *p = calloc(1, sizeof *p);
    if (!p) {
        return NULL;
    }
    snprintf(p->name, sizeof p->name, "%s:%s", c->name, short_name);
    snprintf(p->type, sizeof p->type, "%s", type);
    p->flags = flags;
    p->is_audio = strcmp(type, JACK_DEFAULT_AUDIO_TYPE) == 0;
    p->owner = c;
    G.ports[G.nports++] = p;
    return p;
}

static struct _jack_client *new_client_locked(const char *name) {
    if (G.nclients >= MAX_CLIENTS) {
        return NULL;
    }
    struct _jack_client *c = calloc(1, sizeof *c);
    if (!c) {
        return NULL;
    }
    snprintf(c->name, sizeof c->name, "%s", name);
    G.clients[G.nclients++] = c;
    return c;
}

static int client_exists_locked(const char *name) {
    for (int i = 0; i < G.nclients; i++) {
        if (strcmp(G.clients[i]->name, name) == 0) {
            return 1;
        }
    }
    return 0;
}

static void init_locked(void) {
    if (G.inited) {
        return;
    }
    G.inited = 1;
    G.rate = G.pre_rate ? G.pre_rate : env_uint("VERDANDI_JACK_NULL_RATE", 48000, 8000, 192000);
    G.frames = G.pre_frames ? G.pre_frames : env_uint("VERDANDI_JACK_NULL_FRAMES", 128, 16, MAX_FRAMES);
    G.start_ns = now_ns();
    /* the sound card: two physical capture ports (they carry silence) and two physical playback ports (what is written to them is dropped) */
    struct _jack_client *sys = new_client_locked("system");
    new_port_locked(sys, "capture_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput | JackPortIsPhysical | JackPortIsTerminal);
    new_port_locked(sys, "capture_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput | JackPortIsPhysical | JackPortIsTerminal);
    new_port_locked(sys, "playback_1", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput | JackPortIsPhysical | JackPortIsTerminal);
    new_port_locked(sys, "playback_2", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput | JackPortIsPhysical | JackPortIsTerminal);
}

/* processing order: a client runs after the clients that feed it */
static void compute_order_locked(void) {
    for (int i = 0; i < G.nclients; i++) {
        G.clients[i]->depth = 0;
    }
    for (int pass = 0; pass < G.nclients; pass++) {
        int changed = 0;
        for (int k = 0; k < G.nconns; k++) {
            struct _jack_client *s = G.conns[k].src->owner, *d = G.conns[k].dst->owner;
            if (s != d && !s->loop_breaker && d->depth < s->depth + 1 && s->depth < G.nclients) {
                d->depth = s->depth + 1;
                changed = 1;
            }
        }
        if (!changed) {
            break;
        }
    }
}

static void run_block_locked(void) {
    unsigned n = G.frames;
    int maxdepth = 0;
    for (int i = 0; i < G.nclients; i++) {
        if (G.clients[i]->depth > maxdepth) {
            maxdepth = G.clients[i]->depth;
        }
    }
    for (int depth = 0; depth <= maxdepth; depth++) {
        for (int i = 0; i < G.nclients; i++) {
            struct _jack_client *c = G.clients[i];
            if (c->depth != depth || !c->active || !c->process) {
                continue;
            }
            /* inputs: the sum of what is connected, silence when nothing is */
            for (int pi = 0; pi < G.nports; pi++) {
                struct _jack_port *p = G.ports[pi];
                if (p->owner != c || !(p->flags & JackPortIsInput) || !p->is_audio) {
                    continue;
                }
                memset(p->buf, 0, n * sizeof(float));
                for (int k = 0; k < G.nconns; k++) {
                    if (G.conns[k].dst == p) {
                        const float *s = G.conns[k].src->buf;
                        for (unsigned j = 0; j < n; j++) {
                            p->buf[j] += s[j];
                        }
                    }
                }
            }
            c->process(n, c->process_arg);
        }
    }
}

static void *clock_thread(void *arg) {
    (void)arg;
#ifdef _WIN32
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
#endif
    uint64_t n = 0;
    int64_t period = (int64_t)((double)G.frames * 1e9 / (double)G.rate);
    int64_t t0 = now_ns();
    while (!atomic_load(&G.stop)) {
        n++;
        int64_t target = t0 + (int64_t)n * period;
        sleep_until_ns(target);
        if (atomic_load(&G.stop)) {
            break;
        }
        int64_t begin = now_ns();
        int64_t late = begin - target;
        pthread_mutex_lock(&G.lock);
        if (late > period) {
            /* a missed block: count it, tell the clients, and do not try to catch up */
            atomic_fetch_add(&G.xruns, 1);
            for (int i = 0; i < G.nclients; i++) {
                if (G.clients[i]->active && G.clients[i]->xrun_cb) {
                    G.clients[i]->xrun_cb(G.clients[i]->xrun_arg);
                }
            }
            t0 += (late / period) * period;
        }
        compute_order_locked();
        atomic_store(&G.last_frame, (unsigned)((uint64_t)(begin - G.start_ns) * G.rate / 1000000000ULL));
        run_block_locked();
        pthread_mutex_unlock(&G.lock);
        double used = 100.0 * (double)(now_ns() - begin) / (double)period;
        double c = atomic_load(&G.cpu);
        atomic_store(&G.cpu, c + 0.1 * (used - c));
        atomic_fetch_add(&G.ticks, 1);
    }
    return NULL;
}

/* ---- clients ---- */

jack_client_t *jack_client_open(const char *client_name, jack_options_t options, jack_status_t *status, ...) {
    (void)options;
    pthread_mutex_lock(&G.lock);
    init_locked();
    char name[64];
    snprintf(name, sizeof name, "%s", client_name ? client_name : "client");
    jack_status_t st = 0;
    if (client_exists_locked(name)) {
        size_t len = strlen(name);
        if (len > sizeof name - 8) {
            name[sizeof name - 8] = 0;
        }
        for (int i = 1; i < 100; i++) {
            char cand[80];
            snprintf(cand, sizeof cand, "%s-%02d", name, i);
            if (!client_exists_locked(cand)) {
                snprintf(name, sizeof name, "%.63s", cand);
                break;
            }
        }
        st |= JackNameNotUnique;
    }
    struct _jack_client *c = new_client_locked(name);
    if (!c) {
        st |= JackFailure;
    }
    pthread_mutex_unlock(&G.lock);
    if (status) {
        *status = st;
    }
    return c;
}

int jack_client_close(jack_client_t *client) {
    if (!client) {
        return -1;
    }
    pthread_mutex_lock(&G.lock);
    client->active = 0;
    /* ports and connections of this client */
    for (int i = 0; i < G.nconns;) {
        if (G.conns[i].src->owner == client || G.conns[i].dst->owner == client) {
            G.conns[i] = G.conns[--G.nconns];
        } else {
            i++;
        }
    }
    for (int i = 0; i < G.nports;) {
        if (G.ports[i]->owner == client) {
            free(G.ports[i]);
            G.ports[i] = G.ports[--G.nports];
        } else {
            i++;
        }
    }
    for (int i = 0; i < G.nclients; i++) {
        if (G.clients[i] == client) {
            G.clients[i] = G.clients[--G.nclients];
            break;
        }
    }
    free(client);
    pthread_mutex_unlock(&G.lock);
    return 0;
}

int jack_activate(jack_client_t *client) {
    if (!client) {
        return -1;
    }
    pthread_mutex_lock(&G.lock);
    client->active = 1;
    int start = !G.thread_running && !G.external;
    if (start) {
        G.thread_running = 1;
        atomic_store(&G.stop, 0);
    }
    pthread_mutex_unlock(&G.lock);
    if (start && pthread_create(&G.thread, NULL, clock_thread, NULL) != 0) {
        G.thread_running = 0;
        return -1;
    }
    return 0;
}

int jack_deactivate(jack_client_t *client) {
    if (!client) {
        return -1;
    }
    pthread_mutex_lock(&G.lock);
    client->active = 0;
    pthread_mutex_unlock(&G.lock);
    return 0;
}

const char *jack_get_client_name(jack_client_t *client) { return client ? client->name : NULL; }

jack_nframes_t jack_get_sample_rate(jack_client_t *client) {
    (void)client;
    return G.rate;
}

int jack_set_process_callback(jack_client_t *c, JackProcessCallback cb, void *arg) {
    pthread_mutex_lock(&G.lock);
    c->process = cb;
    c->process_arg = arg;
    pthread_mutex_unlock(&G.lock);
    return 0;
}
void jack_on_shutdown(jack_client_t *c, JackShutdownCallback cb, void *arg) {
    c->shutdown_cb = cb;
    c->shutdown_arg = arg;
}
int jack_set_xrun_callback(jack_client_t *c, JackXRunCallback cb, void *arg) {
    pthread_mutex_lock(&G.lock);
    c->xrun_cb = cb;
    c->xrun_arg = arg;
    pthread_mutex_unlock(&G.lock);
    return 0;
}
int jack_set_port_registration_callback(jack_client_t *c, JackPortRegistrationCallback cb, void *arg) {
    c->portreg_cb = cb;
    c->portreg_arg = arg;
    return 0;
}
int jack_set_client_registration_callback(jack_client_t *c, JackClientRegistrationCallback cb, void *arg) {
    c->clientreg_cb = cb;
    c->clientreg_arg = arg;
    return 0;
}

/* ---- ports ---- */

jack_port_t *jack_port_register(jack_client_t *client, const char *port_name, const char *port_type, unsigned long flags, unsigned long buffer_size) {
    (void)buffer_size;
    pthread_mutex_lock(&G.lock);
    struct _jack_port *p = new_port_locked(client, port_name, port_type, (int)flags);
    pthread_mutex_unlock(&G.lock);
    return p;
}

void *jack_port_get_buffer(jack_port_t *port, jack_nframes_t nframes) {
    (void)nframes;
    return port ? port->buf : NULL;
}
const char *jack_port_name(const jack_port_t *port) { return port ? port->name : NULL; }
const char *jack_port_type(const jack_port_t *port) { return port ? port->type : NULL; }
int jack_port_flags(const jack_port_t *port) { return port ? port->flags : 0; }

static struct _jack_port *find_port_locked(const char *name) {
    for (int i = 0; i < G.nports; i++) {
        if (strcmp(G.ports[i]->name, name) == 0) {
            return G.ports[i];
        }
    }
    return NULL;
}

jack_port_t *jack_port_by_name(jack_client_t *client, const char *port_name) {
    (void)client;
    pthread_mutex_lock(&G.lock);
    struct _jack_port *p = port_name ? find_port_locked(port_name) : NULL;
    pthread_mutex_unlock(&G.lock);
    return p;
}

/* a NULL-terminated array of strings in ONE allocation (jack_free frees it) */
static const char **make_list(const char **names, int n) {
    if (n == 0) {
        return NULL;
    }
    size_t bytes = (size_t)(n + 1) * sizeof(char *);
    for (int i = 0; i < n; i++) {
        bytes += strlen(names[i]) + 1;
    }
    char **list = malloc(bytes);
    if (!list) {
        return NULL;
    }
    char *s = (char *)(list + n + 1);
    for (int i = 0; i < n; i++) {
        list[i] = s;
        size_t l = strlen(names[i]) + 1;
        memcpy(s, names[i], l);
        s += l;
    }
    list[n] = NULL;
    return (const char **)list;
}

const char **jack_get_ports(jack_client_t *client, const char *port_name_pattern, const char *type_name_pattern, unsigned long flags) {
    (void)client;
    const char *names[MAX_PORTS];
    int n = 0;
    pthread_mutex_lock(&G.lock);
    for (int i = 0; i < G.nports; i++) {
        struct _jack_port *p = G.ports[i];
        if (((unsigned long)p->flags & flags) != flags) {
            continue;
        }
        if (port_name_pattern && *port_name_pattern && !strstr(p->name, port_name_pattern)) {
            continue;
        }
        if (type_name_pattern && *type_name_pattern && !strstr(p->type, type_name_pattern)) {
            continue;
        }
        names[n++] = p->name;
    }
    const char **list = make_list(names, n);
    pthread_mutex_unlock(&G.lock);
    return list;
}

const char **jack_port_get_all_connections(const jack_client_t *client, const jack_port_t *port) {
    (void)client;
    const char *names[MAX_CONNS];
    int n = 0;
    pthread_mutex_lock(&G.lock);
    for (int k = 0; k < G.nconns && n < MAX_CONNS; k++) {
        if (G.conns[k].src == port) {
            names[n++] = G.conns[k].dst->name;
        } else if (G.conns[k].dst == port) {
            names[n++] = G.conns[k].src->name;
        }
    }
    const char **list = make_list(names, n);
    pthread_mutex_unlock(&G.lock);
    return list;
}

void jack_free(void *ptr) { free(ptr); }

int jack_connect(jack_client_t *client, const char *source_port, const char *destination_port) {
    (void)client;
    int rc = 0;
    pthread_mutex_lock(&G.lock);
    struct _jack_port *s = source_port ? find_port_locked(source_port) : NULL;
    struct _jack_port *d = destination_port ? find_port_locked(destination_port) : NULL;
    if (!s || !d || !(s->flags & JackPortIsOutput) || !(d->flags & JackPortIsInput) || strcmp(s->type, d->type) != 0) {
        rc = ENOENT;
    } else {
        for (int k = 0; k < G.nconns; k++) {
            if (G.conns[k].src == s && G.conns[k].dst == d) {
                rc = EEXIST;
            }
        }
        if (rc == 0) {
            if (G.nconns >= MAX_CONNS) {
                rc = ENOMEM;
            } else {
                G.conns[G.nconns].src = s;
                G.conns[G.nconns].dst = d;
                G.nconns++;
            }
        }
    }
    pthread_mutex_unlock(&G.lock);
    return rc;
}

int jack_disconnect(jack_client_t *client, const char *source_port, const char *destination_port) {
    (void)client;
    int rc = ENOENT;
    pthread_mutex_lock(&G.lock);
    struct _jack_port *s = source_port ? find_port_locked(source_port) : NULL;
    struct _jack_port *d = destination_port ? find_port_locked(destination_port) : NULL;
    for (int k = 0; s && d && k < G.nconns; k++) {
        if (G.conns[k].src == s && G.conns[k].dst == d) {
            G.conns[k] = G.conns[--G.nconns];
            rc = 0;
            break;
        }
    }
    pthread_mutex_unlock(&G.lock);
    return rc;
}

/* ---- time and load ---- */

float jack_cpu_load(jack_client_t *client) {
    (void)client;
    return (float)atomic_load(&G.cpu);
}

jack_nframes_t jack_frame_time(const jack_client_t *client) {
    (void)client;
    /* the frame time follows the wall clock, not the blocks: matron reads it at any moment */
    if (!G.inited) {
        return 0;
    }
    return (jack_nframes_t)((uint64_t)(now_ns() - G.start_ns) * G.rate / 1000000000ULL);
}

jack_nframes_t jack_last_frame_time(const jack_client_t *client) {
    (void)client;
    return atomic_load(&G.last_frame);
}

/* ---- M2: a sound card runs the blocks ----
 * the Windows build opens the sound card (platform/windows/audio/audio_device.c) and calls verdandi_jack_null_process from its callback instead of the timer thread
 * of the null backend: capture ports get what the card delivers (silence while there is no input), the blocks run, what is connected to the playback ports goes back. */
void verdandi_jack_null_configure(unsigned rate, unsigned frames) {
    pthread_mutex_lock(&G.lock);
    if (!G.inited) {
        G.pre_rate = rate;
        G.pre_frames = frames > MAX_FRAMES ? MAX_FRAMES : frames;
    }
    pthread_mutex_unlock(&G.lock);
}

void verdandi_jack_null_external_clock(int on) {
    pthread_mutex_lock(&G.lock);
    G.external = on ? 1 : 0;
    pthread_mutex_unlock(&G.lock);
}

void verdandi_jack_null_loop_breaker(jack_client_t *client) {
    pthread_mutex_lock(&G.lock);
    if (client) {
        client->loop_breaker = 1;
    }
    pthread_mutex_unlock(&G.lock);
}

int verdandi_jack_null_process(unsigned nframes, const float *cap_l, const float *cap_r, float *play_l, float *play_r) {
    int64_t begin = now_ns();
    pthread_mutex_lock(&G.lock);
    init_locked();
    if (nframes != G.frames) {
        pthread_mutex_unlock(&G.lock);
        return -1;
    }
    struct _jack_port *c1 = find_port_locked("system:capture_1"), *c2 = find_port_locked("system:capture_2");
    if (c1) {
        if (cap_l) memcpy(c1->buf, cap_l, nframes * sizeof(float)); else memset(c1->buf, 0, nframes * sizeof(float));
    }
    if (c2) {
        if (cap_r) memcpy(c2->buf, cap_r, nframes * sizeof(float)); else memset(c2->buf, 0, nframes * sizeof(float));
    }
    compute_order_locked();
    atomic_store(&G.last_frame, (unsigned)((uint64_t)(begin - G.start_ns) * G.rate / 1000000000ULL));
    run_block_locked();
    for (int i = 0; i < 2; i++) {
        float *out = i == 0 ? play_l : play_r;
        struct _jack_port *p = find_port_locked(i == 0 ? "system:playback_1" : "system:playback_2");
        if (!out) {
            continue;
        }
        memset(out, 0, nframes * sizeof(float));
        for (int k = 0; p && k < G.nconns; k++) {
            if (G.conns[k].dst == p) {
                const float *src = G.conns[k].src->buf;
                for (unsigned j = 0; j < nframes; j++) {
                    out[j] += src[j];
                }
            }
        }
    }
    pthread_mutex_unlock(&G.lock);
    double period = (double)nframes * 1e9 / (double)G.rate;
    double used = 100.0 * (double)(now_ns() - begin) / period;
    double c = atomic_load(&G.cpu);
    atomic_store(&G.cpu, c + 0.1 * (used - c));
    atomic_fetch_add(&G.ticks, 1);
    return 0;
}

/* test and diagnostics: how many blocks ran, how many were missed */
unsigned verdandi_jack_null_ticks(void) { return atomic_load(&G.ticks); }
unsigned verdandi_jack_null_xruns(void) { return atomic_load(&G.xruns); }
unsigned verdandi_jack_null_frames(void) { return G.frames; }

/* ---- ring buffer (single reader, single writer) ---- */

struct jack_ringbuffer_s {
    char *buf;
    size_t size; /* a power of two */
    atomic_size_t rd, wr;
};

jack_ringbuffer_t *jack_ringbuffer_create(size_t sz) {
    size_t p = 2;
    while (p < sz + 1) {
        p <<= 1;
    }
    jack_ringbuffer_t *rb = calloc(1, sizeof *rb);
    if (!rb) {
        return NULL;
    }
    rb->buf = calloc(1, p);
    if (!rb->buf) {
        free(rb);
        return NULL;
    }
    rb->size = p;
    return rb;
}
void jack_ringbuffer_free(jack_ringbuffer_t *rb) {
    if (rb) {
        free(rb->buf);
        free(rb);
    }
}
void jack_ringbuffer_reset(jack_ringbuffer_t *rb) {
    atomic_store(&rb->rd, 0);
    atomic_store(&rb->wr, 0);
}
size_t jack_ringbuffer_read_space(const jack_ringbuffer_t *rb) {
    size_t w = atomic_load(&((jack_ringbuffer_t *)rb)->wr), r = atomic_load(&((jack_ringbuffer_t *)rb)->rd);
    return (w - r) & (rb->size - 1);
}
size_t jack_ringbuffer_write_space(const jack_ringbuffer_t *rb) {
    /* one byte stays free, as in JACK's ring buffer */
    return rb->size - 1 - jack_ringbuffer_read_space(rb);
}
size_t jack_ringbuffer_read(jack_ringbuffer_t *rb, char *dest, size_t cnt) {
    size_t avail = jack_ringbuffer_read_space(rb);
    if (cnt > avail) {
        cnt = avail;
    }
    size_t r = atomic_load(&rb->rd);
    for (size_t i = 0; i < cnt; i++) {
        dest[i] = rb->buf[(r + i) & (rb->size - 1)];
    }
    atomic_store(&rb->rd, (r + cnt) & (rb->size - 1));
    return cnt;
}
size_t jack_ringbuffer_write(jack_ringbuffer_t *rb, const char *src, size_t cnt) {
    size_t space = jack_ringbuffer_write_space(rb);
    if (cnt > space) {
        cnt = space;
    }
    size_t w = atomic_load(&rb->wr);
    for (size_t i = 0; i < cnt; i++) {
        rb->buf[(w + i) & (rb->size - 1)] = src[i];
    }
    atomic_store(&rb->wr, (w + cnt) & (rb->size - 1));
    return cnt;
}
