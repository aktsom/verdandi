/* win_paths.h: Windows paths with any letters (UTF-8 in, the wide API underneath) for what the window saves (screenshots, GIFs). the narrow C library functions take the ANSI code page: a user name with an accent
 * would fail. paths are UTF-8; '/' and '\' both work. */
#ifndef VERDANDI_WIN_PATHS_H
#define VERDANDI_WIN_PATHS_H
#include <stddef.h>
#include <stdio.h>
#ifdef __cplusplus
extern "C" {
#endif
/* the Pictures known folder (SHGetKnownFolderPath: follows a OneDrive redirection), UTF-8 with '/'. 0 = ok, -1 = not found */
int win_known_pictures(char *out, size_t n);
/* like fopen, with a UTF-8 path */
FILE *win_fopen_utf8(const char *path, const char *mode);
/* every missing folder of path is made. 0 = it exists now */
int win_mkdirs_utf8(const char *path);
int win_exists_utf8(const char *path);
int win_unlink_utf8(const char *path);
#ifdef __cplusplus
}
#endif
#endif
