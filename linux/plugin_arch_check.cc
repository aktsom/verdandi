/*
 * plugin_arch_check <norns home>: SuperCollider plug-ins built for another machine than this one (see
 * matron/src/platform/linux/plugin_arch.h for what and why). run by linux/norns.sh before sclang starts.
 *
 * scans what sclang/scsynth read: <home>/.local/share/SuperCollider/Extensions, /usr/local/share/SuperCollider/Extensions,
 * /usr/share/SuperCollider/Extensions (every .so and .scx) and <home>/dust/code (*_scsynth.so and .scx only). prints one plain line per
 * wrong file to stdout and writes the paths to <home>/.plugin-mismatch for the note on the device window (matron re-checks that
 * list). REPORT ONLY: it moves, changes and deletes nothing. off with NORNS_PLUGIN_CHECK=0 (norns.sh also reads plugin_check=0 from
 * audio.conf): then it prints nothing and removes the list. PLUGIN_ARCH_UNAME overrides uname -m (tests).
 */

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <algorithm>
#include <set>
#include <string>
#include <vector>

#include "platform/linux/plugin_arch.h"

using namespace plugin_arch;

static void walk(const std::string &dir, int depth, bool inDust, std::vector<std::string> &out) {
    if (depth > 8) {
        return;
    }
    DIR *d = opendir(dir.c_str());
    if (d == NULL) {
        return;
    }
    while (struct dirent *e = readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        std::string path = dir + "/" + name;
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            walk(path, depth + 1, inDust, out); // symlinked directories are not followed (no loops)
        } else if ((S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) && isPluginFile(path, inDust)) {
            out.push_back(path);
        }
    }
    closedir(d);
}

static Reading read_head(const std::string &path) {
    Reading r{false, {}};
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return r;
    }
    uint8_t buf[64];
    ssize_t n = read(fd, buf, sizeof buf);
    close(fd);
    if (n < 0) {
        return r;
    }
    r.readable = true;
    r.bytes.assign(buf, buf + n);
    return r;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: plugin_arch_check <norns home>\n");
        return 2;
    }
    std::string home = argv[1];
    std::string list = home + "/.plugin-mismatch";
    if (!enabled(getenv("NORNS_PLUGIN_CHECK"))) {
        unlink(list.c_str());
        return 0;
    }
    std::string machine;
    if (getenv("PLUGIN_ARCH_UNAME") != NULL) {
        machine = getenv("PLUGIN_ARCH_UNAME");
    } else {
        struct utsname u;
        machine = uname(&u) == 0 ? u.machine : "";
    }

    std::vector<std::string> roots = {home + "/.local/share/SuperCollider/Extensions", "/usr/local/share/SuperCollider/Extensions",
                                      "/usr/share/SuperCollider/Extensions"};
    std::vector<std::string> files;
    for (const auto &r : roots) {
        walk(r, 0, false, files);
    }
    walk(home + "/dust/code", 0, true, files);
    std::sort(files.begin(), files.end());
    files.erase(std::unique(files.begin(), files.end()), files.end());

    std::vector<Finding> found = scan(files, read_head, machine);
    FILE *lf = fopen(list.c_str(), "w");
    // one line per folder (a script's installer drops a dozen plug-ins in one place); the list for the device note keeps one path per file
    for (const auto &g : groupFindings(found, files, roots)) {
        printf("%s\n", message(g, machine, home).c_str());
    }
    for (const auto &f : found) {
        if (lf != NULL) {
            fprintf(lf, "%s\n", f.path.c_str());
        }
    }
    if (lf != NULL) {
        fclose(lf);
    }
    return 0;
}
