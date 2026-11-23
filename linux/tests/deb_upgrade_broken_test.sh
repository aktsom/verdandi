#!/bin/bash
# linux/tests/deb_upgrade_broken_test.sh [OLD.deb NEW.deb] (docs/port/phase-m36.md): the check that the upgrade test CAN fail. the new .deb is repacked four times, each time deliberately broken, and linux/tests/deb_upgrade_test.sh must
# fail each one with the named line; the old package as "new" must fail too (not newer, no BUILD.txt, no version line). opt-in (about 7 minutes per variant, one after the other: several roots at once starve the network): needs the same as deb_upgrade_test.sh.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/build/package"
OLD="${1:-}"; NEW="${2:-}"
[ -n "$NEW" ] || NEW="$(ls -t "$OUT"/verdandi_*.deb 2> /dev/null | head -n 1)"
[ -n "$OLD" ] || OLD="$(ls -t "$OUT"/verdandi_*.deb 2> /dev/null | sed -n 2p)"
[ -f "$NEW" ] && [ -f "$OLD" ] || { echo "SKIP deb_upgrade_broken_test: needs an older and a newer .deb"; exit 77; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mk() { # name edit-command: a copy of NEW, unpacked, edited, packed again
    rm -rf "$T/$1"; mkdir -p "$T/$1"
    dpkg-deb -R "$NEW" "$T/$1/x"
    (cd "$T/$1/x" && eval "$2")
    dpkg-deb --build --root-owner-group "$T/$1/x" "$T/$1.deb" > /dev/null
}
mk deletes-data   "sed -i '2i rm -f /home/tester/Verdandi/midimap.conf' DEBIAN/postinst"
mk second-copy    'mkdir -p opt/verdandi/supercollider/share/SuperCollider/Extensions/mi-UGens && cp -a opt/verdandi/mi-ugens/mi-UGens/Classes opt/verdandi/supercollider/share/SuperCollider/Extensions/mi-UGens/'
mk no-guard       'rm -f DEBIAN/preinst DEBIAN/prerm'
mk no-build-line  'rm -f opt/verdandi/BUILD.txt'
fails=0
run() { # name deb expected-line
    "$REPO/linux/tests/deb_upgrade_test.sh" "$OLD" "$2" > "$T/$1.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] && grep -q "$3" "$T/$1.out"; then echo "ok   a package that $1 fails the upgrade test: $(grep -m1 "$3" "$T/$1.out" | cut -c1-120)"; else echo "FAIL the upgrade test did not fail for '$1' (rc=$rc, wanted '$3')"; grep '^FAIL' "$T/$1.out" | head -3; fails=1; fi
}
run deletes-data  "$T/deletes-data.deb"  'FAIL  the upgrade changed something in the home'
run second-copy   "$T/second-copy.deb"   'FAIL  .* copies of MiPlaits.sc'
run no-guard      "$T/no-guard.deb"      'FAIL  install over a running Verdandi'
run no-build-line "$T/no-build-line.deb" 'FAIL  no /opt/verdandi/BUILD.txt'
# the old package in place of the new one (it is not newer, it has no BUILD.txt and no build line)
"$REPO/linux/tests/deb_upgrade_test.sh" "$OLD" "$OLD" > "$T/same.out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep -q 'FAIL  dpkg: .* is NOT newer' "$T/same.out" && grep -q 'FAIL  no /opt/verdandi/BUILD.txt' "$T/same.out"; then echo "ok   the old package as the new one fails (not newer, no BUILD.txt)"; else echo "FAIL the old package as the new one did not fail as expected (rc=$rc)"; fails=1; fi
exit $fails
