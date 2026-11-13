/* dup_heal.h: the same class defined in two files, and the same plug-in file in two folders (Windows launcher; the file system is reached through the dh_ops table, so linux/tests/dup_heal_test.c runs it on Linux).
 * sclang stops at the first class that two files define ("duplicate Class found", "Library has not been compiled successfully": nothing in norns starts) and scsynth would load two versions of a plug-in.
 * run before every start of sclang (docs/port/phase-m7.md section 9). the rules:
 *   - a class name is collected from every .sc file below the roots (comments stripped); two different files with the same class name = a duplicate
 *   - the copy in a pack Verdandi ships (an extension folder that carries PACK-ID.txt) is kept; the other copy is MOVED to <home>\disabled (a MANIFEST.txt line, never deleted):
 *       the unit moved is the extension folder (a direct child of extensions or of the per-user folder) or, below dust, the one file
 *   - two copies that are both the owner's (no shipped pack involved), or a clash with the program's own classes: NOTHING is moved, the finding is reported (launcher.log and the norns screen)
 *   - plug-in files (.scx): the same file name (any case) in two folders below the extension roots follows the same rules (the file is the unit)
 * paths are UTF-8 with '/' inside this file. */
#ifndef VERDANDI_DUP_HEAL_H
#define VERDANDI_DUP_HEAL_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int (*listdir)(const char *dir, void (*cb)(const char *name, int is_dir, void *ud), void *ud);
    char *(*readfile)(const char *path); /* malloc'ed, NUL-terminated; NULL when unreadable or too big */
    int (*exists)(const char *path);
    int (*move)(const char *from, const char *to); /* a file or a folder; 0 = moved */
    void (*mkdirs)(const char *path);
    void (*log)(const char *line);      /* one plain line for launcher.log */
    void (*manifest)(const char *line); /* one line for disabled/MANIFEST.txt */
} dh_ops;

typedef enum { DH_EXT_ROOT, DH_DUST_ROOT, DH_PROGRAM_ROOT } dh_rootkind;
typedef struct { const char *path; dh_rootkind kind; } dh_root;

typedef struct {
    int moved_units;       /* units moved to disabled */
    int unresolved_pairs;  /* duplicates that were left alone */
    char note[400];        /* the short text for the norns screen when something is unresolved ("" otherwise) */
} dh_result;

#define DH_MAXFILES 20000
#define DH_MAXCLASSES 60000

typedef struct { char *path; int root; int kind_shipped; int unit_len; } dh_file; /* unit_len: length of the unit's path inside path (extension folder), 0 = the file itself */
typedef struct { char name[80]; int file; } dh_class;

typedef struct {
    const dh_ops *ops;
    const dh_root *roots;
    int nroots;
    int curroot;
    dh_file *files;
    int nfiles;
    int scx_mode;
    char *stack_dir;
} dh_scan;

static inline int dh_ieq(const char *a, const char *b) {
    for (; *a && *b; a++, b++) {
        char x = (char)((*a >= 'A' && *a <= 'Z') ? *a + 32 : *a), y = (char)((*b >= 'A' && *b <= 'Z') ? *b + 32 : *b);
        if (x != y) return 0;
    }
    return *a == 0 && *b == 0;
}
static inline int dh_endswith_i(const char *s, const char *suffix) {
    size_t n = strlen(s), m = strlen(suffix);
    return n >= m && dh_ieq(s + n - m, suffix);
}
/* folders that sclang and scsynth do not look into (SC_Filesystem::shouldNotCompileDirectory) */
static inline int dh_skip_dir(const char *name) {
    return dh_ieq(name, "help") || dh_ieq(name, "ignore") || dh_ieq(name, ".git") || dh_ieq(name, ".svn") || dh_ieq(name, "_darcs") || dh_ieq(name, "linux") || dh_ieq(name, "osx") ||
           dh_ieq(name, "windows") || dh_ieq(name, "iphone");
}

