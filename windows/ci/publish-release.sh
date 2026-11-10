#!/usr/bin/env bash
# windows/ci/publish-release.sh: publish the zip of a successful run to GitHub Releases, with the token of the workflow (contents: write).
#   - a release per commit, tag windows-<short hash>: Verdandi-windows-<version>-<short hash>.zip (kept; the newest 20 are kept, older ones are removed). M3: the ASIO build, when the run made one that passed its
#     own checks (ASIO_ZIP_DIR holds Verdandi-windows-asio-<version>-<short hash>.zip), goes into the same releases as a second zip; the WASAPI-only zip stays the default (the fixed name Verdandi-windows-latest.zip)
#   - the release windows-latest, updated each time (only when no check of the run failed, except the ones in NONBLOCKING_CHECKS; updated in place: files replaced, the tag moved): the same zip, a copy named Verdandi-windows-latest.zip (a fixed address for update-and-run), its SHA-256 and BUILD.txt
# inputs (environment): GH_TOKEN (the workflow's token, read by gh), GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID;
#   ZIP_DIR (folder with the zip of the run), ASIO_ZIP_DIR (optional: folder with the ASIO zip), STATUS_DIR (the status files of the report), KEEP (per-commit releases to keep, default 20), GH (the program that is called, default gh: the test uses a stand-in)
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../.." && pwd)"
GH="${GH:-gh}"
KEEP="${KEEP:-20}"
SHA="${GITHUB_SHA:?GITHUB_SHA is not set}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
ZIP_DIR="${ZIP_DIR:?ZIP_DIR is not set}"
VERSION="$(head -n 1 "$REPO_DIR/windows/VERSION" | tr -d '\r ')"
SHORT="$(printf '%s' "$SHA" | cut -c1-7)"
NAME="Verdandi-windows-$VERSION-$SHORT.zip"
[ -f "$ZIP_DIR/$NAME" ] || { echo "the zip $NAME is not in $ZIP_DIR (found: $(ls "$ZIP_DIR" 2> /dev/null | tr '\n' ' '))"; exit 1; }
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/${GITHUB_RUN_ID:-0}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ZIP_DIR/$NAME" "$WORK/$NAME"
cp "$ZIP_DIR/$NAME" "$WORK/Verdandi-windows-latest.zip"
# the ASIO build (optional)
ASIO_NAME="Verdandi-windows-asio-$VERSION-$SHORT.zip"
HAVE_ASIO=0
EXTRA=()
if [ -n "${ASIO_ZIP_DIR:-}" ] && [ -f "$ASIO_ZIP_DIR/$ASIO_NAME" ]; then
    HAVE_ASIO=1
    cp "$ASIO_ZIP_DIR/$ASIO_NAME" "$WORK/$ASIO_NAME"
    cp "$ASIO_ZIP_DIR/$ASIO_NAME" "$WORK/Verdandi-windows-asio-latest.zip"
    (cd "$WORK" && printf '%s  Verdandi-windows-asio-latest.zip\n' "$(sha256sum "$ASIO_NAME" | cut -d' ' -f1)" > Verdandi-windows-asio-latest.zip.sha256)
    EXTRA=("$WORK/$ASIO_NAME")
    echo "the ASIO build is part of this release: $ASIO_NAME"
else
    echo "no ASIO build in this release (the WASAPI-only zip is the whole release)"
fi
export HAVE_ASIO
HASH="$(cd "$WORK" && sha256sum "$NAME" | cut -d' ' -f1)"
printf '%s  Verdandi-windows-latest.zip\n' "$HASH" > "$WORK/Verdandi-windows-latest.zip.sha256"
printf '%s %s\n' "$VERSION" "$SHORT" > "$WORK/BUILD.txt"

