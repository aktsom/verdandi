/* pwd.h for Windows (M1): the user and group names are only used to build a systemd-run command line that Windows never runs */
#ifndef VERDANDI_WIN_PWD_H
#define VERDANDI_WIN_PWD_H
#include <stddef.h>
struct passwd {
    char *pw_name;
    char *pw_dir;
};
static inline struct passwd *getpwuid(unsigned uid) {
    (void)uid;
    return NULL;
}
static inline unsigned getuid(void) { return 0; }
static inline unsigned getgid(void) { return 0; }
#endif
