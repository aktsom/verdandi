#!/usr/bin/env bash
# linux/tests/update_and_run_test.sh: windows/update-and-run.cmd under Wine with stand-ins for curl.exe, tar.exe and choice.exe (Wine has no curl and no tar): the logic of the script, not the tools of Windows.
# what it proves: a newer build is unpacked into a folder of its own next to the old one (named Verdandi-<version>-<hash>), the old one stays until asked, "no" keeps everything, "yes" removes only older
# BUILD folders (Verdandi.exe and norns.exe) and never the data folder, the build in the folder is recognised as the newest, a failed download (404, no connection, an error page, a bad checksum) says so in plain
# words, changes nothing and offers the build that is there. 77 = no cross compiler or no Wine.
set -u
cd "$(dirname "$0")/../.." || exit 1
CC=x86_64-w64-mingw32-gcc-posix
command -v "$CC" > /dev/null || CC=x86_64-w64-mingw32-gcc
command -v "$CC" > /dev/null || { echo "no mingw-w64 cross compiler"; exit 77; }
WINE=/usr/lib/wine/wine64
[ -x "$WINE" ] || WINE="$(command -v wine64 || command -v wine || true)"
[ -n "$WINE" ] || { echo "no Wine"; exit 77; }
T="$(mktemp -d)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
export WINEPREFIX="$T/prefix" WINEDEBUG=-all
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

mkdir -p "$T/stubs" "$T/server/unpacked"
cat > "$T/curl.c" <<'S'
/* stand-in for curl.exe: -o FILE URL; the "address" is a file name in the folder VERDANDI_TEST_SERVER. exit 22 when it is not there (HTTP 404), 7 when VERDANDI_TEST_OFFLINE is set */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    const char *out = NULL, *url = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--version")) { puts("curl stub"); return 0; }
        if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (argv[i][0] != '-' && strstr(argv[i], "://") == NULL && !strchr(argv[i], ':')) { }
        if (strstr(argv[i], "Verdandi") || strstr(argv[i], "BUILD.txt")) url = argv[i];
    }
    if (getenv("VERDANDI_TEST_OFFLINE")) { fprintf(stderr, "curl: (7) Failed to connect\n"); return 7; }
    if (!out || !url) return 2;
    const char *name = strrchr(url, '/'); if (!name) name = strrchr(url, '\\');
    name = name ? name + 1 : url;
    char src[600]; snprintf(src, sizeof src, "%s\\%s", getenv("VERDANDI_TEST_SERVER"), name);
    FILE *f = fopen(src, "rb");
    if (!f) { fprintf(stderr, "curl: (22) The requested URL returned error: 404\n"); return 22; }
    FILE *o = fopen(out, "wb"); char buf[4096]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) fwrite(buf, 1, n, o);
    fclose(f); fclose(o);
    return 0;
}
S
cat > "$T/tar.c" <<'S'
/* stand-in for tar.exe: -xf ZIP -C DIR copies the folder "unpacked" of the test server into DIR (as if the zip held it) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
static int copy_tree(const char *from, const char *to) {
    char pat[800];
    snprintf(pat, sizeof pat, "%s\\*", from);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) return 1;
    CreateDirectoryA(to, NULL);
    do {
        if (!strcmp(fd.cFileName, ".") || !strcmp(fd.cFileName, "..")) continue;
        char a[800], b[800];
        snprintf(a, sizeof a, "%s\\%s", from, fd.cFileName);
        snprintf(b, sizeof b, "%s\\%s", to, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) { if (copy_tree(a, b)) return 1; }
        else if (!CopyFileA(a, b, FALSE)) return 1;
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    return 0;
}
int main(int argc, char **argv) {
    const char *dir = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--version")) { puts("tar stub"); return 0; }
        if (!strcmp(argv[i], "-C") && i + 1 < argc) dir = argv[++i];
    }
    if (!dir) return 2;
    char src[800];
    snprintf(src, sizeof src, "%s\\unpacked", getenv("VERDANDI_TEST_SERVER"));
    return copy_tree(src, dir);
}
S
cat > "$T/choice.c" <<'S'
/* stand-in for choice.exe: the answer is in VERDANDI_TEST_CHOICE (Y or N); errorlevel 1 = the first letter of /C, 2 = the second */
#include <stdlib.h>
#include <stdio.h>
int main(void) { const char *c = getenv("VERDANDI_TEST_CHOICE"); printf("[choice stand-in: answer %s]\n", c ? c : "(unset, yes)"); return c && (c[0] == 'N' || c[0] == 'n') ? 2 : 1; }
S
cat > "$T/app.c" <<'S'
/* a program that stands for Verdandi.exe: writes started.txt next to itself */
#include <stdio.h>
#include <windows.h>
int main(void) { char p[600]; GetModuleFileNameA(NULL, p, sizeof p); char *s = strrchr(p, '\\'); if (s) { *s = 0; } char f[700]; snprintf(f, sizeof f, "%s\\started.txt", p); FILE *o = fopen(f, "w"); if (o) { fputs("started", o); fclose(o); } return 0; }
S
sed -i 's/#include <windows.h>/#include <windows.h>\n#include <string.h>/' "$T/app.c"
for p in curl tar; do $CC -O1 "$T/$p.c" -o "$T/stubs/$p.exe" -static || exit 1; done
$CC -O1 "$T/choice.c" -o "$T/stubs/answer.exe" -static || exit 1 # (named differently: Wine has its own choice.exe and prefers it; the script takes the program from VERDANDI_CHOICE)
$CC -O1 "$T/app.c" -o "$T/app.exe" -static || exit 1

