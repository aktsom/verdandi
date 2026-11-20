#!/bin/bash
# linux/tests/twins_grain_test.sh: linux/twins-grain.sh sync on fake norns homes with a fake script folder dust/code/twins (lib/ugens/TwinGrain.sc.in and x86_64/TwinGrain.so.in):
# the copy twins' own installer makes on K3 ("Missing SuperCollider Libraries: TwinGrain") is made before sclang starts, with the installer's own load test, and
# nothing else is touched. prints "name: ok" / "name: FAIL ..." lines, exit 1 if any failed. docs/port/phase-m29.md
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/twins-grain.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$S" ] || { bad "script" "$S missing"; exit 1; }
if [ "$(uname -m)" != x86_64 ] || ! command -v cc > /dev/null || ! command -v python3 > /dev/null; then echo "SKIP twins_grain_test: needs an x86_64 machine with cc and python3"; exit 77; fi

# a real shared object that python3's ctypes loads (what the installer's test does), and a file that is not one
printf 'int twingrain_probe(void) { return 7; }\n' > "$T/g.c"
cc -shared -fPIC -o "$T/good.so" "$T/g.c" || { echo "SKIP twins_grain_test: cc cannot build a shared object"; exit 77; }
printf 'this is not a shared object\n' > "$T/bad.so"
mktwins() { # home so-file tag
    local h="$1"
    mkdir -p "$h/dust/code/twins/lib/ugens/x86_64" "$h/dust/code/twins/lib/ugens/aarch64"
    echo "TwinGrain : MultiOutUGen { } // $3" > "$h/dust/code/twins/lib/ugens/TwinGrain.sc.in"
    cp "$2" "$h/dust/code/twins/lib/ugens/x86_64/TwinGrain.so.in"
    cp "$T/bad.so" "$h/dust/code/twins/lib/ugens/aarch64/TwinGrain.so.in"
}
newhome() { H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"; }
snap() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) 2> /dev/null; }

# 1. no twins: silent, nothing made
newhome 1
OUT="$("$S" sync "$H" 2>&1)"
[ -z "$OUT" ] && [ ! -e "$E" ] && ok "twins is not installed: silent, nothing is made" || bad "no twins" "$OUT"

# 2. twins with a file that loads: copied, one line; the installer's check (cmp of both files with Extensions/twins/TwinGrain.sc and .so) is now satisfied
newhome 2; mktwins "$H" "$T/good.so" one
OUT="$("$S" sync "$H" 2>&1)"
cmp -s "$H/dust/code/twins/lib/ugens/TwinGrain.sc.in" "$E/twins/TwinGrain.sc" && cmp -s "$H/dust/code/twins/lib/ugens/x86_64/TwinGrain.so.in" "$E/twins/TwinGrain.so" && ok "the script's own two files are copied to <extensions>/twins (what the installer's K3 copies)" || bad "copy" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q '^twins: copied' && ok "...one line says so" || bad "line" "$OUT"
[ -x "$E/twins/TwinGrain.so" ] && [ "$(ls -A "$E/twins" | wc -l)" = 2 ] && ok "...the plug-in is executable and no temp file is left" || bad "leftover" "$(ls -A "$E/twins")"
[ -z "$(find "$H/dust/code/twins" -newer "$T/g.c" -type f -name '*.in' 2> /dev/null | head -n 1)" ] || true
# twins' installer check, written out the way installer.lua does it: find over the extension folder for X.sc and X.so, then cmp with the script's files
[ -n "$(find "$E" -name TwinGrain.sc -type f)" ] && [ -n "$(find "$E" -name TwinGrain.so -type f)" ] && ok "installer's two-halves find sees TwinGrain.sc and TwinGrain.so" || bad "find" "$(find "$E")"

# 3. again: silent, nothing rewritten
touch -d 2020-01-01 "$E/twins/TwinGrain.sc"
OUT="$("$S" sync "$H" 2>&1)"
[ -z "$OUT" ] && [ "$(stat -c %Y "$E/twins/TwinGrain.sc")" = "$(date -d 2020-01-01 +%s)" ] && ok "identical files: silent, nothing rewritten" || bad "again" "$OUT"

# 4. twins updated its file: the installer would call it missing (cmp differs): the copy is replaced
echo "TwinGrain : MultiOutUGen { } // two" > "$H/dust/code/twins/lib/ugens/TwinGrain.sc.in"
OUT="$("$S" sync "$H" 2>&1)"
grep -q '// two' "$E/twins/TwinGrain.sc" && printf '%s\n' "$OUT" | grep -q '^twins: copied' && ok "a newer file of the script replaces the copy in <extensions>/twins" || bad "update" "$OUT"

