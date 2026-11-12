// midi_port.cc: see midi_port.h
#include "midi_port.h"

#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define RING 8192

struct vmidi_port {
    const vmidi_backend *be;
    void *in, *out;
    vmidi_hooks hooks;
    const volatile uint8_t *clock_enabled;

    pthread_mutex_t lock;
    pthread_cond_t cond;
    vmidi_probe_fn probe;
    void *probe_user;
    uint8_t ring[RING];
    size_t head, count;
    int closed;
    int refs;

    /* the song position pointer being collected */
    int spp_pos; /* 0 = none, 1 = waiting for the lsb, 2 = waiting for the msb */
    uint8_t spp_lsb;

    /* the interval of the clock ticks: Welford over the window */
    double last_tick_us;
    unsigned long long n, ticks;
    double mean, m2, mn, mx;
    unsigned long long dropped, bytes;
};

static void rx(void *user, const uint8_t *d, size_t n) {
    vmidi_port *p = (vmidi_port *)user;
    vmidi_probe_fn probe = p->probe;
    if (probe && probe(p->probe_user, d, n, p->be && p->be->now_us ? p->be->now_us() : 0)) {
        return;
    }
    for (size_t i = 0; i < n; i++) {
        uint8_t b = d[i];
        if (b >= 0xf8) {
            if (b == 0xf8 || b == 0xfa || b == 0xfb || b == 0xfc) {
                if (p->clock_enabled == NULL || *p->clock_enabled) {
                    double t = p->be->now_us ? p->be->now_us() : 0;
                    if (b == 0xf8) {
                        pthread_mutex_lock(&p->lock);
                        if (p->last_tick_us > 0) {
                            double dt = t - p->last_tick_us;
                            if (dt < 2e6) {
                                p->n++;
                                double delta = dt - p->mean;
                                p->mean += delta / (double)p->n;
                                p->m2 += delta * (dt - p->mean);
                                if (p->n == 1 || dt < p->mn) p->mn = dt;
                                if (dt > p->mx) p->mx = dt;
                            }
                        }
                        p->last_tick_us = t;
                        p->ticks++;
                        pthread_mutex_unlock(&p->lock);
                    }
                    if (p->hooks.clock_msg) {
                        p->hooks.clock_msg(b);
                    }
                }
            }
        } else if (b >= 0x80) {
            p->spp_pos = (b == 0xf2) ? 1 : 0;
        } else if (p->spp_pos == 1) {
            p->spp_lsb = b;
            p->spp_pos = 2;
        } else if (p->spp_pos == 2) {
            p->spp_pos = 0;
            if (p->hooks.clock_spp && (p->clock_enabled == NULL || *p->clock_enabled)) {
                p->hooks.clock_spp((uint16_t)(p->spp_lsb | (b << 7)));
            }
        }
    }
    vmidi_port_push(p, d, n);
}

void vmidi_port_push(vmidi_port *p, const uint8_t *d, size_t n) {
    pthread_mutex_lock(&p->lock);
    for (size_t i = 0; i < n; i++) {
        if (p->count >= RING) {
            p->dropped++;
            continue;
        }
        p->ring[(p->head + p->count) % RING] = d[i];
        p->count++;
        p->bytes++;
    }
    pthread_cond_signal(&p->cond);
    pthread_mutex_unlock(&p->lock);
}

vmidi_port *vmidi_port_open(const vmidi_backend *be, int in_index, int out_index, const vmidi_hooks *hooks, const volatile uint8_t *clock_enabled, char *note, size_t noten) {
    vmidi_port *p = (vmidi_port *)calloc(1, sizeof *p);
    if (!p) return NULL;
    p->be = be;
    p->refs = 1;
    if (hooks) p->hooks = *hooks;
    p->clock_enabled = clock_enabled;
    pthread_mutex_init(&p->lock, NULL);
    pthread_cond_init(&p->cond, NULL);
    if (note && noten) note[0] = 0;
    char err[160] = "";
    int busy = 0;
    if (in_index >= 0) {
        p->in = be->open_in(in_index, rx, p, err, sizeof err, &busy);
        if (!p->in && note) {
            snprintf(note, noten, "%s", busy ? "held by another program (its input)" : (err[0] ? err : "the input did not open"));
        }
    }
    err[0] = 0;
    busy = 0;
    if (out_index >= 0) {
        p->out = be->open_out(out_index, err, sizeof err, &busy);
        if (!p->out && note && !note[0]) {
            snprintf(note, noten, "%s", busy ? "held by another program (its output)" : (err[0] ? err : "the output did not open"));
        }
    }
    if (!p->in && !p->out) {
        pthread_mutex_destroy(&p->lock);
        pthread_cond_destroy(&p->cond);
        free(p);
        return NULL;
    }
    return p;
}

