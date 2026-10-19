/*
 * jack_tools.c
 *
 * homebrew's jack ships only jackd, but norns needs the jack example clients:
 * Crone.sc wires SuperCollider into crone with `jack_connect`, and scripts call
 * jack_connect / jack_disconnect too. built as three programs; argv[0] selects:
 *
 *   jack_connect <src> <dst>      exit 0 if connected (or already connected)
 *   jack_disconnect <src> <dst>   exit 0 if disconnected
 *   jack_lsp [-c]                 list ports (-c: with connections)
 */

#include <errno.h>
#include <jack/jack.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void silent(const char *msg) {
    (void)msg;
}

static jack_client_t *open_client(const char *name) {
    jack_status_t status;
    jack_set_error_function(silent);
    jack_set_info_function(silent);
    jack_client_t *c = jack_client_open(name, JackNoStartServer, &status);
    if (c == NULL) {
        fprintf(stderr, "%s: cannot connect to jack server\n", name);
    }
    return c;
}

static int lsp(int argc, char **argv) {
    int connections = argc > 1 && strcmp(argv[1], "-c") == 0;
    jack_client_t *c = open_client("jack_lsp");
    if (c == NULL) {
        return 1;
    }
    const char **ports = jack_get_ports(c, NULL, NULL, 0);
    for (int i = 0; ports != NULL && ports[i] != NULL; i++) {
        printf("%s\n", ports[i]);
        if (connections) {
            const char **conn = jack_port_get_all_connections(c, jack_port_by_name(c, ports[i]));
            for (int j = 0; conn != NULL && conn[j] != NULL; j++) {
                printf("   %s\n", conn[j]);
            }
            jack_free(conn);
        }
    }
    jack_free(ports);
    jack_client_close(c);
    return 0;
}

static int connect_ports(const char *tool, int argc, char **argv, int disconnect) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <source port> <destination port>\n", tool);
        return 1;
    }
    jack_client_t *c = open_client(tool);
    if (c == NULL) {
        return 1;
    }
    int r = disconnect ? jack_disconnect(c, argv[1], argv[2]) : jack_connect(c, argv[1], argv[2]);
    jack_client_close(c);
    if (r == 0 || (!disconnect && r == EEXIST)) {
        return 0;
    }
    fprintf(stderr, "%s: cannot %s %s -> %s\n", tool, disconnect ? "disconnect" : "connect", argv[1], argv[2]);
    return 1;
}

int main(int argc, char **argv) {
    const char *tool = basename(argv[0]);
    if (strcmp(tool, "jack_lsp") == 0) {
        return lsp(argc, argv);
    }
    if (strcmp(tool, "jack_disconnect") == 0) {
        return connect_ports(tool, argc, argv, 1);
    }
    return connect_ports("jack_connect", argc, argv, 0);
}
