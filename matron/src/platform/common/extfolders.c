/* extfolders.c: see extfolders.h. one set of rules, two backends (Windows junction through the wide API, POSIX symlink) */
#include "extfolders.h"
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <winioctl.h>
#define SEP '\\'
#else
#include <dirent.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#define SEP '/'
#endif

/* ============================== backend ============================== */

static void say(char *msg, size_t n, const char *s) {
    if (msg && n) {
        snprintf(msg, n, "%s", s);
    }
}

#ifdef _WIN32

#ifndef IO_REPARSE_TAG_MOUNT_POINT
#define IO_REPARSE_TAG_MOUNT_POINT 0xA0000003L
#endif
#ifndef IO_REPARSE_TAG_SYMLINK
#define IO_REPARSE_TAG_SYMLINK 0xA000000CL
#endif

/* UTF-8 -> a full wide path (made absolute; '\\?\' in front when it is long). the caller frees */
static wchar_t *wfull(const char *u8, int long_ok) {
    int n = MultiByteToWideChar(CP_UTF8, 0, u8, -1, NULL, 0);
    if (n <= 0) {
        return NULL;
    }
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (!w) {
        return NULL;
    }
    MultiByteToWideChar(CP_UTF8, 0, u8, -1, w, n);
    for (wchar_t *p = w; *p; p++) {
        if (*p == L'/') {
            *p = L'\\';
        }
    }
    if (wcsncmp(w, L"\\\\?\\", 4) == 0) {
        return w;
    }
    DWORD need = GetFullPathNameW(w, 0, NULL, NULL);
    if (need == 0) {
        free(w);
        return NULL;
    }
    wchar_t *full = (wchar_t *)malloc(((size_t)need + 8) * sizeof(wchar_t));
    if (!full) {
        free(w);
        return NULL;
    }
    DWORD got = GetFullPathNameW(w, need, full, NULL);
    free(w);
    if (got == 0 || got >= need) {
        free(full);
        return NULL;
    }
    if (long_ok && got >= 240 && !(full[0] == L'\\' && full[1] == L'\\')) {
        wchar_t *pre = (wchar_t *)malloc(((size_t)got + 8) * sizeof(wchar_t));
        if (pre) {
            wcscpy(pre, L"\\\\?\\");
            wcscat(pre, full);
            free(full);
            return pre;
        }
    }
    return full;
}

static int to_u8(const wchar_t *w, char *out, size_t n) {
    return WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)n, NULL, NULL) > 0 ? 0 : -1;
}

static int be_attr(const char *path, DWORD *attr) {
    wchar_t *w = wfull(path, 1);
    if (!w) {
        return -1;
    }
    DWORD a = GetFileAttributesW(w);
    free(w);
    if (a == INVALID_FILE_ATTRIBUTES) {
        return -1;
    }
    *attr = a;
    return 0;
}

static int be_exists(const char *path) { /* the entry itself, a link that points nowhere counts */
    DWORD a;
    return be_attr(path, &a) == 0;
}

