/* fnmatch.h for Windows (M1): shell wildcard match (* ? [..]); implemented in platform/windows/posix_compat.c */
#ifndef VERDANDI_WIN_FNMATCH_H
#define VERDANDI_WIN_FNMATCH_H
#define FNM_NOMATCH 1
#ifdef __cplusplus
extern "C" {
#endif
int fnmatch(const char *pattern, const char *string, int flags);
#ifdef __cplusplus
}
#endif
#endif
