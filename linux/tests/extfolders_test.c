/* extfolders.c with the POSIX (symlink) backend: the rules of "ext folders" (docs/port/phase-m8.md).
 * run from the repo root: cc -std=gnu11 -Wall -I matron/src/platform/common linux/tests/extfolders_test.c matron/src/platform/common/extfolders.c -o /tmp/eft && /tmp/eft
 * the Windows runner runs the same cases with the junction backend: windows/ci/extfolders_probe.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include "extfolders.h"
#include "dust_import.h" /* DUST_LINK_DIR: the folder the old Import links in */
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
static void put(const char *dir, const char *name, const char *text) {
    char p[2048]; snprintf(p, sizeof p, "%s/%s", dir, name);
    FILE *f = fopen(p, "wb"); if (f) { fputs(text, f); fclose(f); }
}
static int exists(const char *p) { struct stat st; return lstat(p, &st) == 0; }
static char *slurp(const char *p, char *buf, size_t n) { FILE *f = fopen(p, "rb"); size_t g = 0; if (f) { g = fread(buf, 1, n - 1, f); fclose(f); } buf[g] = 0; return buf; }
int main(void) {
    char root[256] = "/tmp/eftXXXXXX";
    if (!mkdtemp(root)) return 2;
    char dust[300], audio[320], conf[320], msg[300], name[200], p[1024], buf[256];
    snprintf(dust, sizeof dust, "%s/home dust/dust", root);
    snprintf(audio, sizeof audio, "%s/audio", dust);
    snprintf(conf, sizeof conf, "%s/ext-folders.conf", root);
    char cmd[1024]; snprintf(cmd, sizeof cmd, "mkdir -p '%s'", audio); if (system(cmd)) return 2;
    /* two music folders, one with an accent and a blank, one without audio */
    char music[400], music2[400], empty[400], real[400];
    snprintf(music, sizeof music, "%s/M\xc3\xbasica y sonidos", root);
    snprintf(music2, sizeof music2, "%s/other/M\xc3\xbasica y sonidos", root);
    snprintf(empty, sizeof empty, "%s/empty", root);
    snprintf(cmd, sizeof cmd, "mkdir -p '%s' '%s' '%s'", music, music2, empty); if (system(cmd)) return 2;
    put(music, "kick.wav", "RIFF-kick"); put(music, "notes.txt", "keep me"); put(music2, "snare.flac", "fLaC-snare");

    /* add */
    int r = ef_add(conf, audio, dust, music, msg, sizeof msg, name, sizeof name);
    CHECK(r == 0 && strcmp(name, "[ext] M\xc3\xbasica y sonidos") == 0, "add: link named [ext] + folder name (accent, blank)");
    snprintf(p, sizeof p, "%s/%s/kick.wav", audio, name);
    CHECK(strcmp(slurp(p, buf, sizeof buf), "RIFF-kick") == 0, "a script-like reader reads a file through the link");
    char listing[256] = ""; { snprintf(p, sizeof p, "%s/%s", audio, name); char c2[600]; snprintf(c2, sizeof c2, "ls '%s' | sort | tr '\\n' ' '", p); FILE *f = popen(c2, "r"); if (f) { size_t g = fread(listing, 1, 255, f); listing[g] = 0; pclose(f); } }
    CHECK(strstr(listing, "kick.wav") && strstr(listing, "notes.txt"), "a directory listing through the link shows the files");
    CHECK(ef_is_link(p), "ef_is_link on the link");

    /* the same folder twice */
    r = ef_add(conf, audio, dust, music, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "already added"), "the same folder twice is refused and says so");
    char slash[420]; snprintf(slash, sizeof slash, "%s/", music);
    r = ef_add(conf, audio, dust, slash, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "already added"), "the same folder with a trailing slash is refused too");

    /* a folder with the same last name elsewhere: a number */
    r = ef_add(conf, audio, dust, music2, msg, sizeof msg, name, sizeof name);
    CHECK(r == 0 && strcmp(name, "[ext] M\xc3\xbasica y sonidos 2") == 0, "name clash: the second is numbered");

    /* inside dust, containing dust, not a folder, not there, empty text, network-looking text (POSIX has none) */
    char inside_d[400]; snprintf(inside_d, sizeof inside_d, "%s/sub", audio); mkdir(inside_d, 0777);
    r = ef_add(conf, audio, dust, inside_d, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "inside dust"), "a folder inside dust is refused");
    r = ef_add(conf, audio, dust, root, msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "contains the dust"), "a folder that contains dust is refused (a loop)");
    snprintf(p, sizeof p, "%s/music/kick.wav", root);
    r = ef_add(conf, audio, dust, "/nonexistent/folder", msg, sizeof msg, NULL, 0);
    CHECK(r == -1 && strstr(msg, "not there"), "a missing folder is refused");
    char afile[400]; snprintf(afile, sizeof afile, "%s/kick.wav", music);
    r = ef_add(conf, audio, dust, afile, msg, sizeof msg, NULL, 0);
    CHECK(r == -1, "a file is refused");
    r = ef_add(conf, audio, dust, "", msg, sizeof msg, NULL, 0);
    CHECK(r == -1, "no folder is refused");

    /* no audio: added, with the note */
    r = ef_add(conf, audio, dust, empty, msg, sizeof msg, name, sizeof name);
    CHECK(r == 1 && strstr(msg, "no audio files"), "a folder without audio is added with a note");

    /* list */
    ef_item it[8]; int n = ef_list(conf, audio, it, 8);
    CHECK(n == 3 && it[0].state == EF_OK && it[1].state == EF_OK && it[2].state == EF_OK, "list: three entries, all reachable");

    /* restart: the link of an entry is gone (e.g. dust was restored without it): sync makes it again */
    snprintf(p, sizeof p, "%s/%s", audio, it[1].name); unlink(p);
    n = ef_list(conf, audio, it, 8);
    CHECK(it[1].state == EF_NOLINK, "link missing and folder there: shown as to be made again");
    CHECK(ef_sync(conf, audio) == 1 && ef_is_link(p), "sync re-creates the missing link");
    CHECK(ef_sync(conf, audio) == 0, "sync twice does nothing more");

    /* an unplugged drive / renamed target: the entry stays, shown as missing, nothing deleted */
    char moved[400]; snprintf(moved, sizeof moved, "%s.away", music2);
    rename(music2, moved);
    n = ef_list(conf, audio, it, 8);
    CHECK(n == 3 && it[1].state == EF_MISSING, "target renamed: entry kept, shown as unavailable");
    CHECK(ef_sync(conf, audio) == 0, "sync does not try to make a link to a missing folder");
    snprintf(p, sizeof p, "%s/%s", audio, it[1].name); CHECK(ef_is_link(p), "the old link is left (not deleted) while the target is away");
    rename(moved, music2);
    n = ef_list(conf, audio, it, 8);
    CHECK(it[1].state == EF_OK, "target back: reachable again");

    /* a real folder with the name of a link: blocked, never touched, never removed */
    snprintf(real, sizeof real, "%s/[ext] realone", audio);
    mkdir(real, 0777); put(real, "mine.wav", "REAL");
    FILE *f = fopen(conf, "ab"); fprintf(f, "[ext] realone\t%s\n", music); fclose(f);
    n = ef_list(conf, audio, it, 8);
    int found = 0; for (int i = 0; i < n; i++) if (!strcmp(it[i].name, "[ext] realone")) { found = 1; CHECK(it[i].state == EF_BLOCKED, "a real folder with the link's name is BLOCKED"); }
    CHECK(found, "the hand-edited line is listed");
    r = ef_remove(conf, audio, "[ext] realone", msg, sizeof msg);
    snprintf(p, sizeof p, "%s/mine.wav", real);
    CHECK(exists(real) && strcmp(slurp(p, buf, sizeof buf), "REAL") == 0, "remove on a real folder leaves it and its files alone");
    CHECK(strstr(msg, "real folder"), "...and says so");

    /* hand-edited config with names that are not ours: refused, nothing happens */
    CHECK(ef_remove(conf, audio, "kick", msg, sizeof msg) == -1, "a name without the marker is refused");
    CHECK(ef_remove(conf, audio, "[ext] ../x", msg, sizeof msg) == -1, "a name with .. is refused");
    CHECK(ef_remove(conf, audio, "[ext] a/b", msg, sizeof msg) == -1, "a name with a separator is refused");
    CHECK(ef_remove(conf, audio, "[ext] nothere", msg, sizeof msg) == -1, "a name that is not in the list is refused");
    char dustreal[400]; snprintf(dustreal, sizeof dustreal, "%s/tape", audio); mkdir(dustreal, 0777);
    CHECK(ef_remove(conf, audio, "tape", msg, sizeof msg) == -1 && exists(dustreal), "a real dust folder (tape) cannot be removed");

    /* remove while a script has a file from the folder open */
    snprintf(p, sizeof p, "%s/%s/kick.wav", audio, "[ext] M\xc3\xbasica y sonidos");
    int fd = open(p, O_RDONLY);
    CHECK(fd >= 0, "a file opened through the link");
    r = ef_remove(conf, audio, "[ext] M\xc3\xbasica y sonidos", msg, sizeof msg);
    CHECK(r == 0 && strstr(msg, "not touched"), "remove while a file is open works and says the files were not touched");
    char rd[16] = {0}; ssize_t g = read(fd, rd, 9); close(fd);
    CHECK(g == 9 && !strncmp(rd, "RIFF-kick", 9), "the open file can still be read");
    snprintf(p, sizeof p, "%s/%s", audio, "[ext] M\xc3\xbasica y sonidos");
    CHECK(!exists(p), "the link is gone");
    snprintf(p, sizeof p, "%s/kick.wav", music);
    CHECK(strcmp(slurp(p, buf, sizeof buf), "RIFF-kick") == 0, "the file in the real folder survives");
    snprintf(p, sizeof p, "%s/notes.txt", music);
    CHECK(strcmp(slurp(p, buf, sizeof buf), "keep me") == 0, "the other file in the real folder survives");
    n = ef_list(conf, audio, it, 8);
    int still = 0; for (int i = 0; i < n; i++) if (!strcmp(it[i].name, "[ext] M\xc3\xbasica y sonidos")) still = 1;
    CHECK(!still, "the entry is gone from the list");

    /* the config survives a restart: read again from disk */
    n = ef_list(conf, audio, it, 8);
    CHECK(n >= 2, "after a restart the list is read from the file again");

    /* removing a link whose target is gone works, and the other entries stay */
    snprintf(p, sizeof p, "%s/%s", audio, "[ext] empty");
    char gone[400]; snprintf(gone, sizeof gone, "%s.gone", empty); rename(empty, gone);
    CHECK(ef_remove(conf, audio, "[ext] empty", msg, sizeof msg) == 0 && !exists(p), "a link to a missing folder can be removed");
    CHECK(exists(gone), "...and nothing else moved");

    /* M27: the links the old Import made in dust/audio/mac: listed (links only), removed one by one, copies and real files never touched */
    CHECK(strcmp(DUST_LINK_DIR, EF_LEGACY_DIR) == 0, "the legacy folder name is the one dust_import.h makes links in");
    {
        char mac[400], orig[400], copy[400], realdir[400], lk[500];
        snprintf(mac, sizeof mac, "%s/" EF_LEGACY_DIR, audio);
        snprintf(cmd, sizeof cmd, "mkdir -p '%s'", mac); if (system(cmd)) return 2;
        CHECK(ef_legacy_list(audio, it, 8) == 0, "no old import links: an empty list");
        snprintf(orig, sizeof orig, "%s/orig-loop.wav", root); put(root, "orig-loop.wav", "RIFF-loop");
        snprintf(lk, sizeof lk, "%s/loop.wav", mac); if (symlink(orig, lk) != 0) return 2;
        snprintf(lk, sizeof lk, "%s/gone.wav", mac); if (symlink("/nonexistent/gone.wav", lk) != 0) return 2;
        put(mac, "copy.wav", "RIFF-a-copy");                              /* a real file in the same folder: a copy, never listed */
        snprintf(realdir, sizeof realdir, "%s/realdir", mac); mkdir(realdir, 0777);
        n = ef_legacy_list(audio, it, 8);
        CHECK(n == 2 && !strcmp(it[0].name, "gone.wav") && it[0].state == EF_MISSING && !strcmp(it[1].name, "loop.wav") && it[1].state == EF_OK, "the list has the two links, in order, one marked missing, no copy and no folder");
        CHECK(!strcmp(it[1].path, orig), "a link's path is where it points");
        CHECK(ef_legacy_remove(audio, "copy.wav", msg, sizeof msg) == -1 && strstr(msg, "not a link"), "a real file is refused (a copy is never removed)");
        snprintf(copy, sizeof copy, "%s/copy.wav", mac);
        CHECK(strcmp(slurp(copy, buf, sizeof buf), "RIFF-a-copy") == 0, "...and it is still there");
        CHECK(ef_legacy_remove(audio, "realdir", msg, sizeof msg) == -1 && exists(realdir), "a real folder is refused and stays");
        CHECK(ef_legacy_remove(audio, "../audio", msg, sizeof msg) == -1 && ef_legacy_remove(audio, "a/b", msg, sizeof msg) == -1 && ef_legacy_remove(audio, "", msg, sizeof msg) == -1 && ef_legacy_remove(audio, "..", msg, sizeof msg) == -1, "a name with a path in it is refused");
        CHECK(ef_legacy_remove(audio, "nothere.wav", msg, sizeof msg) == -1, "a missing name is refused");
        CHECK(ef_legacy_remove(audio, "loop.wav", msg, sizeof msg) == 0, "a link is removed");
        snprintf(lk, sizeof lk, "%s/loop.wav", mac);
        CHECK(!exists(lk), "...the link is gone");
        CHECK(strcmp(slurp(orig, buf, sizeof buf), "RIFF-loop") == 0, "...the original file is untouched");
        CHECK(ef_legacy_remove(audio, "gone.wav", msg, sizeof msg) == 0, "a link to a missing original is removed too");
        CHECK(ef_legacy_list(audio, it, 8) == 0, "no links left (the copy and the folder are not links)");
        /* a link in the ext folders' own place is not an old import link */
        CHECK(ef_legacy_remove(audio, "[ext] M\xc3\xbasica y sonidos", msg, sizeof msg) == -1, "an ext folder's name is not found in the import folder");
    }

    snprintf(cmd, sizeof cmd, "rm -rf '%s'", root); if (system(cmd)) {}
    if (fails) { printf("%d failed\n", fails); return 1; }
    printf("extfolders: all passed\n");
    return 0;
}
