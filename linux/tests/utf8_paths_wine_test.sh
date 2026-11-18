#!/usr/bin/env bash
# M22 item 1 (docs/port/phase-m22.md): user and program folders with accents and with letters outside the Windows code page.
#   the real launcher (windows/launcher/verdandi.c) starts stand-in programs that use the NARROW ("ANSI") Windows and C-library calls the real programs use (getenv, fopen, CreateFileA-family, argv, a config file that names a folder
#   in UTF-8, as sclang reads sclang_conf.yaml). the folders are named  José Ā Ж  (é is in the Windows code page 1252, Ā and Ж are not) plus a blank, for the user folder AND the program folder.
#   WITH the manifest (windows/manifest/verdandi-utf8.rc, embedded the way the build does it: windres): every call must work.   WITHOUT it (the control): the same programs must fail, which shows that the test CAN see the problem.
# what Wine can show: Wine starts programs with code page 1252 (GetACP) here, whatever the host's locale, and it honours the manifest (code page 65001 with it). so the narrow calls really change meaning, as on a Windows 10/11 with
# a Western code page. what it cannot show: the real programs (norns.exe, sclang.exe, scsynth.exe) and the real Windows file system; those run in the CI on Windows (smoke-m1.sh m22-nonascii).
# env: LAUNCHER_SRC replaces the launcher source. exit 0 = passed, 77 = nothing to run here (no cross compiler or Wine)
set -u
cd "$(dirname "$0")/../.." || exit 1
CC=x86_64-w64-mingw32-gcc-posix
command -v "$CC" > /dev/null || CC=x86_64-w64-mingw32-gcc
command -v "$CC" > /dev/null || { echo "SKIP no mingw-w64 cross compiler"; exit 77; }
WINDRES=x86_64-w64-mingw32-windres
command -v "$WINDRES" > /dev/null || { echo "SKIP no windres"; exit 77; }
WINE=/usr/lib/wine/wine64
[ -x "$WINE" ] || WINE="$(command -v wine64 || command -v wine || true)"
[ -n "$WINE" ] || { echo "SKIP no Wine"; exit 77; }
T="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
export WINEPREFIX="$T/prefix" WINEDEBUG=-all LC_ALL=C.UTF-8 LANG=C.UTF-8
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
NAME=$'Jos\xc3\xa9 \xc4\x80 \xd0\x96'   # José Ā Ж
LSRC="${LAUNCHER_SRC:-windows/launcher/verdandi.c}"

(cd windows/manifest && $WINDRES verdandi-utf8.rc -O coff -o "$T/utf8.o") || exit 1
cat > "$T/probe_acp.c" <<'EOF'
#include <stdio.h>
#include <windows.h>
int main(void) { printf("%u\n", GetACP()); return 0; }
EOF
$CC "$T/probe_acp.c" -o "$T/acp.exe" -static || exit 1
$CC "$T/probe_acp.c" "$T/utf8.o" -o "$T/acp_m.exe" -static || exit 1
ACP0="$("$WINE" "$T/acp.exe" 2> /dev/null | tr -d '\r')"; ACP1="$("$WINE" "$T/acp_m.exe" 2> /dev/null | tr -d '\r')"
echo "code page without the manifest: $ACP0, with it: $ACP1"
ck "Wine here has a real code page difference (not UTF-8 without the manifest, 65001 with it)" "[ '$ACP0' != 65001 ] && [ '$ACP1' = 65001 ]"

