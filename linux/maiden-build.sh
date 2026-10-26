#!/bin/bash
# maiden (the norns web editor and script catalog) for Linux: build it from its pinned commit into
# <norns home>/maiden, as the normal user. Same layout as the Mac port (macos/setup-deps.sh), see
# docs/port/phase-4-maiden.md.
#
# usage: linux/maiden-build.sh          (linux/setup-deps.sh and linux/build.sh run it; NORNS_NO_MAIDEN=1 skips it)
# needs: git, curl, tar, xz, sha256sum, go (apt: golang-go). node 16 is downloaded into the build folder
# (react-scripts 1.x does not run on a current node) and not installed anywhere else.
# environment (optional): NORNS_HOME (default: the folder above this repository), MAIDEN_BUILD_DIR
# (sources and caches, default <norns home>/.maiden-build; safe to delete), MAIDEN_FORCE=1 (rebuild)

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NORNS_HOME="${NORNS_HOME:-$(dirname "$REPO")}"

if [ "${NORNS_NO_MAIDEN:-0}" = 1 ]; then
    echo "maiden-build: NORNS_NO_MAIDEN=1, maiden is not built"
    exit 0
fi

MAIDEN_COMMIT=2e64f7d59284962ac68055dd556e3fd8515462f8 # same as macos/setup-deps.sh
NODE_VERSION=v16.20.2
YARN_VERSION=1.22.22
# applied in this order. the first is the Mac port's, read from there and not copied (one copy)
PATCHES="$REPO/macos/patches/maiden-host-flag.patch $(ls "$REPO"/linux/patches/maiden-*.patch 2>/dev/null | sort | tr '\n' ' ')"

M="$NORNS_HOME/maiden"
B="${MAIDEN_BUILD_DIR:-$NORNS_HOME/.maiden-build}"
STAMP="$M/.verdandi-build"
# a stamp of what was built: commit, patches (contents), tool versions. a change rebuilds
WANT="$MAIDEN_COMMIT $NODE_VERSION $YARN_VERSION $(cat $PATCHES | sha256sum | cut -d' ' -f1)"
if [ "${MAIDEN_FORCE:-0}" != 1 ] && [ -x "$M/maiden" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$WANT" ]; then
    echo "maiden-build: $M is up to date"
    exit 0
fi

command -v go >/dev/null || { echo "maiden-build: go not found (sudo apt install golang-go; linux/setup-deps.sh does it)"; exit 1; }
case "$(uname -m)" in
    x86_64) NODE_ARCH=x64 ;;
    aarch64) NODE_ARCH=arm64 ;;
    *) echo "maiden-build: no node $NODE_VERSION build for $(uname -m)"; exit 1 ;;
esac
case "$B" in *" "*) echo "maiden-build: '$B' contains a space"; exit 1 ;; esac

mkdir -p "$B"
# go and npm/yarn keep their downloads here, not in the home of the user
export GOPATH="$B/gopath" GOCACHE="$B/gocache" GOFLAGS=-mod=mod GOTOOLCHAIN=local
export npm_config_cache="$B/npm-cache" YARN_CACHE_FOLDER="$B/yarn-cache"
export CI=true # react-scripts: no watch mode, warnings are not errors for `build` here

cd "$B"
if [ ! -x node16/bin/node ]; then
    F="node-$NODE_VERSION-linux-$NODE_ARCH.tar.xz"
    echo "== node $NODE_VERSION"
    curl -sSfLO "https://nodejs.org/dist/$NODE_VERSION/$F"
    curl -sSfL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" | grep " $F\$" | sha256sum -c -
    rm -rf node16 && mkdir node16 && tar xJf "$F" -C node16 --strip-components 1 && rm "$F"
fi

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

echo "== maiden server (go $(go env GOVERSION))"
(cd maiden && go build -trimpath -ldflags="-X github.com/monome/maiden/cmd.version=linux-$MAIDEN_COMMIT" -o maiden .)

echo "== maiden web app"
# gen-version.sh wants a tag: the shallow clone has none, so write the file it would write
mkdir -p maiden/web/src
printf "export const VERSION = '0.5.0';\nexport const COMMIT = '%.8s';\n" "$MAIDEN_COMMIT" > maiden/web/src/version.js
(cd maiden/web && export PATH="$B/node16/bin:$PATH" &&
    npx -y yarn@$YARN_VERSION install --frozen-lockfile &&
    npx -y yarn@$YARN_VERSION run react-scripts build)

mkdir -p "$M/app" "$M/dist/sources"
cp maiden/maiden "$M/maiden.new" && mv -f "$M/maiden.new" "$M/maiden" # a running maiden is replaced, not overwritten
cp maiden/maiden.yaml "$M/"
rm -rf "$M/app/build" && cp -R maiden/web/build "$M/app/"
find "$M/app/build" -name '*.map' -delete
cp maiden/sources/*.json "$M/dist/sources/"
echo "$WANT" > "$STAMP"
echo "maiden-build: done, $M"
