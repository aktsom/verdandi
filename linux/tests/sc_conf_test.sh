#!/bin/bash
# the launcher's sclang_conf.yaml (docs/port/KNOWN-ISSUES.md items 20, 21): the Linux-only class folders sc/linux and sc/linux-compat are listed by default, each left out by its switch
# (NORNS_SC_VIRTUAL_HOME=0, NORNS_SC_COMPAT=0), an older conf without them (what an installed package had) is written again with the old one kept as sclang_conf.yaml.old, a conf that
# already matches is not touched. headless boots (linux/tests/norns_probe.sh)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
command -v sclang > /dev/null && command -v xdotool > /dev/null || { echo "SKIP: sclang or xdotool missing"; exit 0; }
printf '#sleep 4\nprint("PROBE conf done")\n' > "$T/probe.lua"
boot() { # home name, env... -> $T/<name>.log
    local name="$1"; shift
    mkdir -p "$T/$name"; [ -e "$T/$name/norns" ] || ln -s "$REPO" "$T/$name/norns"
    env NORNS_HOME="$T/$name" "$@" "$REPO/linux/tests/norns_probe.sh" "$T/probe.lua" "$T/$name.log" > /dev/null 2>&1
}
conf() { echo "$T/$1/.config/SuperCollider/sclang_conf.yaml"; }
has() { grep -qF "\"$REPO/sc/$2\"" "$(conf "$1")"; }

echo "== a new home: both folders"
boot a
has a core && has a engines && has a linux && has a linux-compat && ok "sc/core, sc/engines, sc/linux and sc/linux-compat are listed" || { bad "default conf"; cat "$(conf a)"; }
echo "== the switches"
boot b NORNS_SC_COMPAT=0
has b linux && ! has b linux-compat && ok "NORNS_SC_COMPAT=0: sc/linux only" || bad "compat switch"
boot c NORNS_SC_VIRTUAL_HOME=0
! has c linux && has c linux-compat && ok "NORNS_SC_VIRTUAL_HOME=0: sc/linux-compat only" || bad "virtual home switch"
echo "== an older conf is written again, the old one kept"
mkdir -p "$T/d/.config/SuperCollider"
{ echo "includePaths:"; echo "    - \"$REPO/sc/core\""; echo "    - \"$REPO/sc/engines\""; echo "    - \"$T/d/dust\""; echo "excludePaths:"; echo "    []"; } > "$(conf d)"
cp "$(conf d)" "$T/d.before"
boot d
has d linux && has d linux-compat && ok "rewritten with both folders" || bad "old conf not rewritten"
cmp -s "$T/d.before" "$(conf d).old" && ok "the old conf is kept as sclang_conf.yaml.old" || bad "no .old copy"
grep -q "sclang_conf.yaml did not match" "$T/d.log" && ok "the launcher says so" || bad "no log line"
echo "== a conf that matches is left alone"
cp "$(conf d)" "$T/d.same"
rm -f "$(conf d).old"
boot d
cmp -s "$T/d.same" "$(conf d)" && [ ! -e "$(conf d).old" ] && ok "unchanged, no .old" || bad "a matching conf was rewritten"
[ $FAIL = 0 ] && echo "sc_conf_test: all passed"
exit $FAIL
