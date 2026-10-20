/*
 * dust_import.h
 *
 * files dropped on a norns window go into dust, where scripts look for them:
 *  - audio files (wav aif aiff aifc flac ogg mp3) and folders with audio in them -> dust/audio
 *  - a script folder (a .lua file at its top) -> dust/code, a lone .lua file -> dust/code/<name>
 * nothing is overwritten: a name already there gets " 2", " 3" ... before the extension.
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

// where it goes: <dust>/audio/<name> or <dust>/code/<name>, made unique. false if it is
// skipped or the name does not fit in n bytes
extern int dust_import_dest(const char *dust, const char *path, char *dest, size_t n);

// copy it there (folders whole). the destination is returned in dest; false on failure
extern int dust_import(const char *dust, const char *path, char *dest, size_t n);

#ifdef __cplusplus
}
#endif
