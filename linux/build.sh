#!/bin/bash
# Verdandi on Linux: submodules, waf configure (desktop build), build.
# usage: linux/build.sh   (after linux/setup-deps.sh)

set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/waf-path.sh"
WAF="$(find_waf)"
[ -n "$WAF" ] || { echo "linux/build.sh: waf not found, run linux/setup-deps.sh"; exit 1; }
[ -w "$(dirname "$WAF")" ] || {
    echo "linux/build.sh: $WAF is in a folder you cannot write to, and waf unpacks its library next to itself."
    echo "                run linux/setup-deps.sh (installs waf in ~/.local/share/waf), or copy it somewhere of yours and set WAF=..."
    exit 1
}
cd "$REPO"
git submodule update --init --recursive --depth 1
"$WAF" configure --desktop
"$WAF" build -j"$(nproc)"
# SYSTEM > AUDIO: the card list for norns' own jackd
mkdir -p "$REPO/build/linux"
cc -O2 -Wall "$REPO/linux/audio_devices.c" -o "$REPO/build/linux/audio_devices" $(pkg-config --cflags --libs alsa)
# the check for SuperCollider plug-ins of the wrong architecture (norns.sh runs it before sclang starts)
g++ -O2 -Wall -std=c++14 -I "$REPO/matron/src" "$REPO/linux/plugin_arch_check.cc" -o "$REPO/build/linux/plugin_arch_check"
# maiden: built once by linux/setup-deps.sh; this only builds it if it is missing or its patches changed
# (needs the network). NORNS_NO_MAIDEN=1 skips it. a failure is a warning: norns does not need maiden
if [ "${NORNS_NO_MAIDEN:-0}" != 1 ]; then
    "$REPO/linux/maiden-build.sh" || echo "linux/build.sh: WARNING: maiden was not built (see above); norns works without it"
fi
echo "linux/build.sh: $REPO/build/norns/norns"