static int be_is_dir(const char *path) {
    DWORD a;
    if (be_attr(path, &a) != 0) {
        return 0;
    }
    return (a & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

int ef_is_link(const char *path) {
    wchar_t *w = wfull(path, 1);
    if (!w) {
        return 0;
    }
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(w, &fd);
    free(w);
    if (h == INVALID_HANDLE_VALUE) {
        return 0;
    }
    FindClose(h);
    return (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
           (fd.dwReserved0 == IO_REPARSE_TAG_MOUNT_POINT || fd.dwReserved0 == IO_REPARSE_TAG_SYMLINK);
}

static int be_is_network(const char *path) {
    wchar_t *w = wfull(path, 0);
    if (!w) {
        return 0;
    }
    int net = 0;
    if (wcsncmp(w, L"\\\\?\\UNC\\", 8) == 0 || (w[0] == L'\\' && w[1] == L'\\' && w[2] != L'?' && w[2] != L'.')) {
        net = 1;
    } else {
        wchar_t root[MAX_PATH + 4];
        if (GetVolumePathNameW(w, root, MAX_PATH) && GetDriveTypeW(root) == DRIVE_REMOTE) {
            net = 1;
        }
    }
    free(w);
    return net;
}

/* the form two paths are compared in: absolute, '\\', no \\?\ prefix, no trailing '\\' (a root keeps it), lower case */
static int be_norm(const char *path, char *out, size_t n) {
    wchar_t *w = wfull(path, 0);
    if (!w) {
        return -1;
    }
    wchar_t *p = w;
    if (wcsncmp(p, L"\\\\?\\", 4) == 0 && wcsncmp(p, L"\\\\?\\UNC\\", 8) != 0) {
        p += 4;
    }
    size_t len = wcslen(p);
    while (len > 3 && p[len - 1] == L'\\') {
        p[--len] = 0;
    }
    CharLowerBuffW(p, (DWORD)len);
    int r = to_u8(p, out, n);
    free(w);
    return r;
}

static int be_make_link(const char *link, const char *target, char *why, size_t wn) {
    wchar_t *wl = wfull(link, 1);
    wchar_t *wt = wfull(target, 0);
    int rc = -1;
    HANDLE h = INVALID_HANDLE_VALUE;
    unsigned char *buf = NULL;
    if (!wl || !wt) {
        say(why, wn, "the path could not be read");
        goto done;
    }
    wchar_t *t = wt;
    if (wcsncmp(t, L"\\\\?\\", 4) == 0) {
        t += 4;
    }
    size_t tl = wcslen(t);
    while (tl > 3 && t[tl - 1] == L'\\') {
        t[--tl] = 0;
    }
    if (!CreateDirectoryW(wl, NULL)) {
        snprintf(why, wn, "the shortcut folder could not be made (error %lu)", (unsigned long)GetLastError());
        goto done;
    }
    h = CreateFileW(wl, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        snprintf(why, wn, "the shortcut could not be opened (error %lu)", (unsigned long)GetLastError());
        RemoveDirectoryW(wl);
        goto done;
    }
    size_t sub_len = (4 + tl) * sizeof(wchar_t), print_len = tl * sizeof(wchar_t);
    size_t data_len = 8 + sub_len + 2 + print_len + 2;
    size_t total = 8 + data_len;
    buf = (unsigned char *)calloc(1, total);
    if (!buf || data_len > 0xFFFF) {
        say(why, wn, "the path is too long for a shortcut");
        CloseHandle(h);
        h = INVALID_HANDLE_VALUE;
        RemoveDirectoryW(wl);
        goto done;
    }
    DWORD tag = IO_REPARSE_TAG_MOUNT_POINT;
    unsigned short dl = (unsigned short)data_len, so = 0, sl = (unsigned short)sub_len, po = (unsigned short)(sub_len + 2),
                   pl = (unsigned short)print_len;
    memcpy(buf, &tag, 4);
    memcpy(buf + 4, &dl, 2);
    memcpy(buf + 8, &so, 2);
    memcpy(buf + 10, &sl, 2);
    memcpy(buf + 12, &po, 2);
    memcpy(buf + 14, &pl, 2);
    wchar_t *pb = (wchar_t *)(buf + 16);
    wcscpy(pb, L"\\??\\");
    wcscat(pb, t);
    wcscpy((wchar_t *)(buf + 16 + sub_len + 2), t);
    DWORD got = 0;
    if (!DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, buf, (DWORD)total, NULL, 0, &got, NULL)) {
        snprintf(why, wn, "this drive does not allow shortcuts (error %lu): the dust folder must be on an NTFS drive", (unsigned long)GetLastError());
        CloseHandle(h);
        h = INVALID_HANDLE_VALUE;
        RemoveDirectoryW(wl);
        goto done;
    }
    rc = 0;
done:
    if (h != INVALID_HANDLE_VALUE) {
        CloseHandle(h);
    }
    free(buf);
    free(wl);
    free(wt);
    return rc;
}

/* RemoveDirectory on a junction or directory symlink takes away the link and nothing behind it. a real folder that has files in it fails here (not empty), and ef_remove checks before */
static int be_remove_link(const char *link) {
    wchar_t *w = wfull(link, 1);
    if (!w) {
        return -1;
    }
    BOOL ok = RemoveDirectoryW(w);
    free(w);
    return ok ? 0 : -1;
}

static int be_mkdirs(const char *path) {
    wchar_t *w = wfull(path, 1);
    if (!w) {
        return -1;
    }
    for (wchar_t *p = w + 3; *p; p++) {
        if (*p == L'\\') {
            *p = 0;
            CreateDirectoryW(w, NULL);
            *p = L'\\';
        }
    }
    CreateDirectoryW(w, NULL);
    DWORD a = GetFileAttributesW(w);
    free(w);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) ? 0 : -1;
}

static void be_listdir(const char *dir, void (*cb)(const char *name, int isdir, void *ud), void *ud) {
    char pat[2048];
    snprintf(pat, sizeof pat, "%s\\*", dir);
    wchar_t *w = wfull(pat, 1);
    if (!w) {
        return;
    }
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(w, &fd);
    free(w);
    if (h == INVALID_HANDLE_VALUE) {
        return;
    }
    do {
        if (fd.cFileName[0] == L'.' && (fd.cFileName[1] == 0 || (fd.cFileName[1] == L'.' && fd.cFileName[2] == 0))) {
            continue;
        }
        char name[1024];
        if (to_u8(fd.cFileName, name, sizeof name) == 0) {
            cb(name, (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0, ud);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

static FILE *be_fopen(const char *path, const char *mode) {
    wchar_t *w = wfull(path, 1);
    wchar_t wm[8] = {0};
    for (int i = 0; mode[i] && i < 7; i++) {
        wm[i] = (wchar_t)mode[i];
    }
    FILE *f = w ? _wfopen(w, wm) : NULL;
    free(w);
    return f;
}

static int be_replace(const char *from, const char *to) {
    wchar_t *a = wfull(from, 1), *b = wfull(to, 1);
    int rc = -1;
    if (a && b && MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING)) {
        rc = 0;
    }
    free(a);
    free(b);
    return rc;
}

#else /* POSIX */

static int be_exists(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0;
}

static int be_is_dir(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

int ef_is_link(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0 && S_ISLNK(st.st_mode);
}

static int be_is_network(const char *path) {
    (void)path;
    return 0;
}

static int be_norm(const char *path, char *out, size_t n) {
    char real[PATH_MAX];
    const char *p = realpath(path, real) ? real : path;
    snprintf(out, n, "%s", p);
    size_t len = strlen(out);
    while (len > 1 && out[len - 1] == '/') {
        out[--len] = 0;
    }
    return 0;
}

static int be_make_link(const char *link, const char *target, char *why, size_t wn) {
    if (symlink(target, link) != 0) {
        snprintf(why, wn, "the shortcut could not be made (%s)", strerror(errno));
        return -1;
    }
    return 0;
}

static int be_remove_link(const char *link) {
    return unlink(link);
}

static int be_mkdirs(const char *path) {
    char tmp[2048];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0777);
            *p = '/';
        }
    }
    mkdir(tmp, 0777);
    return be_is_dir(tmp) ? 0 : -1;
}

static void be_listdir(const char *dir, void (*cb)(const char *name, int isdir, void *ud), void *ud) {
    DIR *d = opendir(dir);
    if (!d) {
        return;
    }
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) {
            continue;
        }
        char full[2048];
        snprintf(full, sizeof full, "%s/%s", dir, e->d_name);
        cb(e->d_name, be_is_dir(full), ud);
    }
    closedir(d);
}

