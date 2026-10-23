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
echo "linux/build.sh: $REPO/build/norns/norns"
