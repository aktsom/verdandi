/* linux/tests/dedupe_test.c: matron/src/platform/windows/msg_dedupe.h: the same message written once, the count said when another one comes. */
#include <stdio.h>
#include "../../matron/src/platform/windows/msg_dedupe.h"
int main(void) {
    vmsg_dedupe d = {{0}, 0};
    unsigned sk;
    int fails = 0;
#define CK(c, w) do { if (!(c)) { printf("FAIL %s\n", w); fails++; } } while (0)
    CK(vmsg_dedupe_check(&d, "awake.lua:124: invalid paramset index: out", &sk) == 1 && sk == 0, "the first message is written");
    for (int i = 0; i < 700; i++) CK(vmsg_dedupe_check(&d, "awake.lua:124: invalid paramset index: out", &sk) == 0, "an identical message is not written");
    CK(vmsg_dedupe_check(&d, "something else", &sk) == 1 && sk == 700, "another message is written, with the count of the 700 before");
    CK(vmsg_dedupe_check(&d, "awake.lua:124: invalid paramset index: out", &sk) == 1 && sk == 0, "the old message is new again after another one");
    CK(vmsg_dedupe_check(&d, "x", &sk) == 1 && sk == 0, "no repeats: no count");
    printf(fails ? "dedupe_test: %d failures\n" : "dedupe_test: passed\n", fails);
    return fails != 0;
}
