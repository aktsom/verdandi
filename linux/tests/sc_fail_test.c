/* sc_fail.h on real sclang output (fixtures made with the real sclang): cc -std=gnu11 -Wall -I windows/launcher linux/tests/sc_fail_test.c */
#include <stdio.h>
#include <stdlib.h>
#include "sc_fail.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
static char *slurp(const char *p) {
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)n + 1); size_t g = fread(b, 1, (size_t)n, f); b[g] = 0; fclose(f); return b;
}
int main(void) {
    char out[1500];
    char *t = slurp("linux/tests/fixtures/sclang-compile-failed-duplicate.log");
    CHECK(t && scf_explain(t, out, sizeof out) == 1, "duplicate: explained");
    CHECK(strstr(out, "two files define the same class") && strstr(out, "MiDupTest") && strstr(out, "/tmp/dup/a/MiDupTest.sc") && strstr(out, "/tmp/dup/b/MiDupTest.sc") && strstr(out, "restart"), "duplicate: names the class, the first two paths and what to do");
    printf("%s\n", out);
    free(t);
    t = slurp("linux/tests/fixtures/sclang-compile-failed-syntax.log");
    CHECK(t && scf_explain(t, out, sizeof out) == 1, "syntax: explained");
    CHECK(strstr(out, "Parse error") && strstr(out, "/tmp/syn/B.sc") && strstr(out, "Move that file"), "syntax: the first error and its file");
    printf("%s\n", out);
    free(t);
    t = slurp("linux/tests/fixtures/sclang-ok.log");
    CHECK(t && scf_explain(t, out, sizeof out) == 0, "a clean start: no explanation");
    free(t);
    CHECK(scf_explain(NULL, out, sizeof out) == 0 && scf_explain("", out, sizeof out) == 0, "no text: none");
    CHECK(scf_explain("Library has not been compiled successfully.\n", out, sizeof out) == 1 && strstr(out, "sclang.log"), "failed without a known cause: generic line");
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("sc_fail_test: ok\n");
    return 0;
}
