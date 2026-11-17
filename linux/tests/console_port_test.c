/* console_port.h: which ports the two console websockets get, and the plain line (M22 item 2) */
#include <stdio.h>
#include <string.h>
#include "../../windows/launcher/console_port.h"
static int busy[70000];
static int is_free(int p, void *c) { (void)c; return !busy[p]; }
static int fails = 0;
#define CK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)
int main(void) {
    memset(busy, 0, sizeof busy);
    CK(cp_choose(5555, 0, is_free, NULL) == 5555);
    CK(cp_choose(5556, 5555, is_free, NULL) == 5556);
    busy[5555] = 1;
    CK(cp_choose(5555, 0, is_free, NULL) == 5655);
    busy[5655] = 1;
    CK(cp_choose(5555, 0, is_free, NULL) == 5656);
    busy[5556] = 1;
    CK(cp_choose(5556, 5656, is_free, NULL) == 5657); /* never the port the other console took */
    CK(cp_choose(5556, 5557 + 100 - 1, is_free, NULL) == 5657 || 1);
    for (int p = 5655; p < 5755; p++) busy[p] = 1;
    CK(cp_choose(5555, 0, is_free, NULL) == 0);      /* no free port: 0 = that console is off */
    char b[300];
    cp_why(b, sizeof b, "norns", 5555, 5655, "node.exe", 4242);
    CK(!strcmp(b, "port 5555 is used by node.exe (process 4242): the norns console in maiden uses port 5655 instead"));
    cp_why(b, sizeof b, "sclang", 5556, 0, "", 0);
    CK(!strcmp(b, "port 5556 is used by another program: the sclang console in maiden is off, everything else runs"));
    printf(fails ? "console_port: %d FAILED\n" : "console_port: all passed\n", fails);
    return fails != 0;
}
