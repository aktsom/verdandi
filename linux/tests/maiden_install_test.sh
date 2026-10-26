#!/bin/bash
# linux/tests/maiden_install_test.sh [MAIDEN_DIR]: scripts installed through maiden's API (a zip, as the catalog's zip sources are) land in dust/code,
# norns loads and runs one, and a script that ships a plug-in for another architecture installs without harm and is reported by the plug-in check
# (report only). the git route of maiden (go-git over the network) is not in the automatic tests: docs/port/phase-4-maiden.md.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MD="${1:-$(dirname "$REPO")/maiden}"
if [ ! -x "$MD/maiden" ]; then
    echo "SKIP: $MD/maiden is not built (linux/maiden-build.sh)"
    exit 0
fi
[ -x "$REPO/build/linux/plugin_arch_check" ] || { echo "maiden_install_test: build/linux/plugin_arch_check is not built (linux/build.sh)"; exit 1; }
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi; }
has() { case "$2" in *"$3"*) echo "  ok    $1" ;; *) echo "  FAIL  $1: '$3' not in '$2'"; FAILS=$((FAILS + 1)) ;; esac; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export ZIPS="$T/zips" REPO
mkdir -p "$ZIPS" "$T/src/hello-main" "$T/src/armplug-main/ignore"
cat > "$T/src/hello-main/hello.lua" <<'L'
-- installed through maiden
print("PROBE hello script init")
function init() print("PROBE hello init() ran") end
L
echo 'print("PROBE armplug")' > "$T/src/armplug-main/armplug.lua"
# a plug-in file that has the header of 32-bit ARM, as the Raspberry Pi bundles of the installer library do
printf "\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x28\x00\x00\x00" > "$T/src/armplug-main/ignore/Fake_scsynth.so"
head -c 64 /dev/zero >> "$T/src/armplug-main/ignore/Fake_scsynth.so"
(cd "$T/src" && python3 -I -c '
import zipfile, os
for name in ("hello", "armplug"):
    z = zipfile.ZipFile("../zips/%s.zip" % name, "w")
    for d, _, fs in os.walk(name + "-main"):
        for f in fs:
            z.write(os.path.join(d, f))
')

H="$T/home"
mkdir -p "$H"
ln -s "$REPO" "$H/norns"
PORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
export NORNS_MAIDEN="$MD" NORNS_MAIDEN_PORT="$PORT"
NORNS_HOME="$H" "$HERE/norns_probe.sh" "$HERE/probe_maiden_install.lua" "$T/probe.log" > /dev/null 2>&1

echo "== install through maiden, run in norns"
has "install answered 201 with the project name" "$(cat "$H/probe.marks.install1" 2> /dev/null)" '"project_name":"hello"'
check "files are in dust/code/hello" "$(ls "$H/dust/code/hello" 2> /dev/null | tr '\n' ' ')" "hello.lua "
has "norns loaded and ran the script" "$(cat "$T/probe.log")" "PROBE hello init() ran"
has "maiden lists both projects" "$(cat "$H/probe.marks.projects" 2> /dev/null)" '"armplug"'
echo "== a script that ships a plug-in for another architecture"
check "it installed" "$(ls "$H/dust/code/armplug/ignore" 2> /dev/null | tr '\n' ' ')" "Fake_scsynth.so "
has "the plug-in check reports it" "$(cat "$H/probe.marks.arm" 2> /dev/null)" "Fake_scsynth.so"
check "and moved nothing (report only)" "$(ls "$H/dust/code/armplug/ignore" 2> /dev/null | tr '\n' ' ')" "Fake_scsynth.so "
has "norns went on to the end of the probe" "$(cat "$T/probe.log")" "PROBE install done"

[ $FAILS -eq 0 ] && echo "maiden_install_test: all passed" || { echo "maiden_install_test: $FAILS failed"; tail -15 "$T/probe.log"; }
[ $FAILS -eq 0 ]