static FILE *be_fopen(const char *path, const char *mode) {
    return fopen(path, mode);
}

static int be_replace(const char *from, const char *to) {
    return rename(from, to);
}

#endif

/* ============================== the rules ============================== */

static int is_sep(char c) {
    return c == '/' || c == '\\';
}

static void join(char *out, size_t n, const char *dir, const char *name) {
    size_t l = strlen(dir);
    while (l > 0 && is_sep(dir[l - 1])) {
        l--;
    }
    snprintf(out, n, "%.*s%c%s", (int)l, dir, SEP, name);
}

/* the link name is "[ext] " + something without a separator, a ".." or a control character */
static int name_ok(const char *name) {
    size_t pre = strlen(EF_PREFIX);
    if (!name || strncmp(name, EF_PREFIX, pre) != 0 || strlen(name) <= pre || strlen(name) >= 190) {
        return 0;
    }
    for (const char *p = name; *p; p++) {
        if (is_sep(*p) || (unsigned char)*p < 32 || *p == ':' || *p == '*' || *p == '?' || *p == '"' || *p == '<' || *p == '>' || *p == '|') {
            return 0;
        }
    }
    if (strstr(name, "..")) {
        return 0;
    }
    return 1;
}

/* the name of a folder for the link: the last part of the path, without characters a Windows name cannot hold */
static void base_name(const char *path, char *out, size_t n) {
    char tmp[1100];
    snprintf(tmp, sizeof tmp, "%s", path);
    size_t l = strlen(tmp);
    while (l > 0 && is_sep(tmp[l - 1])) {
        tmp[--l] = 0;
    }
    const char *b = tmp;
    for (const char *p = tmp; *p; p++) {
        if (is_sep(*p)) {
            b = p + 1;
        }
    }
    char name[200];
    snprintf(name, sizeof name, "%.150s", b);
    if (name[0] == 0) {
        snprintf(name, sizeof name, "folder");
    } else if (strlen(name) == 2 && name[1] == ':') {
        snprintf(name, sizeof name, "Drive %c", name[0]);
    }
    for (char *p = name; *p; p++) {
        if (*p == ':' || *p == '*' || *p == '?' || *p == '"' || *p == '<' || *p == '>' || *p == '|' || *p == '/' || *p == '\\' || (unsigned char)*p < 32) {
            *p = '_';
        }
    }
    size_t len = strlen(name);
    if (len > 80) { /* not in the middle of a UTF-8 character */
        len = 80;
        while (len > 0 && ((unsigned char)name[len] & 0xC0) == 0x80) {
            len--;
        }
        name[len] = 0;
    }
    while (len > 0 && (name[len - 1] == '.' || name[len - 1] == ' ')) {
        name[--len] = 0;
    }
    if (len == 0) {
        snprintf(name, sizeof name, "folder");
    }
    snprintf(out, n, "%s%s", EF_PREFIX, name);
}