cat > "$T/norns_stub.c" <<'EOF'
/* stands in for norns.exe: the narrow calls matron and Lua make with the home folder and the program folder */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
static int bad = 0;
static void res(const char *what, int ok) { printf("UTF8 %s %s\n", what, ok ? "ok" : "FAIL"); if (!ok) bad = 1; }
static int write_file(const char *p, const char *text) { FILE *f = fopen(p, "wb"); if (!f) return 0; fputs(text, f); fclose(f); return 1; }
static int read_file(const char *p, char *out, size_t n) { FILE *f = fopen(p, "rb"); if (!f) return 0; size_t k = fread(out, 1, n - 1, f); out[k] = 0; fclose(f); return 1; }
int main(int argc, char **argv) {
    (void)argc;
    const char *h = getenv("HOME");
    { const char *bn = getenv("VERDANDI_BRIDGE"); if (bn) { char nm[200]; snprintf(nm, sizeof nm, "Local\\%s", bn); CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, nm); } } /* what norns.exe does: the launcher waits for it before it starts sclang */
    char p[1500], q[1500], buf[300];
    if (!h) { printf("UTF8 home FAIL (no HOME)\n"); return 1; }
    printf("UTF8 acp=%u\n", GetACP());
    res("home-bytes", strstr(h, "Jos\xc3\xa9 \xc4\x80 \xd0\x96") != NULL);
    char self[1000]; GetModuleFileNameA(NULL, self, sizeof self);
    res("program-folder-name", GetFileAttributesA(self) != INVALID_FILE_ATTRIBUTES);
    /* the script's own data files */
    snprintf(p, sizeof p, "%s/dust/data/own \xc3\xa9\xc4\x80\xd0\x96 data.txt", h);
    res("data-write", write_file(p, "own data"));
    res("data-read", read_file(p, buf, sizeof buf) && !strcmp(buf, "own data"));
    snprintf(q, sizeof q, "%s/dust/data/own \xc3\xa9\xc4\x80\xd0\x96 data 2.txt", h);
    res("rename", MoveFileA(p, q) && GetFileAttributesA(q) != INVALID_FILE_ATTRIBUTES);
    /* script list: a folder listing finds a folder with the odd name */
    snprintf(p, sizeof p, "%s/dust/code/script \xc3\xa9\xc4\x80\xd0\x96", h);
    CreateDirectoryA(p, NULL);
    snprintf(q, sizeof q, "%s/dust/code/*", h);
    WIN32_FIND_DATAA fd; HANDLE fh = FindFirstFileA(q, &fd); int found = 0;
    if (fh != INVALID_HANDLE_VALUE) { do { if (strstr(fd.cFileName, "script \xc3\xa9\xc4\x80\xd0\x96")) found = 1; } while (FindNextFileA(fh, &fd)); FindClose(fh); }
    res("script-list", found);
    snprintf(q, sizeof q, "%s/dust/data/own \xc3\xa9\xc4\x80\xd0\x96 data 2.txt", h);
    res("remove", DeleteFileA(q) && GetFileAttributesA(q) == INVALID_FILE_ATTRIBUTES);
    /* tape: a file written in dust/audio/tape and its size read back */
    snprintf(p, sizeof p, "%s/dust/audio/tape/tape \xc4\x80.wav", h);
    { FILE *f = fopen(p, "wb"); int ok = f != NULL; if (f) { char z[4096] = {0}; ok = fwrite(z, 1, sizeof z, f) == sizeof z; fclose(f); } WIN32_FILE_ATTRIBUTE_DATA a; ok = ok && GetFileAttributesExA(p, GetFileExInfoStandard, &a) && a.nFileSizeLow == 4096; res("tape-write", ok); }
    res("tape-read", read_file(p, buf, 100));
    /* a sample seeded by the test under dust/audio */
    snprintf(p, sizeof p, "%s/dust/audio/sample \xc3\xa9\xc4\x80\xd0\x96.wav", h);
    res("sample-read", read_file(p, buf, sizeof buf) && !strcmp(buf, "RIFF-sample"));
    /* a settings file */
    snprintf(p, sizeof p, "%s/dust/data/settings \xd0\x96.conf", h);
    res("settings", write_file(p, "a=1\n") && read_file(p, buf, sizeof buf) && !strcmp(buf, "a=1\n"));
    /* a script that names a file in the program folder (a path from the command line of a script, here the folder of this program) */
    if (argc > 1) res("argv", strstr(argv[1], "\xc4\x80") != NULL);
    fflush(stdout);
    Sleep(3500);
    return bad;
}
EOF
cat > "$T/sclang_stub.c" <<'EOF'
/* stands in for sclang.exe: reads sclang_conf.yaml (the launcher writes UTF-8) and opens a file in the first include path, with the narrow calls sclang makes */
#include <stdio.h>
#include <string.h>
#include <windows.h>
int main(void) {
    FILE *f = fopen("sclang_conf.yaml", "rb");
    char line[2000], path[2000] = "";
    if (f) { while (fgets(line, sizeof line, f)) { char *a = strchr(line, '"'); if (a) { char *b = strrchr(line, '"'); if (b > a) { *b = 0; snprintf(path, sizeof path, "%s/Crone.sc", a + 1); break; } } } fclose(f); }
    FILE *g = path[0] ? fopen(path, "rb") : NULL;
    printf("UTF8 sclang-include %s\n", g ? "ok" : "FAIL");
    if (g) fclose(g);
    fflush(stdout);
    Sleep(1000);
    return 0;
}
EOF
$CC "$T/norns_stub.c" "$T/utf8.o" -o "$T/norns_m.exe" -static || exit 1
$CC "$T/norns_stub.c" -o "$T/norns_plain.exe" -static || exit 1
$CC "$T/sclang_stub.c" "$T/utf8.o" -o "$T/sclang_m.exe" -static || exit 1
$CC "$T/sclang_stub.c" -o "$T/sclang_plain.exe" -static || exit 1
$CC -municode -mwindows -O2 -w "$LSRC" -I windows/launcher -o "$T/launcher.exe" -static -lws2_32 -liphlpapi || exit 1

