#!/bin/bash
# linux/tests/package_test.sh [FILE.deb]: the package in a clean Ubuntu 24.04 root.
#   host side: the metadata and privacy checks of linux/package.sh check
#   in the root (debootstrap --variant=minbase, nothing else installed): apt-get install ./FILE.deb, no library missing,
#   then, as a normal user (not root), /usr/bin/verdandi --terminal headless: the home is created in ~/Verdandi,
#   norns, sclang and maiden come up and the engines are listed. the program tree is root-owned: a write into it fails.
# needs root, debootstrap, unshare, network (archive.ubuntu.com). the root is cached in build/package/cache/noble-minbase.
# prints "PASS name" / "FAIL name" lines, exit 1 if any failed, exit 77 if it cannot run here (with the reason)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/build/package"
DEB="${1:-$(ls -t "$OUT"/verdandi_*.deb 2>/dev/null | head -1)}"
CACHE_ROOT="$OUT/cache/noble-minbase"
MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"

skip() { echo "SKIP package_test: $*"; exit 77; }
[ "$(id -u)" -eq 0 ] || skip "needs root (chroot)"
command -v debootstrap >/dev/null || skip "debootstrap is not installed"
command -v unshare >/dev/null || skip "unshare is not installed"
[ -f "$DEB" ] || skip "no .deb (linux/package.sh all)"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

if "$REPO/linux/package.sh" check "$DEB" > "$T/check.log" 2>&1; then pass "metadata and privacy scan of $(basename "$DEB")"; else fail "metadata and privacy scan"; cat "$T/check.log"; fi
# the scan must really find a word: a folder name of the package as an identity word
if PACKAGE_PRIVACY_EXTRA="resources" "$REPO/linux/package.sh" check "$DEB" > "$T/neg.log" 2>&1; then
    fail "the privacy scan did not fail for a word that is in the package"
else pass "the privacy scan fails when an identity word is in the package"; fi

if [ ! -x "$CACHE_ROOT/bin/bash" ]; then
    echo "== debootstrap noble (once, cached in $CACHE_ROOT)"
    mkdir -p "$(dirname "$CACHE_ROOT")"
    debootstrap --variant=minbase --include=ca-certificates noble "$CACHE_ROOT.tmp" "$MIRROR" > "$T/debootstrap.log" 2>&1 ||
        { tail -5 "$T/debootstrap.log"; skip "debootstrap failed (network?)"; }
    mv "$CACHE_ROOT.tmp" "$CACHE_ROOT"
fi
R="$T/root"
cp -a "$CACHE_ROOT" "$R"
cp "$DEB" "$R/root/verdandi.deb"

