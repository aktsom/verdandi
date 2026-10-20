/*
 * dust_import_test.c: platform/macos/dust_import.c on files made in a temporary folder
 *
 * cc -std=c11 -Wall -Wextra -I matron/src/platform/macos macos/tests/dust_import_test.c \
 *    matron/src/platform/macos/dust_import.c -o /tmp/dit && /tmp/dit
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
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

static char root[64];

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

int main(void) {
    snprintf(root, sizeof root, "/tmp/dust_import_XXXXXX");
    if (mkdtemp(root) == NULL) {
        return 1;
    }
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

    char dest[1024];
    const char *dust = at("dust");
    char dust_copy[512];
    snprintf(dust_copy, sizeof dust_copy, "%s", dust);

    CHECK(dust_import(dust_copy, at("in/kick.wav"), dest, sizeof dest), "import wav");
    CHECK(same_text("dust/audio/kick.wav", "kick"), "wav copied into dust/audio (%s)", dest);
    // a second time: nothing is overwritten
    CHECK(dust_import(dust_copy, at("in/kick.wav"), dest, sizeof dest), "import wav again");
    CHECK(same_text("dust/audio/kick 2.wav", "kick"), "second copy is 'kick 2.wav' (%s)", dest);
    CHECK(exists("in/kick.wav"), "the original stays");

    CHECK(dust_import(dust_copy, at("in/pack"), dest, sizeof dest), "import folder");
    CHECK(same_text("dust/audio/pack/drums/snare.flac", "snare"), "folder copied whole");
    CHECK(same_text("dust/audio/pack/readme.txt", "pack"), "folder copied with its other files");

    CHECK(dust_import(dust_copy, at("in/awake"), dest, sizeof dest), "import script folder");
    CHECK(same_text("dust/code/awake/awake.lua", "-- awake") && same_text("dust/code/awake/lib/x.lua", "-- lib"),
          "script folder in dust/code");
    CHECK(dust_import(dust_copy, at("in/tiny.lua"), dest, sizeof dest), "import lone script");
    CHECK(same_text("dust/code/tiny/tiny.lua", "-- tiny"), "lone script gets its folder (%s)", dest);
    CHECK(dust_import(dust_copy, at("in/tiny.lua"), dest, sizeof dest), "import lone script again");
    CHECK(same_text("dust/code/tiny 2/tiny.lua", "-- tiny"), "second copy in 'tiny 2' (%s)", dest);

    CHECK(!dust_import(dust_copy, at("in/notes.txt"), dest, sizeof dest), "txt is not imported");
    CHECK(!exists("dust/audio/notes.txt") && !exists("dust/code/notes.txt"), "txt left out");

    char cmd[128];
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", root);
    if (system(cmd) != 0) {
        printf("could not remove %s\n", root);
    }
    printf("%s: %d failures\n", failures ? "FAILED" : "dust import ok", failures);
    return failures != 0;
}
