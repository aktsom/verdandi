#!/usr/bin/env bash
# linux/tests/assemble_flavor_test.sh (M31): windows/ci/assemble-m1.sh with fake inputs. THE zip is the ASIO build: the PortAudio DLL of the ASIO build, the licence text of the SDK, the notice, the source offer and the
# sources are always in it; the names are the static ones without "asio"; there is no FLAVOR.txt and no second zip. no Windows needed.
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
mkdir -p "$T/bin" "$T/sc/SuperCollider" "$T/asio/source"
touch "$T/bin/Verdandi.exe"; echo "MZ fake norns.exe importing libportaudio.dll" > "$T/bin/norns.exe"; echo "msys2-pa" > "$T/bin/libportaudio-2.dll" # (the ASIO assemble reads the PortAudio name norns.exe imports from the file itself: M19)
echo x > "$T/sc/SuperCollider/sclang.exe"; echo x > "$T/sc/SuperCollider/scsynth.exe"; echo c > "$T/sc/SuperCollider/COPYING"
(cd "$T/sc" && zip -qr ../sc.zip SuperCollider)
echo "asio-pa" > "$T/asio/libportaudio-2.dll"; echo "licence text of the SDK" > "$T/asio/source/ASIO-SDK-LICENSE.txt"
echo a > "$T/asio/source/portaudio-source.zip"; echo b > "$T/asio/source/asio-sdk-source.zip"; echo rec > "$T/asio/PA-ASIO-BUILD.txt"
M0_OUT="$T/m0" NORNS_BIN="$T/bin" SC_ZIP="$T/sc.zip" OUT="$T/out" ASIO_DIR="$T/asio" VERDANDI_VERSION=9.9.9 VERDANDI_HASH=abc1234 VERDANDI_REPO=owner/repo bash windows/ci/assemble-m1.sh > "$T/run.log" 2>&1
A="$T/out/Verdandi" # (M22: static names)
ck "the zip and the folder have STATIC names (no version, no asio): Verdandi-windows-latest.zip with the folder Verdandi" "[ -f '$T/out/Verdandi-windows-latest.zip' ] && [ -d '$A' ] && [ \"\$(cat '$T/out/ZIPNAME')\" = Verdandi-windows-latest.zip ] && [ \"\$(cat '$T/out/VZIPNAME')\" = Verdandi-windows-9.9.9-abc1234.zip ]"
ck "the same file with the version in its name is made too, byte for byte" "cmp -s '$T/out/Verdandi-windows-latest.zip' '$T/out/Verdandi-windows-9.9.9-abc1234.zip'"
ck "no second zip and no asio name anywhere in the output" "[ \"\$(ls '$T/out' | grep -ci asio)\" = 0 ]"
ck "the zip holds exactly one folder, Verdandi, with VERSION.txt that names the version and the build (the static-name check of the CI)" "python3 windows/ci/check-static-names.py '$T/out/Verdandi-windows-latest.zip' Verdandi-windows-latest.zip Verdandi > '$T/sn.log' 2>&1 && grep -q 'version 9.9.9, build abc1234' '$A/VERSION.txt'"
ck "the static-name check fails for a zip with a version in its folder (the check itself is tested)" "! python3 windows/ci/check-static-names.py '$T/out/Verdandi-windows-latest.zip' Verdandi-windows-latest.zip Verdandi-9.9.9-abc1234 > '$T/sn3.log' 2>&1"
ck "the PortAudio DLL of the ASIO build is in the zip under the name norns.exe imports (libportaudio.dll: M19), and PORTAUDIO-DLL.txt says which" "grep -q asio-pa '$A/libportaudio.dll' && grep -q libportaudio.dll '$A/PORTAUDIO-DLL.txt'"
ck "licence text of the SDK, notice, source offer, sources and build record travel with it" "grep -q 'licence text of the SDK' '$A/licenses/ASIO-SDK-LICENSE.txt' && [ -f '$A/ASIO-NOTICE.txt' ] && grep -q 'source.portaudio-source.zip' '$A/SOURCE-OFFER.txt' && [ -f '$A/source/portaudio-source.zip' ] && [ -f '$A/source/asio-sdk-source.zip' ] && [ -f '$A/source/PA-ASIO-BUILD.txt' ]"
ck "the source offer is there and names the commit and the repository" "grep -q 'github.com/owner/repo' '$A/SOURCE-OFFER.txt' && grep -q 'build 9.9.9 abc1234' '$A/SOURCE-OFFER.txt'"
ck "no FLAVOR.txt (the updater keeps the name of the folder it runs from); BUILD.txt says asio is built in and its first line stays 'version hash'" "[ ! -e '$A/FLAVOR.txt' ] && grep -q '^asio: built in' '$A/BUILD.txt' && [ \"\$(head -n 1 '$A/BUILD.txt')\" = '9.9.9 abc1234' ]"
ck "the notice says GPLv3 and names the trademark" "grep -q 'GNU General Public License version 3' '$A/ASIO-NOTICE.txt' && grep -q 'trademark' '$A/ASIO-NOTICE.txt'"
ck "without the ASIO build output it stops with a message (the zip is the ASIO build)" "! M0_OUT='$T/m0-x' NORNS_BIN='$T/bin' SC_ZIP='$T/sc.zip' OUT='$T/out-x' ASIO_DIR='$T/nothing' bash windows/ci/assemble-m1.sh > '$T/x.log' 2>&1 || grep -q FAIL '$T/m0-x/status/assemble.status'"
exit $fail
