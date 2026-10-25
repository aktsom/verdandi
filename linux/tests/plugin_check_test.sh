#!/bin/bash
# linux/tests/plugin_check_test.sh <outfile>: linux/plugin_arch_check against a fake norns home with fake extension folders
# (files that only have an ELF header). prints "name: ok" / "name: FAIL ..." lines, exit 1 if any failed. the tool is built here.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
g++ -std=c++14 -I "$REPO/matron/src" "$REPO/linux/plugin_arch_check.cc" -o "$T/check" 2> "$T/cc.log" || { cat "$T/cc.log"; exit 1; }
H="$T/home"
E="$H/.local/share/SuperCollider/Extensions"
mkdir -p "$E/supercollider-plugins" "$E/good" "$E/mixed" "$H/dust/code/foo/lib" "$H/dust/code/foo/ignore"
# the first bytes of an ELF file: magic, class, data, version, padding, type, machine (at 18)
elf() { # class(01|02) machine-low machine-high
    printf "\\x7fELF\\x$1\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x$2\\x$3\\x00\\x00"
    head -c 64 /dev/zero
}
arm32() { elf 01 28 00; }
x86() { elf 02 3e 00; }
aarch() { elf 02 b7 00; }
for n in AnalogChew AnalogLoss AnalogDegrade; do arm32 > "$E/supercollider-plugins/${n}_scsynth.so"; echo "// class" > "$E/supercollider-plugins/$n.sc"; done
x86 > "$E/good/Good_scsynth.so"
arm32 > "$E/mixed/Bad_scsynth.so"
x86 > "$E/mixed/Fine.so"
echo "not elf" > "$E/notelf.so"
arm32 > "$H/dust/code/foo/lib/cjson.so"                 # a Lua library: not a SuperCollider plug-in
arm32 > "$H/dust/code/foo/ignore/PulsePTR_scsynth.so"  # a plug-in that ships with a script
find "$H" -type f -exec sha1sum {} + | sort > "$T/before"

FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
OUT="$(PLUGIN_ARCH_UNAME=x86_64 "$T/check" "$H" 2>&1)"
n=$(printf '%s\n' "$OUT" | grep -c "^SuperCollider plug-in")
[ "$n" = 5 ] && ok "five mismatches, one line each" || bad "five mismatches, one line each" "got $n: $OUT"
for f in AnalogChew AnalogLoss AnalogDegrade; do
    printf '%s\n' "$OUT" | grep -q "supercollider-plugins/${f}_scsynth.so is built for 32-bit ARM, this machine is x86_64" && ok "$f reported" || bad "$f reported" "$OUT"
done
printf '%s\n' "$OUT" | grep -q "mv '$E/supercollider-plugins' '$H/disabled-plugins/'" && ok "a folder that is all bad: the command moves the folder" || bad "folder command" "$OUT"
printf '%s\n' "$OUT" | grep -q "mv '$E/mixed/Bad_scsynth.so' '$H/disabled-plugins/'" && ok "a folder with good files too: the command moves the file" || bad "file command" "$OUT"
printf '%s\n' "$OUT" | grep -q "PulsePTR_scsynth.so is built for 32-bit ARM" && ok "a plug-in in dust/code is reported" || bad "dust/code plug-in" "$OUT"
printf '%s\n' "$OUT" | grep -q "cjson.so" && bad "cjson.so is not a plug-in" "$OUT" || ok "a Lua library in dust/code is not reported"
printf '%s\n' "$OUT" | grep -q "Good_scsynth.so\|Fine.so\|notelf.so" && bad "good and non-ELF files" "$OUT" || ok "x86_64 and non-ELF files are not reported"
printf '%s\n' "$OUT" | grep -q "stops at the first bad file" && ok "says that SuperCollider stops at the first bad file" || bad "stops at the first" "$OUT"
[ "$(wc -l < "$H/.plugin-mismatch")" = 5 ] && ok "the list file for the device note has five paths" || bad "list file" "$(cat "$H/.plugin-mismatch" 2>&1)"
find "$H" -type f -not -name .plugin-mismatch -exec sha1sum {} + | sort > "$T/after"
cmp -s "$T/before" "$T/after" && [ ! -e "$H/disabled-plugins" ] && ok "nothing was moved, changed or created besides the list file" || bad "nothing changed" "files differ"
# the same files on an aarch64 machine: the x86_64 ones are the wrong ones now (and the ARM 32-bit too)
OUT2="$(PLUGIN_ARCH_UNAME=aarch64 "$T/check" "$H" 2>&1)"
printf '%s\n' "$OUT2" | grep -q "Good_scsynth.so is built for 64-bit x86_64, this machine is aarch64" && ok "an x86_64 file on an aarch64 machine is reported" || bad "aarch64 machine" "$OUT2"
# the switch
OUT3="$(NORNS_PLUGIN_CHECK=0 PLUGIN_ARCH_UNAME=x86_64 "$T/check" "$H" 2>&1)"
[ -z "$OUT3" ] && [ ! -e "$H/.plugin-mismatch" ] && ok "NORNS_PLUGIN_CHECK=0: nothing reported, no list file" || bad "switch" "$OUT3"
# after the files are moved away by hand, nothing is left and the list file goes
PLUGIN_ARCH_UNAME=x86_64 "$T/check" "$H" > /dev/null 2>&1
mkdir -p "$H/disabled-plugins"
mv "$E/supercollider-plugins" "$E/mixed/Bad_scsynth.so" "$H/dust/code/foo/ignore/PulsePTR_scsynth.so" "$H/disabled-plugins/"
OUT4="$(PLUGIN_ARCH_UNAME=x86_64 "$T/check" "$H" 2>&1)"
[ -z "$OUT4" ] && [ ! -s "$H/.plugin-mismatch" ] && ok "after moving them: no line, the list is empty" || bad "after moving" "$OUT4"
exit $FAIL