/* the class names a text defines: at the start of a line (blanks before it allowed) a capital word followed by ':' or '{' or '[' ; comments are cut first. names go to out (max); returns how many */
static inline int dh_class_names(const char *text, char names[][80], int max) {
    size_t n = strlen(text);
    char *t = (char *)malloc(n + 1);
    if (!t) return 0;
    size_t j = 0;
    for (size_t i = 0; i < n;) {
        if (text[i] == '/' && i + 1 < n && text[i + 1] == '*') {
            i += 2;
            while (i + 1 < n && !(text[i] == '*' && text[i + 1] == '/')) { if (text[i] == '\n') t[j++] = '\n'; i++; }
            i = i + 2 <= n ? i + 2 : n;
        } else if (text[i] == '/' && i + 1 < n && text[i + 1] == '/') {
            while (i < n && text[i] != '\n') i++;
        } else {
            t[j++] = text[i++];
        }
    }
    t[j] = 0;
    int count = 0;
    char *line = t;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        char *p = line;
        while (*p == ' ' || *p == '\t' || *p == '\r') p++;
        if (*p >= 'A' && *p <= 'Z') {
            char *q = p;
            while ((*q >= 'A' && *q <= 'Z') || (*q >= 'a' && *q <= 'z') || (*q >= '0' && *q <= '9') || *q == '_') q++;
            size_t len = (size_t)(q - p);
            char *r = q;
            while (*r == ' ' || *r == '\t') r++;
            if (len > 0 && len < 80 && (*r == ':' || *r == '{' || *r == '[') && count < max) {
                int seen = 0;
                for (int k = 0; k < count; k++) if (strlen(names[k]) == len && strncmp(names[k], p, len) == 0) { seen = 1; break; }
                if (!seen) { memcpy(names[count], p, len); names[count][len] = 0; count++; }
            }
        }
        line = nl ? nl + 1 : NULL;
    }
    free(t);
    return count;
}

/* ---- walking ---- */
typedef struct { dh_scan *s; char dir[1100]; char **dirs; int ndirs, capdirs; } dh_walk;

static inline void dh_walk_cb(const char *name, int is_dir, void *ud) {
    dh_walk *w = (dh_walk *)ud;
    dh_scan *s = w->s;
    char full[1200];
    if (strlen(w->dir) + strlen(name) + 2 >= sizeof full) return;
    snprintf(full, sizeof full, "%s/%s", w->dir, name);
    if (is_dir) {
        if (dh_skip_dir(name)) return;
        if (w->ndirs == w->capdirs) { w->capdirs = w->capdirs ? w->capdirs * 2 : 16; w->dirs = (char **)realloc(w->dirs, (size_t)w->capdirs * sizeof(char *)); }
        w->dirs[w->ndirs++] = strdup(full);
        return;
    }
    if (!(s->scx_mode ? dh_endswith_i(name, ".scx") : dh_endswith_i(name, ".sc"))) return;
    if (s->nfiles >= DH_MAXFILES) return;
    dh_file *f = &s->files[s->nfiles++];
    f->path = strdup(full);
    f->root = s->curroot;
    f->kind_shipped = 0;
    f->unit_len = 0;
}

static inline void dh_walk_dir(dh_scan *s, const char *dir, int depth) {
    if (depth > 14) return;
    dh_walk w;
    memset(&w, 0, sizeof w);
    w.s = s;
    snprintf(w.dir, sizeof w.dir, "%s", dir);
    s->ops->listdir(dir, dh_walk_cb, &w);
    for (int i = 0; i < w.ndirs; i++) { dh_walk_dir(s, w.dirs[i], depth + 1); free(w.dirs[i]); }
    free(w.dirs);
}

/* the extension folder of a file below an extension root: the first path component after the root */
static inline int dh_unit_len(const char *path, const char *root) {
    size_t rl = strlen(root);
    if (strncmp(path, root, rl) != 0 || path[rl] != '/') return 0;
    const char *p = path + rl + 1;
    const char *slash = strchr(p, '/');
    return slash ? (int)(slash - path) : 0;
}

static inline void dh_collect(dh_scan *s, int scx_mode) {
    s->scx_mode = scx_mode;
    for (int r = 0; r < s->nroots; r++) {
        if (scx_mode && s->roots[r].kind != DH_EXT_ROOT) continue;
        s->curroot = r;
        int before = s->nfiles;
        dh_walk_dir(s, s->roots[r].path, 0);
        for (int i = before; i < s->nfiles; i++) {
            dh_file *f = &s->files[i];
            if (s->roots[r].kind == DH_EXT_ROOT) {
                int ul = dh_unit_len(f->path, s->roots[r].path);
                if (ul > 0) {
                    char marker[1300];
                    snprintf(marker, sizeof marker, "%.*s/PACK-ID.txt", ul, f->path);
                    f->unit_len = ul;
                    f->kind_shipped = s->ops->exists(marker);
                }
            }
        }
    }
}

static inline const char *dh_base(const char *p) { const char *s = strrchr(p, '/'); return s ? s + 1 : p; }

static inline int dh_cmp_class(const void *a, const void *b) {
    const dh_class *x = (const dh_class *)a, *y = (const dh_class *)b;
    int c = strcmp(x->name, y->name);
    return c ? c : (x->file - y->file);
}

