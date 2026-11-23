#!/bin/bash
# linux/tests/deb_upgrade_test.sh [OLD.deb NEW.deb] (docs/port/phase-m36.md): the install / upgrade / remove test (linux/tests/deb_upgrade_inner.sh) in a clean Ubuntu 24.04 root made with debootstrap
# (the workflow runs the same inner script in the docker image ubuntu:24.04). NEW defaults to the newest build/package/verdandi_*.deb, OLD to the one before it. needs root, debootstrap, unshare, the network;
# prints "SKIP ..." and exits 77 when it cannot run here (no two .debs: build the older one with PACKAGE_REVISION=1 linux/package.sh deb, or from an older commit).
set -u
# a host folder that does not exist and cannot be made: if the root run leaks the host environment (the runner sets XDG_CONFIG_HOME to its own home), SuperCollider dies on it and the test fails
export XDG_CONFIG_HOME=/nonexistent-host-folder/.config
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/build/package"
OLD="${1:-}"; NEW="${2:-}"
[ -n "$NEW" ] || NEW="$(ls -t "$OUT"/verdandi_*.deb 2> /dev/null | head -n 1)"
[ -n "$OLD" ] || OLD="$(ls -t "$OUT"/verdandi_*.deb 2> /dev/null | sed -n 2p)"
CACHE_ROOT="$OUT/cache/noble-minbase"
MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
skip() { echo "SKIP deb_upgrade_test: $*"; exit 77; }
[ "$(id -u)" -eq 0 ] || skip "needs root (chroot)"
command -v debootstrap > /dev/null || skip "debootstrap is not installed"
[ -f "$NEW" ] && [ -f "$OLD" ] || skip "needs an older and a newer .deb (linux/package.sh all; the older one: PACKAGE_REVISION=1 linux/package.sh deb, or built from an older commit)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if [ ! -x "$CACHE_ROOT/bin/bash" ]; then
    mkdir -p "$(dirname "$CACHE_ROOT")"
    debootstrap --variant=minbase --include=ca-certificates noble "$CACHE_ROOT.tmp" "$MIRROR" > "$T/debootstrap.log" 2>&1 || { tail -5 "$T/debootstrap.log"; skip "debootstrap failed (network?)"; }
    mv "$CACHE_ROOT.tmp" "$CACHE_ROOT"
fi
R="$T/root"
cp -a "$CACHE_ROOT" "$R"
mkdir -p "$R/work/linux/tests" "$R/debs"
cp "$REPO/linux/tests/deb_upgrade_inner.sh" "$REPO/linux/tests/twins_ugens.scd" "$REPO/linux/tests/mi_ugens.scd" "$R/work/linux/tests/"
cp "$OLD" "$R/debs/old.deb"; cp "$NEW" "$R/debs/new.deb"
printf 'deb %s noble main universe\ndeb %s noble-updates main universe\n' "$MIRROR" "$MIRROR" > "$R/etc/apt/sources.list"
rm -f "$R"/etc/apt/sources.list.d/*
# a clean environment inside the root: nothing of the host's (the runner sets XDG_CONFIG_HOME to its own home: SuperCollider then wrote there and died)
unshare -m sh -c "
 mount -t proc proc '$R/proc' && mount --rbind /dev '$R/dev' && mount -t tmpfs tmpfs '$R/dev/shm' && mount -t tmpfs tmpfs '$R/tmp'
 cp /etc/resolv.conf '$R/etc/resolv.conf' 2>/dev/null
 chroot '$R' /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 http_proxy='${http_proxy:-}' https_proxy='${https_proxy:-}' /bin/bash /work/linux/tests/deb_upgrade_inner.sh /debs/old.deb /debs/new.deb /work/linux/tests" > "$T/inner.out" 2>&1
grep -E '^(PASS|FAIL|   |SKIP|==)' "$T/inner.out"
if grep -q '^FAIL' "$T/inner.out"; then exit 1; fi
grep -q '^== done: all passed' "$T/inner.out" || { echo "FAIL  the run in the root did not finish"; tail -15 "$T/inner.out"; exit 1; }
exit 0
