#!/bin/bash
# the .deb recommends curl and unzip (docs/port/KNOWN-ISSUES.md item 22: mx.samples downloads its sample packs with `curl -L -o` and unpacks them with `unzip`; the manual says wget, apt and the
# like are not provided). checked in the control file text linux/package.sh writes, and in the newest built .deb when it has the field (built .debs from before this change do not: said, not failed)
cd "$(dirname "$0")/../.." || exit 1
fails=0
check() { if ! eval "$2"; then fails=$((fails + 1)); echo "FAIL $1"; fi; }
check "package.sh names curl and unzip as recommended" 'grep -q "^    RECOMMENDS=\"curl, unzip\"" linux/package.sh'
check "the control file gets a Recommends line" 'grep -q "^Recommends: \$RECOMMENDS" linux/package.sh'
check "they are not hard dependencies" '! grep -E "^    DEPENDS=" linux/package.sh | grep -qE "curl|unzip"'
deb="$(ls -t build/package/verdandi_*.deb 2> /dev/null | head -n 1)"
if [ -n "$deb" ] && command -v dpkg-deb > /dev/null; then
    rec="$(dpkg-deb -f "$deb" Recommends 2> /dev/null)"
    if [ -n "$rec" ]; then check "the built .deb ($(basename "$deb")) recommends curl and unzip" 'echo "$rec" | grep -q curl && echo "$rec" | grep -q unzip'; else echo "  (the newest built .deb, $(basename "$deb"), is from before this change and has no Recommends: the next build has it)"; fi
fi
if [ "$fails" -gt 0 ]; then echo "package_recommends_test: $fails failed"; exit 1; fi
echo "package_recommends_test: all passed"
