/* dup_heal.h on Linux (POSIX file system behind the dh_ops table).
 *   dup_heal_test                          the self-contained cases
 *   dup_heal_test --tool EXT USER DUST DISABLED [PROGRAM]   runs the check on those folders and prints the log lines (used by dup_heal_sclang_test.sh with the real sclang) */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "dup_heal.h"

static char logbuf[16000], mfbuf[8000];
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)

static int p_listdir(const char *dir, void (*cb)(const char *, int, void *), void *ud) {
    DIR *d = opendir(dir);
    if (!d) return -1;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        char full[2048];
        snprintf(full, sizeof full, "%s/%s", dir, e->d_name);
        struct stat st;
        if (stat(full, &st) != 0) continue;
        cb(e->d_name, S_ISDIR(st.st_mode), ud);
    }
    closedir(d);
    return 0;
}
static char *p_readfile(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n > 2000000) { fclose(f); return NULL; }
    char *b = malloc((size_t)n + 1);
    size_t got = fread(b, 1, (size_t)n, f);
    b[got] = 0;
    fclose(f);
    return b;
}
static int p_exists(const char *p) { struct stat st; return stat(p, &st) == 0; }
static int p_move(const char *a, const char *b) { return rename(a, b); }
static void p_mkdirs(const char *p) {
    char t[2048];
    snprintf(t, sizeof t, "%s", p);
    for (char *q = t + 1; *q; q++) if (*q == '/') { *q = 0; mkdir(t, 0755); *q = '/'; }
    mkdir(t, 0755);
}
static void p_log(const char *l) { strncat(logbuf, l, sizeof logbuf - strlen(logbuf) - 2); strcat(logbuf, "\n"); }
static void p_manifest(const char *l) { strncat(mfbuf, l, sizeof mfbuf - strlen(mfbuf) - 2); strcat(mfbuf, "\n"); }
static const dh_ops ops = {p_listdir, p_readfile, p_exists, p_move, p_mkdirs, p_log, p_manifest};

static void wr(const char *path, const char *text) {
    char dir[2048];
    snprintf(dir, sizeof dir, "%s", path);
    char *s = strrchr(dir, '/');
    if (s) { *s = 0; p_mkdirs(dir); }
    FILE *f = fopen(path, "wb");
    fputs(text, f);
    fclose(f);
}
static void p(char *out, const char *base, const char *rel) { snprintf(out, 2048, "%s/%s", base, rel); }

