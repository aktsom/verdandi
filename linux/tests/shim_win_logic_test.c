/* windows/shims/shim_logic.h: what nice, sudo and systemctl do with their command lines (the exact lines twins' installer uses). run from the repo root:
 *   cc -std=gnu11 -Wall -I windows/shims linux/tests/shim_win_logic_test.c -o /tmp/swl && /tmp/swl */
#include <stdio.h>
#include <string.h>
#include "shim_logic.h"
static int fails;
#define CHECK(c, what) do { if (!(c)) { fails++; printf("FAIL %s\n", what); } } while (0)
int main(void) {
    shim_plan p;
    { const char *a[] = {"nice", "-n", "19", "git", "-C", "/x", "fetch", "--quiet"}; shim_decide("nice", 8, a, &p);
      CHECK(p.action == SHIM_RUN && p.first == 3, "nice -n 19 git ...: the command starts at git"); }
    { const char *a[] = {"nice", "-n19", "git"}; shim_decide("nice", 3, a, &p); CHECK(p.action == SHIM_RUN && p.first == 2, "nice -n19 git"); }
    { const char *a[] = {"nice", "-5", "ls"}; shim_decide("nice", 3, a, &p); CHECK(p.first == 2, "nice -5 ls"); }
    { const char *a[] = {"nice", "--adjustment=10", "ls"}; shim_decide("nice", 3, a, &p); CHECK(p.first == 2, "nice --adjustment=10 ls"); }
    { const char *a[] = {"nice", "--adjustment", "10", "ls"}; shim_decide("nice", 4, a, &p); CHECK(p.first == 3, "nice --adjustment 10 ls"); }
    { const char *a[] = {"nice", "--", "ls", "-n"}; shim_decide("nice", 4, a, &p); CHECK(p.first == 2, "nice -- ls -n: options of the command are not nice's"); }
    { const char *a[] = {"nice", "git", "-n", "5"}; shim_decide("nice", 4, a, &p); CHECK(p.first == 1, "nice git -n 5: -n after the command is the command's"); }
    { const char *a[] = {"nice"}; shim_decide("nice", 1, a, &p); CHECK(p.first >= 1 && p.code == 125 && strstr(p.text, "command"), "nice alone says a command is needed"); }
    { const char *a[] = {"sudo", "systemctl", "restart", "norns-jack.service"}; shim_decide("sudo", 4, a, &p); CHECK(p.action == SHIM_RUN && p.first == 1, "sudo systemctl ...: runs systemctl (this folder's shim)"); }
    { const char *a[] = {"sudo", "-n", "-E", "ls"}; shim_decide("sudo", 4, a, &p); CHECK(p.first == 3, "sudo -n -E ls"); }
    { const char *a[] = {"sudo", "-u", "root", "ls"}; shim_decide("sudo", 4, a, &p); CHECK(p.first == 3, "sudo -u root ls: the value of -u is skipped"); }
    { const char *a[] = {"sudo", "FOO=1", "BAR=2", "env"}; shim_decide("sudo", 4, a, &p); CHECK(p.first == 3, "sudo FOO=1 BAR=2 env: assignments before the command"); }
    { const char *a[] = {"sudo", "--", "ls"}; shim_decide("sudo", 3, a, &p); CHECK(p.first == 2, "sudo -- ls"); }
    { const char *a[] = {"sudo"}; shim_decide("sudo", 1, a, &p); CHECK(p.code == 1 && strstr(p.text, "command"), "sudo alone"); }
    { const char *a[] = {"systemctl", "restart", "norns-jack.service", "norns-crone.service", "norns-matron.service"}; shim_decide("systemctl", 5, a, &p);
      CHECK(p.action == SHIM_RESTART && p.code == 0 && strstr(p.text, "restart requested"), "the restart line of twins' installer leaves a restart request"); }
    { const char *a[] = {"systemctl", "--user", "try-restart", "norns.target"}; shim_decide("systemctl", 4, a, &p); CHECK(p.action == SHIM_RESTART, "try-restart norns.target"); }
    { const char *a[] = {"systemctl", "start", "norns-matron"}; shim_decide("systemctl", 3, a, &p); CHECK(p.action == SHIM_SAY && p.code == 0, "start of a norns unit: nothing to do, 0"); }
    { const char *a[] = {"systemctl", "stop", "norns-matron"}; shim_decide("systemctl", 3, a, &p); CHECK(p.action == SHIM_SAY && p.code == 1, "stop of a norns unit: 1"); }
    { const char *a[] = {"systemctl", "restart", "sshd"}; shim_decide("systemctl", 3, a, &p); CHECK(p.action == SHIM_SAY && p.code == 1 && strstr(p.text, "no systemd"), "another unit: 1, plainly"); }
    { const char *a[] = {"systemctl"}; shim_decide("systemctl", 1, a, &p); CHECK(p.code == 1, "no verb: 1"); }
    char b[64];
    shim_basename("C:\\Users\\a b\\Verdandi\\Nice.EXE", b, sizeof b); CHECK(!strcmp(b, "nice"), "base name of a Windows path");
    shim_basename("sudo.exe", b, sizeof b); CHECK(!strcmp(b, "sudo"), "base name sudo.exe");
    { const char *a[] = {"x"}; shim_decide("other", 1, a, &p); CHECK(p.code == 2, "an unknown name says so"); }
    if (fails) { printf("%d failed\n", fails); return 1; }
    printf("shim logic: all passed\n");
    return 0;
}
