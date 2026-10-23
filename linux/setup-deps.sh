#!/bin/bash
# Verdandi on Linux: install the build and runtime dependencies (Ubuntu 24.04), build
# libmonome 1.4.9 (patched, see linux/patches) and waf 2.1.9 (neither is usable from apt, and the waf in this repo needs
# python's removed `imp`). needs root (or sudo) for apt and /usr/local.
#
# usage: linux/setup-deps.sh
# writes: /usr/local (libmonome), /opt/waf/waf; override with WAF_DIR, PREFIX.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"

PREFIX="${PREFIX:-/usr/local}"
WAF_DIR="${WAF_DIR:-/opt/waf}"
LIBMONOME_VERSION=1.4.9
WAF_VERSION=2.1.9
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git pkg-config python3 \
    libasound2-dev libavahi-client-dev libavahi-compat-libdnssd-dev libboost-dev libcairo2-dev \
    libevdev-dev libfftw3-dev libglib2.0-dev libgpiod-dev libjack-jackd2-dev liblo-dev \
    liblua5.3-dev libncurses-dev libnng-dev libreadline-dev libsamplerate0-dev libsdl2-dev \
    libsndfile1-dev libudev-dev \
    jackd2 lua5.3 supercollider-server supercollider-language sc3-plugins-server \
    sc3-plugins-language xvfb xauth

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# libmonome with linux/patches/libmonome-pty-serial.patch (the virtual grid and arc are ptys).
# the stamp says that this build has the patch
STAMP="$PREFIX/share/verdandi/libmonome-pty-serial"
if [ ! -f "$STAMP" ] || ! ldconfig -p | grep -q libmonome.so; then
    echo "== libmonome $LIBMONOME_VERSION + pty serial patch"
    git clone -q --depth 1 --branch "v$LIBMONOME_VERSION" https://github.com/monome/libmonome.git "$T/libmonome"
    (cd "$T/libmonome" && git apply "$HERE/patches/libmonome-pty-serial.patch" &&
        ./waf configure --prefix="$PREFIX" --libdir="$PREFIX/lib" && ./waf && $SUDO ./waf install)
    $SUDO mkdir -p "$(dirname "$STAMP")" && $SUDO touch "$STAMP"
    $SUDO ldconfig
fi

if [ ! -x "$WAF_DIR/waf" ]; then
    echo "== waf $WAF_VERSION (built from the gitlab tag)"
    curl -sSfL "https://gitlab.com/ita1024/waf/-/archive/waf-$WAF_VERSION/waf-waf-$WAF_VERSION.tar.gz" | tar -xz -C "$T"
    (cd "$T/waf-waf-$WAF_VERSION" && python3 waf-light build)
    $SUDO mkdir -p "$WAF_DIR"
    $SUDO cp "$T/waf-waf-$WAF_VERSION/waf" "$WAF_DIR/waf"
fi
echo "linux/setup-deps.sh: done"
