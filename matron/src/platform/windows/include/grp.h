/* grp.h for Windows (M1): see pwd.h. group names are only used to build a systemd-run command line that Windows never runs. */
#ifndef VERDANDI_WIN_GRP_H
#define VERDANDI_WIN_GRP_H
#include <stddef.h>
struct group {
    char *gr_name;
};
static inline struct group *getgrgid(unsigned gid) {
    (void)gid;
    return NULL;
}
#endif
