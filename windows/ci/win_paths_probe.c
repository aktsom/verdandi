/* win_paths_probe.c: the real Windows API behind the screenshot/GIF folder (matron/src/platform/windows/win_paths.c), run on the CI runner: the Pictures known folder is found, a folder with letters outside ASCII is made and
 * written to through the wide API, and the choice falls back to dust when the folder cannot be made. prints "WINPATHS ..." lines; exit 1 on any failure. build: gcc windows/ci/win_paths_probe.c -o probe.exe -lole32 -lshell32 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../matron/src/platform/windows/win_paths.c"
#include "../../matron/src/platform/windows/capture_dir.h"

static int fails;
#define CHECK(c, what) do { if (c) printf("WINPATHS ok   %s\n", what); else { fails++; printf("WINPATHS FAIL %s\n", what); } } while (0)

static int write_read(const char *path) {
    FILE *f = win_fopen_utf8(path, "wb");
    if (!f) return 0;
    fwrite("verdandi", 1, 8, f);
    if (fclose(f) != 0) return 0;
    f = win_fopen_utf8(path, "rb");
    char b[16] = {0};
    size_t n = f ? fread(b, 1, 15, f) : 0;
    if (f) fclose(f);
    return n == 8 && strcmp(b, "verdandi") == 0;
}

int main(void) {
    char pic[2048], sub[2300], file[2500], out[2400];
    CHECK(win_known_pictures(pic, sizeof pic) == 0 && pic[0] != 0, "the Pictures known folder is found");
    printf("WINPATHS pictures=%s\n", pic);
    CHECK(strchr(pic, '\\') == NULL && (pic[1] == ':' || pic[0] == '/'), "it comes back as an absolute path with slashes");
    snprintf(sub, sizeof sub, "%s/%s", pic, CAPTURE_SUBFOLDER);
    CHECK(win_mkdirs_utf8(sub) == 0 && win_exists_utf8(sub), "<Pictures>/Verdandi is made (it need not exist before)");
    snprintf(file, sizeof file, "%s/probe \xc3\xa9\xc3\xb1 test.png", sub);
    CHECK(write_read(file) && win_exists_utf8(file), "a file with accents in its name is written and read back there");
    CHECK(win_unlink_utf8(file) == 0 && !win_exists_utf8(file), "and removed");
    CHECK(capture_dir_pick(pic, 1, "C:/dust", out, sizeof out) == 1 && strcmp(out, sub) == 0, "the choice is <Pictures>/Verdandi");
    /* a folder with letters outside ASCII and a blank, below the temp folder (a user name with an accent is the same case) */
    const char *tmp = getenv("TEMP");
    snprintf(sub, sizeof sub, "%s/Caf\xc3\xa9 \xc3\xbcn\xc3\xaf/sub folder", tmp ? tmp : "C:/Windows/Temp");
    for (char *q = sub; *q; q++) if (*q == '\\') *q = '/';
    snprintf(file, sizeof file, "%s/\xcf\x80 shot.gif", sub);
    CHECK(win_mkdirs_utf8(sub) == 0 && win_exists_utf8(sub), "a nested folder with accents and blanks is made");
    CHECK(write_read(file), "a GIF-like file is written there through the wide API");
    win_unlink_utf8(file);
    /* the fallback */
    CHECK(capture_dir_pick(pic, 0, "C:/dust", out, sizeof out) == 0 && strcmp(out, "C:/dust") == 0, "when the folder cannot be made: the dust folder");
    CHECK(win_mkdirs_utf8("Z:/this/drive/does/not/exist") != 0, "a folder that cannot be made is reported");
    if (fails) { printf("WINPATHS %d FAILED\n", fails); return 1; }
    printf("WINPATHS all passed\n");
    return 0;
}
