#!/bin/bash
# windows/ci/build-maiden.sh: maiden (the norns web editor and script catalog) for Windows, built on a LINUX runner: the server is Go (pure Go, GOOS=windows cross-builds), the web app is static files (the same
# on every system). the same pinned commit and patches as linux/maiden-build.sh (the Mac port's --host flag, the guard of the systemd unit API); output: maiden-win/{maiden.exe, maiden.yaml, app/build, dist/sources}.
# the web app needs node 16 (react-scripts 1.x does not run on a current node): downloaded into the build folder, checked against nodejs.org's SHASUMS256.txt, installed nowhere.
# environment: OUT (default ./maiden-win), B (build folder, default ./maiden-build), MAIDEN_SKIP_WEB=1 (Go only: for a quick local check)
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-$PWD/maiden-win}"
B="${B:-$PWD/maiden-build}"
MAIDEN_COMMIT=2e64f7d59284962ac68055dd556e3fd8515462f8
NODE_VERSION=v16.20.2
YARN_VERSION=1.22.22
PATCHES="$REPO/macos/patches/maiden-host-flag.patch $(ls "$REPO"/linux/patches/maiden-*.patch | sort | tr '\n' ' ') $(ls "$REPO"/windows/maiden/maiden-*.patch | sort | tr '\n' ' ')"
command -v go > /dev/null || { echo "go not found"; exit 1; }
mkdir -p "$B" "$OUT"
export GOPATH="$B/gopath" GOCACHE="$B/gocache" GOFLAGS=-mod=mod GOTOOLCHAIN=local
export npm_config_cache="$B/npm-cache" YARN_CACHE_FOLDER="$B/yarn-cache" CI=true
cd "$B"
echo "== maiden source ($MAIDEN_COMMIT)"
rm -rf maiden
git init -q maiden
git -C maiden remote add origin https://github.com/monome/maiden.git
git -C maiden fetch -q --depth 1 origin "$MAIDEN_COMMIT"
git -C maiden checkout -q FETCH_HEAD
for p in $PATCHES; do
    echo "   patch $(basename "$p")"
    git -C maiden apply "$p"
done
echo "== maiden server for Windows (go $(go env GOVERSION))"
(cd maiden && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-X github.com/monome/maiden/cmd.version=windows-$MAIDEN_COMMIT" -o maiden.exe .)
if [ "${MAIDEN_SKIP_WEB:-0}" != 1 ]; then
    echo "== node $NODE_VERSION"
    F="node-$NODE_VERSION-linux-x64.tar.xz"
    curl -sSfLO "https://nodejs.org/dist/$NODE_VERSION/$F"
    curl -sSfL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" | grep " $F\$" | sha256sum -c -
    rm -rf node16 && mkdir node16 && tar xJf "$F" -C node16 --strip-components 1 && rm "$F"
    echo "== maiden web app"
    mkdir -p maiden/web/src
    printf "export const VERSION = '0.5.0';\nexport const COMMIT = '%.8s';\n" "$MAIDEN_COMMIT" > maiden/web/src/version.js
    (cd maiden/web && export PATH="$B/node16/bin:$PATH" &&
        npx -y yarn@$YARN_VERSION install --frozen-lockfile &&
        npx -y yarn@$YARN_VERSION run react-scripts build)
fi
rm -rf "$OUT"
mkdir -p "$OUT/app" "$OUT/dist/sources"
cp maiden/maiden.exe "$OUT/maiden.exe"
cp maiden/maiden.yaml "$OUT/"
if [ "${MAIDEN_SKIP_WEB:-0}" != 1 ]; then
    cp -R maiden/web/build "$OUT/app/"
    find "$OUT/app/build" -name '*.map' -delete
fi
cp maiden/sources/*.json "$OUT/dist/sources/"
cp maiden/LICENSE "$OUT/LICENSE-maiden.txt" 2> /dev/null || true
echo "$MAIDEN_COMMIT" > "$OUT/MAIDEN-COMMIT.txt"
echo "maiden-build (windows): done, $OUT"
ls -l "$OUT" "$OUT/app" 2> /dev/null | head -20
