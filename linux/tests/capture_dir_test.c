/* capture_dir.h and win_messages.h (Windows screenshots/GIFs folder choice and the plain "not available yet" sentences); also checks that the sources use them.
 * run from the repo root: cc -std=gnu11 -Wall -I matron/src/platform/windows linux/tests/capture_dir_test.c -o /tmp/cdt && /tmp/cdt */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "capture_dir.h"
#include "win_messages.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
static char *slurp(const char *p) {
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)n + 1); size_t g = fread(b, 1, (size_t)n, f); b[g] = 0; fclose(f); return b;
}
int main(void) {
    char out[512];
    CHECK(capture_dir_pick("C:/Users/a b/Pictures", 1, "C:/Users/a b/Verdandi/dust", out, sizeof out) == 1 && strcmp(out, "C:/Users/a b/Pictures/Verdandi") == 0, "Pictures found and made: <Pictures>/Verdandi");
    CHECK(capture_dir_pick("C:/Users/Jos\xc3\xa9/OneDrive/Pictures/", 1, "d", out, sizeof out) == 1 && strcmp(out, "C:/Users/Jos\xc3\xa9/OneDrive/Pictures/Verdandi") == 0, "a non-ASCII, OneDrive path and a trailing slash");
    CHECK(capture_dir_pick("C:\\Users\\x\\Pictures\\", 1, "d", out, sizeof out) == 1 && strcmp(out, "C:\\Users\\x\\Pictures/Verdandi") == 0, "a trailing backslash is cut");
    CHECK(capture_dir_pick("C:/Users/x/Pictures", 0, "C:/dust", out, sizeof out) == 0 && strcmp(out, "C:/dust") == 0, "the subfolder could not be made: the dust folder");
    CHECK(capture_dir_pick("", 1, "C:/dust", out, sizeof out) == 0 && strcmp(out, "C:/dust") == 0, "no Pictures folder: the dust folder");
    CHECK(capture_dir_pick(NULL, 1, "C:/dust", out, sizeof out) == 0 && strcmp(out, "C:/dust") == 0, "NULL: the dust folder");
    CHECK(capture_dir_pick(NULL, 0, NULL, out, sizeof out) == 0 && strcmp(out, ".") == 0, "nothing at all: the current folder");
    /* the sentences */
    CHECK(strstr(WIN_IMPORT_NOT_AVAILABLE, "not available yet") && strstr(WIN_IMPORT_NOT_AVAILABLE, "dust folder"), "the import sentence says it is not available yet and what to do");
    CHECK(strstr(WIN_DIALOG_NOT_AVAILABLE, "no file dialog") && strstr(WIN_DIALOG_NOT_AVAILABLE, "dust folder"), "the dialog sentence says there is none and what to do");
    CHECK(!strstr(WIN_IMPORT_NOT_AVAILABLE, "zenity") && !strstr(WIN_DIALOG_NOT_AVAILABLE, "zenity") && !strstr(WIN_DIALOG_NOT_AVAILABLE, "portal") && !strstr(WIN_IMPORT_NOT_AVAILABLE, "nothing to import"), "no Linux words, no 'nothing to import'");
    CHECK(strlen(WIN_IMPORT_NOT_AVAILABLE) < 100 && strlen(WIN_DIALOG_NOT_AVAILABLE) < 100, "short enough for the toast");
    /* the sources use them under NORNS_WINDOWS */
    char *sh = slurp("matron/src/platform/linux/desktop_shell_linux.cc"), *br = slurp("matron/src/platform/macos/sdl_bridge.cc");
    CHECK(sh && strstr(sh, "#ifdef NORNS_WINDOWS") && strstr(sh, "NO_DIALOG_NOTE WIN_DIALOG_NOT_AVAILABLE") && !strstr(sh, "note(\"no file dialog (install zenity"), "desktop_shell: the dialog note is the Windows sentence under NORNS_WINDOWS (and the Linux one stays)");
    CHECK(sh && strstr(sh, "\"no file dialog (install zenity or an xdg-desktop-portal)\""), "desktop_shell: the Linux sentence is unchanged");
    CHECK(br && strstr(br, "msg = WIN_IMPORT_NOT_AVAILABLE") && strstr(br, "nothing to import: not audio or a script"), "sdl_bridge: the Windows sentence replaces the old one on Windows only");
    CHECK(br && strstr(br, "win_known_pictures") && strstr(br, "capture_dir_pick") && strstr(br, "win_fopen_utf8"), "sdl_bridge: screenshots and GIFs use the known folder and wide paths on Windows");
    free(sh); free(br);
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("capture_dir_test: ok\n");
    return 0;
}
