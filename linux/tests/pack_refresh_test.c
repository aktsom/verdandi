/* pack_refresh.h (the plug-in pack refresh rules of the Windows launcher): cc -std=gnu11 -Wall -I windows/launcher linux/tests/pack_refresh_test.c */
#include <stdio.h>
#include "pack_refresh.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
int main(void) {
    char b[64];
    pack_id_clean("  abc123-L2 \r\nsecond line\n", b, sizeof b); CHECK(strcmp(b, "abc123-L2") == 0, "marker: first line, trimmed");
    pack_id_clean("", b, sizeof b); CHECK(b[0] == 0, "marker: empty");
    pack_id_clean(NULL, b, sizeof b); CHECK(b[0] == 0, "marker: NULL");
    pack_id_clean("\n\nx", b, sizeof b); CHECK(strcmp(b, "x") == 0, "marker: blank lines first");
    pack_id_clean("0123456789", b, 5); CHECK(strcmp(b, "0123") == 0, "marker: bounded");
    CHECK(pack_decide(0, "A-L2", "", 0, 0) == PACK_COPY, "not there: copy");
    CHECK(pack_decide(0, "", "", 0, 0) == PACK_COPY, "not there, old seed: copy");
    CHECK(pack_decide(1, "A-L2", "A-L2", 0, 0) == PACK_KEEP, "same marker: keep");
    CHECK(pack_decide(1, "B-L2", "A-L2", 0, 0) == PACK_REPLACE, "other marker: replace");
    CHECK(pack_decide(1, "A-L2", "", 1, 0) == PACK_REPLACE, "the first release (no marker, our files): replace");
    CHECK(pack_decide(1, "A-L2", "", 0, 0) == PACK_KEEP, "no marker and not ours: the user's own folder is kept");
    CHECK(pack_decide(1, "", "A-L2", 0, 0) == PACK_KEEP, "a seed without marker never replaces");
    CHECK(pack_decide(1, "", "", 1, 0) == PACK_KEEP, "a seed without marker never replaces (first release folder)");
    CHECK(pack_decide(1, NULL, NULL, 0, 0) == PACK_KEEP, "NULL markers: keep");
    CHECK(pack_decide(1, "A-L2", "", 0, 1) == PACK_REPLACE, "no marker, plug-ins for another system only (a Linux copy unpacked by a script): replace");
    CHECK(pack_decide(1, "A-L2", "A-L2", 0, 1) == PACK_KEEP, "the same marker: keep, whatever is inside");
    CHECK(pack_decide(1, "", "", 0, 1) == PACK_KEEP, "a seed without marker never replaces");
    CHECK(pack_target_of("user\n") == PACK_IN_USER && pack_target_of("  USER  ") == PACK_IN_USER, "target: user");
    CHECK(pack_target_of("extensions") == PACK_IN_EXTENSIONS && pack_target_of("") == PACK_IN_EXTENSIONS && pack_target_of(NULL) == PACK_IN_EXTENSIONS && pack_target_of("username") == PACK_IN_EXTENSIONS, "target: anything else is extensions");
    CHECK(pack_legacy_place(0, "A", 1) == 0, "legacy: not there: nothing");
    CHECK(pack_legacy_place(1, "A-L2", 0) == 1 && pack_legacy_place(1, "", 1) == 1, "legacy: our marker, or the first release's layout: move it aside");
    CHECK(pack_legacy_place(1, "", 0) == 0, "legacy: a folder of the owner's own (no marker, not our layout): left alone");
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("pack_refresh_test: ok\n");
    return 0;
}
