/*
 * compat_sock.h: BSD sockets on winsock for ONE translation unit, matron/src/platform/macos/sdl_bridge.cc (it asks whether maiden's port answers: connect with O_NONBLOCK, poll, getsockopt, close).
 * force-included for that file only (windows/cmake/CMakeLists.txt, windows/ci/xcheck.sh), because the macros below would break other code (crone has a method called connect).
 * a socket is a SOCKET stored in an int.
 */
#pragma once
#ifdef _WIN32
#include <ws2tcpip.h>
#define F_GETFL 3
#define F_SETFL 4
#ifndef O_NONBLOCK
#define O_NONBLOCK 0x4000
#endif
#ifdef __cplusplus
extern "C" {
#endif
static inline int norns_win_fcntl(int fd, int cmd, ...) {
    if (cmd == F_SETFL) {
        /* only O_NONBLOCK is ever set: this is used on sockets */
        u_long nb = 1;
        return ioctlsocket((SOCKET)fd, FIONBIO, &nb);
    }
    return 0;
}
static inline int norns_win_connect(int s, const struct sockaddr *a, int l) {
    int r = connect((SOCKET)s, a, l);
    if (r != 0) {
        errno = WSAGetLastError() == WSAEWOULDBLOCK ? EINPROGRESS : ECONNREFUSED;
    }
    return r;
}
static inline int norns_win_close(int fd) {
    int type = 0, len = sizeof type;
    if (getsockopt((SOCKET)fd, SOL_SOCKET, SO_TYPE, (char *)&type, &len) == 0) {
        return closesocket((SOCKET)fd);
    }
    return _close(fd);
}
#ifdef __cplusplus
}
#endif
#define fcntl norns_win_fcntl
#define connect(s, a, l) norns_win_connect((s), (a), (l))
#define close(fd) norns_win_close(fd)
#define getsockopt(s, l, o, v, n) getsockopt((SOCKET)(s), (l), (o), (char *)(v), (n))
#ifndef EINPROGRESS
#define EINPROGRESS 115
#endif


#endif
