#!/usr/bin/env bash
# linux/tests/asio_backend_test.sh (M20): the Windows build's PortAudio backend (the real audio_backend_pa.c) against the stub ASIO driver, under Wine. what it proves: an ASIO driver can be closed and opened again, from any
# thread, with another pair and another buffer; the card's clock is never changed; the driver's channel names and buffer sizes arrive. see asio_backend_test.c.
# needs mingw-w64, wine64 and an ASIO build of PortAudio for mingw: PA_ASIO_DIR (libportaudio.dll, libportaudio.dll.a, include/) or, without it, a build from the sources of PortAudio 19.7 and the ASIO SDK
# (windows/ci/asio-sdk.env; git and the network are needed): SKIP when neither is possible. the SDK is only used to build this test, it is not shipped.
set -u
cd "$(dirname "$0")/../.." || exit 1
REPO="$PWD"
CC=x86_64-w64-mingw32-gcc
command -v "$CC" > /dev/null || { echo "SKIP: no mingw-w64"; exit 0; }
WINE="$(command -v wine64 || true)"
[ -n "$WINE" ] || { [ -x /usr/lib/wine/wine64 ] && WINE=/usr/lib/wine/wine64; }
[ -n "$WINE" ] || { echo "SKIP: no wine64"; exit 0; }
PA="${PA_ASIO_DIR:-$REPO/build/pa-asio-wine}"
if [ ! -f "$PA/libportaudio.dll" ]; then
    command -v git > /dev/null && command -v cmake > /dev/null && command -v ninja > /dev/null || { echo "SKIP: no ASIO build of PortAudio (PA_ASIO_DIR) and no git/cmake/ninja to make one"; exit 0; }
    # shellcheck disable=SC1091
    . windows/ci/asio-sdk.env
    W="$(mktemp -d)"
    ok=1
    timeout 120 git clone -q --depth 1 --branch "$PA_TAG" "$PA_REPO" "$W/pa" > /dev/null 2>&1 || ok=0
    sdk=""
    for r in $ASIO_SDK_REPOS; do [ -d "$W/sdk" ] || timeout 120 git clone -q --depth 1 "$r" "$W/sdk" > /dev/null 2>&1; done
    [ -f "$W/sdk/common/asio.h" ] || ok=0
    [ "$ok" = 1 ] || { echo "SKIP: PortAudio or the ASIO SDK could not be fetched (no network?)"; rm -rf "$W"; exit 0; }
    cat > "$W/tc.cmake" << 'E'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
E
    cmake -S "$W/pa" -B "$W/b" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$W/tc.cmake" -DCMAKE_BUILD_TYPE=Release -DPA_BUILD_SHARED_LIBS=ON -DPA_BUILD_TESTS=OFF -DPA_BUILD_EXAMPLES=OFF -DPA_USE_ASIO=ON \
        -DPA_USE_WASAPI=OFF -DPA_USE_DS=OFF -DPA_USE_WMME=OFF -DPA_USE_WDMKS=OFF -DPA_USE_WDMKS_DEVICE_INFO=OFF -DASIOSDK_ROOT_DIR="$W/sdk" -DASIO_SDK_PATH="$W/sdk" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > "$W/cmake.log" 2>&1 && cmake --build "$W/b" > "$W/build.log" 2>&1 || { echo "SKIP: PortAudio with ASIO did not build here (see $W)"; exit 0; }
    mkdir -p "$PA/include"
    cp "$W/b/libportaudio.dll" "$W/b/libportaudio.dll.a" "$PA/" && cp "$W/pa/include/"*.h "$PA/include/" && rm -f "$PA/include/pa_win_wasapi.h" # (this PortAudio is built without WASAPI)
    rm -rf "$W"
fi
T="$(mktemp -d)"
export WINEPREFIX="$T/prefix" WINEDEBUG=-all WINEARCH=win64
fails=0
A=matron/src/platform/windows/audio
$CC -std=gnu11 -Wall -Wextra -shared -o "$T/asio_stub.dll" windows/ci/asio_stub.c -Wl,--kill-at -lole32 -luuid -lwinmm || exit 1
$CC -std=gnu11 -Wall -I "$PA/include" -I $A -o "$T/backend.exe" linux/tests/asio_backend_test.c $A/audio_backend_pa.c $A/audio_asio_probe.c "$PA/libportaudio.dll.a" -lole32 -luuid -lpsapi -lwinmm || { echo "FAIL: the test did not compile"; exit 1; }
cp "$PA/libportaudio.dll" "$T/"
"$WINE" wineboot -i > /dev/null 2>&1
cp "$T/asio_stub.dll" "$T/prefix/drive_c/asio_stub.dll"
REG="$WINE reg" bash windows/ci/register_asio_stub.sh install 'C:\asio_stub.dll' > /dev/null
for card in 48000 44100; do
    for mode in "" single; do
        echo "--- the card runs at $card Hz, driver mode '${mode:-normal}'"
        rm -f "$T/stub.log"
        VERDANDI_STUB_RATE=$card VERDANDI_STUB_ASIO=$mode VERDANDI_STUB_LOG='C:\stub.log' VERDANDI_STUB_CTL='C:\stub.ctl' VERDANDI_STUB_BUFMAX=8192 timeout 200 "$WINE" "$T/backend.exe" "$card" 2>&1 | tee "$T/out.txt" | sed 's/^/    /'
        grep -q "asio_backend_test: ok" "$T/out.txt" || fails=$((fails + 1))
        rm -f "$T/prefix/drive_c/stub.log" "$T/prefix/drive_c/stub.ctl"
    done
done
REG="$WINE reg" bash windows/ci/register_asio_stub.sh remove > /dev/null
rm -rf "$T"
if [ "$fails" -ne 0 ]; then echo "asio_backend_test: $fails run(s) FAILED"; exit 1; fi
echo "asio_backend_test: all runs ok"
