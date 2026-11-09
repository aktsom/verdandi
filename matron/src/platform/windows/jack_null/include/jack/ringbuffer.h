/* jack/ringbuffer.h of the JACK-compatible null backend: a single reader / single writer lock-free byte ring buffer with the JACK names (implementation: jack_null.c) */
#ifndef VERDANDI_JACK_NULL_RINGBUFFER_H
#define VERDANDI_JACK_NULL_RINGBUFFER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct jack_ringbuffer_s jack_ringbuffer_t;

jack_ringbuffer_t *jack_ringbuffer_create(size_t sz);
void jack_ringbuffer_free(jack_ringbuffer_t *rb);
void jack_ringbuffer_reset(jack_ringbuffer_t *rb);
size_t jack_ringbuffer_read_space(const jack_ringbuffer_t *rb);
size_t jack_ringbuffer_write_space(const jack_ringbuffer_t *rb);
size_t jack_ringbuffer_read(jack_ringbuffer_t *rb, char *dest, size_t cnt);
size_t jack_ringbuffer_write(jack_ringbuffer_t *rb, const char *src, size_t cnt);

#ifdef __cplusplus
}
#endif

#endif
