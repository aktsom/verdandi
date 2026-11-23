#!/bin/bash
# linux/tests/tools_hint_test.sh (docs/port/phase-m35.md): what the build says when a tool is missing. for every optional part (mi-UGens, PortedPlugins, maiden) and for the main build the message names
# the missing tools and the exact install command ("sudo apt install ninja-build"), says that Verdandi starts without the part, and the optional parts do not stop the build (exit 0).
# linux/setup-deps.sh stays the one place that installs everything: every package the messages can name is in its apt list. no network is used.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }

# a PATH with everything of /usr/bin except the named tools
without() { # tool...
    rm -rf "$T/bin"; mkdir -p "$T/bin"
    local f n skip
    for f in /usr/bin/* /bin/*; do
        n="$(basename "$f")"; skip=0
        for x in "$@"; do [ "$n" = "$x" ] && skip=1; done
        [ $skip = 0 ] && [ ! -e "$T/bin/$n" ] && ln -s "$f" "$T/bin/$n"
    done
    # c++ and strip are alternatives that point into /usr/bin: the names above are what the scripts look for
}
mkdir -p "$T/repo"

# 1. mi-UGens: cmake and ninja missing
without cmake ninja
OUT="$(PATH="$T/bin" "$REPO/linux/mi-ugens-build.sh" checkout "$T/repo" 2>&1)"; rc=$?
[ $rc = 0 ] && ok "mi-UGens, cmake and ninja missing: the build step does not fail (exit 0)" || bad "mi exit" "rc=$rc $OUT"
printf '%s\n' "$OUT" | grep -q "sudo apt install cmake ninja-build" && ok "...and prints the exact command: sudo apt install cmake ninja-build" || bad "mi command" "$OUT"
printf '%s\n' "$OUT" | grep -q "linux/setup-deps.sh" && printf '%s\n' "$OUT" | grep -qi "starts without" && ok "...names linux/setup-deps.sh and says that Verdandi starts without the part" || bad "mi text" "$OUT"
[ ! -d "$T/repo/build/linux/mi-ugens/mi-ugens-pack" ] && ok "...and builds nothing" || bad "mi built" "$(ls "$T/repo/build/linux/mi-ugens")"

# 2. PortedPlugins: only the C++ compiler missing
without c++ g++
OUT="$(PATH="$T/bin" "$REPO/linux/portedplugins-build.sh" checkout "$T/repo" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s\n' "$OUT" | grep -q "sudo apt install build-essential" && ok "PortedPlugins, no C++ compiler: exit 0 and 'sudo apt install build-essential'" || bad "ported" "rc=$rc $OUT"

# 3. only ninja missing: the command names only ninja-build
without ninja
OUT="$(PATH="$T/bin" "$REPO/linux/portedplugins-build.sh" checkout "$T/repo" 2>&1)"
printf '%s\n' "$OUT" | grep -q "sudo apt install ninja-build$" && ok "only ninja missing: 'sudo apt install ninja-build' and nothing more" || bad "ninja only" "$OUT"

# 4. maiden: go missing (the build step of linux/build.sh turns the exit 1 into its own warning)
without go
OUT="$(PATH="$T/bin" NORNS_HOME="$T/nh" "$REPO/linux/maiden-build.sh" 2>&1)"
printf '%s\n' "$OUT" | grep -q "sudo apt install golang-go" && ok "maiden, go missing: 'sudo apt install golang-go'" || bad "maiden" "$OUT"

# 5. the main build: git and pkg-config missing (nothing can be built: it stops, and says why)
without git pkg-config
OUT="$(PATH="$T/bin" "$REPO/linux/build.sh" 2>&1)"; rc=$?
[ $rc != 0 ] && printf '%s\n' "$OUT" | grep -q "sudo apt install git pkg-config" && ok "main build, git and pkg-config missing: stops with 'sudo apt install git pkg-config'" || bad "main" "rc=$rc $OUT"

# 6. setup-deps.sh installs every package the messages name
APT="$(sed -n '/apt-get install/,/^$/p' "$REPO/linux/setup-deps.sh")"
. "$REPO/linux/tools-hint.sh"
miss=""
for t in git cmake ninja c++ cc strip python3 pkg-config go curl xz tar sha256sum; do
    for p in $(tool_package "$t"); do
        printf '%s\n' "$APT" | grep -qw -- "$p" || miss="$miss $p"
    done
done
[ -z "$miss" ] && ok "every package the messages name is in the apt list of linux/setup-deps.sh" || bad "setup-deps" "not installed by setup-deps.sh:$miss"
exit $FAIL
