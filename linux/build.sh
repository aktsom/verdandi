#!/bin/bash
# Verdandi on Linux: submodules, waf configure (desktop build), build.
# usage: linux/build.sh   (after linux/setup-deps.sh)

set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WAF="${WAF:-/opt/waf/waf}"
[ -x "$WAF" ] || WAF="$(command -v waf || true)"
[ -n "$WAF" ] || { echo "linux/build.sh: waf not found, run linux/setup-deps.sh"; exit 1; }
cd "$REPO"
git submodule update --init --recursive --depth 1
"$WAF" configure --desktop
"$WAF" build -j"$(nproc)"
echo "linux/build.sh: $REPO/build/norns/norns"
