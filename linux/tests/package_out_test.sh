#!/bin/bash
# linux/tests/package_out_test.sh: the build output (docs/port/clean-layout.md section 5), on a fixture folder (PACKAGE_OUT), nothing is built:
# `status` reads only and names every part; `clean cache` removes cache/ only; `clean` removes stage/ cache/ clean-root/ control/ and the logs,
# never a .deb; the newest 2 .deb files are kept (prune_debs, the function build_deb calls)
cd "$(dirname "$0")/../.." || exit 1
fails=0
check() { if ! eval "$2"; then fails=$((fails + 1)); echo "FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "${W:?}"' EXIT
O="$W/out"
mk() {
    rm -rf "${O:?}"; mkdir -p "$O/stage/opt" "$O/cache/x" "$O/clean-root/root" "$O/control"
    head -c 200000 /dev/zero > "$O/stage/opt/f"; head -c 100000 /dev/zero > "$O/cache/x/f"
    for i in 1 2 3; do echo deb > "$O/verdandi_0.1~git$i.1.a_amd64.deb"; touch -d "$((4 - i)) days ago" "$O/verdandi_0.1~git$i.1.a_amd64.deb"; done
    echo log > "$O/package-deb.log"
}
snap() { (cd "$O" && find . -printf '%p %s %T@\n' | sort | md5sum); }

mk
before="$(snap)"
out="$(PACKAGE_OUT="$O" linux/package.sh status 2>&1)"
check "status reads only" '[ "$(snap)" = "$before" ]'
for w in stage/ cache/ clean-root/ control/ package-\*.log "linux/package.sh clean" "clean cache" .deb; do check "status names $w" 'echo "$out" | grep -qF -- "$w"'; done
check "status says what the stage is" 'echo "$out" | grep -q "made again from the cache"'
check "status shows sizes" 'echo "$out" | grep -qE "^  [0-9.]+[KMG]?\s+stage/"'
out="$(PACKAGE_OUT="$W/none" linux/package.sh status 2>&1)"
check "status of a missing folder says so" 'echo "$out" | grep -q "nothing built"'
check "status makes no folder" '[ ! -e "$W/none" ]'

mk
PACKAGE_OUT="$O" linux/package.sh clean cache > /dev/null 2>&1
check "clean cache removes cache/" '[ ! -e "$O/cache" ]'
check "clean cache keeps the rest" '[ -d "$O/stage" ] && [ -d "$O/clean-root" ] && [ -f "$O/package-deb.log" ] && [ "$(ls "$O"/*.deb | wc -l)" = 3 ]'

mk
PACKAGE_OUT="$O" linux/package.sh clean > /dev/null 2>&1
check "clean removes stage cache clean-root control" '[ ! -e "$O/stage" ] && [ ! -e "$O/cache" ] && [ ! -e "$O/clean-root" ] && [ ! -e "$O/control" ]'
check "clean removes the logs" '[ ! -e "$O/package-deb.log" ]'
check "clean never removes a .deb" '[ "$(ls "$O"/*.deb | wc -l)" = 3 ]'
check "a wrong argument is refused" '! PACKAGE_OUT="$O" linux/package.sh clean everything > /dev/null 2>&1'

# the .deb files: the newest 2 stay
mk
eval "$(sed -n '/^prune_debs() {/,/^}/p' linux/package.sh)"
OUT="$O" prune_debs > /dev/null
check "prune keeps the 2 newest" '[ "$(ls "$O"/*.deb | wc -l)" = 2 ] && [ -f "$O/verdandi_0.1~git3.1.a_amd64.deb" ] && [ -f "$O/verdandi_0.1~git2.1.a_amd64.deb" ]'
OUT="$O" PACKAGE_KEEP_DEBS=1 prune_debs > /dev/null
check "PACKAGE_KEEP_DEBS=1 keeps one" '[ "$(ls "$O"/*.deb | wc -l)" = 1 ]'
check "build_deb calls prune_debs and removes the stage" 'grep -q "^    prune_debs" linux/package.sh && grep -q "rm -rf \"\${STAGE:?}\"" linux/package.sh'
check "build_deb no longer removes every .deb first" '! grep -q "rm -f \"\$OUT\"/verdandi_\*.deb" linux/package.sh'

[ "$fails" = 0 ] && echo "package_out_test: all passed" || { echo "package_out_test: $fails failed"; exit 1; }
