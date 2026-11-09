/* dust_import_win.c: files dropped on the window are not imported in Windows M1 (the macOS version links or copies them into dust with copyfile(3)). the API is the same; every call says "skip". */
#include <stdio.h>
#include <string.h>

#include "platform/macos/dust_import.h"

static void say_once(void) {
    static int said;
    if (!said) {
        said = 1;
        fprintf(stderr, "dust import: dropping files on the window is not available in this Windows build yet (copy them into the dust folder)\n");
    }
}

dust_kind_t dust_import_kind(const char *path) {
    (void)path;
    return DUST_SKIP;
}
int dust_import_dest(const char *dust, const char *path, int link, char *dest, size_t n) {
    (void)dust, (void)path, (void)link, (void)dest, (void)n;
    return -1;
}
int dust_import(const char *dust, const char *path, int link, char *dest, size_t n, int *linked) {
    (void)dust, (void)path, (void)link, (void)dest, (void)n;
    if (linked) {
        *linked = 0;
    }
    say_once();
    return -1;
}
void dust_prune_links(const char *dust) { (void)dust; }
int dust_import_volatile(const char *path, const char *tmpdir, const char *home) {
    (void)path, (void)tmpdir, (void)home;
    say_once();
    return -1;
}
