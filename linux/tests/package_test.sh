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
until grep -aq 'startup_status.ok' /home/tester/launcher.out 2>/dev/null && grep -aq 'engines: \[' /home/tester/Verdandi/logs/sclang.log 2>/dev/null; do
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
pgrep -u tester -l | grep -v 'run.sh\|pgrep\|grep' > /home/tester/left.out
exit 0
RUN
chmod 755 /home/tester/run.sh
# a script's Raspberry Pi mi-UGens download that is there before the first start: the first start seeds the own pack and moves the download aside before sclang
mkdir -p /home/tester/Verdandi/.local/share/SuperCollider/Extensions/arm-pack
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000\000\000' > /home/tester/Verdandi/.local/share/SuperCollider/Extensions/arm-pack/MiPlaits.so
# the princeton script's Raspberry Pi NamAmp.so in its place (the folder of the script stands for the script): the first start moves it aside and seeds Verdandi's own x86-64 copy
mkdir -p /home/tester/Verdandi/dust/code/princeton /home/tester/Verdandi/.local/share/SuperCollider/Extensions/princeton
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000\000\000' > /home/tester/Verdandi/.local/share/SuperCollider/Extensions/princeton/NamAmp.so
chown -R tester:tester /home/tester/Verdandi
runuser -u tester -- /home/tester/run.sh
H=/home/tester/Verdandi
grep -aq startup_status.ok /home/tester/launcher.out && p "installed launcher boots norns as a normal user (headless)" || { f "norns did not boot"; tail -25 /home/tester/launcher.out | sed 's/^/   /'; tail -10 $H/logs/norns.log $H/logs/jackd.log 2>/dev/null | sed 's/^/   /'; }
grep -a 'engines: \[' $H/logs/sclang.log | head -1 | grep -q PolyPerc && p "bundled SuperCollider lists the engines: $(grep -a 'engines: \[' $H/logs/sclang.log | head -1 | cut -c1-100)" || { f "no engine list"; tail -20 $H/logs/sclang.log | sed 's/^/   /'; }
grep -aq 'PROBE-OK' /home/tester/launcher.out && p "the Lua prompt answers" || f "the Lua prompt does not answer"
[ "$(readlink $H/norns)" = /opt/verdandi ] && p "~/Verdandi/norns leads to /opt/verdandi" || f "norns link: $(readlink $H/norns)"
grep -q '/opt/verdandi/sc/core' /home/tester/.config/SuperCollider/sclang_conf.yaml 2>/dev/null || grep -q '/opt/verdandi/sc/core' $H/.config/SuperCollider/sclang_conf.yaml && p "sclang_conf.yaml names the installed program" || f "sclang_conf.yaml"
grep -aq '200\|302\|301' /home/tester/maiden.http 2>/dev/null && p "maiden answers on 127.0.0.1:5000 ($(cat /home/tester/maiden.http | tr -d '\r'))" || { f "maiden does not answer"; tail -5 $H/logs/maiden.log; }
[ ! -f /home/tester/write.out ] && p "the program tree is read-only for the user" || f "a normal user could write into /opt/verdandi"
[ -s /home/tester/left.out ] && { f "processes left after the stop: $(tr '\n' ' ' < /home/tester/left.out)"; } || p "no process left after the stop"
# mi-UGens: the pack is in the package (x86_64, stamped, intact, licences), the first run copied it into the user's extension folder with the same stamp
MI=/opt/verdandi/mi-ugens/mi-UGens
U=$H/.local/share/SuperCollider/Extensions/mi-UGens
[ -f $MI/MiPlaits.so ] && [ -f $MI/MiBeads.so ] && [ -f $MI/Classes/MiBeads.sc ] && [ -f $MI/.verdandi-stamp ] && (cd $MI && sha256sum --quiet -c .verdandi-files) && p "the mi-UGens pack is in the package, stamped and intact ($(grep '^commit=' $MI/.verdandi-stamp | cut -c8-14))" || f "mi-UGens pack missing or not intact in the package"
arm=0; for so in $MI/*.so; do [ "$(od -An -tx1 -j18 -N1 "$so" | tr -d ' ')" = 3e ] || arm=1; done
[ $arm = 0 ] && p "every mi-UGens binary in the package is x86_64" || f "a mi-UGens binary is not x86_64"
[ -f /opt/verdandi/licenses/mi-ugens/LICENSE-GPL-3.0.md ] && [ -f /opt/verdandi/licenses/mi-ugens/LICENSE-eurorack-MIT.txt ] && [ -f /opt/verdandi/licenses/mi-ugens/LICENSE-libsamplerate-BSD-2.txt ] && grep -q "v7b1/mi-UGens" /opt/verdandi/licenses/SOURCES.txt && p "mi-UGens licences (GPL-3.0-or-later, MIT, BSD-2) and the source location are installed" || f "mi-UGens licences or source note missing"
[ -f $U/.verdandi-stamp ] && cmp -s $U/.verdandi-stamp $MI/.verdandi-stamp && [ -f $U/Classes/MiPlaits.sc ] && p "the first run copied the pack into the user's SuperCollider extension folder (same stamp)" || f "the pack was not seeded: $(ls $H/.local/share/SuperCollider/Extensions 2>&1)"
NA=/opt/verdandi/namamp/NamAmp
[ -f $NA/NamAmp.so ] && [ -f $NA/.verdandi-namamp ] && [ "$(sha256sum $NA/NamAmp.so | cut -d' ' -f1)" = "$(sed -n 's/^sha256=//p' $NA/.verdandi-namamp)" ] && [ "$(od -An -tx1 -j18 -N2 $NA/NamAmp.so | tr -d ' ')" = 3e00 ] && p "the NamAmp plug-in is in the package: x86-64, stamped, sha256 matches" || f "NamAmp pack missing, not x86-64 or not intact"
for lic in LICENSE-NeuralAmpModelerCore-MIT.txt LICENSE-Eigen-MPL-2.0.txt LICENSE-nlohmann-json-MIT.txt NamAmp.cpp.txt; do [ -f /opt/verdandi/licenses/namamp/$lic ] || { f "NamAmp licence file $lic missing"; }; done
grep -q "NeuralAmpModelerCore" /opt/verdandi/licenses/SOURCES.txt && grep -q "eigen" /opt/verdandi/licenses/SOURCES.txt && grep -q "nlohmann" /opt/verdandi/licenses/SOURCES.txt && p "NamAmp licences (MIT, MPL-2.0, MIT, our wrapper) and the source locations are installed" || f "NamAmp source note missing"
[ -x /opt/verdandi/linux/shims/cmp ] && [ -x /opt/verdandi/linux/shims/cp ] && [ -x /opt/verdandi/linux/namamp-seed.sh ] && [ -x /opt/verdandi/linux/plugin-heal.sh ] && p "the cmp and cp shims, the seed and the heal scripts are installed" || f "shims or scripts missing"
SEED=$H/.local/share/SuperCollider/Extensions/princeton
[ "$(sha256sum $SEED/NamAmp.so 2>/dev/null | cut -d' ' -f1)" = "$(sha256sum $NA/NamAmp.so | cut -d' ' -f1)" ] && grep -aq "NamAmp: seeded" /home/tester/launcher.out && grep -aq "plugin heal: moved 2 " /home/tester/launcher.out && p "the princeton script's Raspberry Pi NamAmp.so was moved aside and the package's x86-64 copy seeded before sclang (one line each)" || f "NamAmp not healed and seeded: $(ls -la $SEED 2>&1 | tail -3)"
[ -x /opt/verdandi/build/linux/mi_heal ] && p "the mi-UGens scanner (mi_heal) is in the package" || f "mi_heal missing in the package"
[ ! -e $H/.local/share/SuperCollider/Extensions/arm-pack ] && grep -aq "plugin heal: moved 2 wrong-architecture" /home/tester/launcher.out && grep -q "wrong-architecture plug-in" $H/disabled/MANIFEST.tsv && p "a Raspberry Pi mi-UGens download next to the own pack was moved aside before sclang (manifest line, one log line)" || { f "the foreign pack was not moved aside: $(ls $H/.local/share/SuperCollider/Extensions 2>&1) / $(grep -a "mi-UGens" /home/tester/launcher.out | head -3)"; }
grep -aq 'wrong ELF class\|not found\|duplicate Class' $H/logs/sclang.log && f "sclang.log has a class or ELF error: $(grep -a 'wrong ELF class\|not found\|duplicate Class' $H/logs/sclang.log | head -2)" || p "sclang compiled the seeded pack without a class or ELF error"
[ -d /opt/verdandi/supercollider ] && ! [ -e /root/Verdandi ] && p "nothing written outside the user's home by the user's run" || f "root home touched"
INNER
chmod 755 "$R/root/inner.sh"

unshare -m sh -c "
 mount -t proc proc '$R/proc' && mount --rbind /dev '$R/dev' && mount -t tmpfs tmpfs '$R/dev/shm' && mount -t tmpfs tmpfs '$R/tmp'
 cp /etc/resolv.conf '$R/etc/resolv.conf' 2>/dev/null
 chroot '$R' /usr/bin/env MIRROR='$MIRROR' http_proxy='${http_proxy:-}' https_proxy='${https_proxy:-}' /bin/bash /root/inner.sh" > "$T/inner.out" 2>&1
cat "$T/inner.out" | grep -E '^(PASS|FAIL|   |SKIP)' 
grep -q '^FAIL' "$T/inner.out" && FAIL=1
grep -q '^PASS  nothing written' "$T/inner.out" || { echo "FAIL  the run in the root did not finish"; tail -15 "$T/inner.out"; FAIL=1; }
exit $FAIL
