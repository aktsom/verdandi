/* windows/launcher/server_watch.h: the line of sclang, the decision, the sentences. run from the repo root: cc -std=gnu11 -Wall -I windows/launcher linux/tests/server_watch_test.c -o /tmp/swt && /tmp/swt */
#include <stdio.h>
#include <string.h>
#include "server_watch.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
int main(void) {
    unsigned long code = 7;
    CHECK(sw_find_exit("Server 'localhost' exited with exit code -1073741819.\nsomething else\n", &code) && code == 0xC0000005UL, "the crash of the owner's log: -1073741819 is 0xC0000005");
    CHECK(sw_find_exit("a\nServer 'localhost' exited with exit code 1.\n", &code) && code == 1, "exit code 1 (taskkill /F)");
    CHECK(sw_find_exit("Server 'localhost' exited with exit code 0.\n", &code) && code == 0, "exit code 0 is found as 0");
    CHECK(sw_find_exit("Server 'localhost' exited with exit code 3.\nServer 'localhost' exited with exit code -1073740791.\n", &code) && code == 0xC0000409UL, "the last one counts");
    CHECK(!sw_find_exit("nothing here\nthe script printed: exited with exit code 5\n", &code), "a line that is not sclang's own (no Server ' at the start) is not a stop");
    CHECK(!sw_find_exit("", &code), "empty text");
    CHECK(sw_decide(0, 0) == 0, "exit code 0 is a normal end: nothing");
    CHECK(sw_decide(0xC0000005UL, 0) == 1 && sw_decide(1, 1) == 1, "the first and the second stop restart");
    CHECK(sw_decide(0xC0000005UL, 2) == 2, "the third stop in a row: give up");
    char m[300];
    sw_message(1, 0xC0000005UL, 1, m, sizeof m);
    CHECK(strstr(m, "0xC0000005") && strstr(m, "1 of 2") && strstr(m, "restarting"), "the restart line");
    sw_message(2, 1, 2, m, sizeof m);
    CHECK(strstr(m, "keeps stopping") && strstr(m, "error 1") && strstr(m, "not restarting") && !strchr(m, '\n'), "the last line, one line");
    CHECK(strlen(m) < 200, "short enough for a note");
    if (fails) { printf("%d failed\n", fails); return 1; }
    printf("server watch: all passed\n");
    return 0;
}
