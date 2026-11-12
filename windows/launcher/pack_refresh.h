/* pack_refresh.h: what to do with a plug-in pack of extensions-seed when the extensions folder already has a folder of the same name (Windows launcher; pure, linux/tests/pack_refresh_test.c).
 * every pack of the seed carries PACK-ID.txt (the revision of its sources and the layout of the folder). rules:
 *   - the folder is not there                                  -> COPY it
 *   - the seed has no PACK-ID.txt (an old kind of seed)         -> KEEP what is there (the old behaviour: nothing is ever overwritten)
 *   - the installed folder has a PACK-ID.txt: the same          -> KEEP;  another one -> REPLACE
 *   - the installed folder has none: it is the pack of the first release of the packs (0.8.0: it has a SOURCE-REVISION.txt and a plugins folder, written by our build, and no PACK-ID.txt) -> REPLACE;
 *     any other folder without a marker is the user's own and is KEPT, whatever its name
 * REPLACE never deletes: the launcher moves the old folder to <home>\disabled first (restorable, one line in the log). a folder of extensions that is not a pack of the seed is never looked at. */
#ifndef VERDANDI_PACK_REFRESH_H
#define VERDANDI_PACK_REFRESH_H
#include <string.h>

typedef enum { PACK_COPY, PACK_KEEP, PACK_REPLACE } pack_action;

/* the first line of a marker text, without line ends and blanks at both ends, copied to out (empty when there is none) */
static inline void pack_id_clean(const char *text, char *out, size_t n) {
    size_t i = 0, j = 0;
    if (!text || n == 0) {
        if (n) out[0] = 0;
        return;
    }
    while (text[i] == ' ' || text[i] == '\t' || text[i] == '\r' || text[i] == '\n') i++;
    while (text[i] && text[i] != '\r' && text[i] != '\n' && j + 1 < n) out[j++] = text[i++];
    while (j > 0 && (out[j - 1] == ' ' || out[j - 1] == '\t')) j--;
    out[j] = 0;
}

/* seed_id, inst_id: the cleaned markers ("" when missing); inst_exists: the folder is there; inst_first_release: it has SOURCE-REVISION.txt and a plugins folder */
static inline pack_action pack_decide(int inst_exists, const char *seed_id, const char *inst_id, int inst_first_release) {
    if (!inst_exists) return PACK_COPY;
    if (!seed_id || !seed_id[0]) return PACK_KEEP;
    if (inst_id && inst_id[0]) return strcmp(seed_id, inst_id) == 0 ? PACK_KEEP : PACK_REPLACE;
    return inst_first_release ? PACK_REPLACE : PACK_KEEP;
}
#endif
