#!/usr/bin/env bash
# linux/tests/update_and_run_test.sh: windows/update-and-run.cmd under Wine with stand-ins for curl.exe, tar.exe and choice.exe (Wine has no curl and no tar): the logic of the script, not the tools of Windows.
# what it proves (M22: STATIC folder names): a newer build replaces the folder Verdandi (the ASIO build: Verdandi-asio) in the same place, under the same name, so that a Windows Defender exclusion keeps working; the build it replaces
# is kept as Verdandi.previous; the script that runs is inside the folder that is replaced (it copies itself to the temp folder first); "no" keeps older builds, "yes" removes only Verdandi.previous and old
# versioned folders (Verdandi.exe and norns.exe) and never the data folder, the build in the folder is recognised as the newest, a failed download (404, no connection, an error page, a bad checksum) says so in plain
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

mkdir -p "$T/stubs" "$T/server/unpacked" "$T/server/unpacked-asio"
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
    snprintf(src, sizeof src, "%s\\%s", getenv("VERDANDI_TEST_SERVER"), getenv("VERDANDI_TEST_UNPACK") ? getenv("VERDANDI_TEST_UNPACK") : "unpacked");
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
# the "release": BUILD.txt, a zip (any 1.2 MB file; the checksum is left out here), and the folders the stand-in tar unpacks: Verdandi (the default build) and Verdandi-asio. both folders have FIXED names
mkbuild "$T/server/unpacked/Verdandi" 0.3.0 bbbbbbb
mkbuild "$T/server/unpacked-asio/Verdandi-asio" 0.3.0 bbbbbbb; echo asio > "$T/server/unpacked-asio/Verdandi-asio/FLAVOR.txt"
printf '0.3.0 bbbbbbb\n' > "$T/server/BUILD.txt"
head -c 1200000 /dev/zero > "$T/server/Verdandi-windows-latest.zip"

newroot() { # a parent folder "X" as Windows' Extract All makes it (Verdandi-windows-latest), the old build in X/Verdandi, the data folder and something else next to it
    R="$T/r$1"
    rm -rf "$R"; mkdir -p "$R/X" "$R/other" "$R/mydata/dust/code"
    echo "my script" > "$R/mydata/dust/code/mine.lua"
    mkbuild "$R/X/Verdandi" 0.2.0 aaaaaaa
    ROOT="$R"; OLD="$R/X/Verdandi"; PAR="$R/X"
}
# shellcheck disable=SC1003
winpath() { printf 'Z:%s' "$1" | tr / '\\'; }
run() { # script folder, extra args, env assignments...; the output is in $T/out.txt
    local dir="$1" args="$2"; shift 2
    printf '@echo off\r\nset PATH=%s;%%PATH%%\r\ncd /d %s\r\nset VERDANDI_TEST_SERVER=%s\r\nset USERPROFILE=%s\r\nset VERDANDI_HOME=%s\r\nset VERDANDI_CHOICE=%s\\answer.exe\r\n%s\r\ncall "%s\\update-and-run.cmd" %s\r\necho EXITCODE=%%errorlevel%%\r\n' \
        "$(winpath "$T/stubs")" "$(winpath "$T/stubs")" "$(winpath "$T/server")" "$(winpath "$ROOT")" "$(winpath "$ROOT/mydata")" "$(winpath "$T/stubs")" "$*" "$(winpath "$dir")" "$args" > "$T/run.cmd"
    (cd "$T" && timeout 120 "$WINE" cmd /c "$(winpath "$T/run.cmd")" > "$T/out.txt" 2>&1)
}
first_line() { head -n 1 "$1" | tr -d '\r'; }

