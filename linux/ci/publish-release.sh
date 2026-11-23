#!/usr/bin/env bash
# linux/ci/publish-release.sh (docs/port/phase-m36.md): publish the .deb of a successful run to GitHub Releases with the token of the workflow (contents: write). Modelled on windows/ci/publish-release.sh
# and its M30 rules; it only ever touches releases whose tag starts with linux- (never windows-latest or any windows-* release):
#   - a release per commit, tag linux-<short hash>: Verdandi-linux-<version>-<short hash>.deb (the newest KEEP are kept, older ones removed)
#   - the release linux-latest (fixed address), UPDATED in place, never deleted first: Verdandi-linux-latest.deb, its .sha256, BUILD.txt and the versioned copy. this job only adds or replaces its own files; the
#     versioned copies of OLDER builds (Verdandi-linux-*.deb) are replaced by the new one, every other file on the release is left alone. afterwards the release is read back and the job FAILS with the names when
#     Verdandi-linux-latest.deb, its .sha256, BUILD.txt or the versioned copy is missing
#   - the 403 of the per-commit tag (the token may not make a tag at a commit that changes workflow files): that release is skipped, linux-latest is still updated in place without moving its tag, and the notes say so
# inputs (environment): GH_TOKEN, GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID; DEB (the built .deb), TESTS (text for the notes), KEEP (default 10), GH (the program, default gh)
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH="${GH:-gh}"
KEEP="${KEEP:-10}"
SHA="${GITHUB_SHA:?GITHUB_SHA is not set}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
DEB="${DEB:?DEB is not set (the built .deb)}"
[ -f "$DEB" ] || { echo "the .deb $DEB does not exist"; exit 1; }
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/${GITHUB_RUN_ID:-0}"
SHORT="$(printf '%s' "$SHA" | cut -c1-7)"
PACKAGE_VERSION="$(dpkg-deb -f "$DEB" Version)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# BUILD.txt comes out of the package itself: its first line "<Windows number> <hash>" is what the program shows, so the page, the package and the program say the same
dpkg-deb --fsys-tarfile "$DEB" | tar -xO ./opt/verdandi/BUILD.txt > "$WORK/BUILD.txt" || { echo "no /opt/verdandi/BUILD.txt in $DEB"; exit 1; }
VERSION="$(head -n 1 "$WORK/BUILD.txt" | cut -d' ' -f1)"
BUILD_HASH="$(head -n 1 "$WORK/BUILD.txt" | cut -d' ' -f2)"
[ "$BUILD_HASH" = "$SHORT" ] || { echo "ERROR: the package was built from $BUILD_HASH, this run is $SHORT"; exit 1; }
[ "${PACKAGE_VERSION%%-*}" = "$VERSION" ] || { echo "ERROR: the package version $PACKAGE_VERSION does not start with the number in BUILD.txt ($VERSION)"; exit 1; }
NAME="Verdandi-linux-$VERSION-$SHORT.deb"
STATIC="Verdandi-linux-latest.deb"
cp "$DEB" "$WORK/$NAME"
cp "$DEB" "$WORK/$STATIC"
printf '%s  %s\n' "$(sha256sum "$WORK/$STATIC" | cut -d' ' -f1)" "$STATIC" > "$WORK/$STATIC.sha256"
printf 'run %s\n' "$RUN_URL" >> "$WORK/BUILD.txt"
VERSION="$VERSION" PACKAGE_VERSION="$PACKAGE_VERSION" SHORT="$SHORT" SHA="$SHA" RUN_URL="$RUN_URL" REPO="$REPO" TESTS="${TESTS:-}" "$HERE/release-notes.sh" > "$WORK/notes.md"
TITLE="Verdandi Linux $VERSION ($SHORT)"

# the release of this commit (a rerun replaces it)
TAG="linux-$SHORT"
"$GH" release delete "$TAG" --cleanup-tag --yes --repo "$REPO" 2> /dev/null || true
REF_BLOCKED=0
if "$GH" release create "$TAG" "$WORK/$NAME" --repo "$REPO" --target "$SHA" --title "$TITLE" --notes-file "$WORK/notes.md" --prerelease; then
    echo "published $TAG"
