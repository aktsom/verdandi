/*
 * dust_import.h
 *
 * files dropped on a norns window go into dust, where scripts look for them:
 *  - audio files (wav aif aiff aifc flac ogg mp3) and folders with audio in them are linked
 *    from dust/audio/mac (the originals stay where they are; deleting a link loses nothing),
 *    or copied into dust/audio
 *  - a script folder (a .lua file at its top) is copied to dust/code, a lone .lua file to
 *    dust/code/<name>: scripts belong to norns (maiden updates them, norns resumes them)
 * nothing is overwritten: a name already there gets " 2", " 3" ... before the extension. a
 * link that is already there for the same original is used again; links whose original is
 * gone are removed.
 * pure C on top of copyfile(3) (macos/tests/dust_import_test.c).
 */

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DUST_SKIP = 0,   // not something norns can use
    DUST_AUDIO = 1,  // into dust/audio
    DUST_SCRIPT = 2, // into dust/code
} dust_kind_t;

// what a dropped path is
extern dust_kind_t dust_import_kind(const char *path);

// the folder in dust/audio that holds the links
#define DUST_LINK_DIR "mac"

// where it goes: <dust>/audio/mac/<name> (link, audio only), <dust>/audio/<name> or
// <dust>/code/<name>, made unique. false if it is skipped or the name does not fit in n bytes
extern int dust_import_dest(const char *dust, const char *path, int link, char *dest, size_t n);

// link (audio, link != 0) or copy it there (folders whole); path must be absolute to link.
// on a disk that cannot hold links audio is copied. the destination is returned in dest and
// *linked says which it was; false on failure
extern int dust_import(const char *dust, const char *path, int link, char *dest, size_t n, int *linked);

// remove the links in dust/audio/mac whose original is gone
extern void dust_prune_links(const char *dust);

// path is a file the system or an app deletes on its own: in a temporary folder (tmpdir,
// /tmp, /var/folders), a cache (<home>/Library/Caches) or a trash. a link to it would die
// soon, so it is copied. tmpdir and home may be NULL
extern int dust_import_volatile(const char *path, const char *tmpdir, const char *home);

#ifdef __cplusplus
}
#endif
