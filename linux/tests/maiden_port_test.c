/* maiden_port.h: cc -std=gnu11 -Wall -I windows/launcher linux/tests/maiden_port_test.c */
#include <stdio.h>
#include "maiden_port.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
int main(void) {
    char b[160];
    CHECK(mp_decide(0, "") == MP_FREE, "nobody listens: free");
    CHECK(mp_decide(0, "maiden.exe") == MP_FREE, "nobody listens, stale name given: free");
    CHECK(mp_decide(1, "maiden.exe") == MP_STOP_STALE, "maiden.exe holds it: stop it (any folder)");
    CHECK(mp_decide(1, "MAIDEN.EXE") == MP_STOP_STALE, "case does not matter");
    CHECK(mp_decide(1, "chrome.exe") == MP_FOREIGN, "another program: foreign");
    CHECK(mp_decide(1, "maiden.exe.bak") == MP_FOREIGN, "only the exact name");
    CHECK(mp_decide(1, "my-maiden.exe") == MP_FOREIGN, "only the exact name (prefix)");
    CHECK(mp_decide(1, "") == MP_FOREIGN, "holder unknown: foreign (never stopped)");
    CHECK(mp_decide(1, NULL) == MP_FOREIGN, "holder NULL: foreign");
    mp_why(b, sizeof b, 5000, "node.exe"); CHECK(strcmp(b, "maiden is not started: port 5000 is used by node.exe") == 0, "why: named");
    mp_why(b, sizeof b, 5000, ""); CHECK(strcmp(b, "maiden is not started: port 5000 is used by another program") == 0, "why: unnamed");
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("maiden_port_test: ok\n");
    return 0;
}
