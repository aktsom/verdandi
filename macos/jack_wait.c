/*
 * jack_wait.c
 *
 * homebrew's jack ships only jackd. this stands in for `jack_wait -w`: wait until a jack
 * server accepts clients, without ever starting one.
 *
 * usage: jack_wait [timeout seconds, default 10]  (exit 0 = server up)
 */

#include <jack/jack.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void silent(const char *msg) {
    (void)msg;
}

int main(int argc, char **argv) {
    double timeout = argc > 1 ? atof(argv[1]) : 10.0;
    jack_set_error_function(silent);
    jack_set_info_function(silent);
    for (double waited = 0; waited <= timeout; waited += 0.2) {
        jack_status_t status;
        jack_client_t *c = jack_client_open("jack_wait", JackNoStartServer, &status);
        if (c != NULL) {
            jack_client_close(c);
            return 0;
        }
        usleep(200000);
    }
    fprintf(stderr, "jack_wait: no jack server after %.1f s\n", timeout);
    return 1;
}
