#!/usr/bin/env bash
# linux/ci/release-notes.sh: the text of a Linux release on GitHub (docs/port/phase-m36.md): what to download, how to install, the commit message, the tests of the run.
#   VERSION (the Windows number) PACKAGE_VERSION SHORT SHA RUN_URL   the build
#   TESTS (a text: what the run checked)   REPO (owner/name, for the links)   COMMIT_MESSAGE (default: git log -1 of SHA)
# prints Markdown on stdout
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../.." && pwd)"
VERSION="${VERSION:?}" PACKAGE_VERSION="${PACKAGE_VERSION:?}" SHORT="${SHORT:?}" SHA="${SHA:-unknown}" RUN_URL="${RUN_URL:-}" REPO="${REPO:-}" TESTS="${TESTS:-}"
MSG="${COMMIT_MESSAGE:-$(git -C "$REPO_DIR" log -1 --format=%B "$SHA" 2> /dev/null | grep -v -E '^(Co-Authored-By|Claude-Session):' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')}"
cat << MD
# Verdandi Linux $VERSION ($SHORT)

**Download one file: \`Verdandi-linux-latest.deb\`** (Ubuntu 24.04 and Linux Mint 22, 64-bit). Double-click it in the file manager: the installer (GDebi or the Software Manager) asks for your password and installs everything, including the libraries it needs. Then start **Verdandi Linux** from the application menu. Installing a newer file over an older one updates it: your folder \`~/Verdandi\` (scripts, mods, presets, settings) is not touched. Close Verdandi before you update.

- Package version: \`$PACKAGE_VERSION\` (the number before the dash is the Windows version number of the same build).
- Check the download: \`sha256sum -c Verdandi-linux-latest.deb.sha256\`.
- The file is not signed (it is installed from a file, not from a software source); the checksum is on this page.
- Other Linux systems (Ubuntu 22.04, Mint 21, Debian) are not covered by this package.

## This build

> ${MSG:-(no commit message)}

Commit \`$SHORT\`${SHA:+ ($SHA)}${RUN_URL:+, [the workflow run]($RUN_URL)}.

## What was checked in a clean Ubuntu 24.04 before it was published

${TESTS:-(no list of checks was given)}

Not checked by anyone yet: the real double-click installer on a Linux Mint desktop, real sound hardware, real grids and arcs.
MD