mkbuild() { # dir version hash
    mkdir -p "$1"
    cp "$T/app.exe" "$1/Verdandi.exe"; cp "$T/app.exe" "$1/norns.exe"
    printf '%s %s\nbuilt: test\n' "$2" "$3" > "$1/BUILD.txt"
    cp windows/update-and-run.cmd "$1/"
    echo "owner/repo" > "$1/UPDATE-SOURCE.txt"
}
# the "release": BUILD.txt, a zip (any 1.2 MB file), its checksum is left out here, and the folder the stand-in tar unpacks
mkbuild "$T/server/unpacked/Verdandi-0.3.0-bbbbbbb" 0.3.0 bbbbbbb
printf '0.3.0 bbbbbbb\n' > "$T/server/BUILD.txt"
head -c 1200000 /dev/zero > "$T/server/Verdandi-windows-latest.zip"

newroot() { # a parent folder with an old build, the data folder and something else
    R="$T/r$1"
    rm -rf "$R"; mkdir -p "$R/Verdandi/dust/code" "$R/other"
    echo "my script" > "$R/Verdandi/dust/code/mine.lua"
    mkbuild "$R/Verdandi-0.2.0-aaaaaaa" 0.2.0 aaaaaaa
    mkbuild "$R/Verdandi" 0.1.0 oldold   # (a very old build folder that is also named like the data folder: it holds Verdandi.exe, norns.exe, dust and logs of its own)
    rm -f "$R/Verdandi/Verdandi.exe" "$R/Verdandi/norns.exe" # ... but this one is the data folder: no program in it
}
# shellcheck disable=SC1003
winpath() { printf 'Z:%s' "$1" | tr / '\\'; }
run() { # script folder, extra args, env assignments...; the output is in $T/out.txt
    local dir="$1" args="$2"; shift 2
    printf '@echo off\r\nset PATH=%s;%%PATH%%\r\ncd /d %s\r\nset VERDANDI_TEST_SERVER=%s\r\nset USERPROFILE=%s\r\nset VERDANDI_CHOICE=%s\\answer.exe\r\n%s\r\ncall "%s\\update-and-run.cmd" %s\r\necho EXITCODE=%%errorlevel%%\r\n' \
        "$(winpath "$T/stubs")" "$(winpath "$T/stubs")" "$(winpath "$T/server")" "$(winpath "$ROOT")" "$(winpath "$T/stubs")" "$*" "$(winpath "$dir")" "$args" > "$T/run.cmd"
    (cd "$T" && timeout 120 "$WINE" cmd /c "$(winpath "$T/run.cmd")" > "$T/out.txt" 2>&1)
}

echo "== a newer build exists; the answer to 'remove older builds' is no"
ROOT="$T/r1"; newroot 1; mkbuild "$T/r1/Verdandi-0.1.5-ccccccc" 0.1.5 ccccccc
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
tr -d "\r" < "$T/out.txt" | head -40
tr -d "\r" < "$T/out.txt" | sed -n 11,40p
ck "it says which build this folder holds and which is the newest" "grep -q 'This folder holds build: 0.2.0 aaaaaaa' '$T/out.txt' && grep -q 'The newest build is:     0.3.0 bbbbbbb' '$T/out.txt'"
ck "the new build is unpacked into a folder of its own next to the old one" "[ -f '$ROOT/Verdandi-0.3.0-bbbbbbb/Verdandi.exe' ] && [ -f '$ROOT/Verdandi-0.2.0-aaaaaaa/Verdandi.exe' ]"
ck "the temporary unpack folder is gone" "[ ! -e '$ROOT/.verdandi-unpack' ]"
ck "an older build (not the folder the script runs from) is listed and kept (answer no)" "grep -q 'Older unpacked builds' '$T/out.txt' && grep -q 'Verdandi-0.1.5-ccccccc' '$T/out.txt' && [ -f '$ROOT/Verdandi-0.1.5-ccccccc/Verdandi.exe' ] && [ -f '$ROOT/Verdandi-0.2.0-aaaaaaa/Verdandi.exe' ]"
ck "the data folder (Verdandi, with dust) is not offered and not touched" "! grep -q 'r1.Verdandi\$' '$T/out.txt' && [ -f '$ROOT/Verdandi/dust/code/mine.lua' ]"
ck "the script ends with 0 and does not start Verdandi with /NOSTART" "grep -q 'EXITCODE=0' '$T/out.txt' && [ ! -e '$ROOT/Verdandi-0.3.0-bbbbbbb/started.txt' ]"

