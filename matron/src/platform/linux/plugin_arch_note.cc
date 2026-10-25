/*
 * plugin_arch_note.cc: see plugin_arch.h
 *
 * the note for the device window: linux/plugin_arch_check (run by norns.sh before sclang starts) wrote the paths of SuperCollider plug-ins
 * built for another machine to <norns home>/.plugin-mismatch. this looks at those files again (a stat and 64 bytes each, not a new
 * scan), so the note goes away when they have been moved or replaced. lua asks for it every few seconds. reads only.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <string>
#include <vector>

#include "plugin_arch.h"
#include "plugin_arch_note.h"

using namespace plugin_arch;

extern "C" const char *plugin_arch_note_text(void) {
    if (!enabled(getenv("NORNS_PLUGIN_CHECK"))) {
        return NULL;
    }
    const char *home = getenv("HOME");
    if (home == NULL) {
        return NULL;
    }
    std::string list = std::string(home) + "/.plugin-mismatch";
    FILE *f = fopen(list.c_str(), "r");
    if (f == NULL) {
        return NULL;
    }
    struct utsname u;
    std::string machine = uname(&u) == 0 ? u.machine : "";
    if (getenv("PLUGIN_ARCH_UNAME") != NULL) {
        machine = getenv("PLUGIN_ARCH_UNAME");
    }
    Expect e = expectedFor(machine);
    bool any = false;
    char line[4096];
    while (fgets(line, sizeof line, f) != NULL) {
        size_t n = strlen(line);
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
            line[--n] = '\0';
        }
        if (n == 0) {
            continue;
        }
        Reading r{false, {}};
        int fd = open(line, O_RDONLY);
        if (fd >= 0) {
            uint8_t buf[64];
            ssize_t got = read(fd, buf, sizeof buf);
            close(fd);
            if (got >= 0) {
                r.readable = true;
                r.bytes.assign(buf, buf + got);
            }
        }
        if (check(r, e) == Verdict::Mismatch) {
            any = true;
            break;
        }
    }
    fclose(f);
    return any ? note() : NULL;
}
