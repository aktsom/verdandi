/*
 * dust_import.c: see dust_import.h
 */

#if !defined(__APPLE__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE // copy_file_range
#endif

#ifdef __APPLE__
#include <copyfile.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#endif
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
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

#ifdef __APPLE__
static int copy_path(const char *path, const char *dest, int dir) {
    copyfile_flags_t flags = COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL;
    if (dir) {
        flags |= COPYFILE_RECURSIVE;
    }
    return copyfile(path, dest, NULL, flags) == 0;
}
#else
// everywhere else: what COPYFILE_DATA | COPYFILE_STAT | COPYFILE_EXCL | COPYFILE_RECURSIVE do.
// nothing that exists is overwritten; links inside a folder are copied as links; a failed
// copy removes what it made (copy_path)
#define COPY_MAX_DEPTH 32

static int copy_data(int in, int out) {
    int use_range = 1;
    char buf[1 << 16];
    for (;;) {
        if (use_range) {
            ssize_t n = copy_file_range(in, NULL, out, NULL, 1 << 24, 0);
            if (n > 0) {
                continue;
            }
            if (n == 0) {
                return 1;
            }
            // another file system, an old kernel: read and write
            if (errno != EXDEV && errno != ENOSYS && errno != EINVAL && errno != EOPNOTSUPP && errno != EBADF) {
                return 0;
            }
            use_range = 0;
        }
        ssize_t n = read(in, buf, sizeof buf);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return 0;
        }
        if (n == 0) {
            return 1;
        }
        for (ssize_t done = 0; done < n;) {
            ssize_t w = write(out, buf + done, (size_t)(n - done));
            if (w < 0) {
                if (errno == EINTR) {
                    continue;
                }
                return 0;
            }
            done += w;
        }
    }
}

static int copy_file(const char *src, const char *dst, const struct stat *st) {
    int in = open(src, O_RDONLY | O_CLOEXEC);
    if (in < 0) {
        return 0;
    }
    int out = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (out < 0) {
        close(in);
        return 0;
    }
    int ok = copy_data(in, out);
    struct timespec times[2] = {st->st_atim, st->st_mtim};
    ok = ok && fchmod(out, st->st_mode & 07777) == 0;
    // times are best effort (some file systems refuse)
    futimens(out, times);
    ok = close(out) == 0 && ok;
    close(in);
    if (!ok) {
        unlink(dst);
    }
    return ok;
}

static int copy_tree(const char *src, const char *dst, int depth);

static int copy_dir(const char *src, const char *dst, const struct stat *st, int depth) {
    if (depth > COPY_MAX_DEPTH || mkdir(dst, 0700) != 0) {
        return 0;
    }
    DIR *d = opendir(src);
    if (d == NULL) {
        return 0;
    }
    int ok = 1;
    struct dirent *e;
    while (ok && (e = readdir(d)) != NULL) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) {
            continue;
        }
        char from[2048], to[2048];
        if (snprintf(from, sizeof from, "%s/%s", src, e->d_name) >= (int)sizeof from ||
            snprintf(to, sizeof to, "%s/%s", dst, e->d_name) >= (int)sizeof to) {
            ok = 0;
            break;
        }
        ok = copy_tree(from, to, depth + 1);
    }
    closedir(d);
    // the folder's own mode last: a read-only folder could not be filled before
    return ok && chmod(dst, st->st_mode & 07777) == 0;
}

static int copy_tree(const char *src, const char *dst, int depth) {
    struct stat st;
    if (lstat(src, &st) != 0) {
        return 0;
    }
    if (S_ISDIR(st.st_mode)) {
        return copy_dir(src, dst, &st, depth);
    }
    if (S_ISLNK(st.st_mode)) {
        char target[2048];
        ssize_t n = readlink(src, target, sizeof target - 1);
        if (n < 0) {
            return 0;
        }
        target[n] = '\0';
        return symlink(target, dst) == 0;
    }
    if (S_ISREG(st.st_mode)) {
        return copy_file(src, dst, &st);
    }
    return 1; // sockets, fifos, devices: nothing to import
}

static void remove_tree(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) {
        return;
    }
    if (S_ISDIR(st.st_mode)) {
        chmod(path, 0700);
        DIR *d = opendir(path);
        if (d != NULL) {
            struct dirent *e;
            while ((e = readdir(d)) != NULL) {
                char sub[2048];
                if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..") &&
                    snprintf(sub, sizeof sub, "%s/%s", path, e->d_name) < (int)sizeof sub) {
                    remove_tree(sub);
                }
            }
            closedir(d);
        }
        rmdir(path);
    } else {
        unlink(path);
    }
}

static int copy_path(const char *path, const char *dest, int dir) {
    (void)dir;
    if (copy_tree(path, dest, 0)) {
        return 1;
    }
    // no half copy may look like an imported sample
    remove_tree(dest);
    return 0;
}
#endif

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
        if (copy_path(path, file, 0)) {
            return 1;
        }
#ifndef __APPLE__
        rmdir(dest);
#endif
        return 0;
    }
    return copy_path(path, dest, dir);
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
    if (under(path, tmpdir) || under_home(path, home, "Library/Caches") || under_home(path, home, ".Trash") ||
        strstr(path, "/.Trashes/") != NULL) {
        return 1;
    }
#ifndef __APPLE__
    // linux: the user's runtime and cache folders, the trash, a disk's trash
    const char *runtime = getenv("XDG_RUNTIME_DIR"), *cache = getenv("XDG_CACHE_HOME");
    return under(path, runtime) || under(path, cache) || under_home(path, home, ".cache") ||
           under_home(path, home, ".local/share/Trash") || strstr(path, "/.Trash-") != NULL;
#else
    return 0;
#endif
}