static int ends_audio(const char *name) {
    const char *dot = strrchr(name, '.');
    if (!dot) {
        return 0;
    }
    static const char *ext[] = {"wav", "wave", "aif", "aiff", "aifc", "flac", "ogg", "mp3"};
    char low[8];
    size_t l = strlen(dot + 1);
    if (l == 0 || l >= sizeof low) {
        return 0;
    }
    for (size_t i = 0; i < l; i++) {
        low[i] = (char)tolower((unsigned char)dot[1 + i]);
    }
    low[l] = 0;
    for (size_t i = 0; i < sizeof ext / sizeof *ext; i++) {
        if (!strcmp(low, ext[i])) {
            return 1;
        }
    }
    return 0;
}

typedef struct {
    char (*names)[256];
    unsigned char *dirs;
    int n, max;
} lst_t;

static void lst_add(const char *name, int isdir, void *ud) {
    lst_t *l = (lst_t *)ud;
    if (l->n < l->max) {
        snprintf(l->names[l->n], 256, "%s", name);
        l->dirs[l->n] = (unsigned char)isdir;
        l->n++;
    }
}

static int scan(const char *dir, int depth, int *budget) {
    lst_t l = {malloc(512 * 256), malloc(512), 0, 512};
    int found = 0;
    if (!l.names || !l.dirs) {
        free(l.names);
        free(l.dirs);
        return 0;
    }
    be_listdir(dir, lst_add, &l);
    for (int i = 0; i < l.n && !found && *budget > 0; i++) {
        (*budget)--;
        if (!l.dirs[i]) {
            found = ends_audio(l.names[i]);
        }
    }
    for (int i = 0; i < l.n && !found && depth > 0 && *budget > 0; i++) {
        if (l.dirs[i]) {
            char sub[2048];
            join(sub, sizeof sub, dir, l.names[i]);
            found = scan(sub, depth - 1, budget);
        }
    }
    free(l.names);
    free(l.dirs);
    return found;
}

int ef_scan_audio(const char *dir, int depth) {
    int budget = 4000;
    return scan(dir, depth, &budget);
}

/* ---- the config file: name<TAB>path, one entry a line, '#' lines are comments ---- */

typedef struct {
    int n;
    ef_item it[EF_MAX];
} conf_t;

static void conf_read(const char *conf, conf_t *c) {
    c->n = 0;
    FILE *f = be_fopen(conf, "rb");
    if (!f) {
        return;
    }
    char line[1400];
    while (c->n < EF_MAX && fgets(line, sizeof line, f)) {
        size_t l = strlen(line);
        while (l > 0 && (line[l - 1] == '\n' || line[l - 1] == '\r')) {
            line[--l] = 0;
        }
        char *tab = strchr(line, '\t');
        if (line[0] == '#' || !tab) {
            continue;
        }
        *tab = 0;
        if (!name_ok(line) || tab[1] == 0 || strlen(tab + 1) >= sizeof((ef_item *)0)->path) { /* an edited or damaged line is skipped, never acted on */
            continue;
        }
        ef_item *it = &c->it[c->n++];
        snprintf(it->name, sizeof it->name, "%.190s", line);
        snprintf(it->path, sizeof it->path, "%s", tab + 1);
        it->state = EF_OK;
    }
    fclose(f);
}

