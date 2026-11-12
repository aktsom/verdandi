// osc_in.cc: see osc_in.h. bound to 127.0.0.1 only: nothing on the network can reach it.
#include "osc_in.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "osc_midi.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
#define CLOSE_SOCK closesocket
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int sock_t;
#define BAD_SOCK (-1)
#define CLOSE_SOCK close
#endif

static sock_t S = BAD_SOCK;
static pthread_t TH;
static bool UP;
static vmidi_port *PORT;
static unsigned long long USED, IGNORED;

static void *run(void *) {
    uint8_t pkt[2048], out[512];
    while (true) {
        int n = (int)recv(S, (char *)pkt, sizeof pkt, 0);
        if (n < 0) break; /* the socket was closed */
        size_t ol = 0;
        int made = vosc::packet(pkt, (size_t)n, out, sizeof out, &ol);
        if (made > 0 && ol > 0) {
            vmidi_port_push(PORT, out, ol);
            USED++;
        } else {
            IGNORED++;
        }
    }
    return NULL;
}

int vmidi_osc_start(vmidi_port *p, int port, char *err, size_t errn) {
    if (UP) return 0;
#ifdef _WIN32
    WSADATA wd;
    WSAStartup(MAKEWORD(2, 2), &wd);
#endif
    S = socket(AF_INET, SOCK_DGRAM, 0);
    if (S == BAD_SOCK) {
        snprintf(err, errn, "no socket");
        return -1;
    }
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons((unsigned short)port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(S, (struct sockaddr *)&a, sizeof a) != 0) {
        snprintf(err, errn, "port %d is in use by another program (osc_in_port in audio.conf)", port);
        CLOSE_SOCK(S);
        S = BAD_SOCK;
        return -1;
    }
    PORT = p;
    UP = true;
    pthread_create(&TH, NULL, run, NULL);
    return 0;
}

void vmidi_osc_stop(void) {
    if (!UP) return;
    UP = false;
#ifndef _WIN32
    shutdown(S, SHUT_RDWR);
#endif
    CLOSE_SOCK(S);
    S = BAD_SOCK;
    pthread_join(TH, NULL);
}

void vmidi_osc_counts(unsigned long long *used, unsigned long long *ignored) {
    if (used) *used = USED;
    if (ignored) *ignored = IGNORED;
}