# one run: variant = m (with the manifest) or plain (without). program folder and user folder both have the odd name
run() {
    local v="$1"
    local parent="$T/Verdandi $NAME folder $v"
    local app="$parent/Verdandi" home="$T/user $NAME home $v"
    mkdir -p "$app/lua/core" "$app/supercollider" "$app/update" "$app/sc/core" "$home/dust/code" "$home/dust/data" "$home/dust/audio/tape"
    printf "9.9.9 abcdef1\nbuilt: test\n" > "$app/BUILD.txt"; touch "$app/lua/core/config.lua" "$app/sc/core/Crone.sc"; echo test > "$app/update/version.txt"
    cp "$T/launcher.exe" "$app/Verdandi.exe"; cp "$T/norns_$v.exe" "$app/norns.exe"; cp "$T/sclang_$v.exe" "$app/supercollider/sclang.exe"
    printf 'RIFF-sample' > "$home/dust/audio/sample $(printf '\xc3\xa9\xc4\x80\xd0\x96').wav"
    (cd "$app" && VERDANDI_NO_LINK=1 timeout 90 "$WINE" ./Verdandi.exe --headless --exit-after=6 --home="Z:$home" > "$T/launcher-$v.out" 2>&1); echo $? > "$T/rc-$v"
    "$WS" -k 2> /dev/null
    sleep 1
    eval "APP_$v=\"\$app\"; HOME_$v=\"\$home\""
}
WS="$(command -v wineserver || ls /usr/lib/wine/wineserver* 2> /dev/null | head -n 1)"
run m
run plain
L="$HOME_m/logs"
echo "== with the manifest (the way Verdandi is built)"
ck "the launcher ran in the program folder with the odd name and wrote its log in the user folder with the odd name" "grep -q 'norns.exe started' '$L/launcher.log' && grep -q 'sclang.exe started' '$L/launcher.log'"
ck "the launcher log names the folders in readable UTF-8 (not as ? or Latin-1)" "grep -qF \"\$NAME\" '$L/launcher.log'"
for w in acp home-bytes program-folder-name data-write data-read rename script-list remove tape-write tape-read sample-read settings; do
    case "$w" in acp) ck "norns stand-in runs with code page 65001" "grep -q 'UTF8 acp=65001' '$L/norns.log'" ;; *) ck "norns stand-in: $w" "grep -q 'UTF8 $w ok' '$L/norns.log'" ;; esac
done
ck "sclang stand-in opens a file through the UTF-8 include path of sclang_conf.yaml" "grep -q 'UTF8 sclang-include ok' '$L/sclang.log'"
ck "files written by the stand-in are really named with the odd letters on disk (own data, tape, settings)" "ls '$HOME_m'/dust/data/ | grep -q 'settings' && ls '$HOME_m'/dust/audio/tape/ | grep -qF \"tape \$(printf '\\xc4\\x80').wav\""
ck "the launcher ended with code 0" "[ \"\$(cat '$T/rc-m')\" = 0 ]"
echo "== without the manifest (the control: it must FAIL, or this test would see nothing)"
L2="$HOME_plain/logs"
ck "the launcher itself still works (it uses the wide calls)" "grep -q 'norns.exe started' '$L2/launcher.log'"
ck "the stand-in has code page $ACP0, not 65001" "grep -q 'UTF8 acp=$ACP0' '$L2/norns.log'"
ck "without it HOME arrives as Latin-1 / best fit bytes: home-bytes FAILS" "grep -q 'UTF8 home-bytes FAIL' '$L2/norns.log'"
ck "without it the narrow calls do not find the files: at least one more check FAILS (the sample)" "grep -q 'UTF8 sample-read FAIL' '$L2/norns.log'"
ck "without it sclang cannot open the include path of its yaml file" "grep -q 'UTF8 sclang-include FAIL' '$L2/sclang.log'"
echo
[ "$fail" = 0 ] && echo "utf8 paths: all passed" || echo "utf8 paths: FAILED"
exit $fail
