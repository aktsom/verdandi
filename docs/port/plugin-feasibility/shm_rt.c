// shm_rt.c: a stereo audio exchange between two processes through shared memory, measured (docs/port/plugin-feasibility.md).
//  host   = a stand-in for a DAW's audio thread (a timer thread that fires once per block period, absolute CLOCK_MONOTONIC times)
//  helper = a separate process (fork) that plays the norns side
// mode sync : the host writes a block, wakes the helper through a process-shared semaphore and waits for it to say it is done (what yabridge-like bridges do): measures the wait per block
// mode async: the helper runs on its own clock (optionally off by ppm parts per million, like another sound card) and the two sides meet in ring buffers: measures the fill level and under/overruns
// build: cc -O2 -o shm_rt shm_rt.c -lpthread -lrt -lm      run: shm_rt sync SR N SECONDS | shm_rt async SR N SECONDS PPM PREFILL_BLOCKS
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAXN 2048
#define RING 65536 // frames, power of two
typedef struct {
    sem_t go, done;
    _Atomic int quit;
    // sync: one block each way
    float in[2][MAXN], out[2][MAXN];
    // async: rings
    float rin[2][RING], rout[2][RING];
    _Atomic unsigned long win, rin_pos, wout, rout_pos; // write/read counters in frames
    _Atomic unsigned long under_helper, under_host, over_host;
    _Atomic unsigned long fill_min, fill_max;
} shm_t;

static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static void add_ns(struct timespec *t, long ns) { t->tv_nsec += ns; while (t->tv_nsec >= 1000000000L) { t->tv_nsec -= 1000000000L; t->tv_sec++; } }
static void try_rt(int prio) { struct sched_param p = {prio}; if (sched_setscheduler(0, SCHED_FIFO, &p) != 0) { /* not allowed here: normal scheduling */ } }
static int cmpd(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return x < y ? -1 : x > y; }

static void helper_sync(shm_t *s, int n) {
    while (!atomic_load(&s->quit)) {
        if (sem_wait(&s->go) != 0) continue;
        if (atomic_load(&s->quit)) break;
        for (int c = 0; c < 2; c++) for (int i = 0; i < n; i++) s->out[c][i] = s->in[c][i] * 0.5f; // the "engine": a gain
        sem_post(&s->done);
    }
}

