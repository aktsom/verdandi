/* glob.h for Windows (M1): glob() with the patterns norns uses (a path with * and ? in the last component), implemented with FindFirstFile in platform/windows/posix_compat.c */
#ifndef VERDANDI_WIN_GLOB_H
#define VERDANDI_WIN_GLOB_H
#include <stddef.h>
typedef struct {
    size_t gl_pathc;
    char **gl_pathv;
    size_t gl_offs;
} glob_t;
#define GLOB_NOSPACE 1
#define GLOB_ABORTED 2
#define GLOB_NOMATCH 3
#define GLOB_ERR 1
#define GLOB_MARK 2
#define GLOB_NOSORT 4
#define GLOB_BRACE 0x400 /* accepted and ignored: no {a,b} expansion */
#define GLOB_TILDE 0x1000 /* accepted and ignored: Windows has no ~ */
#ifdef __cplusplus
extern "C" {
#endif
int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *pglob);
void globfree(glob_t *pglob);
#ifdef __cplusplus
}
#endif
#endif
