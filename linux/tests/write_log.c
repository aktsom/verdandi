/* LD_PRELOAD shim for linux/tests/grid_led_test.sh: logs every write() to a pseudo terminal (/dev/pts/N: the virtual grid's device, which libmonome
 * writes to as it would to a real grid's serial port) to the file in WRITE_LOG: "W <length> <hex bytes>", one line per write. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

ssize_t write(int fd, const void *buf, size_t n) {
    static ssize_t (*real)(int, const void *, size_t) = NULL;
    if (real == NULL) {
        real = (ssize_t(*)(int, const void *, size_t))dlsym(RTLD_NEXT, "write");
    }
    ssize_t r = real(fd, buf, n);
    const char *log = getenv("WRITE_LOG");
    if (log != NULL && n > 0 && n < 4096) {
        char link[64], path[256];
        snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
        ssize_t l = readlink(link, path, sizeof path - 1);
        if (l > 9) {
            path[l] = 0;
            if (strncmp(path, "/dev/pts/", 9) == 0) {
                int f = open(log, O_WRONLY | O_APPEND | O_CREAT, 0644);
                if (f >= 0) {
                    char line[2 * 4096 + 64];
                    int o = snprintf(line, sizeof line, "W %zu %zd ", n, r);
                    for (size_t i = 0; i < n; i++) {
                        o += snprintf(line + o, sizeof line - o, "%02x", ((const unsigned char *)buf)[i]);
                    }
                    line[o++] = '\n';
                    real(f, line, o);
                    close(f);
                }
            }
        }
    }
    return r;
}