echo "== a newer build exists; it goes into the SAME folder name; the old one is kept as Verdandi.previous; the answer to 'remove older builds' is no"
newroot 1; mkbuild "$PAR/Verdandi-0.1.5-ccccccc" 0.1.5 ccccccc
run "$OLD" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
tr -d "\r" < "$T/out.txt" | sed -n 1,40p
ck "it says which build this folder holds and which is the newest" "grep -q 'This folder holds build: 0.2.0 aaaaaaa' '$T/out.txt' && grep -q 'The newest build is:     0.3.0 bbbbbbb' '$T/out.txt'"
ck "the new build is in the folder Verdandi, the same path as the old one (the path an exclusion is made for)" "[ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.3.0 bbbbbbb' ] && [ -f '$PAR/Verdandi/Verdandi.exe' ]"
ck "the old build is kept beside it as Verdandi.previous, and the answer says so" "[ \"\$(first_line '$PAR/Verdandi.previous/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && grep -q 'kept as' '$T/out.txt'"
ck "no folder with the version in its name was made" "[ ! -e '$PAR/Verdandi-0.3.0-bbbbbbb' ]"
ck "the temporary unpack folder is gone" "[ ! -e '$PAR/.verdandi-unpack' ]"
ck "older builds (Verdandi.previous and the old versioned folder) are listed and kept (answer no)" "grep -q 'Older unpacked builds next to it' '$T/out.txt' && grep -q 'Verdandi.previous' '$T/out.txt' && grep -q 'Verdandi-0.1.5-ccccccc' '$T/out.txt' && [ -d '$PAR/Verdandi-0.1.5-ccccccc' ]"
ck "the data folder is not offered and not touched" "[ -f '$ROOT/mydata/dust/code/mine.lua' ] && ! grep -q 'mydata' '$T/out.txt' | grep -q x"
ck "the script ends with 0 and does not start Verdandi with /NOSTART" "grep -q 'EXITCODE=0' '$T/out.txt' && [ ! -e '$PAR/Verdandi/started.txt' ]"
ck "the copy of the script that ran is not in the folder that was replaced (it ran from the temp folder)" "grep -q 'Put in place' '$T/out.txt'"

echo "== start: the new Verdandi.exe is started from the same folder"
newroot 2
run "$OLD" "/KEEP" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
sleep 2
ck "Verdandi.exe of the new build was started" "[ -f '$PAR/Verdandi/started.txt' ]"
ck "/KEEP: no question about older builds" "! grep -q 'Older unpacked builds next to it' '$T/out.txt'"

echo "== run again from the new folder: it is the newest; 'yes' removes Verdandi.previous, not itself, not the data"
run "$PAR/Verdandi" "/NOSTART" "set VERDANDI_TEST_CHOICE=Y&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "it says that this is the newest build" "grep -q 'You already have the newest build' '$T/out.txt'"
ck "the older build (Verdandi.previous) is removed" "[ ! -e '$PAR/Verdandi.previous' ]"
ck "the new build and the data folder are still there" "[ -f '$PAR/Verdandi/Verdandi.exe' ] && [ -f '$ROOT/mydata/dust/code/mine.lua' ] && [ -d '$ROOT/other' ]"

echo "== a third update: the one before is replaced, not piled up"
newroot 7; mkdir -p "$PAR/Verdandi.previous"; echo oldest > "$PAR/Verdandi.previous/BUILD.txt"; cp "$T/app.exe" "$PAR/Verdandi.previous/Verdandi.exe"; cp "$T/app.exe" "$PAR/Verdandi.previous/norns.exe"
run "$OLD" "/NOSTART /KEEP" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "Verdandi.previous is now the build that was replaced (0.2.0), the older one is gone" "[ \"\$(first_line '$PAR/Verdandi.previous/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && [ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.3.0 bbbbbbb' ]"

echo "== the download fails: nothing published (404)"
newroot 3
mv "$T/server/BUILD.txt" "$T/server/BUILD.txt.hidden"
run "$OLD" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
mv "$T/server/BUILD.txt.hidden" "$T/server/BUILD.txt"
ck "a plain message says that nothing is published (and that a private repository cannot be read)" "grep -q 'There is no published build' '$T/out.txt' && grep -q 'repository is private' '$T/out.txt'"
ck "nothing was changed and the exit code says so" "[ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && [ ! -e '$PAR/Verdandi.previous' ] && grep -Eq 'EXITCODE=[12]' '$T/out.txt'" # (Wine reports 1 where Windows reports 2: exit /b of a called batch file)

echo "== the download fails: no internet"
newroot 4
run "$OLD" "/NOSTART" "set VERDANDI_TEST_OFFLINE=1&set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "a plain message says that the server cannot be reached" "grep -q 'Cannot connect to the server' '$T/out.txt' && grep -q 'Nothing was changed' '$T/out.txt'"

echo "== the download is an error page, not the zip"
newroot 5
mv "$T/server/Verdandi-windows-latest.zip" "$T/server/zip.hidden"
echo "<html>Not found</html>" > "$T/server/Verdandi-windows-latest.zip"
run "$OLD" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
mv "$T/server/zip.hidden" "$T/server/Verdandi-windows-latest.zip"
ck "a file that is too small is refused as an error page, and the old build is untouched" "grep -q 'that is an error page' '$T/out.txt' && [ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.2.0 aaaaaaa' ]"

