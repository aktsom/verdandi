#!/bin/bash
# linux/tests/portedplugins_build_test.sh: linux/portedplugins-build.sh, the step that linux/build.sh runs for a checkout (and linux/package.sh runs for the .deb), for real: the SuperCollider headers of the
# installed version are fetched (sparse clone), the pinned PortedPlugins (linux/portedplugins.pin) is built, and the pack has what twins needs. needs the network, git, cmake, ninja and a C++ compiler
# (prints SKIP and exits 77 without). prints "name: ok" / "name: FAIL ...". docs/port/phase-m29.md
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
B="$REPO/linux/portedplugins-build.sh"
. "$REPO/linux/portedplugins.pin"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
for t in git cmake ninja c++ strip; do command -v $t > /dev/null || { echo "SKIP portedplugins_build_test: $t is not installed"; exit 77; }; done
mkdir -p "$T/repo"
printf '0.10.18\n' > /dev/null

# 1. the checkout step, from nothing
OUT="$("$B" checkout "$T/repo" 2>&1)"; rc=$?
P="$T/repo/build/linux/portedplugins/PortedPlugins"
if [ ! -f "$P/.verdandi-stamp" ]; then
    case "$OUT" in *"Could not resolve"* | *"unable to access"* | *"Failed to connect"* | *"fatal: unable to"*) echo "SKIP portedplugins_build_test: no network ($(printf '%s\n' "$OUT" | tail -n 1))"; exit 77 ;; esac
    bad "checkout step" "rc=$rc $(printf '%s\n' "$OUT" | tail -n 5)"
    exit 1
fi
[ $rc = 0 ] && ok "the checkout step builds the pack from nothing (headers, clone of the pinned tag, build)" || bad "rc" "$rc"
printf '%s\n' "$OUT" | grep -q "portedplugins: pack .*: [0-9]* plug-ins" && ok "...and says how many plug-ins and how big" || bad "summary" "$(printf '%s\n' "$OUT" | tail -n 2)"
for n in $PORTED_TWINS_NEEDS; do
    [ -f "$P/Classes/$n.sc" ] && [ -f "$P/${n}_scsynth.so" ] || bad "twins needs $n" "$(ls "$P" | head -5)"
done
ok "the pack has the class file and the plug-in of what twins needs ($PORTED_TWINS_NEEDS), so the installer's two halves are found"
[ "$(git -C "$T/repo/build/linux/portedplugins/src" rev-parse HEAD)" = "$PORTED_COMMIT" ] && ok "the source built is the pinned commit $PORTED_COMMIT" || bad "commit" "$(git -C "$T/repo/build/linux/portedplugins/src" rev-parse HEAD)"
grep -q "^commit=$PORTED_COMMIT$" "$P/.verdandi-stamp" && grep -q "^serial=$PORTED_SERIAL$" "$P/.verdandi-stamp" && grep -q "^pack=PortedPlugins$" "$P/.verdandi-stamp" && ok "the stamp names the pack, the serial and the commit" || bad "stamp" "$(cat "$P/.verdandi-stamp")"
(cd "$P" && sha256sum --quiet -c .verdandi-files) && ok "the file list of the stamp matches every file" || bad "list" ""
n86=0; n_all=0
for so in "$P"/*.so; do
    n_all=$((n_all + 1))
    [ "$(od -An -tx1 -j18 -N2 "$so" | tr -d ' ')" = 3e00 ] && n86=$((n86 + 1))
done
[ "$n_all" -ge 3 ] && [ "$n86" = "$n_all" ] && ok "every plug-in ($n_all of them) is an x86_64 shared object" || bad "arch" "$n86 of $n_all"
[ ! -e "$P/HelpSource" ] && [ -f "$P/licenses/LICENSE-GPL-3.0.txt" ] && [ -f "$P/SOURCE-OFFER.txt" ] && ok "no help files; the GPL-3.0 text and the source offer are in the pack" || bad "licences" "$(ls "$P")"
grep -q "^twins needs: $PORTED_TWINS_NEEDS" "$T/repo/build/linux/portedplugins/BUILD-REPORT.txt" && ok "the build report lists what was built, what was not and what twins needs" || bad "report" "$(cat "$T/repo/build/linux/portedplugins/BUILD-REPORT.txt")"

# 2. again: up to date, nothing rebuilt
touch -d 2020-01-01 "$P/.verdandi-stamp"
OUT="$("$B" checkout "$T/repo" 2>&1)"
printf '%s\n' "$OUT" | grep -q "up to date" && [ "$(stat -c %Y "$P/.verdandi-stamp")" = "$(date -d 2020-01-01 +%s)" ] && ok "the second run says up to date and rebuilds nothing" || bad "again" "$OUT"

# 3. a class that something else already defines is taken out (sclang stops at a duplicate class)
SC="$T/repo/build/linux/portedplugins/sc-headers"
mkdir -p "$T/other"
printf 'Fverb { }\nLPG : UGen { *ar { ^1 } }\n' > "$T/other/Other.sc"
OUT="$("$B" build "$T/work2" "$SC" --other-classes "$T/other" 2>&1)"
P2="$T/work2/PortedPlugins"
[ -f "$P2/.verdandi-stamp" ] && [ ! -e "$P2/Classes/Fverb.sc" ] && [ ! -e "$P2/Classes/LPG.sc" ] && [ -f "$P2/Classes/AnalogChew.sc" ] && ok "classes that another folder defines (one written with a superclass, one without) are taken out of the pack" || bad "taken out" "$(ls "$P2/Classes" 2> /dev/null | head -4 | tr '\n' ' ') $OUT"
grep -q "classes taken out.*Fverb" "$T/work2/BUILD-REPORT.txt" && grep -q "classes taken out.*LPG" "$T/work2/BUILD-REPORT.txt" && ok "...and the build report lists them" || bad "taken report" "$(cat "$T/work2/BUILD-REPORT.txt" 2> /dev/null)"
# AnalogLoss is one of what twins needs: taking its class out must stop the build (a pack that cannot satisfy twins is not shipped)
mkdir -p "$T/other2"; printf 'AnalogLoss : UGen { *ar { ^1 } }\n' > "$T/other2/Other.sc"
OUT="$("$B" build "$T/work3" "$SC" --other-classes "$T/other2" 2>&1)"; rc=$?
[ $rc != 0 ] && printf '%s\n' "$OUT" | grep -q "the pack lacks what twins needs: AnalogLoss" && [ ! -f "$T/work3/PortedPlugins/.verdandi-stamp" ] && ok "taking out a class twins needs stops the build with a plain message, no stamped pack" || bad "needs guard" "rc=$rc $OUT"

# 4. no network: a warning, exit 0, no pack, norns still starts (the step must never stop linux/build.sh)
mkdir -p "$T/repo2"
OUT="$(https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 timeout 120 "$B" checkout "$T/repo2" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s\n' "$OUT" | grep -q "WARNING: the PortedPlugins pack" && [ ! -f "$T/repo2/build/linux/portedplugins/PortedPlugins/.verdandi-stamp" ] && ok "no network: one warning, exit 0, no pack (linux/build.sh goes on)" || bad "offline" "rc=$rc $(printf '%s\n' "$OUT" | tail -n 3)"
exit $FAIL
