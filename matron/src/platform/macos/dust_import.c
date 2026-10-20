/*
 * dust_import.c: see dust_import.h
 */

#include <copyfile.h>
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#include "dust_import.h"

static const char *audio_ext[] = {"wav", "wave", "aif", "aiff", "aifc", "flac", "ogg", "mp3", NULL};

static const char *ext_of(const char *name) {
    const char *dot = strrchr(name, '.');
    return dot != NULL && dot != name ? dot + 1 : "";
}

static int is_audio_name(const char *name) {
    const char *e = ext_of(name);
    for (int i = 0; audio_ext[i] != NULL; i++) {
        if (strcasecmp(e, audio_ext[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

static int is_lua_name(const char *name) {
    return strcasecmp(ext_of(name), "lua") == 0;
}

static const char *base_of(const char *path) {
    const char *s = strrchr(path, '/');
    return s != NULL ? s + 1 : path;
}

// depth-first: any audio file below dir (a few levels, sample packs nest)
static int has_audio(const char *dir, int depth) {
    DIR *d = opendir(dir);
    if (d == NULL) {
        return 0;
    }
    int found = 0;
    struct dirent *e;
    while (!found && (e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') {
            continue;
        }
        if (e->d_type == DT_DIR) {
            if (depth > 0) {
                char sub[2048];
                if (snprintf(sub, sizeof sub, "%s/%s", dir, e->d_name) < (int)sizeof sub) {
                    found = has_audio(sub, depth - 1);
                }
            }
        } else if (is_audio_name(e->d_name)) {
            found = 1;
        }
    }
    closedir(d);
    return found;
}

static int has_lua(const char *dir) {
    DIR *d = opendir(dir);
    if (d == NULL) {
        return 0;
    }
    int found = 0;
    struct dirent *e;
    while (!found && (e = readdir(d)) != NULL) {
        found = e->d_type != DT_DIR && e->d_name[0] != '.' && is_lua_name(e->d_name);
    }
    closedir(d);
    return found;
}

dust_kind_t dust_import_kind(const char *path) {
    struct stat st;
    if (path == NULL || stat(path, &st) != 0) {
        return DUST_SKIP;
    }
    if (S_ISDIR(st.st_mode)) {
        if (has_lua(path)) {
            return DUST_SCRIPT;
        }
        return has_audio(path, 4) ? DUST_AUDIO : DUST_SKIP;
    }
    if (!S_ISREG(st.st_mode)) {
        return DUST_SKIP;
    }
    if (is_audio_name(base_of(path))) {
        return DUST_AUDIO;
    }
    return is_lua_name(base_of(path)) ? DUST_SCRIPT : DUST_SKIP;
}

// where a link to path in dir would be, or is already: a link with this name that points
// at path is the one to reuse
static int same_link(const char *link, const char *path) {
    char target[2048];
    ssize_t n = readlink(link, target, sizeof target - 1);
    if (n < 0) {
        return 0;
    }
    target[n] = '\0';
    return strcmp(target, path) == 0;
}

int dust_import_dest(const char *dust, const char *path, int link, char *dest, size_t n) {
    dust_kind_t kind = dust_import_kind(path);
    if (kind == DUST_SKIP) {
        return 0;
    }
    // scripts are always copied
    link = link && kind == DUST_AUDIO;
    struct stat st;
    int dir = stat(path, &st) == 0 && S_ISDIR(st.st_mode);
    char name[1024];
    snprintf(name, sizeof name, "%s", base_of(path));
    // a path ending in '/' has no name of its own
    if (name[0] == '\0') {
        return 0;
    }
    // a lone script gets a folder named after it, as scripts live on norns
    char stem[1024];
    snprintf(stem, sizeof stem, "%s", name);
    const char *ext = "";
    if (!dir) {
        char *dot = strrchr(stem, '.');
        if (dot != NULL && dot != stem) {
            ext = name + (dot - stem);
            *dot = '\0';
        }
    }
    const char *sub = link ? "audio/" DUST_LINK_DIR : (kind == DUST_AUDIO ? "audio" : "code");
    int lone_script = kind == DUST_SCRIPT && !dir;
    for (int i = 1; i < 1000; i++) {
        char suffix[16] = "";
        if (i > 1) {
            snprintf(suffix, sizeof suffix, " %d", i);
        }
        int w;
        if (lone_script) {
            w = snprintf(dest, n, "%s/%s/%s%s", dust, sub, stem, suffix);
        } else {
            w = snprintf(dest, n, "%s/%s/%s%s%s", dust, sub, stem, suffix, ext);
        }
        if (w < 0 || (size_t)w >= n) {
            return 0;
        }
        struct stat ls;
        if (lstat(dest, &ls) != 0 || (link && same_link(dest, path))) {
            return 1;
        }
    }
    return 0;
}

void dust_prune_links(const char *dust) {
    char dir[2048];
    snprintf(dir, sizeof dir, "%s/audio/%s", dust, DUST_LINK_DIR);
    DIR *d = opendir(dir);
    if (d == NULL) {
        return;
    }
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        char p[4096];
        struct stat st;
        if (e->d_type != DT_LNK || snprintf(p, sizeof p, "%s/%s", dir, e->d_name) >= (int)sizeof p) {
            continue;
        }
        // the original is gone (moved, deleted, its disk unplugged)
        if (stat(p, &st) != 0) {
            unlink(p);
        }
    }
    closedir(d);
}

static int copy_into(const char *path, const char *dest, dust_kind_t kind) {
    struct stat st;
    int dir = stat(path, &st) == 0 && S_ISDIR(st.st_mode);
    if (!dir && kind == DUST_SCRIPT) {
        // <dust>/code/<name>/<name>.lua
        if (mkdir(dest, 0755) != 0) {
            return 0;
        }
        char file[2048];
        if (snprintf(file, sizeof file, "%s/%s", dest, base_of(path)) >= (int)sizeof file) {
            return 0;
        }
        return copyfile(path, file, NULL, COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL) == 0;
    }
    copyfile_flags_t flags = COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL;
    if (dir) {
        flags |= COPYFILE_RECURSIVE;
    }
    return copyfile(path, dest, NULL, flags) == 0;
}

int dust_import(const char *dust, const char *path, int link, char *dest, size_t n, int *linked) {
    *linked = 0;
    dust_kind_t kind = dust_import_kind(path);
    // a link must name the original from anywhere: an absolute path
    if (kind == DUST_SKIP || (link && path[0] != '/')) {
        return 0;
    }
    char parent[2048];
    snprintf(parent, sizeof parent, "%s/%s", dust, kind == DUST_AUDIO ? "audio" : "code");
    mkdir(parent, 0755);
    if (link && kind == DUST_AUDIO) {
        snprintf(parent, sizeof parent, "%s/audio/%s", dust, DUST_LINK_DIR);
        mkdir(parent, 0755);
        dust_prune_links(dust);
        if (!dust_import_dest(dust, path, 1, dest, n)) {
            return 0;
        }
        if (same_link(dest, path) || symlink(path, dest) == 0) {
            *linked = 1;
            return 1;
        }
        // a disk without links (exFAT, FAT): a copy then
    }
    if (!dust_import_dest(dust, path, 0, dest, n)) {
        return 0;
    }
    return copy_into(path, dest, kind);
}

static int under(const char *path, const char *dir) {
    size_t n = dir != NULL ? strlen(dir) : 0;
    while (n > 0 && dir[n - 1] == '/') {
        n--;
    }
    return n > 0 && strncmp(path, dir, n) == 0 && path[n] == '/';
}

static int under_home(const char *path, const char *home, const char *sub) {
    char d[2048];
    return home != NULL && home[0] != '\0' && snprintf(d, sizeof d, "%s/%s", home, sub) < (int)sizeof d &&
           under(path, d);
}

int dust_import_volatile(const char *path, const char *tmpdir, const char *home) {
    static const char *temp[] = {"/tmp", "/private/tmp", "/var/folders", "/private/var/folders", NULL};
    if (path == NULL) {
        return 0;
    }
    for (int i = 0; temp[i] != NULL; i++) {
        if (under(path, temp[i])) {
            return 1;
        }
    }
    return under(path, tmpdir) || under_home(path, home, "Library/Caches") || under_home(path, home, ".Trash") ||
           strstr(path, "/.Trashes/") != NULL;
}