/* a unit to move or a pair to report. one record per unit / per pair of units, with the classes (or file names) that caused it */
typedef struct { int a, b; char names[600]; int count; } dh_issue; /* a: file index kept (or first of the pair), b: file index to move (or second) */

static inline void dh_add_issue(dh_issue **v, int *n, int *cap, int a, int b, const char *name, int unit_a_len, int unit_b_len, const dh_file *files) {
    (void)unit_a_len; (void)unit_b_len;
    for (int i = 0; i < *n; i++) {
        const dh_file *x = &files[(*v)[i].b], *y = &files[b];
        int same = x->unit_len ? (x->unit_len == y->unit_len && strncmp(x->path, y->path, (size_t)x->unit_len) == 0) : strcmp(x->path, y->path) == 0;
        const dh_file *xa = &files[(*v)[i].a], *ya = &files[a];
        int samea = xa->unit_len ? (xa->unit_len == ya->unit_len && strncmp(xa->path, ya->path, (size_t)xa->unit_len) == 0) : strcmp(xa->path, ya->path) == 0;
        if (same && samea) {
            dh_issue *it = &(*v)[i];
            it->count++;
            if (strlen(it->names) + strlen(name) + 3 < sizeof it->names && it->count <= 8) { strcat(it->names, ", "); strcat(it->names, name); }
            return;
        }
    }
    if (*n == *cap) { *cap = *cap ? *cap * 2 : 8; *v = (dh_issue *)realloc(*v, (size_t)*cap * sizeof(dh_issue)); }
    dh_issue *it = &(*v)[(*n)++];
    it->a = a; it->b = b; it->count = 1;
    snprintf(it->names, sizeof it->names, "%s", name);
}

static inline void dh_unit_text(const dh_file *f, char *out, size_t n) {
    if (f->unit_len) snprintf(out, n, "%.*s", f->unit_len, f->path);
    else snprintf(out, n, "%s", f->path);
}

/* decide one duplicate between files i and j (i, j: indexes): returns 1 = move j, 2 = move i, 0 = leave alone and report */
static inline int dh_decide(const dh_scan *s, int i, int j) {
    const dh_file *a = &s->files[i], *b = &s->files[j];
    int ka = s->roots[a->root].kind, kb = s->roots[b->root].kind;
    if (ka == DH_PROGRAM_ROOT || kb == DH_PROGRAM_ROOT) return 0;
    if (a->kind_shipped && !b->kind_shipped) return 1;
    if (b->kind_shipped && !a->kind_shipped) return 2;
    return 0;
}

static inline void dh_resolve(dh_scan *s, dh_issue *v, int n, const char *what, const char *disabled_dir, dh_result *res) {
    for (int k = 0; k < n; k++) {
        dh_issue *it = &v[k];
        char ta[1300], tb[1300], line[5200];
        int d = dh_decide(s, it->a, it->b);
        if (d == 0) {
            dh_unit_text(&s->files[it->a], ta, sizeof ta);
            dh_unit_text(&s->files[it->b], tb, sizeof tb);
            snprintf(line, sizeof line, "duplicate %s (%d: %s%s) are defined in both %s and %s: neither is a pack Verdandi ships (or one is the program's own): NOTHING was moved. move one of the two folders out of the way by hand (never delete), or SuperCollider will not start", what, it->count, it->names, it->count > 8 ? ", ..." : "", ta, tb);
            s->ops->log(line);
            res->unresolved_pairs++;
            if (res->note[0] == 0) snprintf(res->note, sizeof res->note, "SuperCollider: duplicate %s (%.150s) in two folders of yours: move one by hand, see launcher.log", what, it->names);
            continue;
        }
        const dh_file *keep = &s->files[d == 1 ? it->a : it->b], *mv = &s->files[d == 1 ? it->b : it->a];
        dh_unit_text(keep, ta, sizeof ta);
        dh_unit_text(mv, tb, sizeof tb);
        /* a unit that is already gone (moved for an earlier finding) is skipped */
        if (!s->ops->exists(tb)) continue;
        char dest[1400];
        s->ops->mkdirs(disabled_dir);
        const char *base = dh_base(tb);
        for (int tries = 0; tries < 100; tries++) {
            if (tries == 0) snprintf(dest, sizeof dest, "%s/%s-duplicate", disabled_dir, base);
            else snprintf(dest, sizeof dest, "%s/%s-duplicate-%d", disabled_dir, base, tries + 1);
            if (!s->ops->exists(dest)) break;
        }
        if (s->ops->move(tb, dest) != 0) {
            snprintf(line, sizeof line, "duplicate %s (%d: %s) are defined in %s (shipped pack, kept) and in %s: that copy could NOT be moved to disabled (in use?): SuperCollider may not start", what, it->count, it->names, ta, tb);
            s->ops->log(line);
            res->unresolved_pairs++;
            continue;
        }
        snprintf(line, sizeof line, "duplicate %s (%d: %s%s) were defined in %s (the pack Verdandi ships, kept) and in %s: the second copy was moved to %s (nothing is deleted; a script that copies it again is handled the same way at every start)", what, it->count, it->names, it->count > 8 ? ", ..." : "", ta, tb, dest);
        s->ops->log(line);
        char mf[4400];
        snprintf(mf, sizeof mf, "duplicate %s: moved from %s to %s: %d name(s) were also defined in %s (the shipped copy)", what, tb, dest, it->count, ta);
        s->ops->manifest(mf);
        res->moved_units++;
    }
}