static int conf_write(const char *conf, const conf_t *c) {
    char tmp[2100];
    snprintf(tmp, sizeof tmp, "%s.tmp", conf);
    FILE *f = be_fopen(tmp, "wb");
    if (!f) {
        return -1;
    }
    fprintf(f, "# folders added in SYSTEM > EXTRA FOLDERS: link name, a tab, the folder. edit them there, not here\n");
    for (int i = 0; i < c->n; i++) {
        fprintf(f, "%s\t%s\n", c->it[i].name, c->it[i].path);
    }
    int bad = ferror(f);
    if (fclose(f) != 0 || bad) {
        return -1;
    }
    return be_replace(tmp, conf);
}

static int state_of(const char *audio, const ef_item *it) {
    char link[2048];
    join(link, sizeof link, audio, it->name);
    int exists = be_exists(link), is_link = ef_is_link(link);
    int target = be_is_dir(it->path);
    if (exists && !is_link) {
        return EF_BLOCKED;
    }
    if (!target) {
        return EF_MISSING;
    }
    return is_link ? EF_OK : EF_NOLINK;
}

int ef_list(const char *conf, const char *audio, ef_item *out, int max) {
    conf_t *c = (conf_t *)malloc(sizeof *c);
    if (!c) {
        return 0;
    }
    conf_read(conf, c);
    int n = c->n < max ? c->n : max;
    for (int i = 0; i < n; i++) {
        out[i] = c->it[i];
        out[i].state = state_of(audio, &c->it[i]);
    }
    free(c);
    return n;
}

int ef_sync(const char *conf, const char *audio) {
    conf_t *c = (conf_t *)malloc(sizeof *c);
    int made = 0;
    if (!c) {
        return 0;
    }
    conf_read(conf, c);
    be_mkdirs(audio);
    for (int i = 0; i < c->n; i++) {
        if (state_of(audio, &c->it[i]) == EF_NOLINK) {
            char link[2048], why[200];
            join(link, sizeof link, audio, c->it[i].name);
            if (be_make_link(link, c->it[i].path, why, sizeof why) == 0) {
                made++;
            } else {
                fprintf(stderr, "extra folders: %s: %s\n", c->it[i].name, why);
            }
        }
    }
    free(c);
    return made;
}

static int inside(const char *a, const char *b) { /* a is b or lies in b (both normalised) */
    size_t lb = strlen(b);
    if (strncmp(a, b, lb) != 0) {
        return 0;
    }
    return a[lb] == 0 || is_sep(a[lb]) || (lb > 0 && is_sep(b[lb - 1]));
}