else
    # the workflow's token may not make a tag (HTTP 403 "Resource not accessible by integration") at a commit whose history changes a workflow file (seen on the Windows releases, M22). the per-commit release is then
    # NOT made, linux-latest is still updated in place (the files are replaced, its tag stays where it is), and the notes say so. say what the API answers, with probes that are removed again
    REF_BLOCKED=1
    echo "== the release of the commit ($TAG) could not be made: the per-commit release is skipped and linux-latest is updated without moving its tag. what the GitHub API says (the probes are removed again):"
    echo "-- a draft release:"; "$GH" api -i -X POST "repos/$REPO/releases" -f tag_name="diag-$SHORT" -f target_commitish="$SHA" -f name="diag" -F draft=true 2>&1 | grep -i -E '^(HTTP|x-accepted-github-permissions)|"message"' | head -4 || true
    "$GH" api "repos/$REPO/releases?per_page=30" --jq '.[] | select(.name=="diag") | .id' 2> /dev/null | while read -r id; do "$GH" api -X DELETE "repos/$REPO/releases/$id" > /dev/null 2>&1 || true; done
    "$GH" api -X DELETE "repos/$REPO/git/refs/tags/diag-$SHORT" > /dev/null 2>&1 || true
fi
# the release that has a fixed address. it is UPDATED in place, never deleted: if the run is cancelled half way the release is still there, with old or new files
LATEST_TITLE="Verdandi Linux: the newest build ($VERSION, $SHORT)"
ASSETS=("$WORK/$NAME" "$WORK/$STATIC" "$WORK/$STATIC.sha256" "$WORK/BUILD.txt")
if "$GH" release view linux-latest --repo "$REPO" > /dev/null 2>&1; then
    "$GH" release upload linux-latest "${ASSETS[@]}" --repo "$REPO" --clobber
    if [ "$REF_BLOCKED" -eq 0 ]; then
        "$GH" api -X PATCH "repos/$REPO/git/refs/tags/linux-latest" -f sha="$SHA" -F force=true > /dev/null
    else
        printf '\n> **Note:** GitHub did not let the workflow move the tag `linux-latest` to this build (a tag at a commit that changes workflow files needs a permission the workflow token cannot have). The files above ARE this build (version %s, commit %s).\n' "$VERSION" "$SHORT" >> "$WORK/notes.md"
    fi
    # only the versioned copies of older builds go (Verdandi-linux-<number>-<hash>.deb); the fixed names, BUILD.txt and every file that is not ours stay
    "$GH" release view linux-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null | while read -r asset; do
        case "$asset" in
            "$NAME") ;;
            Verdandi-linux-latest.deb | Verdandi-linux-latest.deb.sha256 | BUILD.txt) ;;
            Verdandi-linux-*.deb) "$GH" release delete-asset linux-latest "$asset" --repo "$REPO" --yes || true ;;
            *) ;;
        esac
    done
    "$GH" release edit linux-latest --repo "$REPO" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest=false
else
    "$GH" release create linux-latest "${ASSETS[@]}" --repo "$REPO" --target "$SHA" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest=false
fi
echo "published linux-latest"
# the release must end with the fixed .deb, its SHA-256 file, BUILD.txt and the versioned copy: look at the release itself, not at what this script meant to upload
GOT="$("$GH" release view linux-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null || true)"
missing=""
for need in "$STATIC" "$STATIC.sha256" BUILD.txt "$NAME"; do
    printf '%s\n' "$GOT" | grep -qx "$need" || missing="$missing $need"
done
if [ -n "$missing" ]; then
    echo "ERROR: the release linux-latest is missing:$missing (it has: $(printf '%s' "$GOT" | tr '\n' ' '))"
    PUBLISH_INCOMPLETE=1
else
    echo "linux-latest has the .deb, its SHA-256 file, BUILD.txt and the versioned copy"
fi

# keep the newest $KEEP per-commit releases (tags linux-<7 hex digits> only)
"$GH" release list --repo "$REPO" --limit 200 --json tagName,createdAt --jq '.[] | select(.tagName | test("^linux-[0-9a-f]{7}$")) | "\(.createdAt) \(.tagName)"' 2> /dev/null \
    | sort -r | tail -n +"$((KEEP + 1))" | while read -r _ old; do
        [ -n "$old" ] || continue
        echo "removing the old release $old"
        "$GH" release delete "$old" --cleanup-tag --yes --repo "$REPO" || true
    done
exit "${PUBLISH_INCOMPLETE:-0}"