static inline void dh_free_files(dh_scan *s) {
    for (int i = 0; i < s->nfiles; i++) free(s->files[i].path);
    s->nfiles = 0;
}

/* the whole check. disabled_dir: <home>/disabled (UTF-8, '/'). returns the counts and the note for the screen */
static inline dh_result dh_run(const dh_ops *ops, const dh_root *roots, int nroots, const char *disabled_dir) {
    dh_result res;
    memset(&res, 0, sizeof res);
    dh_scan s;
    memset(&s, 0, sizeof s);
    s.ops = ops;
    s.roots = roots;
    s.nroots = nroots;
    s.files = (dh_file *)calloc(DH_MAXFILES, sizeof(dh_file));
    if (!s.files) return res;
    /* classes */
    dh_collect(&s, 0);
    dh_class *cls = (dh_class *)malloc(sizeof(dh_class) * DH_MAXCLASSES);
    int ncls = 0;
    if (cls) {
        for (int i = 0; i < s.nfiles; i++) {
            char *text = ops->readfile(s.files[i].path);
            if (!text) continue;
            char (*names)[80] = (char (*)[80])malloc(80 * 400);
            int nn = names ? dh_class_names(text, names, 400) : 0;
            for (int k = 0; k < nn && ncls < DH_MAXCLASSES; k++) { snprintf(cls[ncls].name, sizeof cls[ncls].name, "%s", names[k]); cls[ncls].file = i; ncls++; }
            free(names);
            free(text);
        }
        qsort(cls, (size_t)ncls, sizeof(dh_class), dh_cmp_class);
        dh_issue *issues = NULL; int nissues = 0, capissues = 0;
        for (int i = 0; i < ncls;) {
            int j = i + 1;
            while (j < ncls && strcmp(cls[j].name, cls[i].name) == 0) j++;
            if (j - i >= 2) {
                int first = cls[i].file;
                for (int k = i + 1; k < j; k++) {
                    int other = cls[k].file;
                    /* the shipped copy is the 'a' side where there is one, so that the report names the kept one first */
                    int a = first, b = other;
                    if (s.files[b].kind_shipped && !s.files[a].kind_shipped) { a = other; b = first; }
                    dh_add_issue(&issues, &nissues, &capissues, a, b, cls[i].name, 0, 0, s.files);
                }
            }
            i = j;
        }
        dh_resolve(&s, issues, nissues, "classes", disabled_dir, &res);
        free(issues);
        free(cls);
    }
    dh_free_files(&s);
    /* plug-in files: the same file name below the extension roots */
    dh_collect(&s, 1);
    {
        dh_issue *issues = NULL; int nissues = 0, capissues = 0;
        for (int i = 0; i < s.nfiles; i++) {
            for (int j = i + 1; j < s.nfiles; j++) {
                if (!dh_ieq(dh_base(s.files[i].path), dh_base(s.files[j].path))) continue;
                int a = i, b = j;
                if (s.files[b].kind_shipped && !s.files[a].kind_shipped) { a = j; b = i; }
                /* the plug-in unit is the FILE, not its folder */
                s.files[a].unit_len = 0; s.files[b].unit_len = 0;
                dh_add_issue(&issues, &nissues, &capissues, a, b, dh_base(s.files[i].path), 0, 0, s.files);
            }
        }
        dh_resolve(&s, issues, nissues, "plug-in files (.scx)", disabled_dir, &res);
        free(issues);
    }
    dh_free_files(&s);
    free(s.files);
    return res;
}
#endif
