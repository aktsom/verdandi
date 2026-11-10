/*
 * bridge_guest_tool.c: the scsynth side of the audio bridge as a small program (what the driver of windows/patches/scsynth-null-audio.patch does, with a sine): opens the bridge NAME, waits for
 * blocks, plays 0.5 * sin(440 Hz) plus the host's input, until the host closes the bridge. A second PROCESS next to bridge_host_tool: on Windows (Wine) this proves the named shared memory and the named
 * event between two programs.   bridge_guest_tool NAME
 */
#define _GNU_SOURCE 1
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "audio/verdandi_bridge.h"

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    vb_t g;
    if (vb_guest_open(&g, argv[1], 10000) != 0) {
        printf("FAIL the guest could not open the bridge\n");
        return 1;
    }
    unsigned n = g.sh->frames;
    double rate = g.sh->rate, ph = 0;
    float *il = malloc(n * sizeof(float)), *ir = malloc(n * sizeof(float)), *ol = malloc(n * sizeof(float)), *orr = malloc(n * sizeof(float));
    vb_guest_attach(&g);
    long blocks = 0;
    for (;;) {
        int r = vb_guest_wait(&g, 50, il, ir);
        if (r < 0) break;
        if (r == 0) continue;
        for (unsigned i = 0; i < n; i++, ph += 440.0 / rate) {
            float s = 0.5f * sinf((float)(2 * M_PI * ph));
            ol[i] = s + il[i];
            orr[i] = s + ir[i];
        }
        vb_guest_push(&g, ol, orr);
        blocks++;
    }
    vb_guest_detach(&g);
    vb_close(&g);
    printf("guest: %ld blocks, the host closed the bridge\n", blocks);
    return 0;
}