# 5. a file that does not load (the installer's own load test): nothing is made
newhome 5; mktwins "$H" "$T/bad.so" one
OUT="$("$S" sync "$H" 2>&1)"
[ -z "$OUT" ] && [ ! -e "$E" ] && ok "a plug-in that does not load: nothing is copied, silent (the installer then decides)" || bad "no load" "$OUT"

# 6. the installer's skip marker
newhome 6; mktwins "$H" "$T/good.so" one; mkdir -p "$H/dust/data/twins"; echo 1 > "$H/dust/data/twins/skip_TwinGrain_x86_64"
OUT="$("$S" sync "$H" 2>&1)"
[ -z "$OUT" ] && [ ! -e "$E" ] && ok "the installer's skip marker (it found the file unusable on this machine once): nothing is copied" || bad "skip" "$OUT"

# 7. another TwinGrain somewhere else: left alone, one line
newhome 7; mktwins "$H" "$T/good.so" one; mkdir -p "$E/old-twin"; echo "// theirs" > "$E/old-twin/TwinGrain.sc"
snap "$H/.local" > "$T/s.before"
OUT="$("$S" sync "$H" 2>&1)"
snap "$H/.local" > "$T/s.after"
cmp -s "$T/s.before" "$T/s.after" && [ ! -e "$E/twins" ] && printf '%s\n' "$OUT" | grep -q "old-twin/TwinGrain.sc exists" && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && ok "another TwinGrain in the extension folders: nothing is touched, one line names it" || bad "other" "$OUT"
newhome 71; mktwins "$H" "$T/good.so" one; mkdir -p "$H/dust/code/copy/Classes"; echo "// theirs" > "$H/dust/code/copy/Classes/TwinGrain.sc"
OUT="$("$S" sync "$H" 2>&1)"
[ ! -e "$E/twins" ] && printf '%s\n' "$OUT" | grep -q "dust/code/copy/Classes/TwinGrain.sc exists" && ok "another TwinGrain.sc in dust/code: nothing is copied (duplicate class)" || bad "other dust" "$OUT"
# the script's own .sc.in and .so.in files are not copies
newhome 72; mktwins "$H" "$T/good.so" one
OUT="$("$S" sync "$H" 2>&1)"; printf '%s\n' "$OUT" | grep -q 'exists' && bad "own files" "$OUT" || ok "the script's own lib/ugens files do not count as another copy"

# 8. the folder <extensions>/twins holds an older copy of the installer's: replaced; a foreign file next to it stays
newhome 8; mktwins "$H" "$T/good.so" one; mkdir -p "$E/twins"; echo "// old" > "$E/twins/TwinGrain.sc"; cp "$T/good.so" "$E/twins/TwinGrain.so"; echo "x" > "$E/twins/other.txt"
OUT="$("$S" sync "$H" 2>&1)"
grep -q 'one' "$E/twins/TwinGrain.sc" && [ -f "$E/twins/other.txt" ] && ok "an older copy in <extensions>/twins is replaced, another file there is not touched" || bad "older" "$OUT"

# 9. off
for v in 0 off false no; do
    newhome 9; mktwins "$H" "$T/good.so" one
    OUT="$(NORNS_TWINS_GRAIN=$v "$S" sync "$H" 2>&1)"
    [ -z "$OUT" ] && [ ! -e "$E" ] || bad "off $v" "$OUT"
done
ok "NORNS_TWINS_GRAIN=0 / off / false / no: nothing is copied, nothing is said"
# never fails the launcher
"$S" sync "$T/does-not-exist" > /dev/null 2>&1; [ $? = 0 ] && ok "a home that is not there: exit 0" || bad "exit" ""
# a read-only extension folder: one line, exit 0
newhome 10; mktwins "$H" "$T/good.so" one; mkdir -p "$E"; chmod 555 "$E"
OUT="$("$S" sync "$H" 2>&1)"; rc=$?
chmod 755 "$E"
if [ "$(id -u)" = 0 ]; then ok "(running as root: the read-only case cannot be tried)"; else [ $rc = 0 ] && printf '%s\n' "$OUT" | grep -q 'cannot write' && ok "an extension folder that cannot be written: one line, exit 0" || bad "readonly" "$OUT"; fi
exit $FAIL
