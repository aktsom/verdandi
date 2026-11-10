#!/usr/bin/env bash
# windows/ci/publish-release.sh: publish the zip of a successful run to GitHub Releases, with the token of the workflow (contents: write).
#   - a release per commit, tag windows-<short hash>: Verdandi-windows-<version>-<short hash>.zip (kept; the newest 20 are kept, older ones are removed)
#   - the release windows-latest, updated each time (only when no check of the run failed; updated in place: files replaced, the tag moved): the same zip, a copy named Verdandi-windows-latest.zip (a fixed address for update-and-run), its SHA-256 and BUILD.txt
# inputs (environment): GH_TOKEN (the workflow's token, read by gh), GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID;
#   ZIP_DIR (folder with the zip of the run), STATUS_DIR (the status files of the report), KEEP (per-commit releases to keep, default 20), GH (the program that is called, default gh: the test uses a stand-in)
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
HASH="$(cd "$WORK" && sha256sum "$NAME" | cut -d' ' -f1)"
printf '%s  Verdandi-windows-latest.zip\n' "$HASH" > "$WORK/Verdandi-windows-latest.zip.sha256"
printf '%s %s\n' "$VERSION" "$SHORT" > "$WORK/BUILD.txt"

failed=0
if [ -n "${STATUS_DIR:-}" ] && ls "$STATUS_DIR"/*.status > /dev/null 2>&1; then
    grep -l '^FAIL' "$STATUS_DIR"/*.status > /dev/null 2>&1 && failed=1
fi
VERSION="$VERSION" SHORT="$SHORT" SHA="$SHA" RUN_URL="$RUN_URL" STATUS_DIR="${STATUS_DIR:-}" REPO="$REPO" "$HERE/release-notes.sh" > "$WORK/notes.md"
TITLE="Verdandi for Windows $VERSION ($SHORT)"

# the release of this commit (a rerun replaces it)
TAG="windows-$SHORT"
"$GH" release delete "$TAG" --cleanup-tag --yes --repo "$REPO" 2> /dev/null || true
"$GH" release create "$TAG" "$WORK/$NAME" --repo "$REPO" --target "$SHA" --title "$TITLE" --notes-file "$WORK/notes.md" --prerelease
echo "published $TAG"

# the release that has a fixed address. it is UPDATED in place, never deleted first: if the run is cancelled half way (a newer push cancels the run) the release is still there, with old or new files
if [ "$failed" -eq 0 ]; then
    LATEST_TITLE="Verdandi for Windows: the newest build ($VERSION, $SHORT)"
    ASSETS=("$WORK/$NAME" "$WORK/Verdandi-windows-latest.zip" "$WORK/Verdandi-windows-latest.zip.sha256" "$WORK/BUILD.txt")
    if "$GH" release view windows-latest --repo "$REPO" > /dev/null 2>&1; then
        "$GH" release upload windows-latest "${ASSETS[@]}" --repo "$REPO" --clobber
        # the tag moves to this commit; the files of older builds (another version or hash in the name) are removed
        "$GH" api -X PATCH "repos/$REPO/git/refs/tags/windows-latest" -f sha="$SHA" -F force=true > /dev/null
        "$GH" release view windows-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null | while read -r asset; do
            case "$asset" in
                "$NAME" | Verdandi-windows-latest.zip | Verdandi-windows-latest.zip.sha256 | BUILD.txt) ;;
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
