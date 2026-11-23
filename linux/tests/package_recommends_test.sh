#!/bin/bash
# the .deb DEPENDS on curl and unzip (M36; before it only recommended them, and GDebi and the Software Manager do not install Recommends). docs/port/KNOWN-ISSUES.md item 22: mx.samples downloads its sample packs with `curl -L -o` and unpacks them with `unzip`. checked in the control file text linux/package.sh writes, and in the newest built .deb when it has curl in Depends
cd "$(dirname "$0")/../.." || exit 1
fails=0
check() { if ! eval "$2"; then fails=$((fails + 1)); echo "FAIL $1"; fi; }
check "package.sh makes curl and unzip hard dependencies (M36: GDebi and the Software Manager install Depends, not Recommends)" 'grep -E "^    DEPENDS=" linux/package.sh | grep -q "curl, unzip"'
check "there is no Recommends line left that could hide them" '! grep -q "^Recommends:" linux/package.sh'
deb="$(ls -t build/package/verdandi_*.deb 2> /dev/null | head -n 1)"
if [ -n "$deb" ] && command -v dpkg-deb > /dev/null; then
    rec="$(dpkg-deb -f "$deb" Depends 2> /dev/null)"
    if echo "$rec" | grep -q curl; then check "the built .deb ($(basename "$deb")) depends on curl and unzip" 'echo "$rec" | grep -q curl && echo "$rec" | grep -q unzip'; else echo "  (the newest built .deb, $(basename "$deb"), is from before this change and has no Recommends: the next build has it)"; fi
fi
if [ "$fails" -gt 0 ]; then echo "package_recommends_test: $fails failed"; exit 1; fi
echo "package_recommends_test: all passed"
