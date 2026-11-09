/* sys/prctl.h for Windows (M1): the sidecar process of Linux names itself and asks to die with its parent. on Windows the sidecar is a thread of norns.exe, so these are no-ops. */
#ifndef VERDANDI_WIN_PRCTL_H
#define VERDANDI_WIN_PRCTL_H
#define PR_SET_NAME 15
#define PR_SET_PDEATHSIG 1
static inline int prctl(int option, ...) {
    (void)option;
    return 0;
}
#endif
