/* poll.h for Windows (M1): poll() on sockets is WSAPoll (pipes are not supported by it: the sidecar's shell runner has its own loop) */
#ifndef VERDANDI_WIN_POLL_H
#define VERDANDI_WIN_POLL_H
#include <winsock2.h>
#define poll(fds, n, t) WSAPoll((fds), (n), (t))
#ifndef POLLIN
#define POLLIN POLLRDNORM
#define POLLOUT POLLWRNORM
#endif
#endif
