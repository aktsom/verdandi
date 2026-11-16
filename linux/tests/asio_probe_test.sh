#!/usr/bin/env bash
# linux/tests/asio_probe_test.sh (M19): the ASIO probe of the Windows build (matron/src/platform/windows/audio/audio_asio_probe.c) against the CI's stub ASIO driver (windows/ci/asio_stub.c), on Windows code run by Wine:
# nothing registered, a working driver (name, channels, buffer sizes), a driver that refuses to start (its own message), a class that cannot be made, a driver file that is not there. needs mingw-w64 and wine64: SKIP without
set -u
cd "$(dirname "$0")/../.." || exit 1
CC=x86_64-w64-mingw32-gcc
command -v "$CC" > /dev/null || { echo "SKIP: no mingw-w64"; exit 0; }
WINE="$(command -v wine64 || true)"
[ -n "$WINE" ] || [ -x /usr/lib/wine/wine64 ] && WINE="${WINE:-/usr/lib/wine/wine64}"
[ -n "$WINE" ] || { echo "SKIP: no wine64"; exit 0; }
T="$(mktemp -d)"
export WINEPREFIX="$T/prefix" WINEDEBUG=-all WINEARCH=win64
fails=0
check() { if grep -q -E "$2" "$T/out.txt"; then echo "ok   $1"; else echo "FAIL $1 (wanted: $2)"; sed 's/^/     | /' "$T/out.txt" | head -8; fails=$((fails + 1)); fi; }
$CC -std=gnu11 -Wall -Wextra -shared -o "$T/asio_stub.dll" windows/ci/asio_stub.c -Wl,--kill-at -lole32 -luuid || exit 1
cat > "$T/main.c" << 'EOC'
#include <stdio.h>
#include "audio_asio_probe.h"
static void lg(const char *l) { puts(l); }
int main(void) { static va_driver d[VA_MAX]; int n = va_probe(d, VA_MAX, lg); char s[400]; int u; va_summary(d, n, s, sizeof s, &u); printf("SUMMARY n=%d usable=%d: %s\n", n, u, s); return 0; }
EOC
$CC -std=gnu11 -Wall -I matron/src/platform/windows/audio "$T/main.c" matron/src/platform/windows/audio/audio_asio_probe.c -o "$T/probe.exe" -lole32 -luuid || exit 1
"$WINE" wineboot -i > /dev/null 2>&1
cp "$T/asio_stub.dll" "$T/prefix/drive_c/asio_stub.dll"
run() { "$WINE" "$T/probe.exe" > "$T/out.txt" 2>&1; }
run
check "nothing registered: says so and the summary says no driver is installed" "no ASIO driver is registered on this PC.*"
check "... in both registry views" "64-bit registry has no ASIO drivers"
REG="$WINE reg" bash windows/ci/register_asio_stub.sh install 'C:\asio_stub.dll' > /dev/null
run
check "a working driver: its name, version, channels, buffer sizes and rate" "driver 'Verdandi Test ASIO' \(64-bit registry, C:.asio_stub.dll\): loads and starts; it calls itself 'Verdandi Test ASIO' version 1, 4 inputs, 4 outputs, buffer 64 to 2048 frames \(preferred 256, powers of two\), 48000 Hz"
check "... and the summary counts it usable" "SUMMARY n=1 usable=1: 1 ASIO driver usable"
VERDANDI_STUB_ASIO=busy run
check "a driver that refuses: its own message and the likely reason" "NOT usable: the driver refused to start: \"Verdandi Test ASIO: the device is in use by another program\" \(usually another program has the card"
check "... the summary says none can be used" "SUMMARY n=1 usable=0: 1 ASIO driver found, none can be used: Verdandi Test ASIO: the driver refused to start"
VERDANDI_STUB_ASIO=broken run
check "a class that cannot be made: the error number" "NOT usable: Windows could not make the driver \(error 0x80004005\)"
REG="$WINE reg" bash windows/ci/register_asio_stub.sh remove > /dev/null
REG="$WINE reg" bash windows/ci/register_asio_stub.sh install 'C:\not_there.dll' > /dev/null
run
check "a driver file that is not there is named" "the driver file is not there: C:.not_there.dll"
REG="$WINE reg" bash windows/ci/register_asio_stub.sh remove > /dev/null
rm -rf "$T"
if [ "$fails" -ne 0 ]; then echo "$fails FAILED"; exit 1; fi
echo "asio_probe_test: ok"
