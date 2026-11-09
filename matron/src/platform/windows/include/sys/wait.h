/* sys/wait.h for Windows (M1): norns waits for child processes with waitpid on Linux. here the status macros only; process control is done by the launcher (Verdandi.exe). */
#ifndef VERDANDI_WIN_SYS_WAIT_H
#define VERDANDI_WIN_SYS_WAIT_H
#include <sys/types.h>
#define WNOHANG 1
#define WIFEXITED(s) 1
#define WEXITSTATUS(s) ((s) & 0xff)
#define WIFSIGNALED(s) 0
#define WTERMSIG(s) 0
#ifdef __cplusplus
extern "C" {
#endif
static inline pid_t waitpid(pid_t pid, int *status, int options) {
    (void)pid;
    (void)options;
    if (status) {
        *status = 0;
    }
    return -1;
}
#ifdef __cplusplus
}
#endif
#endif
