#!/bin/bash
# linux/tests/namamp_shim_test.sh: the cmp and cp shims of linux/shims. princeton compares its own (Raspberry Pi) NamAmp.so with the one in the extension folder and copies it
# over on a difference ("cmp -s SRC DST" / "cp SRC DST"); with Verdandi's own intact x86-64 copy there, exactly that pair is answered "equal" and "copied" without doing anything
# (nothing in dust/ is touched). every other call goes to the real cmp and cp unchanged. prints "name: ok" / "name: FAIL ...", exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/namamp-seed.sh"
SHIMS="$REPO/linux/shims"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$SHIMS/cmp" ] && [ -x "$SHIMS/cp" ] || { bad "shims" "linux/shims/cmp and cp are missing"; exit 1; }
elf() { printf "\\x7fELF\\x$1\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x$2\\x00\\x00\\x00"; head -c 64 /dev/zero; }
PACK="$T/pack/NamAmp"; mkdir -p "$PACK"; { elf 02 3e; echo "ours"; } > "$PACK/NamAmp.so"
"$S" stamp "$PACK" 1 0b3d3c9 2026-11-08 0.1~gitX "test"
H="$T/home"; E="$H/.local/share/SuperCollider/Extensions"; D="$E/princeton"
mkdir -p "$H/dust/code/princeton/lib/nam"
"$S" seed "$PACK" "$H" > /dev/null 2>&1
SRC="$H/dust/code/princeton/lib/nam/NamAmp.so"; DST="$D/NamAmp.so"
{ elf 01 28; echo "the script's own raspberry pi build"; } > "$SRC"
sum_all() { (cd "$H" && find . -type f -exec sha1sum {} + | sort); }
sum_all > "$T/before"
run() { PATH="$SHIMS:/usr/bin:/bin" "$@"; }   # what a script's os.execute sees: the shims first
REALCMP=/usr/bin/cmp; REALCP=/usr/bin/cp
$REALCMP -s "$SRC" "$DST" && bad "premise" "the two files are equal" || ok "premise: the real cmp finds the Raspberry Pi file and Verdandi's copy different"

# the pair princeton uses
run cmp -s "$SRC" "$DST"; rc=$?
[ $rc = 0 ] && ok "cmp -s <princeton's ARM file> <our intact copy>: equal (exit 0), so the script sees NAM as installed" || bad "cmp" "exit $rc"
OUT="$(run sh -c "mkdir -p '$D' && cp '$SRC' '$DST'" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s\n' "$OUT" | grep -q "^norns: NamAmp.so" && ok "mkdir -p && cp <ARM file> <our copy>: exit 0, nothing copied, one line in the log" || bad "cp" "exit $rc: $OUT"
sum_all > "$T/after"
cmp -s "$T/before" "$T/after" && ok "not one byte in the norns home changed (dust/ untouched, our copy intact)" || bad "touched" "$(diff $T/before $T/after)"
"$S" info "$H" | grep -q '^state=own' && ok "...and the copy is still ours and intact" || bad "own" ""
run cp -f "$SRC" "$DST"; [ $? = 0 ] && cmp -s "$T/before" <(sum_all) && ok "cp -f / cp -a / cp -p are the same case" || bad "options" ""
run cp -a "$SRC" "$DST"; run cp -p "$SRC" "$DST"; sum_all > "$T/after"; cmp -s "$T/before" "$T/after" && ok "...also -a and -p" || bad "options2" ""

# every other call is the real program
printf 'one\n' > "$T/a"; printf 'two\n' > "$T/b"; cp "$T/a" "$T/a2"
run cmp -s "$T/a" "$T/b"; [ $? = 1 ] && ok "cmp of two different files: 1 as always" || bad "cmp other" ""
run cmp -s "$T/a" "$T/a2"; [ $? = 0 ] && ok "cmp of two equal files: 0 as always" || bad "cmp equal" ""
run cmp "$T/a" "$T/b" > "$T/cmp.out" 2>&1; grep -q "differ" "$T/cmp.out" && ok "cmp without -s says where they differ" || bad "cmp output" "$(cat $T/cmp.out)"
run cp "$T/a" "$T/c"; cmp -s "$T/a" "$T/c" && ok "cp of any file copies" || bad "cp other" ""
mkdir -p "$T/d1"; run cp -r "$T/d1" "$T/d2"; [ -d "$T/d2" ] && ok "cp -r works" || bad "cp -r" ""
run cp "$T/a" "$T/b" "$T/d1/"; [ -f "$T/d1/a" ] && [ -f "$T/d1/b" ] && ok "cp with several sources works" || bad "cp several" ""
run cp -t "$T/d1" "$T/c"; [ -f "$T/d1/c" ] && ok "cp -t works" || bad "cp -t" ""
run cp /nonexistent "$T/x" 2> /dev/null; [ $? != 0 ] && ok "cp of a missing file still fails" || bad "cp missing" ""
run cmp -s -n 1 "$T/a" "$T/a2"; [ $? = 0 ] && ok "cmp with an option that takes a value works (-n 1)" || bad "cmp -n" ""

# the same name somewhere else, an unstamped copy, a changed copy, an x86 source: the real programs
mkdir -p "$T/other"; { elf 02 3e; echo "plain"; } > "$T/other/NamAmp.so"
run cp "$SRC" "$T/other/NamAmp.so"; cmp -s "$SRC" "$T/other/NamAmp.so" && ok "NamAmp.so in a folder without our stamp: really copied" || bad "other folder" ""
run cmp -s "$SRC" "$T/other/NamAmp.so"; [ $? = 0 ] && ok "...and cmp there is the real answer (equal now)" || bad "other cmp" ""
{ elf 02 3e; echo "an x86 build from the script"; } > "$T/x86src_NamAmp.so"; mkdir -p "$T/x86src"; mv "$T/x86src_NamAmp.so" "$T/x86src/NamAmp.so"
run cmp -s "$T/x86src/NamAmp.so" "$DST"; [ $? = 1 ] && ok "an x86-64 source (not a wrong architecture): the real cmp (different)" || bad "x86 source cmp" ""
echo "edited" >> "$DST"
run cmp -s "$SRC" "$DST"; [ $? = 1 ] && ok "our copy changed by hand: not ours any more, the real cmp (different)" || bad "modified cmp" ""
run cp "$SRC" "$DST"; cmp -s "$SRC" "$DST" && ok "...and the real cp (the script's copy goes in: the heal handles it at the next start)" || bad "modified cp" ""
# off switch
H2="$T/home2"; mkdir -p "$H2/dust/code/princeton/lib/nam"; "$S" seed "$PACK" "$H2" > /dev/null 2>&1
{ elf 01 28; echo arm; } > "$H2/dust/code/princeton/lib/nam/NamAmp.so"
NORNS_NAMAMP=0 run cmp -s "$H2/dust/code/princeton/lib/nam/NamAmp.so" "$H2/.local/share/SuperCollider/Extensions/princeton/NamAmp.so"; [ $? = 1 ] && ok "NORNS_NAMAMP=0: the shims do nothing special" || bad "off" ""
# no namamp name in the arguments: straight to the real program, exit codes pass through
run cmp /nonexistent1 /nonexistent2 2> /dev/null; [ $? = 2 ] && ok "exit codes of the real cmp pass through (2: missing file)" || bad "exit code" ""
exit $FAIL
