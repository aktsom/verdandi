/*
 * dust_import_test.c: platform/macos/dust_import.c on files made in a temporary folder
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos macos/tests/dust_import_test.c \
 *    matron/src/platform/macos/dust_import.c -o /tmp/dit && /tmp/dit [dir on another disk]
 *
 * with a folder on another disk (an exFAT stick, a network share) as argument it also checks
 * that audio ends up readable there: linked where the disk holds links (macOS does on exFAT),
 * copied where it does not.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "dust_import.h"

static int failures = 0;

#define CHECK(cond, ...)                                                                                               \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                                \
            printf(__VA_ARGS__);                                                                                       \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

static char root[1024];

static void put(const char *rel, const char *text) {
    char p[512];
    snprintf(p, sizeof p, "%s/%s", root, rel);
    FILE *f = fopen(p, "w");
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

static void dir(const char *rel) {
    char p[512];
    snprintf(p, sizeof p, "%s/%s", root, rel);
    mkdir(p, 0755);
}

static const char *at(const char *rel) {
    static char p[4][512];
    static int i = 0;
    i = (i + 1) % 4;
    snprintf(p[i], sizeof p[i], "%s/%s", root, rel);
    return p[i];
}

static int exists(const char *rel) {
    return access(at(rel), F_OK) == 0;
}

static int is_link_to(const char *rel, const char *target) {
    char buf[1024];
    ssize_t n = readlink(at(rel), buf, sizeof buf - 1);
    if (n < 0) {
        return 0;
    }
    buf[n] = '\0';
    return strcmp(buf, target) == 0;
}

static int same_text(const char *rel, const char *text) {
    char buf[256] = {0};
    FILE *f = fopen(at(rel), "r");
    if (f == NULL) {
        return 0;
    }
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    return n == strlen(text) && memcmp(buf, text, n) == 0;
}

static void make_inputs(void) {
    dir("in");
    dir("dust");
    put("in/kick.wav", "kick");
    put("in/Pad.AIFF", "pad");
    put("in/notes.txt", "no");
    put("in/song.mp3", "mp3");
    dir("in/pack");
    dir("in/pack/drums");
    put("in/pack/drums/snare.flac", "snare");
    put("in/pack/readme.txt", "pack");
    dir("in/empty");
    put("in/empty/a.txt", "x");
    dir("in/awake");
    put("in/awake/awake.lua", "-- awake");
    dir("in/awake/lib");
    put("in/awake/lib/x.lua", "-- lib");
    put("in/tiny.lua", "-- tiny");
    dir("other");
    put("other/kick.wav", "other kick");
    put("gone.wav", "soon gone");
}

static void remove_root(void) {
    char cmd[1200];
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", root);
    if (system(cmd) != 0) {
        printf("could not remove %s\n", root);
    }
}

// another disk: linked if it holds links, else copied, and it says which
static void test_other_disk(const char *base) {
    snprintf(root, sizeof root, "%s/dust_import_XXXXXX", base);
    if (mkdtemp(root) == NULL) {
        printf("FAIL: no scratch folder in %s\n", base);
        failures++;
        return;
    }
    make_inputs();
    char dust[1100], dest[1024];
    snprintf(dust, sizeof dust, "%s", at("dust"));
    int linked = -1;
    CHECK(dust_import(dust, at("in/kick.wav"), 1, dest, sizeof dest, &linked), "other disk: import");
    CHECK(linked ? is_link_to("dust/audio/mac/kick.wav", at("in/kick.wav")) : same_text("dust/audio/kick.wav", "kick"),
          "other disk: %s, %s", linked ? "linked" : "copied", dest);
    printf("other disk: audio %s\n", linked ? "linked" : "copied");
    remove_root();
}

int main(int argc, char **argv) {
    snprintf(root, sizeof root, "/tmp/dust_import_XXXXXX");
    if (mkdtemp(root) == NULL) {
        return 1;
    }
    make_inputs();

    // what goes where
    CHECK(dust_import_kind(at("in/kick.wav")) == DUST_AUDIO, "wav is audio");
    CHECK(dust_import_kind(at("in/Pad.AIFF")) == DUST_AUDIO, "upper case AIFF is audio");
    CHECK(dust_import_kind(at("in/song.mp3")) == DUST_AUDIO, "mp3 is audio");
    CHECK(dust_import_kind(at("in/notes.txt")) == DUST_SKIP, "txt is skipped");
    CHECK(dust_import_kind(at("in/pack")) == DUST_AUDIO, "folder with audio below is audio");
    CHECK(dust_import_kind(at("in/empty")) == DUST_SKIP, "folder without audio is skipped");
    CHECK(dust_import_kind(at("in/awake")) == DUST_SCRIPT, "folder with a lua file is a script");
    CHECK(dust_import_kind(at("in/tiny.lua")) == DUST_SCRIPT, "lone lua file is a script");
    CHECK(dust_import_kind(at("in/missing.wav")) == DUST_SKIP, "missing file");

    char dest[1024], dust[1100];
    snprintf(dust, sizeof dust, "%s", at("dust"));
    int linked = -1;

    // audio, linked: the original stays, dust/audio/mac points at it
    char kick[1100], pack[1100], other[1100], gone[1100];
    snprintf(kick, sizeof kick, "%s", at("in/kick.wav"));
    snprintf(pack, sizeof pack, "%s", at("in/pack"));
    snprintf(other, sizeof other, "%s", at("other/kick.wav"));
    snprintf(gone, sizeof gone, "%s", at("gone.wav"));
    CHECK(dust_import(dust, kick, 1, dest, sizeof dest, &linked), "link wav");
    CHECK(linked == 1 && is_link_to("dust/audio/mac/kick.wav", kick), "wav linked from dust/audio/mac (%s)", dest);
    CHECK(same_text("dust/audio/mac/kick.wav", "kick"), "the link reads the original");
    CHECK(!exists("dust/audio/kick.wav"), "nothing copied for a link");
    // the same file again: the same link, no "kick 2"
    CHECK(dust_import(dust, kick, 1, dest, sizeof dest, &linked), "link wav again");
    CHECK(linked == 1 && !exists("dust/audio/mac/kick 2.wav") && strstr(dest, "/mac/kick.wav") != NULL,
          "linking again reuses the link (%s)", dest);
    // another file with the same name: its own link
    CHECK(dust_import(dust, other, 1, dest, sizeof dest, &linked), "link other kick");
    CHECK(is_link_to("dust/audio/mac/kick 2.wav", other), "same name, other file: 'kick 2.wav' (%s)", dest);
    // a folder: one link to it; norns' file browser (ls -pL) sees a folder
    CHECK(dust_import(dust, pack, 1, dest, sizeof dest, &linked), "link folder");
    CHECK(is_link_to("dust/audio/mac/pack", pack) && same_text("dust/audio/mac/pack/drums/snare.flac", "snare"),
          "folder linked whole");
    // relative paths cannot be linked
    CHECK(!dust_import(dust, "in/kick.wav", 1, dest, sizeof dest, &linked), "relative path refused");
    // deleting a link loses nothing
    unlink(at("dust/audio/mac/kick.wav"));
    CHECK(same_text("in/kick.wav", "kick"), "removing the link keeps the original");

    // an original that goes away: its link is removed on the next import
    CHECK(dust_import(dust, gone, 1, dest, sizeof dest, &linked), "link gone.wav");
    unlink(gone);
    CHECK(dust_import(dust, kick, 1, dest, sizeof dest, &linked), "link wav after one went away");
    struct stat ls;
    CHECK(lstat(at("dust/audio/mac/gone.wav"), &ls) != 0, "dead link pruned");
    CHECK(is_link_to("dust/audio/mac/kick 2.wav", other), "live links stay");

    // audio, copied (option held): into dust/audio, never overwriting
    CHECK(dust_import(dust, kick, 0, dest, sizeof dest, &linked), "copy wav");
    CHECK(linked == 0 && same_text("dust/audio/kick.wav", "kick"), "wav copied into dust/audio (%s)", dest);
    CHECK(dust_import(dust, kick, 0, dest, sizeof dest, &linked), "copy wav again");
    CHECK(same_text("dust/audio/kick 2.wav", "kick"), "second copy is 'kick 2.wav' (%s)", dest);
    CHECK(dust_import(dust, pack, 0, dest, sizeof dest, &linked), "copy folder");
    CHECK(same_text("dust/audio/pack/drums/snare.flac", "snare") && same_text("dust/audio/pack/readme.txt", "pack"),
          "folder copied whole");
    lstat(at("dust/audio/pack"), &ls);
    CHECK(!S_ISLNK(ls.st_mode), "a copied folder is no link");

    // scripts are copied, also when linking is asked for
    CHECK(dust_import(dust, at("in/awake"), 1, dest, sizeof dest, &linked), "import script folder");
    lstat(at("dust/code/awake"), &ls);
    CHECK(linked == 0 && !S_ISLNK(ls.st_mode) && same_text("dust/code/awake/awake.lua", "-- awake") &&
              same_text("dust/code/awake/lib/x.lua", "-- lib"),
          "script folder copied to dust/code");
    CHECK(dust_import(dust, at("in/tiny.lua"), 1, dest, sizeof dest, &linked), "import lone script");
    CHECK(same_text("dust/code/tiny/tiny.lua", "-- tiny"), "lone script gets its folder (%s)", dest);
    CHECK(dust_import(dust, at("in/tiny.lua"), 0, dest, sizeof dest, &linked), "import lone script again");
    CHECK(same_text("dust/code/tiny 2/tiny.lua", "-- tiny"), "second copy in 'tiny 2' (%s)", dest);

    CHECK(!dust_import(dust, at("in/notes.txt"), 1, dest, sizeof dest, &linked), "txt is not imported");
    CHECK(!exists("dust/audio/notes.txt") && !exists("dust/audio/mac/notes.txt") && !exists("dust/code/notes.txt"),
          "txt left out");
    remove_root();

    // files that go away on their own are copied, not linked
    const char *tmp = "/var/folders/ab/xyz/T/", *home = "/Users/me";
    CHECK(dust_import_volatile("/var/folders/ab/xyz/T/norns-drops/1/memo.m4a", tmp, home), "TMPDIR is volatile");
    CHECK(dust_import_volatile("/private/var/folders/ab/c/T/x.wav", NULL, NULL), "/private/var/folders");
    CHECK(dust_import_volatile("/tmp/x.wav", NULL, NULL) && dust_import_volatile("/private/tmp/x.wav", NULL, NULL),
          "/tmp");
    CHECK(dust_import_volatile("/Users/me/Library/Caches/com.app/preview.wav", tmp, home), "a cache is volatile");
    CHECK(dust_import_volatile("/Users/me/.Trash/old.wav", tmp, home), "the trash is volatile");
    CHECK(dust_import_volatile("/Volumes/stick/.Trashes/501/old.wav", tmp, home), "a disk's trash is volatile");
    CHECK(!dust_import_volatile("/Users/me/Music/Samples/kick.wav", tmp, home), "a sample folder is not");
    CHECK(!dust_import_volatile("/Users/me/Library/CachesNot/kick.wav", tmp, home), "only the folder itself");
    CHECK(!dust_import_volatile("/tmpfoo/kick.wav", tmp, home), "/tmpfoo is not /tmp");
    CHECK(!dust_import_volatile("/Volumes/stick/kick.wav", NULL, NULL), "another disk is not");

    if (argc > 1) {
        test_other_disk(argv[1]);
    }
    printf("%s: %d failures\n", failures ? "FAILED" : "dust import ok", failures);
    return failures != 0;
}