cat > "$R/root/inner.sh" <<'INNER'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; }
printf 'deb %s noble main universe\ndeb %s noble-updates main universe\n' "$MIRROR" "$MIRROR" > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/*
apt-get update -q > /root/apt-update.log 2>&1 || { f "apt-get update"; exit 0; }
if apt-get install -y -q /root/verdandi.deb > /root/apt-install.log 2>&1; then p "apt-get install ./verdandi.deb in a clean Ubuntu 24.04 ($(grep -c '^Setting up' /root/apt-install.log) packages set up)"; else f "apt-get install"; tail -15 /root/apt-install.log; exit 0; fi

missing=0
for b in $(find /opt/verdandi -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) ! -path '*/lua/*' ! -path '*/maiden/*'); do
    head -c4 "$b" | grep -q '^.ELF' || continue
    LD_LIBRARY_PATH=/opt/verdandi/lib ldd "$b" 2>/dev/null | grep -q 'not found' && { echo "   missing library for $b"; missing=1; }
done
[ $missing = 0 ] && p "no missing library (ldd) for any binary of the package" || f "a library is missing"
[ -x /usr/bin/verdandi ] && [ -f /usr/share/applications/verdandi.desktop ] && [ -f /usr/share/icons/hicolor/256x256/apps/verdandi.png ] &&
    [ -f /usr/lib/udev/rules.d/70-verdandi-monome.rules ] && p "launcher, desktop entry, icon and udev rule are installed" || f "desktop files missing"
[ -f /usr/share/doc/verdandi/copyright ] && zcat /usr/share/doc/verdandi/changelog.gz | head -1 | grep -q '^verdandi (' && p "copyright and changelog installed" || f "copyright / changelog"

# test-only tools: a display and a JACK server for the headless run
apt-get install -y -q xvfb xauth jackd2 x11-apps > /root/apt-test.log 2>&1 && p "test tools installed" || { f "test tools"; exit 0; }
useradd -m -s /bin/bash tester
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
(Xvfb :99 -screen 0 1280x800x24 > /root/xvfb.log 2>&1 &)
sleep 2
cat > /home/tester/run.sh <<'RUN'
#!/bin/bash
export HOME=/home/tester DISPLAY=:99 NORNS_JACK_DRIVER=dummy SDL_AUDIODRIVER=dummy
rm -f /tmp/vfifo; mkfifo /tmp/vfifo
verdandi --terminal < /tmp/vfifo > /home/tester/launcher.out 2>&1 &
PID=$!
exec 3> /tmp/vfifo
n=0
until grep -aq 'startup_status.ok' /home/tester/launcher.out 2>/dev/null && grep -aq 'engines: \[' /home/tester/Verdandi/sclang.log 2>/dev/null; do
    n=$((n + 1)); [ $n -gt 450 ] && break
    kill -0 $PID 2>/dev/null || break
    sleep 0.2
done
sleep 2
echo 'print("PROBE-OK")' >&3
sleep 2
# maiden answers on 127.0.0.1
exec 4<>/dev/tcp/127.0.0.1/5000 && printf 'GET /maiden HTTP/1.0\r\n\r\n' >&4 && head -1 <&4 > /home/tester/maiden.http
# the program tree is root-owned: a normal user cannot write into it
touch /opt/verdandi/should-not-work 2> /home/tester/write.err && echo written > /home/tester/write.out
kill $PID; wait $PID 2>/dev/null
sleep 3
pgrep -u tester -l | grep -v 'run.sh\|pgrep' > /home/tester/left.out
exit 0
RUN
chmod 755 /home/tester/run.sh
runuser -u tester -- /home/tester/run.sh
H=/home/tester/Verdandi
grep -aq startup_status.ok /home/tester/launcher.out && p "installed launcher boots norns as a normal user (headless)" || { f "norns did not boot"; tail -25 /home/tester/launcher.out | sed 's/^/   /'; tail -10 $H/norns.log $H/jackd.log 2>/dev/null | sed 's/^/   /'; }
grep -a 'engines: \[' $H/sclang.log | head -1 | grep -q PolyPerc && p "bundled SuperCollider lists the engines: $(grep -a 'engines: \[' $H/sclang.log | head -1 | cut -c1-100)" || { f "no engine list"; tail -20 $H/sclang.log | sed 's/^/   /'; }
grep -aq 'PROBE-OK' /home/tester/launcher.out && p "the Lua prompt answers" || f "the Lua prompt does not answer"
[ "$(readlink $H/norns)" = /opt/verdandi ] && p "~/Verdandi/norns leads to /opt/verdandi" || f "norns link: $(readlink $H/norns)"
grep -q '/opt/verdandi/sc/core' /home/tester/.config/SuperCollider/sclang_conf.yaml 2>/dev/null || grep -q '/opt/verdandi/sc/core' $H/.config/SuperCollider/sclang_conf.yaml && p "sclang_conf.yaml names the installed program" || f "sclang_conf.yaml"
grep -aq '200\|302\|301' /home/tester/maiden.http 2>/dev/null && p "maiden answers on 127.0.0.1:5000 ($(cat /home/tester/maiden.http | tr -d '\r'))" || { f "maiden does not answer"; tail -5 $H/maiden.log; }
[ ! -f /home/tester/write.out ] && p "the program tree is read-only for the user" || f "a normal user could write into /opt/verdandi"
[ -s /home/tester/left.out ] && { f "processes left after the stop: $(tr '\n' ' ' < /home/tester/left.out)"; } || p "no process left after the stop"
[ -d /opt/verdandi/supercollider ] && ! [ -e /root/Verdandi ] && p "nothing written outside the user's home by the user's run" || f "root home touched"
INNER
chmod 755 "$R/root/inner.sh"

unshare -m sh -c "
 mount -t proc proc '$R/proc' && mount --rbind /dev '$R/dev' && mount -t tmpfs tmpfs '$R/tmp'
 cp /etc/resolv.conf '$R/etc/resolv.conf' 2>/dev/null
 chroot '$R' /usr/bin/env MIRROR='$MIRROR' http_proxy='${http_proxy:-}' https_proxy='${https_proxy:-}' /bin/bash /root/inner.sh" > "$T/inner.out" 2>&1
cat "$T/inner.out" | grep -E '^(PASS|FAIL|   |SKIP)' 
grep -q '^FAIL' "$T/inner.out" && FAIL=1
grep -q '^PASS  nothing written' "$T/inner.out" || { echo "FAIL  the run in the root did not finish"; tail -15 "$T/inner.out"; FAIL=1; }
exit $FAIL
