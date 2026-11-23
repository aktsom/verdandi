#!/bin/bash
# linux/debian/{preinst,prerm,postinst,postrm} (docs/port/phase-m36.md), run for real with a fake /proc:
#   - a running program of this installation (a process whose exe is under /opt/verdandi) stops an install, an upgrade and a removal with a plain message, exit 1
#   - with nothing running they pass, and the udev scripts pass without udevadm
#   - none of them writes, moves or deletes anything: a fake home and the whole temporary tree are the same before and after, also on purge
#   - the built package (when there is one) has all four scripts, and no script mentions a home folder
# prints "name: ok" / "name: FAIL ...", exit 1 on a failure
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
D="$REPO/linux/debian"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
for s in preinst prerm postinst postrm; do [ -x "$D/$s" ] || { bad "script $s" "$D/$s is missing or not executable"; exit 1; }; done

mkdir -p "$T/proc-idle/1" "$T/proc-run/1" "$T/proc-run/2" "$T/proc-other/1" "$T/home/Verdandi/dust/code/mine"
ln -s /usr/bin/bash "$T/proc-idle/1/exe"
ln -s /usr/bin/bash "$T/proc-run/1/exe"; ln -s /opt/verdandi/build/norns/norns "$T/proc-run/2/exe"
ln -s /opt/verdandi-other/thing "$T/proc-other/1/exe"
echo "a script of the owner" > "$T/home/Verdandi/dust/code/mine/mine.lua"
echo "midimap" > "$T/home/Verdandi/midimap.conf"
ln -s /opt/verdandi "$T/home/Verdandi/norns"
snap() { (cd "$T/home" && find . -print0 | sort -z | xargs -0 stat -c '%n %F %s %Y %N' 2> /dev/null; cat Verdandi/midimap.conf Verdandi/dust/code/mine/mine.lua) | sha256sum; }
before="$(snap)"

run() { # script args... with VERDANDI_PROC_DIR
    local dir="$1" s="$2"; shift 2
    HOME="$T/home" VERDANDI_PROC_DIR="$dir" "$D/$s" "$@" > "$T/out.txt" 2>&1
}
for a in "install" "upgrade 0.1~git20261122.55.985caf98"; do
    run "$T/proc-run" preinst $a; rc=$?
    [ $rc = 1 ] && grep -q "Verdandi is running. Close Verdandi" "$T/out.txt" && ok "preinst $a: refused while the program runs, with a plain message" || bad "preinst $a" "rc=$rc $(cat "$T/out.txt")"
    run "$T/proc-idle" preinst $a; rc=$?
    [ $rc = 0 ] && ok "preinst $a: passes when nothing of the program runs" || bad "preinst idle $a" "rc=$rc"
done
run "$T/proc-other" preinst upgrade 1; [ $? = 0 ] && ok "a process of another program (a folder that only starts with /opt/verdandi) does not stop it" || bad "other" "$(cat "$T/out.txt")"
for a in remove upgrade; do
    run "$T/proc-run" prerm $a; rc=$?
    [ $rc = 1 ] && grep -q "Verdandi is running" "$T/out.txt" && ok "prerm $a: refused while the program runs" || bad "prerm $a" "rc=$rc"
done
run "$T/proc-idle" prerm remove; [ $? = 0 ] && ok "prerm remove: passes when nothing runs" || bad "prerm idle" ""
# a failed-upgrade or deconfigure call is never refused (dpkg must be able to clean up)
for c in "preinst abort-upgrade 1" "prerm failed-upgrade 1" "prerm deconfigure" "preinst abort-install"; do
    run "$T/proc-run" $c; [ $? = 0 ] || bad "$c" "refused"
done
ok "the clean-up calls of dpkg (abort, failed-upgrade, deconfigure) are never refused"
for c in "postinst configure 0.1~git20261122.55.985caf98" "postinst abort-upgrade" "postrm remove" "postrm purge" "postrm upgrade 1" "postrm abort-install"; do
    run "$T/proc-idle" $c || bad "$c" "failed: $(cat "$T/out.txt")"
done
ok "postinst and postrm pass (configure, remove, purge, upgrade) with or without udevadm"
after="$(snap)"
[ "$before" = "$after" ] && ok "the fake home (scripts, midimap.conf, the norns link) is exactly the same after every call, purge included" || bad "home changed" ""
# no script has a command that writes, moves or deletes anything but the udev reload; none names a home folder
if grep -nE '\brm\b|\bmv\b|\bcp\b|\bln\b|\bmkdir\b|\btouch\b|\bchown\b|\bchmod\b|>>|[^2&>]> *[^/&]|\$HOME|~/|/home/' "$D"/preinst "$D"/prerm "$D"/postinst "$D"/postrm | grep -v '^[^:]*:[0-9]*:#' | grep -v '/dev/null'; then
    bad "writes or names a home" "(lines above)"
else
    ok "no script has a command that writes, moves or deletes a file, and none names a home folder"
fi
# the built package carries them
deb="$(ls -t "$REPO"/build/package/verdandi_*.deb 2> /dev/null | head -n 1)"
if [ -n "$deb" ]; then
    n="$(dpkg-deb -I "$deb" | grep -cE '^ +[0-9]+ bytes, +[0-9]+ lines +\*? +(preinst|prerm|postinst|postrm) ')"
    [ "$n" = 4 ] && ok "the built package ($(basename "$deb")) has preinst, prerm, postinst and postrm" || bad "package scripts" "found $n of 4 in $deb"
else
    echo "(no built .deb in build/package: the package itself is checked by the upgrade test)"
fi
exit $FAIL
