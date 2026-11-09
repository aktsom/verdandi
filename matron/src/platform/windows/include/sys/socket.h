/* sys/socket.h for Windows (M1): winsock. sockets are not file descriptors here; the shared code that polls a connection (sdl_bridge.cc, "is maiden up") uses SOCKETs. */
#ifndef VERDANDI_WIN_SYS_SOCKET_H
#define VERDANDI_WIN_SYS_SOCKET_H
#include <winsock2.h>
#include <ws2tcpip.h>
#endif
