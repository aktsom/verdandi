#!/bin/bash
# Verdandi on Linux: install the build and runtime dependencies (Ubuntu 24.04), build
# libmonome 1.4.9 (patched, see linux/patches) and waf 2.1.9 (neither is usable from apt, and the waf in this repo needs
# python's removed `imp`). needs root (or sudo) for apt and /usr/local.
#
# usage: linux/setup-deps.sh
# writes: /usr/local (libmonome, needs sudo), ~/.local/share/waf/waf (waf, owned by you: waf unpacks its library next to
# itself, so a root-owned /opt/waf fails for a normal user); override with WAF_DIR, PREFIX.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"

PREFIX="${PREFIX:-/usr/local}"
. "$HERE/waf-path.sh"
WAF_DIR="${WAF_DIR:-$WAF_DEFAULT_DIR}"
LIBMONOME_VERSION=1.4.9
WAF_VERSION=2.1.9
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl dpkg-dev git ninja-build pkg-config python3 \
    libasound2-dev libavahi-client-dev libavahi-compat-libdnssd-dev libboost-dev libcairo2-dev \
    libevdev-dev libfftw3-dev libglib2.0-dev libgpiod-dev libjack-jackd2-dev liblo-dev \
    liblua5.3-dev libncurses-dev libnng-dev libreadline-dev libsamplerate0-dev libsdl2-dev \
    libsndfile1-dev libudev-dev golang-go \
    jackd2 lua5.3 supercollider-server supercollider-language sc3-plugins-server \
    sc3-plugins-language xvfb xauth x11-apps xdotool imagemagick dbus python3-gi gir1.2-glib-2.0 zenity

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# libmonome with linux/patches/libmonome-pty-serial.patch (the virtual grid and arc are ptys).
# its bundled ./waf starts with "#!/usr/bin/env python" and a stock Ubuntu has no `python`, only python3:
# so it is run as `python3 ./waf` (waf 2.0.26 there works with python 3.12; no python2-compat package needed)
# the stamp says that this build has the patch
STAMP="$PREFIX/share/verdandi/libmonome-pty-serial"
if [ ! -f "$STAMP" ] || ! ldconfig -p | grep -q libmonome.so; then
    echo "== libmonome $LIBMONOME_VERSION + pty serial patch"
    git clone -q --depth 1 --branch "v$LIBMONOME_VERSION" https://github.com/monome/libmonome.git "$T/libmonome"
    (cd "$T/libmonome" && git apply "$HERE/patches/libmonome-pty-serial.patch" &&
        python3 ./waf configure --prefix="$PREFIX" --libdir="$PREFIX/lib" && python3 ./waf && $SUDO python3 ./waf install)
    $SUDO mkdir -p "$(dirname "$STAMP")" && $SUDO touch "$STAMP"
    $SUDO ldconfig
fi

if [ ! -x "$WAF_DIR/waf" ] || ! [ -w "$WAF_DIR" ]; then
    echo "== waf $WAF_VERSION (built from the gitlab tag)"
    curl -sSfL "https://gitlab.com/ita1024/waf/-/archive/waf-$WAF_VERSION/waf-waf-$WAF_VERSION.tar.gz" | tar -xz -C "$T"
    (cd "$T/waf-waf-$WAF_VERSION" && python3 waf-light build)
    # owned by the user who builds, not root. under "sudo setup-deps.sh" that is SUDO_USER
    mkdir -p "$WAF_DIR"
    cp "$T/waf-waf-$WAF_VERSION/waf" "$WAF_DIR/waf"
    if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$WAF_DIR"
    fi
fi
# maiden (web editor and script catalog): built as the normal user, into <norns home>/maiden. NORNS_NO_MAIDEN=1 skips it.
# a failure (no network, ...) is a warning: norns itself does not need it. run linux/maiden-build.sh to try again
if [ "${NORNS_NO_MAIDEN:-0}" != 1 ]; then
    echo "== maiden"
    if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
        MB="sudo -u $SUDO_USER env NORNS_HOME=${NORNS_HOME:-} PATH=$PATH $HERE/maiden-build.sh"
        [ -n "${NORNS_HOME:-}" ] || MB="sudo -u $SUDO_USER env PATH=$PATH $HERE/maiden-build.sh"
    else
        MB="$HERE/maiden-build.sh"
    fi
    $MB || echo "linux/setup-deps.sh: WARNING: maiden was not built (see above); norns works without it. retry: linux/maiden-build.sh"
fi
echo "linux/setup-deps.sh: done"
