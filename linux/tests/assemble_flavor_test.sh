#!/usr/bin/env bash
# linux/tests/assemble_flavor_test.sh: windows/ci/assemble-m1.sh with fake inputs, for both flavours: the default zip (WASAPI only) has no ASIO file, the ASIO zip has the PortAudio DLL of the ASIO build, the licence
# text of the SDK, the notice, the source offer and the sources, its own names, and a FLAVOR.txt for update-and-run. no Windows needed.
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
mkdir -p "$T/bin" "$T/sc/SuperCollider" "$T/asio/source"
touch "$T/bin/Verdandi.exe" "$T/bin/norns.exe"; echo "msys2-pa" > "$T/bin/libportaudio-2.dll"
echo x > "$T/sc/SuperCollider/sclang.exe"; echo x > "$T/sc/SuperCollider/scsynth.exe"; echo c > "$T/sc/SuperCollider/COPYING"
(cd "$T/sc" && zip -qr ../sc.zip SuperCollider)
echo "asio-pa" > "$T/asio/libportaudio-2.dll"; echo "licence text of the SDK" > "$T/asio/source/ASIO-SDK-LICENSE.txt"
echo a > "$T/asio/source/portaudio-source.zip"; echo b > "$T/asio/source/asio-sdk-source.zip"; echo rec > "$T/asio/PA-ASIO-BUILD.txt"
for fl in default asio; do
    f=""; [ "$fl" = asio ] && f=asio
    M0_OUT="$T/m0-$fl" NORNS_BIN="$T/bin" SC_ZIP="$T/sc.zip" OUT="$T/out-$fl" FLAVOR="$f" ASIO_DIR="$T/asio" VERDANDI_VERSION=9.9.9 VERDANDI_HASH=abc1234 VERDANDI_REPO=owner/repo bash windows/ci/assemble-m1.sh > "$T/$fl.log" 2>&1
done
D="$T/out-default/Verdandi-9.9.9-abc1234"; A="$T/out-asio/Verdandi-asio-9.9.9-abc1234"
ck "default: the zip and the folder have the plain names" "[ -f '$T/out-default/Verdandi-windows-9.9.9-abc1234.zip' ] && [ -d '$D' ]"
ck "default: the PortAudio DLL is the MSYS2 one (WASAPI only), no ASIO file, no FLAVOR.txt" "grep -q msys2-pa '$D/libportaudio-2.dll' && [ ! -e '$D/ASIO-NOTICE.txt' ] && [ ! -e '$D/FLAVOR.txt' ] && [ ! -e '$D/source' ] && [ ! -e '$D/licenses/ASIO-SDK-LICENSE.txt' ]"
ck "default: the source offer is there and names the commit and the repository" "grep -q 'github.com/owner/repo' '$D/SOURCE-OFFER.txt' && grep -q 'build 9.9.9 abc1234' '$D/SOURCE-OFFER.txt'"
ck "asio: its own zip and folder names" "[ -f '$T/out-asio/Verdandi-windows-asio-9.9.9-abc1234.zip' ] && [ -d '$A' ]"
ck "asio: the PortAudio DLL of the ASIO build replaced the MSYS2 one" "grep -q asio-pa '$A/libportaudio-2.dll'"
ck "asio: licence text of the SDK, notice, source offer, sources and build record travel with it" "grep -q 'licence text of the SDK' '$A/licenses/ASIO-SDK-LICENSE.txt' && [ -f '$A/ASIO-NOTICE.txt' ] && grep -q 'source.portaudio-source.zip' '$A/SOURCE-OFFER.txt' && [ -f '$A/source/portaudio-source.zip' ] && [ -f '$A/source/asio-sdk-source.zip' ] && [ -f '$A/source/PA-ASIO-BUILD.txt' ]"
ck "asio: FLAVOR.txt (for update-and-run) and the flavor line in BUILD.txt, whose first line stays 'version hash'" "grep -q asio '$A/FLAVOR.txt' && grep -q '^flavor: asio' '$A/BUILD.txt' && [ \"\$(head -n 1 '$A/BUILD.txt')\" = '9.9.9 abc1234' ]"
ck "the notice says GPLv3 and names the trademark" "grep -q 'GNU General Public License version 3' '$A/ASIO-NOTICE.txt' && grep -q 'trademark' '$A/ASIO-NOTICE.txt'"
ck "asio without the build output stops with a message" "! M0_OUT='$T/m0-x' NORNS_BIN='$T/bin' SC_ZIP='$T/sc.zip' OUT='$T/out-x' FLAVOR=asio ASIO_DIR='$T/nothing' bash windows/ci/assemble-m1.sh > '$T/x.log' 2>&1 || grep -q FAIL '$T/m0-x/status/assemble.status'"
exit $fail
