/* extfolders.h: extra sample folders anywhere on the computer, shown inside dust/audio as links named "[ext] <folder name>" (docs/port/phase-m8.md).
 * a Windows junction or a POSIX symlink, so the norns browser, the tape page and scripts need no change. paths are UTF-8 ('/' or '\' on Windows).
 * the rules (what is refused, how a link is removed) live in extfolders.c and are the same for both backends. removing never touches the target: only the link, and only a real link. */
#ifndef VERDANDI_EXTFOLDERS_H
#define VERDANDI_EXTFOLDERS_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

#define EF_PREFIX "[ext] "
#define EF_MAX 64

enum {
    EF_OK = 0,      /* the link is there and the folder is reachable */
    EF_MISSING = 1, /* the folder is not reachable now (an unplugged drive, renamed, deleted): the entry stays */
    EF_NOLINK = 2,  /* the folder is there, the link is not (it is made again at the next start, or now by ef_sync) */
    EF_BLOCKED = 3, /* a real folder or file has the name of the link: left alone, never touched */
};

typedef struct {
    char name[200];  /* the link name, "[ext] Samples" */
    char path[1024]; /* the folder, as it was added */
    int state;
} ef_item;

/* the entries of the config file with their state. returns how many (at most max) */
int ef_list(const char *conf, const char *audio_dir, ef_item *out, int max);

/* add a folder. 0 = added; 1 = added, the text says "no audio files found yet"; -1 = refused (the text says why, in plain words). name_out (may be NULL) gets the link name */
int ef_add(const char *conf, const char *audio_dir, const char *dust_dir, const char *target, char *msg, size_t n, char *name_out, size_t nn);

/* remove an entry: the link (only if it really is a link) and the line of the config file. 0 = done, -1 = refused (the text says why). the folder itself is never touched */
int ef_remove(const char *conf, const char *audio_dir, const char *name, char *msg, size_t n);

/* at start: a link that is missing is made again when its folder is there. nothing is deleted. returns how many were made */
int ef_sync(const char *conf, const char *audio_dir);

/* 1 when an audio file (wav wave aif aiff aifc flac ogg mp3) is found within depth levels (and the first few thousand entries) */
int ef_scan_audio(const char *dir, int depth);

/* 1 = a link (symlink; on Windows a junction or symbolic link, a reparse point), 0 = a real folder, a file, or not there */
int ef_is_link(const char *path);

/* the links an older "Import" (macOS, and Linux before 0.10.16) made in dust/audio/<EF_LEGACY_DIR>: audio linked from where it was. only real symlinks are listed (name = the file name, path = where it points,
 * state EF_OK or EF_MISSING when the original is gone); copies and real files in that folder are never listed. POSIX only: on Windows there is no such folder and the list is empty */
#define EF_LEGACY_DIR "mac" /* = DUST_LINK_DIR of dust_import.h (a test checks that they agree) */
int ef_legacy_list(const char *audio_dir, ef_item *out, int max);

/* take away one such link. 0 = removed; -1 = refused (the text says why: not a link, a real file or folder, a name with a path in it). the original is never touched */
int ef_legacy_remove(const char *audio_dir, const char *name, char *msg, size_t n);

#ifdef __cplusplus
}
#endif
#endif
