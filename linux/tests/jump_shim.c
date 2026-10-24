/* jump_shim.so: LD_PRELOAD library that adds a forward jump to JACK's frame time once, when the file named by
 * $JUMP_FILE appears (JUMP_SECONDS, default 560): what happens to norns when the base of the frame time changes
 * (docs/port/KNOWN-ISSUES.md item 6). cc -shared -fPIC -o jump_shim.so linux/tests/jump_shim.c -ldl */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <jack/jack.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

jack_nframes_t jack_frame_time(const jack_client_t *c) {
    static jack_nframes_t (*real)(const jack_client_t *);
    static uint32_t offset;
    static int done;
    if (!real) {
        real = (jack_nframes_t(*)(const jack_client_t *))dlsym(RTLD_NEXT, "jack_frame_time");
    }
    const char *f = getenv("JUMP_FILE");
    if (!done && f != NULL && access(f, F_OK) == 0) {
        const char *s = getenv("JUMP_SECONDS");
        offset = (uint32_t)((s ? atof(s) : 560.0) * 48000.0);
        done = 1;
    }
    return real(c) + offset;
}
