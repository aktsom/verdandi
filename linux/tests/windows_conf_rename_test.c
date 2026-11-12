/* the state file of the detached window on Windows: rename() of the C runtime fails when the new name exists, so the second save was lost and a restart brought the first size back. this test compiles
 * screen_window_conf.c as Windows code (-D_WIN32) and links a rename() that behaves like the Windows one:
 *   gcc -D_WIN32 -I matron/src/platform/linux linux/tests/windows_conf_rename_test.c matron/src/platform/linux/screen_window_conf.c -o /tmp/wcr && /tmp/wcr */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "screen_window_conf.h"

int rename(const char *a, const char *b) { /* the Windows C runtime's */
    if (access(b, F_OK) == 0) { errno = EEXIST; return -1; }
    char cmd[2400];
    snprintf(cmd, sizeof cmd, "mv '%s' '%s'", a, b);
    return system(cmd) == 0 ? 0 : -1;
}

int main(void) {
    char dir[] = "/tmp/wcrXXXXXX";
    if (!mkdtemp(dir)) return 2;
    char path[300];
    snprintf(path, sizeof path, "%s/screen-window.conf", dir);
    sw_conf_t c;
    memset(&c, 0, sizeof c);
    c.has_pos = 1; c.x = 10; c.y = 20; c.w = 640; c.h = 320;
    int fails = 0;
    if (sw_conf_save(path, &c) != 0) { puts("FAIL first save"); fails++; }
    c.w = 1280; c.h = 640;
    if (sw_conf_save(path, &c) != 0) { puts("FAIL second save"); fails++; }
    FILE *f = fopen(path, "r");
    char buf[400] = "";
    if (f) { size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = 0; fclose(f); }
    if (!strstr(buf, "w=1280")) { printf("FAIL the file has the old size: %s\n", buf); fails++; }
    char tmp[320]; snprintf(tmp, sizeof tmp, "%s.tmp", path);
    if (access(tmp, F_OK) == 0) { puts("FAIL temporary file left"); fails++; }
    puts(fails ? "windows conf rename: failures" : "windows conf rename: all scenarios pass");
    return fails != 0;
}