echo "== start: the new Verdandi.exe is started from its own folder"
ROOT="$T/r2"; newroot 2
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/KEEP" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
sleep 2
ck "Verdandi.exe of the new build was started" "[ -f '$ROOT/Verdandi-0.3.0-bbbbbbb/started.txt' ]"
ck "/KEEP: no question about older builds" "! grep -q 'Older unpacked builds' '$T/out.txt'"

echo "== run again from the new folder: it is the newest; 'yes' removes the older build, not itself, not the data"
run "$ROOT/Verdandi-0.3.0-bbbbbbb" "/NOSTART" "set VERDANDI_TEST_CHOICE=Y&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "it says that this is the newest build" "grep -q 'You already have the newest build' '$T/out.txt'"
ck "the older build is removed" "[ ! -e '$ROOT/Verdandi-0.2.0-aaaaaaa' ]"
ck "the new build and the data folder are still there" "[ -f '$ROOT/Verdandi-0.3.0-bbbbbbb/Verdandi.exe' ] && [ -f '$ROOT/Verdandi/dust/code/mine.lua' ] && [ -d '$ROOT/other' ]"

echo "== the download fails: nothing published (404)"
ROOT="$T/r3"; newroot 3
mv "$T/server/BUILD.txt" "$T/server/BUILD.txt.hidden"
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
mv "$T/server/BUILD.txt.hidden" "$T/server/BUILD.txt"
ck "a plain message says that nothing is published (and that a private repository cannot be read)" "grep -q 'There is no published build' '$T/out.txt' && grep -q 'repository is private' '$T/out.txt'"
ck "nothing was changed and the exit code says so" "[ ! -e '$ROOT/Verdandi-0.3.0-bbbbbbb' ] && grep -Eq 'EXITCODE=[12]' '$T/out.txt'" # (Wine reports 1 where Windows reports 2: exit /b of a called batch file)

echo "== the download fails: no internet"
ROOT="$T/r4"; newroot 4
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_OFFLINE=1&set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "a plain message says that the server cannot be reached" "grep -q 'Cannot connect to the server' '$T/out.txt' && grep -q 'Nothing was changed' '$T/out.txt'"

echo "== the download is an error page, not the zip"
ROOT="$T/r5"; newroot 5
mv "$T/server/Verdandi-windows-latest.zip" "$T/server/zip.hidden"
echo "<html>Not found</html>" > "$T/server/Verdandi-windows-latest.zip"
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
mv "$T/server/zip.hidden" "$T/server/Verdandi-windows-latest.zip"
ck "a file that is too small is refused as an error page" "grep -q 'that is an error page' '$T/out.txt' && [ ! -e '$ROOT/Verdandi-0.3.0-bbbbbbb' ]"

echo "== the ASIO build updates to the ASIO build (FLAVOR.txt): its own zip, its own folder name"
ROOT="$T/r6"; newroot 6
mkbuild "$ROOT/Verdandi-asio-0.2.0-aaaaaaa" 0.2.0 aaaaaaa; echo asio > "$ROOT/Verdandi-asio-0.2.0-aaaaaaa/FLAVOR.txt"
mv "$T/server/Verdandi-windows-latest.zip" "$T/server/zip.hidden"
head -c 1200000 /dev/zero > "$T/server/Verdandi-windows-asio-latest.zip"
run "$ROOT/Verdandi-asio-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
rm -f "$T/server/Verdandi-windows-asio-latest.zip"; mv "$T/server/zip.hidden" "$T/server/Verdandi-windows-latest.zip"
ck "the ASIO zip is downloaded and unpacked into Verdandi-asio-<version>-<hash>" "[ -f '$ROOT/Verdandi-asio-0.3.0-bbbbbbb/Verdandi.exe' ] && [ ! -e '$ROOT/Verdandi-0.3.0-bbbbbbb' ]"

echo "== no address to download from"
ROOT="$T/r6"; newroot 6
rm -f "$ROOT/Verdandi-0.2.0-aaaaaaa/UPDATE-SOURCE.txt"
run "$ROOT/Verdandi-0.2.0-aaaaaaa" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE="
ck "it says that this copy does not know where to download from" "grep -q 'does not know where the newest build is published' '$T/out.txt'"
exit $fail
