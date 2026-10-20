#!/bin/bash
# make-app.sh: build a self-contained norns.app (and a .dmg) from this checkout.
#
# needs what macos/setup-deps.sh provides, a norns build (waf), and homebrew's jack and GNU
# tools to copy from. the app is ad-hoc signed (no developer identity).
#
# usage: macos/make-app.sh [--dmg]

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NORNS_HOME="$(dirname "$REPO")"
d="$REPO"
while [ "$d" != "/" ] && [ ! -d "$d/deps/prefix" ]; do d="$(dirname "$d")"; done
P="${NORNS_DEPS:-$d/deps/prefix}"
BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
# built on APFS: codesign trips over the xattr files exFAT and similar volumes keep
OUT="${NORNS_APP_OUT:-${TMPDIR:-/tmp}/norns-app}"
# outside build/: waf clean empties that
# the dmg goes on top of the project folder (the one with deps/), where it is found first;
# without such a folder, into dist/ of the checkout
if [ "$d" != "/" ]; then DIST="$d"; else DIST="$REPO/dist"; fi
APP="$OUT/norns.app"
R="$APP/Contents/Resources"
VERSION="$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo dev)"

echo "== norns.app ($VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$R/norns/build/norns" "$R/norns/build/ws-wrapper" "$R/norns/build/macos" \
    "$R/norns/macos" "$R/deps/bin" "$R/deps/lib/jack" "$R/deps/gnubin" "$R/deps/SuperCollider"

# runtime part of the repository, same layout as the checkout
for f in lua sc resources doc matronrc.lua LICENSE.txt readme-macos.md; do
    cp -R "$REPO/$f" "$R/norns/"
done
cp "$REPO/macos/norns.sh" "$REPO/macos/norns-icon.png" "$R/norns/macos/"
# the MANUAL button on the device (lua/core/menu.lua) opens it when a script has no docs
mkdir -p "$R/norns/macos/manual"
cp "$REPO/macos/manual/manual.html" "$R/norns/macos/manual/"
cp "$REPO/build/norns/norns" "$R/norns/build/norns/"
cp "$REPO/build/ws-wrapper/ws-wrapper" "$R/norns/build/ws-wrapper/"
cp "$REPO"/build/macos/jack_wait "$REPO"/build/macos/jack_connect "$REPO"/build/macos/jack_disconnect \
    "$REPO"/build/macos/jack_lsp "$REPO"/build/macos/auv3_bridge "$REPO"/build/macos/audio_devices \
    "$R/norns/build/macos/"

# jack server and the drivers norns uses
cp "$(readlink -f "$BREW/bin/jackd")" "$R/deps/bin/jackd"
for drv in jack_coreaudio jack_coremidi jack_dummy jack_loopback; do
    cp "$BREW/opt/jack/lib/jack/$drv.so" "$R/deps/lib/jack/"
done

# GNU userland under the plain names (scripts call find -printf, sed -i, stat -c ...)
for pkg in coreutils findutils gnu-sed grep; do
    for t in "$BREW/opt/$pkg/libexec/gnubin/"*; do
        [ -f "$(readlink -f "$t")" ] || continue
        cp "$(readlink -f "$t")" "$R/deps/gnubin/$(basename "$t")"
    done
done

# SuperCollider (jack build) and sc3-plugins, without help files
cp -R "$P/SuperCollider/SuperCollider.app" "$R/deps/SuperCollider/"
SC3="$NORNS_HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins"
cp -R "$SC3" "$R/deps/SC3plugins"
find "$R/deps/SC3plugins" -type d -name HelpSource -prune -exec rm -rf {} +

# sdl2-compat loads SDL3 from next to itself at runtime
cp "$(readlink -f "$BREW/opt/sdl3/lib/libSDL3.0.dylib")" "$R/deps/lib/libSDL3.dylib"

# maiden
cp -R "$NORNS_HOME/maiden" "$R/maiden"
find "$R/maiden" -name '*.map' -delete

# launcher + Info.plist
cp "$REPO/macos/app-launcher.sh" "$APP/Contents/MacOS/norns"
chmod +x "$APP/Contents/MacOS/norns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>norns</string>
    <key>CFBundleDisplayName</key><string>norns</string>
    <key>CFBundleIdentifier</key><string>community.norns-macos.app</string>
    <key>CFBundleExecutable</key><string>norns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>norns records and processes audio input (softcut, tape, engines).</string>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0. community port, not affiliated with monome.</string>
</dict>
</plist>
EOF
[ -f "$REPO/macos/norns.icns" ] && cp "$REPO/macos/norns.icns" "$R/" &&
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string norns" "$APP/Contents/Info.plist"

# no extended attributes (quarantine, provenance, finder info) in a signed bundle, and
# normal permissions (sources on exFAT and similar volumes come out as rwx------)
xattr -cr "$APP"
chmod -R u+rwX,go+rX,go-w "$APP"

echo "== libraries"
python3 -I "$REPO/macos/bundle_dylibs.py" "$R" "$R/deps/lib"

echo "== AUv3"
mkdir -p "$APP/Contents/PlugIns"
"$REPO/macos/auv3/build-appex.sh" "$APP/Contents/PlugIns/norns-au.appex" "$VERSION"

codesign --force --sign - "$APP"

echo "== check: nothing may point outside the app"
bad=0
while IFS= read -r f; do
    if otool -L "$f" 2>/dev/null | tail -n +2 | grep -E '/opt/homebrew|/usr/local|/Users/' >/dev/null; then
        echo "  external reference: ${f#$APP/}"; bad=1
    fi
done < <(find "$APP" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' -o -name '*.scx' \))
[ $bad -eq 0 ] && echo "  ok"

if [ "${1:-}" = "--dmg" ]; then
    echo "== dmg"
    STAGE="$OUT/dmg"
    rm -rf "$STAGE" "$OUT/norns.dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    [ -f "$REPO/macos/manual/norns-macos-manual.pdf" ] && cp "$REPO/macos/manual/norns-macos-manual.pdf" "$STAGE/Manual.pdf"
    [ -f "$REPO/macos/manual/manual.html" ] && cp "$REPO/macos/manual/manual.html" "$STAGE/Manual.html"
    chmod 644 "$STAGE"/Manual.* 2>/dev/null
    xattr -c "$STAGE"/Manual.* 2>/dev/null
    hdiutil create -volname norns -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT/norns.dmg" >/dev/null
    rm -rf "$STAGE"
    mkdir -p "$DIST"
    cp "$OUT/norns.dmg" "$DIST/norns.dmg"
    ls -la "$DIST/norns.dmg"
fi