int main(int argc, char **argv) {
    if (argc >= 6 && !strcmp(argv[1], "--tool")) {
        dh_root roots[4];
        int n = 0;
        roots[n++] = (dh_root){argv[2], DH_EXT_ROOT};
        roots[n++] = (dh_root){argv[3], DH_EXT_ROOT};
        roots[n++] = (dh_root){argv[4], DH_DUST_ROOT};
        if (argc >= 7) roots[n++] = (dh_root){argv[6], DH_PROGRAM_ROOT};
        dh_result r = dh_run(&ops, roots, n, argv[5]);
        fputs(logbuf, stdout);
        printf("moved=%d unresolved=%d note=[%s]\n", r.moved_units, r.unresolved_pairs, r.note);
        return 0;
    }
    char base[] = "/tmp/dhXXXXXX";
    if (!mkdtemp(base)) return 2;
    char ext[2048], usr[2048], dust[2048], prog[2048], dis[2048], a[2048];
    p(ext, base, "home/extensions"); p(usr, base, "home/.local/share/SuperCollider/Extensions"); p(dust, base, "home/dust"); p(prog, base, "app/sc/core"); p(dis, base, "home/disabled");
    dh_root roots[4] = {{ext, DH_EXT_ROOT}, {usr, DH_EXT_ROOT}, {dust, DH_DUST_ROOT}, {prog, DH_PROGRAM_ROOT}};
    dh_result r;

    /* 1. the report: the shipped pack in extensions, a copy of its classes (a script's unpacking) in the per-user folder */
    p(a, ext, "mi-UGens/PACK-ID.txt"); wr(a, "abc-L2\n");
    p(a, ext, "mi-UGens/Classes/MiBraids.sc"); wr(a, "// volker\nMiBraids : UGen {\n\t*ar { ^1 }\n}");
    p(a, ext, "mi-UGens/Classes/MiClouds.sc"); wr(a, "MiClouds : MultiOutUGen {\n}\n");
    p(a, usr, "mi-UGens/Classes/MiBraids.sc"); wr(a, "MiBraids : UGen { }\n");
    p(a, usr, "mi-UGens/Classes/MiClouds.sc"); wr(a, "MiClouds : MultiOutUGen { }\n");
    p(a, usr, "mi-UGens/Classes/MiOnlyHere.sc"); wr(a, "MiOnlyHere : UGen { }\n");
    p(a, dust, "code/script/script.lua"); wr(a, "-- a lua file\n");
    p(a, prog, "Crone.sc"); wr(a, "Crone {\n}\n");
    logbuf[0] = mfbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 1 && r.unresolved_pairs == 0, "1: one unit moved, nothing unresolved");
    p(a, ext, "mi-UGens/Classes/MiBraids.sc"); CHECK(p_exists(a), "1: the shipped pack is kept");
    p(a, usr, "mi-UGens"); CHECK(!p_exists(a), "1: the copy in the per-user folder is gone from there");
    p(a, dis, "mi-UGens-duplicate/Classes/MiOnlyHere.sc"); CHECK(p_exists(a), "1: the whole copy (with the file that was not a duplicate) is in disabled: nothing deleted");
    CHECK(strstr(logbuf, "MiBraids, MiClouds") && strstr(logbuf, "the pack Verdandi ships, kept") && strstr(logbuf, "/home/extensions/mi-UGens") && strstr(logbuf, ".local/share/SuperCollider/Extensions/mi-UGens"), "1: one plain line naming the classes and both paths");
    CHECK(strstr(mfbuf, "moved from") != NULL, "1: a MANIFEST line");
    CHECK(strstr(logbuf, "MiOnlyHere") == NULL, "1: a class defined once is not named");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 0 && r.unresolved_pairs == 0 && logbuf[0] == 0, "1: the second run (the next round) finds nothing: nothing happens");

    /* 2. a class in a comment, and in a help folder, is not a duplicate; a class name inside a string line is not at the start of a line */
    p(a, usr, "Other/Classes/O.sc"); wr(a, "/* MiBraids : UGen { } old copy */\n// MiClouds : UGen {\nOther : UGen { }\n");
    p(a, usr, "Other/Help/h.sc"); wr(a, "MiBraids : UGen { }\n");
    p(a, usr, "Other/linux/l.sc"); wr(a, "MiBraids : UGen { }\n");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 0 && r.unresolved_pairs == 0, "2: comments, help folders and platform folders are not duplicates");

    /* 3. two folders that are both the owner's: nothing is moved, said plainly */
    p(a, usr, "FoldA/FoldA.sc"); wr(a, "Shared : UGen { }\nSharedTwo : UGen { }\n");
    p(a, ext, "FoldB/FoldB.sc"); wr(a, "Shared : UGen { }\nSharedTwo : UGen { }\n");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 0 && r.unresolved_pairs == 1, "3: two folders of the owner: nothing moved, one finding");
    p(a, usr, "FoldA/FoldA.sc"); CHECK(p_exists(a), "3: both folders are still there");
    p(a, ext, "FoldB/FoldB.sc"); CHECK(p_exists(a), "3: ... both");
    CHECK(strstr(logbuf, "NOTHING was moved") && strstr(logbuf, "Shared, SharedTwo") && strstr(logbuf, "FoldA") && strstr(logbuf, "FoldB"), "3: the line names the classes and both folders");
    CHECK(strstr(r.note, "duplicate classes") && strstr(r.note, "move one by hand"), "3: a note for the norns screen");
    p(a, usr, "FoldA"); { char b2[2048]; p(b2, dis, "x"); (void)b2; }
    { char cmd[4200]; snprintf(cmd, sizeof cmd, "rm -rf '%s/FoldA' '%s/FoldB'", usr, ext); (void)!system(cmd); }

    /* 4. below dust only the file moves, and the script's other files stay */
    p(a, dust, "code/myscript/lib/MiClouds.sc"); wr(a, "MiClouds : MultiOutUGen { }\n");
    p(a, dust, "code/myscript/myscript.lua"); wr(a, "-- script\n");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 1, "4: the dust copy is moved");
    p(a, dust, "code/myscript/lib/MiClouds.sc"); CHECK(!p_exists(a), "4: the file is gone from dust");
    p(a, dust, "code/myscript/myscript.lua"); CHECK(p_exists(a), "4: the script itself stays");
    p(a, dis, "MiClouds.sc-duplicate"); CHECK(p_exists(a), "4: the file is in disabled");

    /* 5. a clash with the program's own class: nothing moved */
    p(a, ext, "mi-UGens/Classes/Crone.sc"); wr(a, "Crone { }\n");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 0 && r.unresolved_pairs == 1 && strstr(logbuf, "NOTHING was moved"), "5: a clash with the program's own class is reported, nothing moved");
    p(a, ext, "mi-UGens/Classes/Crone.sc"); unlink(a);

    /* 6. plug-in files: the same file name (any case) in two folders: the copy outside the shipped pack is moved */
    p(a, ext, "mi-UGens/plugins/MiBraids.scx"); wr(a, "MZ");
    p(a, usr, "Mine/plugins/mibraids.scx"); wr(a, "MZ2");
    p(a, usr, "Mine/plugins/Other.scx"); wr(a, "MZ3");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 1 && strstr(logbuf, "plug-in files (.scx)") && strstr(logbuf, "mibraids.scx"), "6: the duplicate plug-in file is moved and named");
    p(a, usr, "Mine/plugins/mibraids.scx"); CHECK(!p_exists(a), "6: gone from the per-user folder");
    p(a, usr, "Mine/plugins/Other.scx"); CHECK(p_exists(a), "6: a plug-in that is not a duplicate stays");
    p(a, ext, "mi-UGens/plugins/MiBraids.scx"); CHECK(p_exists(a), "6: the shipped plug-in stays");
    /* two plug-in files of the owner: nothing moved */
    p(a, usr, "Mine/plugins/Dup.scx"); wr(a, "MZ");
    p(a, ext, "Yours/plugins/dup.scx"); wr(a, "MZ");
    logbuf[0] = 0;
    r = dh_run(&ops, roots, 4, dis);
    CHECK(r.moved_units == 0 && r.unresolved_pairs == 1 && strstr(r.note, "plug-in files"), "6: two plug-in files of the owner: reported, not moved");

    { char cmd[4200]; snprintf(cmd, sizeof cmd, "rm -rf '%s'", base); (void)!system(cmd); }
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("dup_heal_test: ok\n");
    return 0;
}