vmidi_port *vmidi_port_new_push(const vmidi_hooks *hooks, const volatile uint8_t *clock_enabled) {
    vmidi_port *p = (vmidi_port *)calloc(1, sizeof *p);
    if (!p) return NULL;
    p->refs = 1;
    if (hooks) p->hooks = *hooks;
    p->clock_enabled = clock_enabled;
    p->in = (void *)1; /* marks an input */
    pthread_mutex_init(&p->lock, NULL);
    pthread_cond_init(&p->cond, NULL);
    return p;
}

int vmidi_port_has_input(const vmidi_port *p) { return p && p->in != NULL; }
int vmidi_port_has_output(const vmidi_port *p) { return p && p->out != NULL; }

/* the reader thread of norns can be cancelled (device.cc dev_delete cancels the thread of a device that is removed, then joins it): cancelling is only allowed while the lock is not held, so the lock is never left taken.
 * the wait is in slices of 100 ms for that reason: a cancel waits for the end of a slice */
long vmidi_port_read(vmidi_port *p, uint8_t *buf, size_t max) {
    int old;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old);
    pthread_mutex_lock(&p->lock);
    while (p->count == 0 && !p->closed) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_nsec += 100 * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&p->cond, &p->lock, &ts);
        if (p->count == 0 && !p->closed) {
            pthread_mutex_unlock(&p->lock);
            pthread_setcancelstate(old, NULL);
            pthread_testcancel();
            pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old);
            pthread_mutex_lock(&p->lock);
        }
    }
    size_t n = 0;
    while (n < max && p->count > 0) {
        buf[n++] = p->ring[p->head];
        p->head = (p->head + 1) % RING;
        p->count--;
    }
    int closed = p->closed && n == 0;
    pthread_mutex_unlock(&p->lock);
    pthread_setcancelstate(old, NULL);
    return closed ? 0 : (long)n;
}

long vmidi_port_send(vmidi_port *p, const uint8_t *data, size_t n) {
    if (!p->be || !p->out || n == 0) return -1;
    return p->be->send(p->out, data, n);
}

void vmidi_port_close(vmidi_port *p) {
    if (!p) return;
    if (p->be && p->in) p->be->close_in(p->in); /* after this the backend calls rx no more */
    if (p->be && p->out) p->be->close_out(p->out);
    pthread_mutex_lock(&p->lock);
    p->closed = 1;
    pthread_cond_broadcast(&p->cond);
    pthread_mutex_unlock(&p->lock);
}

void vmidi_port_ref(vmidi_port *p) {
    pthread_mutex_lock(&p->lock);
    p->refs++;
    pthread_mutex_unlock(&p->lock);
}

void vmidi_port_unref(vmidi_port *p) {
    pthread_mutex_lock(&p->lock);
    int left = --p->refs;
    pthread_mutex_unlock(&p->lock);
    if (left == 0) {
        pthread_mutex_destroy(&p->lock);
        pthread_cond_destroy(&p->cond);
        free(p);
    }
}

void vmidi_port_stats(vmidi_port *p, vmidi_stats *o) {
    pthread_mutex_lock(&p->lock);
    memset(o, 0, sizeof *o);
    o->ticks = p->ticks;
    o->mean_us = p->mean;
    o->min_us = p->mn;
    o->max_us = p->mx;
    o->jitter_us = p->n > 1 ? sqrt(p->m2 / (double)(p->n - 1)) : 0;
    o->dropped = p->dropped;
    o->bytes = p->bytes;
    p->n = 0; p->mean = p->m2 = 0; p->mn = p->mx = 0;
    pthread_mutex_unlock(&p->lock);
}

void vmidi_port_set_probe(vmidi_port *p, vmidi_probe_fn fn, void *user) {
    p->probe_user = user;
    p->probe = fn;
}

double vmidi_port_now_us(vmidi_port *p) {
    return p->be && p->be->now_us ? p->be->now_us() : 0;
}

double vmidi_port_tick_age_us(vmidi_port *p) {
    pthread_mutex_lock(&p->lock);
    double last = p->last_tick_us;
    pthread_mutex_unlock(&p->lock);
    if (last <= 0 || !p->be || !p->be->now_us) return -1;
    return p->be->now_us() - last;
}
