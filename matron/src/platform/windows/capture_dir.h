/* capture_dir.h: where screenshots and GIFs go on Windows (pure, linux/tests/capture_dir_test.c). the Windows Pictures folder (the known folder: it follows a OneDrive redirection and a user name with any letters) in a
 * subfolder "Verdandi"; when it cannot be found or made, the dust folder as before. the paths are UTF-8 with '/'. */
#ifndef VERDANDI_CAPTURE_DIR_H
#define VERDANDI_CAPTURE_DIR_H
#include <stdio.h>
#include <string.h>

#define CAPTURE_SUBFOLDER "Verdandi"

/* pictures: the Pictures folder ("" or NULL when the lookup failed); made_ok: <pictures>/Verdandi exists or could be made. returns 1 and out = <pictures>/Verdandi, or 0 and out = dust */
static inline int capture_dir_pick(const char *pictures, int made_ok, const char *dust, char *out, size_t n) {
    if (pictures && pictures[0] && made_ok) {
        size_t l = strlen(pictures);
        while (l > 1 && (pictures[l - 1] == '/' || pictures[l - 1] == '\\')) l--;
        snprintf(out, n, "%.*s/%s", (int)l, pictures, CAPTURE_SUBFOLDER);
        return 1;
    }
    snprintf(out, n, "%s", dust ? dust : ".");
    return 0;
}
#endif
