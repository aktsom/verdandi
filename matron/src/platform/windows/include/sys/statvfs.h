/* sys/statvfs.h for Windows (M1): disk space of a folder (GetDiskFreeSpaceExW); implemented in platform/windows/posix_compat.c */
#ifndef VERDANDI_WIN_STATVFS_H
#define VERDANDI_WIN_STATVFS_H
#include <stdint.h>
typedef uint64_t fsblkcnt_t;
struct statvfs {
    unsigned long f_bsize, f_frsize;
    fsblkcnt_t f_blocks, f_bfree, f_bavail;
};
#ifdef __cplusplus
extern "C" {
#endif
int statvfs(const char *path, struct statvfs *buf);
#ifdef __cplusplus
}
#endif
#endif
