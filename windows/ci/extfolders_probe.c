/* extfolders_probe.c: the junction backend of platform/common/extfolders.c on the real Windows runner (docs/port/phase-m8.md). a folder with a blank and an accented letter, junction creation and removal, the refusals (a network path,
 * inside dust, the same folder twice), a real folder with the name of a link is never touched, only a real link is removed, the files behind it survive, removal while a file is open through it,
 * a missing target and the link made again, a long path, and a script-like reader (list and read through the link). prints "EXTFOLDERS FAIL <what>" lines and "EXTFOLDERS all passed".
 * build (the runner's gcc): gcc -std=gnu11 -Wall -I matron/src/platform/common windows/ci/extfolders_probe.c matron/src/platform/common/extfolders.c -o extfolders_probe.exe */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "extfolders.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("EXTFOLDERS FAIL %s\n", what); } } while (0)

static wchar_t *w(const char *u8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, u8, -1, NULL, 0);
    wchar_t *o = (wchar_t *)malloc((size_t)n * 2);
    MultiByteToWideChar(CP_UTF8, 0, u8, -1, o, n);
    for (wchar_t *p = o; *p; p++) if (*p == L'/') *p = L'\\';
    return o;
}
/* \\?\ + full path, so that any length works in the probe itself */
static wchar_t *wl(const char *u8) {
    wchar_t *a = w(u8);
    wchar_t full[32768];
    DWORD g = GetFullPathNameW(a, 32768, full, NULL);
    free(a);
    wchar_t *o = (wchar_t *)malloc((g + 8) * 2);
    wcscpy(o, L"\\\\?\\");
    wcscat(o, full);
    return o;
}
static void mk(const char *u8) { wchar_t *p = wl(u8); CreateDirectoryW(p, NULL); free(p); }
static void put(const char *dir, const char *name, const char *text) {
    char path[4000]; snprintf(path, sizeof path, "%s\\%s", dir, name);
    wchar_t *p = wl(path);
    HANDLE h = CreateFileW(p, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) { DWORD g; WriteFile(h, text, (DWORD)strlen(text), &g, NULL); CloseHandle(h); }
    free(p);
}
static int slurp(const char *path, char *buf, size_t n) {
    wchar_t *p = wl(path);
    HANDLE h = CreateFileW(p, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    free(p);
    if (h == INVALID_HANDLE_VALUE) { buf[0] = 0; return -1; }
    DWORD g = 0; ReadFile(h, buf, (DWORD)n - 1, &g, NULL); CloseHandle(h); buf[g] = 0; return (int)g;
}
static int exists(const char *path) { wchar_t *p = wl(path); DWORD a = GetFileAttributesW(p); free(p); return a != INVALID_FILE_ATTRIBUTES; }
static int reparse(const char *path) { wchar_t *p = wl(path); DWORD a = GetFileAttributesW(p); free(p); return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_REPARSE_POINT); }
static int renamed(const char *a, const char *b) { wchar_t *x = wl(a), *y = wl(b); BOOL ok = MoveFileW(x, y); free(x); free(y); return ok; }
static int listing_has(const char *dir, const char *want) { /* a script-like listing: FindFirstFile through the link */
    char pat[4000]; snprintf(pat, sizeof pat, "%s\\*", dir);
    wchar_t *p = wl(pat); WIN32_FIND_DATAW fd; HANDLE h = FindFirstFileW(p, &fd); free(p);
    if (h == INVALID_HANDLE_VALUE) return 0;
    int found = 0; wchar_t *ww = w(want);
    do { if (wcscmp(fd.cFileName, ww) == 0) found = 1; } while (FindNextFileW(h, &fd));
    FindClose(h); free(ww); return found;
}
int main(void) {
    char tmp[MAX_PATH], root[1200];
    GetTempPathA(MAX_PATH, tmp);
    /* "Verdandi ext t\xc3\xa9st": a blank and an accent in the user part of every path */
    snprintf(root, sizeof root, "%sVerdandi ext t\xc3\xa9st %lu", tmp, (unsigned long)GetCurrentProcessId());
    char dust[1300], audio[1400], conf[1400], music[1400], music2[1400], empty[1400], msg[400], name[200], p[4000], buf[256];
    mk(root);
    snprintf(dust, sizeof dust, "%s\\home\xc3\xa9\\dust", root);
    snprintf(audio, sizeof audio, "%s\\audio", dust);
    snprintf(conf, sizeof conf, "%s\\extra-folders.conf", root);
    char t[1400]; snprintf(t, sizeof t, "%s\\home\xc3\xa9", root); mk(t); mk(dust); mk(audio);
    snprintf(music, sizeof music, "%s\\M\xc3\xbasica y sonidos", root); mk(music);
    snprintf(t, sizeof t, "%s\\other", root); mk(t);
    snprintf(music2, sizeof music2, "%s\\other\\M\xc3\xbasica y sonidos", root); mk(music2);
    snprintf(empty, sizeof empty, "%s\\empty", root); mk(empty);
    put(music, "kick.wav", "RIFF-kick"); put(music, "notes.txt", "keep me"); put(music2, "snare.flac", "fLaC-snare");

    int r = ef_add(conf, audio, dust, music, msg, sizeof msg, name, sizeof name);
    printf("add: r=%d name=%s msg=%s\n", r, name, msg);
    CHECK(r == 0 && strcmp(name, "[ext] M\xc3\xbasica y sonidos") == 0, "add: a junction named [ext] + the folder name (blank, accent)");
    snprintf(p, sizeof p, "%s\\%s", audio, name);
    CHECK(reparse(p) && ef_is_link(p), "the entry in dust\\audio is a reparse point (a junction)");
    snprintf(p, sizeof p, "%s\\%s\\kick.wav", audio, name);
    CHECK(slurp(p, buf, sizeof buf) == 9 && !strcmp(buf, "RIFF-kick"), "a script-like reader reads a file through the junction");
    snprintf(p, sizeof p, "%s\\%s", audio, name);
    CHECK(listing_has(p, "kick.wav") && listing_has(p, "notes.txt"), "a listing through the junction shows the files");

    r = ef_add(conf, audio, dust, music, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "already added"), "the same folder twice is refused");
    snprintf(p, sizeof p, "%s\\", music);
    r = ef_add(conf, audio, dust, p, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "already added"), "the same folder with a trailing backslash is refused");
    for (char *c = music; *c; c++) if (*c >= 'A' && *c <= 'Z') *c = (char)(*c + 32); /* an upper/lower case difference is the same folder on Windows */
    r = ef_add(conf, audio, dust, music, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "already added"), "the same folder in another letter case is refused");
    snprintf(music, sizeof music, "%s\\M\xc3\xbasica y sonidos", root);

    r = ef_add(conf, audio, dust, music2, msg, sizeof msg, name, sizeof name);
    CHECK(r == 0 && strcmp(name, "[ext] M\xc3\xbasica y sonidos 2") == 0, "a clash of names: the second is numbered");

    snprintf(t, sizeof t, "%s\\sub", audio); mk(t);
    r = ef_add(conf, audio, dust, t, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "inside dust"), "a folder inside dust is refused");
    r = ef_add(conf, audio, dust, root, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "contains the dust"), "a folder that contains dust is refused");
    r = ef_add(conf, audio, dust, "\\\\some-server\\share\\samples", msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "network"), "a network path (UNC) is refused in plain words");
    r = ef_add(conf, audio, dust, "//some-server/share/samples", msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "network"), "a network path with forward slashes is refused");
    snprintf(t, sizeof t, "%s\\nothere", root);
    r = ef_add(conf, audio, dust, t, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "not there"), "a missing folder is refused");
    snprintf(t, sizeof t, "%s\\kick.wav", music);
    r = ef_add(conf, audio, dust, t, msg, sizeof msg, NULL, 0);
    CHECK(r == -1, "a file is refused");
    r = ef_add(conf, audio, dust, empty, msg, sizeof msg, name, sizeof name);
    CHECK(r == 1 && strstr(msg, "no audio"), "a folder without audio is added with a note");

    ef_item it[16]; int n = ef_list(conf, audio, it, 16);
    CHECK(n == 3 && it[0].state == EF_OK && it[1].state == EF_OK && it[2].state == EF_OK, "list: three entries, all reachable");

    /* the link is gone (dust restored without it): sync makes it again */
    snprintf(p, sizeof p, "%s\\%s", audio, it[1].name);
    r = ef_remove(conf, audio, "[ext] nothere", msg, sizeof msg); CHECK(r == -1, "a name that is not in the list is refused");
    { wchar_t *pw = wl(p); RemoveDirectoryW(pw); free(pw); }
    n = ef_list(conf, audio, it, 16);
    CHECK(it[1].state == EF_NOLINK, "link missing and folder there: NOLINK");
    CHECK(ef_sync(conf, audio) == 1 && ef_is_link(p), "sync makes the junction again");

    /* an unplugged drive / renamed folder: the entry stays, nothing is deleted */
    char away[1400]; snprintf(away, sizeof away, "%s.away", music2);
    CHECK(renamed(music2, away), "(setup) rename the folder away");
    n = ef_list(conf, audio, it, 16);
    CHECK(n == 3 && it[1].state == EF_MISSING, "target renamed: the entry stays, shown as MISSING");
    CHECK(ef_sync(conf, audio) == 0 && ef_is_link(p), "sync makes nothing for a missing folder and the old link is left");
    CHECK(renamed(away, music2), "(setup) rename it back");
    n = ef_list(conf, audio, it, 16);
    CHECK(it[1].state == EF_OK, "target back: reachable again");

    /* a real folder with the name of a link: BLOCKED, never touched, never removed */
    char real[1500]; snprintf(real, sizeof real, "%s\\[ext] realone", audio); mk(real); put(real, "mine.wav", "REAL");
    { FILE *f = fopen(conf, "ab"); fprintf(f, "[ext] realone\t%s\n", music); fclose(f); }
    n = ef_list(conf, audio, it, 16);
    int seen = 0; for (int i = 0; i < n; i++) if (!strcmp(it[i].name, "[ext] realone")) { seen = 1; CHECK(it[i].state == EF_BLOCKED, "a real folder with the name of a link is BLOCKED"); }
    CHECK(seen, "the hand-edited line is listed");
    r = ef_remove(conf, audio, "[ext] realone", msg, sizeof msg);
    snprintf(p, sizeof p, "%s\\mine.wav", real);
    CHECK(exists(real) && slurp(p, buf, sizeof buf) == 4 && !strcmp(buf, "REAL"), "removing it leaves the real folder and its file alone");
    CHECK(strstr(msg, "real folder"), "...and says so");
    CHECK(ef_remove(conf, audio, "kick", msg, sizeof msg) == -1, "a name without the marker is refused");
    CHECK(ef_remove(conf, audio, "[ext] ..\\x", msg, sizeof msg) == -1, "a name with a backslash is refused");
    snprintf(t, sizeof t, "%s\\tape", audio); mk(t);
    CHECK(ef_remove(conf, audio, "tape", msg, sizeof msg) == -1 && exists(t), "a real dust folder (tape) cannot be removed");

    /* removal while a script has a file open through the junction */
    char linkname[300]; snprintf(linkname, sizeof linkname, "[ext] M\xc3\xbasica y sonidos");
    snprintf(p, sizeof p, "%s\\%s\\kick.wav", audio, linkname);
    wchar_t *pw = wl(p);
    HANDLE h = CreateFileW(pw, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    free(pw);
    CHECK(h != INVALID_HANDLE_VALUE, "(setup) a file opened through the junction");
    r = ef_remove(conf, audio, linkname, msg, sizeof msg);
    printf("remove with a file open: r=%d %s\n", r, msg);
    CHECK(r == 0 && strstr(msg, "not touched"), "remove while a file is open works");
    char rd[16] = {0}; DWORD g = 0; SetFilePointer(h, 0, NULL, FILE_BEGIN); ReadFile(h, rd, 9, &g, NULL); CloseHandle(h);
    CHECK(g == 9 && !strncmp(rd, "RIFF-kick", 9), "the open file could still be read");
    snprintf(p, sizeof p, "%s\\%s", audio, linkname);
    CHECK(!exists(p), "the junction is gone");
    snprintf(p, sizeof p, "%s\\kick.wav", music);
    CHECK(slurp(p, buf, sizeof buf) == 9 && !strcmp(buf, "RIFF-kick"), "the file in the real folder survives");
    snprintf(p, sizeof p, "%s\\notes.txt", music);
    CHECK(slurp(p, buf, sizeof buf) == 7 && !strcmp(buf, "keep me"), "the other file survives");
    CHECK(exists(music), "the real folder survives");

    /* a long target (over 260 characters), added and read through the junction */
    char longd[3000]; snprintf(longd, sizeof longd, "%s\\long", root); mk(longd);
    for (int i = 0; i < 6; i++) { char seg[80]; snprintf(seg, sizeof seg, "\\segment-number-%d-with-a-fairly-long-name-here", i); strcat(longd, seg); mk(longd); }
    put(longd, "deep.wav", "RIFF-deep");
    printf("long path length: %d\n", (int)strlen(longd));
    r = ef_add(conf, audio, dust, longd, msg, sizeof msg, name, sizeof name);
    printf("long add: r=%d %s\n", r, msg);
    CHECK(r >= 0 && strlen(longd) > 260, "a target path longer than 260 characters is added");
    snprintf(p, sizeof p, "%s\\%s\\deep.wav", audio, name);
    CHECK(slurp(p, buf, sizeof buf) == 9 && !strcmp(buf, "RIFF-deep"), "a file is read through the junction to the long path");
    r = ef_remove(conf, audio, name, msg, sizeof msg);
    CHECK(r == 0, "the long one is removed");
    snprintf(p, sizeof p, "%s\\deep.wav", longd);
    CHECK(slurp(p, buf, sizeof buf) == 9, "and its file survives");

    /* removing a junction to a folder that is gone */
    char gone[1400]; snprintf(gone, sizeof gone, "%s.gone", empty);
    CHECK(renamed(empty, gone), "(setup) the folder goes away");
    snprintf(p, sizeof p, "%s\\[ext] empty", audio);
    r = ef_remove(conf, audio, "[ext] empty", msg, sizeof msg);
    CHECK(r == 0 && !exists(p) && exists(gone), "a junction to a missing folder can be removed, nothing else moves");

    if (fails) { printf("EXTFOLDERS %d failed\n", fails); return 1; }
    printf("EXTFOLDERS all passed\n");
    return 0;
}