# checks that are red for a known reason and do not hold back windows-latest (a space separated list of step names; they are named in the notes). default: NONE (the start/restart cycle test, which used
# to be on this list, is green in the workflow since M2; every red check holds windows-latest back). the workflow may name a check that has never run before for the first runs only
NONBLOCKING_CHECKS="${NONBLOCKING_CHECKS-}"
export NONBLOCKING_CHECKS
failed=0
if [ -n "${STATUS_DIR:-}" ] && ls "$STATUS_DIR"/*.status > /dev/null 2>&1; then
    for f in $(grep -l '^FAIL' "$STATUS_DIR"/*.status 2> /dev/null); do
        step="$(basename "$f" .status)"
        case " $NONBLOCKING_CHECKS " in
            *" $step "*) echo "check $step is red, but it is on the list of checks that do not block the release" ;;
            *) failed=1 ;;
        esac
    done
fi
VERSION="$VERSION" SHORT="$SHORT" SHA="$SHA" RUN_URL="$RUN_URL" STATUS_DIR="${STATUS_DIR:-}" REPO="$REPO" "$HERE/release-notes.sh" > "$WORK/notes.md"
TITLE="Verdandi for Windows $VERSION ($SHORT)"

# the release of this commit (a rerun replaces it)
TAG="windows-$SHORT"
"$GH" release delete "$TAG" --cleanup-tag --yes --repo "$REPO" 2> /dev/null || true
"$GH" release create "$TAG" "$WORK/$NAME" "${EXTRA[@]}" --repo "$REPO" --target "$SHA" --title "$TITLE" --notes-file "$WORK/notes.md" --prerelease
echo "published $TAG"

# the release that has a fixed address. it is UPDATED in place, never deleted first: if the run is cancelled half way (a newer push cancels the run) the release is still there, with old or new files
if [ "$failed" -eq 0 ]; then
    LATEST_TITLE="Verdandi for Windows: the newest build ($VERSION, $SHORT)"
    ASSETS=("$WORK/$NAME" "$WORK/Verdandi-windows-latest.zip" "$WORK/Verdandi-windows-latest.zip.sha256" "$WORK/BUILD.txt")
    if [ "$HAVE_ASIO" -eq 1 ]; then ASSETS+=("$WORK/$ASIO_NAME" "$WORK/Verdandi-windows-asio-latest.zip" "$WORK/Verdandi-windows-asio-latest.zip.sha256"); fi
    if "$GH" release view windows-latest --repo "$REPO" > /dev/null 2>&1; then
        "$GH" release upload windows-latest "${ASSETS[@]}" --repo "$REPO" --clobber
        # the tag moves to this commit; the files of older builds (another version or hash in the name) are removed
        "$GH" api -X PATCH "repos/$REPO/git/refs/tags/windows-latest" -f sha="$SHA" -F force=true > /dev/null
        "$GH" release view windows-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null | while read -r asset; do
            case "$asset" in
                "$NAME" | Verdandi-windows-latest.zip | Verdandi-windows-latest.zip.sha256 | BUILD.txt) ;;
                "$ASIO_NAME" | Verdandi-windows-asio-latest.zip | Verdandi-windows-asio-latest.zip.sha256) [ "$HAVE_ASIO" -eq 1 ] || "$GH" release delete-asset windows-latest "$asset" --repo "$REPO" --yes || true ;;
                *) "$GH" release delete-asset windows-latest "$asset" --repo "$REPO" --yes || true ;;
            esac
        done
        "$GH" release edit windows-latest --repo "$REPO" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest
    else
        "$GH" release create windows-latest "${ASSETS[@]}" --repo "$REPO" --target "$SHA" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest
    fi
    echo "published windows-latest"
else
    echo "checks failed: windows-latest is left as it was"
fi

# keep the newest $KEEP per-commit releases
"$GH" release list --repo "$REPO" --limit 200 --json tagName,createdAt --jq '.[] | select(.tagName | test("^windows-[0-9a-f]{7}$")) | "\(.createdAt) \(.tagName)"' 2> /dev/null \
    | sort -r | tail -n +"$((KEEP + 1))" | while read -r _ old; do
        [ -n "$old" ] || continue
        echo "removing the old release $old"
        "$GH" release delete "$old" --cleanup-tag --yes --repo "$REPO" || true
    done
exit 0
