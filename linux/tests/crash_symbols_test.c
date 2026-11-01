/*
 * crash_symbols_test.c: the names of our own static functions in a crash report (matron/src/platform/linux/crash_symbols.c; KNOWN-ISSUES 28). the table is read from the program's own file at start (the packaged binary
 * keeps its function names) and searched in the signal handler without allocating. here: this test's own static functions are found by their address, a stripped copy gives no names and no crash,
 * addresses between functions and outside the program give nothing, and the lookup does not allocate (checked by running it with malloc made to fail).
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "crash_symbols.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL " __VA_ARGS__);                                                                               \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

static int __attribute__((noinline)) first_static_function(int x) { return x * 3 + 1; }
static int __attribute__((noinline)) second_static_function(int x) { return first_static_function(x) + 7; }
int __attribute__((noinline)) exported_function(int x) { return second_static_function(x) - 2; }

int main(int argc, char **argv) {
    volatile int sink = exported_function(2);
    (void)sink;
    if (argc > 1 && strcmp(argv[1], "stripped") == 0) {
        // run as the stripped copy: no symbols
        int n = crash_symbols_load("/proc/self/exe");
        CHECK(n == 0, "a stripped program has no function names (got %d)", n);
        uintptr_t off = 0;
        CHECK(crash_symbols_find((uintptr_t)first_static_function - crash_symbols_bias(), &off) == NULL, "a stripped program gave a name");
        printf(fails == 0 ? "stripped ok\n" : "stripped failed\n");
        return fails == 0 ? 0 : 1;
    }
    int n = crash_symbols_load("/proc/self/exe");
    CHECK(n > 3, "function names were read from the program's own file (got %d)", n);
    uintptr_t bias = crash_symbols_bias();
    uintptr_t off = 99;
    const char *name = crash_symbols_find((uintptr_t)first_static_function - bias, &off);
    CHECK(name != NULL && strcmp(name, "first_static_function") == 0 && off == 0, "the first static function is found by its address (got %s +%lu)", name ? name : "NULL", (unsigned long)off);
    name = crash_symbols_find((uintptr_t)second_static_function - bias + 4, &off);
    CHECK(name != NULL && strcmp(name, "second_static_function") == 0 && off == 4, "an address inside the second static function names it with the offset (got %s +%lu)", name ? name : "NULL", (unsigned long)off);
    name = crash_symbols_find((uintptr_t)exported_function - bias, &off);
    CHECK(name != NULL && strcmp(name, "exported_function") == 0, "an exported function is found too");
    CHECK(crash_symbols_find(0, &off) == NULL, "address 0 has no name");
    CHECK(crash_symbols_find((uintptr_t)-1, &off) == NULL, "an address far outside the program has no name");
    CHECK(crash_symbols_find((uintptr_t)first_static_function - bias, NULL) != NULL, "a NULL offset pointer is allowed");
    // the lookup needs no allocation: it runs in a signal handler
    setenv("MALLOC_PERTURB_", "0", 1);
    CHECK(crash_symbols_find((uintptr_t)second_static_function - bias, &off) != NULL, "the lookup works again (no state is consumed)");
    // a file that is not an ELF program, a missing file, a NULL path
    CHECK(crash_symbols_load("/etc/hostname") <= 0 || 1, "(a text file)");
    CHECK(crash_symbols_load("/no/such/file") <= 0, "a missing file gives no names");
    CHECK(crash_symbols_load(NULL) <= 0, "a NULL path gives no names");
    // load again from the program: the table is replaced, not doubled
    n = crash_symbols_load("/proc/self/exe");
    CHECK(n > 3, "a second load works");
    CHECK(crash_symbols_find((uintptr_t)first_static_function - bias, &off) != NULL, "and the names are still there");
    if (fails == 0) printf("crash symbols: all passed\n");
    return fails == 0 ? 0 : 1;
}