echo "== M31: ONE zip. a folder of an earlier ASIO build (Verdandi-asio, FLAVOR.txt) updates from Verdandi-windows-latest.zip and KEEPS its folder name (the path of a Defender exclusion), the normal folder next to it is not touched"
newroot 6
mkbuild "$PAR/Verdandi-asio" 0.2.0 aaaaaaa; echo asio > "$PAR/Verdandi-asio/FLAVOR.txt"
run "$PAR/Verdandi-asio" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "the one zip is downloaded and put in Verdandi-asio (kept as Verdandi-asio.previous)" "[ \"\$(first_line '$PAR/Verdandi-asio/BUILD.txt')\" = '0.3.0 bbbbbbb' ] && [ \"\$(first_line '$PAR/Verdandi-asio.previous/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && [ ! -d '$PAR/Verdandi-asio/Verdandi' ]"
ck "the normal build's folder is not touched by it (and not offered for removal)" "[ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && ! grep -q 'next to it.*Verdandi\\\$' '$T/out.txt'"
echo "== the new folder has no FLAVOR.txt: its NEXT update still keeps the name Verdandi-asio (the name comes from the folder it runs from)"
printf '0.4.0 ccccccc\n' > "$T/server/BUILD.txt"; printf '0.4.0 ccccccc\nbuilt: test\n' > "$T/server/unpacked/Verdandi/BUILD.txt"
run "$PAR/Verdandi-asio" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "again Verdandi-asio, built 0.4.0, and no folder named Verdandi-asio-<something> or a second Verdandi appeared" "[ \"\$(first_line '$PAR/Verdandi-asio/BUILD.txt')\" = '0.4.0 ccccccc' ] && [ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.2.0 aaaaaaa' ]"
printf '0.3.0 bbbbbbb\n' > "$T/server/BUILD.txt"; printf '0.3.0 bbbbbbb\nbuilt: test\n' > "$T/server/unpacked/Verdandi/BUILD.txt"
echo "== a copy of the folder with FLAVOR.txt under another name still updates into Verdandi-asio; a plain Verdandi stays Verdandi"
newroot 7
mkbuild "$PAR/mycopy" 0.2.0 aaaaaaa; echo asio > "$PAR/mycopy/FLAVOR.txt"
run "$PAR/mycopy" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "FLAVOR.txt in a folder with another name: the new build is put in Verdandi-asio" "[ \"\$(first_line '$PAR/Verdandi-asio/BUILD.txt')\" = '0.3.0 bbbbbbb' ]"
newroot 9
run "$OLD" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
ck "a plain folder named Verdandi stays Verdandi (the zip is the one zip)" "[ \"\$(first_line '$PAR/Verdandi/BUILD.txt')\" = '0.3.0 bbbbbbb' ] && [ ! -d '$PAR/Verdandi-asio' ]"
echo "== the update routine of the EARLIER ASIO build (0.10.21: it asks for Verdandi-windows-asio-latest.zip) works against the new release: the transition copy"
newroot 10
mkbuild "$PAR/Verdandi-asio" 0.2.0 aaaaaaa; echo asio > "$PAR/Verdandi-asio/FLAVOR.txt"
cp linux/tests/fixtures/update-and-run-0.10.21.cmd "$PAR/Verdandi-asio/update-and-run.cmd"
mv "$T/server/Verdandi-windows-latest.zip" "$T/server/zip.hidden"
cp "$T/server/zip.hidden" "$T/server/Verdandi-windows-asio-latest.zip" # (the transition copy: the same bytes)
run "$PAR/Verdandi-asio" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE=$(winpath "$T/server")"
rm -f "$T/server/Verdandi-windows-asio-latest.zip"; mv "$T/server/zip.hidden" "$T/server/Verdandi-windows-latest.zip"
ck "the old routine downloads the old name, takes the folder Verdandi out of it and puts it in Verdandi-asio: the same path, built 0.3.0" "[ \"\$(first_line '$PAR/Verdandi-asio/BUILD.txt')\" = '0.3.0 bbbbbbb' ] && [ \"\$(first_line '$PAR/Verdandi-asio.previous/BUILD.txt')\" = '0.2.0 aaaaaaa' ] && [ -f '$PAR/Verdandi-asio/update-and-run.cmd' ]"

echo "== no address to download from"
newroot 8
rm -f "$OLD/UPDATE-SOURCE.txt"
run "$OLD" "/NOSTART" "set VERDANDI_TEST_CHOICE=N&set VERDANDI_UPDATE_BASE="
ck "it says that this copy does not know where to download from" "grep -q 'does not know where the newest build is published' '$T/out.txt'"
exit $fail