int ef_add(const char *conf, const char *audio, const char *dust, const char *target, char *msg, size_t n, char *name_out, size_t nn) {
    if (name_out && nn) {
        name_out[0] = 0;
    }
    if (!target || !*target) {
        say(msg, n, "No folder was chosen.");
        return -1;
    }
    char path[1024];
    if (strlen(target) >= sizeof path - 4) {
        say(msg, n, "That path is too long to keep in the list.");
        return -1;
    }
    snprintf(path, sizeof path, "%s", target);
    size_t pl = strlen(path);
    while (pl > 3 && is_sep(path[pl - 1])) {
        path[--pl] = 0;
    }
    for (const char *p = path; *p; p++) {
        if ((unsigned char)*p < 32) {
            say(msg, n, "That folder name has a character norns cannot keep in its list.");
            return -1;
        }
    }
    if (be_is_network(path)) {
        say(msg, n, "A folder on the network cannot be added. Copy the files to this computer, or add a folder on a drive inside it.");
        return -1;
    }
    if (!be_is_dir(path)) {
        say(msg, n, "That folder is not there (or it is a file).");
        return -1;
    }
    char np[2100], nd[2100];
    if (be_norm(path, np, sizeof np) != 0 || be_norm(dust, nd, sizeof nd) != 0) {
        say(msg, n, "That path could not be read.");
        return -1;
    }
    if (inside(np, nd)) {
        say(msg, n, "That folder is inside dust already: norns sees it without a shortcut.");
        return -1;
    }
    if (inside(nd, np)) {
        say(msg, n, "That folder contains the dust folder: a shortcut to it would loop. Choose a folder inside it.");
        return -1;
    }
    conf_t *c = (conf_t *)malloc(sizeof *c);
    if (!c) {
        say(msg, n, "Out of memory.");
        return -1;
    }
    conf_read(conf, c);
    if (c->n >= EF_MAX) {
        free(c);
        say(msg, n, "That is the most folders that can be added. Remove one first.");
        return -1;
    }
    for (int i = 0; i < c->n; i++) {
        char other[2100];
        if (be_norm(c->it[i].path, other, sizeof other) == 0 && strcmp(other, np) == 0) {
            snprintf(msg, n, "That folder is already added as %s.", c->it[i].name);
            free(c);
            return -1;
        }
    }
    if (be_mkdirs(audio) != 0) {
        free(c);
        say(msg, n, "The dust audio folder could not be made.");
        return -1;
    }
    char base[200], name[200], link[2048], why[240];
    base_name(path, base, sizeof base);
    snprintf(name, sizeof name, "%s", base);
    for (int k = 2; k < 1000; k++) {
        join(link, sizeof link, audio, name);
        int taken = be_exists(link);
        for (int i = 0; i < c->n && !taken; i++) {
            taken = !strcmp(c->it[i].name, name);
        }
        if (!taken) {
            break;
        }
        snprintf(name, sizeof name, "%.150s %d", base, k);
    }
    if (be_make_link(link, path, why, sizeof why) != 0) {
        snprintf(msg, n, "Could not add it: %s.", why);
        free(c);
        return -1;
    }
    ef_item *it = &c->it[c->n++];
    snprintf(it->name, sizeof it->name, "%s", name);
    snprintf(it->path, sizeof it->path, "%s", path);
    it->state = EF_OK;
    if (conf_write(conf, c) != 0) {
        be_remove_link(link);
        free(c);
        say(msg, n, "Could not save the list of folders, so nothing was added.");
        return -1;
    }
    free(c);
    if (name_out && nn) {
        snprintf(name_out, nn, "%s", name);
    }
    if (!ef_scan_audio(path, 3)) {
        snprintf(msg, n, "Added %s, but no audio files were found in it yet.", name);
        return 1;
    }
    snprintf(msg, n, "Added %s.", name);
    return 0;
}

int ef_remove(const char *conf, const char *audio, const char *name, char *msg, size_t n) {
    if (!name_ok(name)) {
        say(msg, n, "Not removed: that is not the name of an extra folder shortcut.");
        return -1;
    }
    conf_t *c = (conf_t *)malloc(sizeof *c);
    if (!c) {
        say(msg, n, "Out of memory.");
        return -1;
    }
    conf_read(conf, c);
    int idx = -1;
    for (int i = 0; i < c->n; i++) {
        if (!strcmp(c->it[i].name, name)) {
            idx = i;
        }
    }
    if (idx < 0) {
        free(c);
        say(msg, n, "Not removed: that folder is not in the list.");
        return -1;
    }
    char link[2048];
    join(link, sizeof link, audio, name);
    int exists = be_exists(link);
    if (exists && !ef_is_link(link)) {
        /* a real folder or file has this name: it is not ours, it stays. the entry is dropped from the list so it stops being shown */
        for (int i = idx; i + 1 < c->n; i++) {
            c->it[i] = c->it[i + 1];
        }
        c->n--;
        conf_write(conf, c);
        free(c);
        snprintf(msg, n, "%s is a real folder in dust, not a shortcut: it was left alone and taken off the list.", name);
        return 0;
    }
    if (exists && be_remove_link(link) != 0) {
        free(c);
        say(msg, n, "Not removed: the shortcut could not be taken away (is something using it?).");
        return -1;
    }
    for (int i = idx; i + 1 < c->n; i++) {
        c->it[i] = c->it[i + 1];
    }
    c->n--;
    int w = conf_write(conf, c);
    free(c);
    if (w != 0) {
        say(msg, n, "The shortcut is gone, but the list could not be saved.");
        return -1;
    }
    snprintf(msg, n, "Removed %s. Your files were not touched.", name);
    return 0;
}
