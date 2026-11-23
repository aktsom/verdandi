#!/bin/bash
# Verdandi on Linux: submodules, waf configure (desktop build), build.
# usage: linux/build.sh   (after linux/setup-deps.sh)

set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/waf-path.sh"
. "$(dirname "$0")/tools-hint.sh"
# the tools of the main build: without them nothing can be built, so this one stops (the optional parts below only warn)
if ! missing_tools_warning "Verdandi itself" git python3 pkg-config c++ cc; then
    exit 1
fi
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
g++ -O2 -Wall -std=c++14 -I "$REPO/matron/src" "$REPO/linux/mi_heal.cc" -o "$REPO/build/linux/mi_heal"
# maiden: built once by linux/setup-deps.sh; this only builds it if it is missing or its patches changed
# (needs the network). NORNS_NO_MAIDEN=1 skips it. a failure is a warning: norns does not need maiden
if [ "${NORNS_NO_MAIDEN:-0}" != 1 ]; then
    "$REPO/linux/maiden-build.sh" || echo "linux/build.sh: WARNING: maiden was not built (see above); norns works without it"
fi
# the libraries the script twins asks for (PortedPlugins: AnalogChew, AnalogLoss, AnalogDegrade and the rest of the collection), built for this checkout against the headers of the installed
# SuperCollider: seconds, once (again only when linux/portedplugins.pin or SuperCollider changes), needs the network. norns.sh copies the pack into the SuperCollider extension folder
# before sclang starts, so that twins' installer finds them (docs/port/phase-m29.md). a failure is a warning: norns works without it. NORNS_NO_PORTED=1 skips this step
if [ "${NORNS_NO_PORTED:-0}" != 1 ]; then
    "$REPO/linux/portedplugins-build.sh" checkout "$REPO" || echo "linux/build.sh: WARNING: the PortedPlugins pack was not built (see above); the script twins will say that libraries are missing"
fi
# the x86_64 mi-UGens pack (MiPlaits, MiRings, MiBeads, ...: the mods emplaitress and fx_resonator, Terrarium and others need it), built the same way for this checkout against the headers of the
# installed SuperCollider with the recipe of linux/package.sh (linux/mi-ugens-build.sh, pin linux/mi-ugens.pin): about 20 seconds and 4 MB, once (again only when the pin or SuperCollider changes),
# needs the network once. norns.sh copies the pack into the SuperCollider extension folder before sclang starts. a failure is a warning: norns starts without it. NORNS_NO_MI=1 skips this step
if [ "${NORNS_NO_MI:-0}" != 1 ]; then
    "$REPO/linux/mi-ugens-build.sh" checkout "$REPO" || echo "linux/build.sh: WARNING: the mi-UGens pack was not built (see above); the scripts and mods that use MiPlaits, MiRings, ... will not find them"
fi
echo "linux/build.sh: $REPO/build/norns/norns"
