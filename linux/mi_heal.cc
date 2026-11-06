/*
 * mi_heal scan <norns home>: lists the mi-UGens files that are not Verdandi's own pack (see matron/src/platform/linux/mi_foreign.h). READ ONLY: it moves
 * nothing; linux/mi-ugens-seed.sh heal does the moving with `verdandi tidy disable`. one tab-separated line each:
 *   own<TAB>0|1                         <extensions>/mi-UGens carries Verdandi's stamp
 *   arm<TAB>path<TAB>dir|file<TAB>why   a wrong-architecture mi-UGens item that may be moved aside
 *   x86<TAB>path                        a copy that is not ours but loads on this machine (left alone)
 * PLUGIN_ARCH_UNAME overrides uname -m (tests).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>

#include "platform/linux/mi_foreign.h"

int main(int argc, char **argv) {
    if (argc < 3 || strcmp(argv[1], "scan") != 0) {
        fprintf(stderr, "usage: mi_heal scan <norns home>\n");
        return 2;
    }
    std::string home = argv[2];
    std::string machine;
    if (getenv("PLUGIN_ARCH_UNAME") != NULL) {
        machine = getenv("PLUGIN_ARCH_UNAME");
    } else {
        struct utsname u;
        machine = uname(&u) == 0 ? u.machine : "";
    }
    mi_foreign::Result r = mi_foreign::scan(home, machine, mi_foreign::ownClasses(home));
    printf("own\t%d\n", r.own_present ? 1 : 0);
    for (const auto &t : r.arm) {
        printf("arm\t%s\t%s\t%s\n", t.path.c_str(), t.dir ? "dir" : "file", t.why.c_str());
    }
    for (const auto &p : r.foreign_x86) {
        printf("x86\t%s\n", p.c_str());
    }
    return 0;
}