static void helper_async(shm_t *s, int sr, int n, double ppm, int prefill) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    long period = (long)(1e9 * n / sr * (1.0 + ppm * 1e-6));
    // prefill the output ring with silence: the latency the host will see
    atomic_store(&s->wout, (unsigned long)prefill * n);
    for (;;) {
        add_ns(&t, period);
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL);
        if (atomic_load(&s->quit)) break;
        unsigned long w = atomic_load(&s->win), r = atomic_load(&s->rin_pos);
        if (w - r >= (unsigned long)n) {
            for (int c = 0; c < 2; c++) for (int i = 0; i < n; i++) s->rout[c][(atomic_load(&s->wout) + i) & (RING - 1)] = s->rin[c][(r + i) & (RING - 1)] * 0.5f;
            atomic_store(&s->rin_pos, r + n);
        } else {
            for (int c = 0; c < 2; c++) for (int i = 0; i < n; i++) s->rout[c][(atomic_load(&s->wout) + i) & (RING - 1)] = 0;
            atomic_fetch_add(&s->under_helper, 1);
        }
        atomic_fetch_add(&s->wout, n);
    }
}

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: shm_rt sync|async SR N SECONDS [PPM PREFILL]\n"); return 2; }
    int async = strcmp(argv[1], "async") == 0, sr = atoi(argv[2]), n = atoi(argv[3]);
    double secs = atof(argv[4]), ppm = argc > 5 ? atof(argv[5]) : 0; int prefill = argc > 6 ? atoi(argv[6]) : 2;
    shm_t *s = mmap(NULL, sizeof(shm_t), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    memset(s, 0, sizeof *s);
    sem_init(&s->go, 1, 0); sem_init(&s->done, 1, 0);
    atomic_store(&s->fill_min, ~0ul);
    pid_t pid = fork();
    if (pid == 0) { try_rt(20); if (async) helper_async(s, sr, n, ppm, prefill); else helper_sync(s, n); _exit(0); }
    try_rt(30);
    long period = (long)(1e9 * n / sr);
    int blocks = (int)(secs * sr / n);
    double *lat = calloc(blocks, sizeof(double));
    int nlat = 0, miss80 = 0, miss100 = 0;
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    double jit_max = 0; double *jit = calloc(blocks, sizeof(double));
    double last_fire = 0;
    for (int b = 0; b < blocks; b++) {
        add_ns(&t, period);
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL);
        double t0 = now_s();
        double target = t.tv_sec + t.tv_nsec * 1e-9;
        jit[b] = (t0 - target) * 1e6; // how late the host's own timer fired (us)
        if (jit[b] > jit_max) jit_max = jit[b];
        (void)last_fire;
        if (!async) {
            for (int c = 0; c < 2; c++) for (int i = 0; i < n; i++) s->in[c][i] = (float)sin((b * n + i) * 0.01);
            sem_post(&s->go);
            struct timespec to; clock_gettime(CLOCK_REALTIME, &to); add_ns(&to, 2 * period + 20000000L);
            if (sem_timedwait(&s->done, &to) != 0) { miss100++; continue; }
            double l = (now_s() - t0) * 1e6;
            lat[nlat++] = l;
            double frac = l / (period / 1e3);
            if (frac > 0.8) miss80++;
            if (frac > 1.0) miss100++;
        } else {
            unsigned long w = atomic_load(&s->win);
            for (int c = 0; c < 2; c++) for (int i = 0; i < n; i++) s->rin[c][(w + i) & (RING - 1)] = (float)sin((b * n + i) * 0.01);
            atomic_store(&s->win, w + n);
            unsigned long wo = atomic_load(&s->wout), ro = atomic_load(&s->rout_pos);
            if (wo - ro >= (unsigned long)n) atomic_store(&s->rout_pos, ro + n); else atomic_fetch_add(&s->under_host, 1);
            unsigned long fill = (atomic_load(&s->wout) - atomic_load(&s->rout_pos)) / n; // blocks waiting in the output ring
            unsigned long mn = atomic_load(&s->fill_min), mx = atomic_load(&s->fill_max);
            if (fill < mn) atomic_store(&s->fill_min, fill);
            if (fill > mx) atomic_store(&s->fill_max, fill);
            if (fill > (unsigned long)(RING / n - 4)) atomic_fetch_add(&s->over_host, 1);
            lat[nlat++] = (double)fill;
        }
    }
    atomic_store(&s->quit, 1); sem_post(&s->go);
    waitpid(pid, NULL, 0);
    qsort(jit, blocks, sizeof(double), cmpd);
    printf("%s sr=%d n=%d period=%.0fus blocks=%d | host timer lateness us: p50 %.0f p99 %.0f max %.0f", argv[1], sr, n, period / 1e3, blocks, jit[blocks / 2], jit[(int)(blocks * 0.99)], jit[blocks - 1]);
    if (!async) {
        qsort(lat, nlat, sizeof(double), cmpd);
        printf(" | wait for helper us: p50 %.0f p99 %.0f p99.9 %.0f max %.0f | >80%% of period %d, >100%% %d (of %d)\n", lat[nlat / 2], lat[(int)(nlat * 0.99)], lat[(int)(nlat * 0.999)], lat[nlat - 1], miss80, miss100, nlat);
    } else {
        printf(" | ppm=%g prefill=%d | output ring fill (blocks) min %lu max %lu | underruns helper %lu host %lu overruns %lu\n", ppm, prefill, atomic_load(&s->fill_min), atomic_load(&s->fill_max),
               atomic_load(&s->under_helper), atomic_load(&s->under_host), atomic_load(&s->over_host));
    }
    return 0;
}
