#!/usr/bin/env bash
# windows/ci/publish-release.sh: publish the zip of a successful run to GitHub Releases, with the token of the workflow (contents: write).
# M31: THERE IS ONE ZIP (the ASIO build is the build: docs/port/phase-m31.md).
#   - a release per commit, tag windows-<short hash>: Verdandi-windows-<version>-<short hash>.zip (kept; the newest 20 are kept, older ones are removed)
#   - the release windows-latest, updated each time (only when no check of the run failed, except the ones in NONBLOCKING_CHECKS; updated in place: files replaced, the tag moved): the same zip, a copy named
#     Verdandi-windows-latest.zip (a fixed address for update-and-run), its SHA-256 and BUILD.txt. THE TRANSITION COPY: Verdandi-windows-asio-latest.zip and its SHA-256 (the name inside says the asio name) are made from
#     the same file, byte for byte, so that an update routine of an earlier build, which asks for that name, keeps working and installs the one zip. nothing retires it here: a separate change does, when the owner says so.
#   - this job ONLY ADDS OR REPLACES: it never deletes a file of the release that it did not make (M30). the only files it removes are the versioned copies of older builds of THE zip (Verdandi-windows-<version>-<hash>.zip,
#     replaced by the new one); the versioned ASIO zips of earlier builds, the fixed names and everything else stay. afterwards the release is READ BACK and the job fails with the names when a file is missing:
#     windows-latest must always have a working download, the new zip is on it before anything else changes.
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
# M22: the zip is built with the STATIC name (Verdandi-windows-latest.zip; the folder inside has a fixed name too); the copy with the version in its name is made here
STATIC="Verdandi-windows-latest.zip"
[ -f "$ZIP_DIR/$STATIC" ] || { echo "the zip $STATIC is not in $ZIP_DIR (found: $(ls "$ZIP_DIR" 2> /dev/null | tr '\n' ' '))"; exit 1; }
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/${GITHUB_RUN_ID:-0}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ZIP_DIR/$STATIC" "$WORK/$NAME"
cp "$ZIP_DIR/$STATIC" "$WORK/Verdandi-windows-latest.zip"
# the transition copy: the same bytes under the name the update routine of an earlier build asks for
OLDNAME="Verdandi-windows-asio-latest.zip"
cp "$ZIP_DIR/$STATIC" "$WORK/$OLDNAME"
(cd "$WORK" && printf '%s  %s\n' "$(sha256sum "$NAME" | cut -d' ' -f1)" "$OLDNAME" > "$OLDNAME.sha256")
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
REF_BLOCKED=0
if "$GH" release create "$TAG" "$WORK/$NAME" --repo "$REPO" --target "$SHA" --title "$TITLE" --notes-file "$WORK/notes.md" --prerelease; then
    echo "published $TAG"
else
    # M22: the workflow's token may not make a tag (HTTP 403 "Resource not accessible by integration"; the answer asked for contents=write AND workflows=write, which GITHUB_TOKEN cannot have) at a commit whose history changes
    # a workflow file. the per-commit release is then NOT made, windows-latest is still updated in place (the files are replaced, its tag stays where it is), and the notes say so. say what the API answers, with probes that are removed again
    REF_BLOCKED=1
    echo "== the release of the commit ($TAG) could not be made: the per-commit release is skipped and windows-latest is updated without moving its tag. what the GitHub API says (the probes are removed again):"
    echo "-- a draft release:"; "$GH" api -i -X POST "repos/$REPO/releases" -f tag_name="diag-$SHORT" -f target_commitish="$SHA" -f name="diag" -F draft=true 2>&1 | grep -i -E '^(HTTP|x-accepted-github-permissions)|"message"' | head -4 || true
    "$GH" api "repos/$REPO/releases?per_page=30" --jq '.[] | select(.name=="diag") | .id' 2> /dev/null | while read -r id; do "$GH" api -X DELETE "repos/$REPO/releases/$id" > /dev/null 2>&1 || true; done
    "$GH" api -X DELETE "repos/$REPO/git/refs/tags/diag-$SHORT" > /dev/null 2>&1 || true
fi
# the release that has a fixed address. it is UPDATED in place, never deleted first: if the run is cancelled half way (a newer push cancels the run) the release is still there, with old or new files
if [ "$failed" -eq 0 ]; then
    LATEST_TITLE="Verdandi for Windows: the newest build ($VERSION, $SHORT)"
    ASSETS=("$WORK/$NAME" "$WORK/Verdandi-windows-latest.zip" "$WORK/Verdandi-windows-latest.zip.sha256" "$WORK/BUILD.txt" "$WORK/$OLDNAME" "$WORK/$OLDNAME.sha256")
    if "$GH" release view windows-latest --repo "$REPO" > /dev/null 2>&1; then
        # the new files go on first (replacing the ones with the same names); only then is anything of an older build removed
        "$GH" release upload windows-latest "${ASSETS[@]}" --repo "$REPO" --clobber
        # the tag moves to this commit
        if [ "$REF_BLOCKED" -eq 0 ]; then
            "$GH" api -X PATCH "repos/$REPO/git/refs/tags/windows-latest" -f sha="$SHA" -F force=true > /dev/null
        else
            printf '\n> **Note:** GitHub did not let the workflow move the tag `windows-latest` to this build (a tag at a commit that changes workflow files needs a permission the workflow token cannot have). The files above ARE this build (version %s, commit %s).\n' "$VERSION" "$SHORT" >> "$WORK/notes.md"
        fi
        # M30/M31: this job only ever adds or replaces. the one kind of file it removes: the versioned copy of an OLDER build of the zip (Verdandi-windows-<version>-<hash>.zip, replaced by the new one).
        # the versioned ASIO zips of earlier builds, the fixed names, BUILD.txt and every other file stay
        "$GH" release view windows-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null | while read -r asset; do
            case "$asset" in
                "$NAME") ;;
                Verdandi-windows-asio-*) ;;
                Verdandi-windows-[0-9]*.zip) "$GH" release delete-asset windows-latest "$asset" --repo "$REPO" --yes || true ;;
                *) ;;
            esac
        done
        "$GH" release edit windows-latest --repo "$REPO" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest
    else
        "$GH" release create windows-latest "${ASSETS[@]}" --repo "$REPO" --target "$SHA" --title "$LATEST_TITLE" --notes-file "$WORK/notes.md" --latest
    fi
    echo "published windows-latest"
    # M30: the release must end with the zip, its SHA-256 file and BUILD.txt, whatever happened: look at the release itself, not at what this script meant to upload. M31: and the transition copy and its SHA-256
    GOT="$("$GH" release view windows-latest --repo "$REPO" --json assets --jq '.assets[].name' 2> /dev/null || true)"
    missing=""
    for need in Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 "$NAME" "$OLDNAME" "$OLDNAME.sha256" BUILD.txt; do
        printf '%s\n' "$GOT" | grep -qx "$need" || missing="$missing $need"
    done
    if [ -n "$missing" ]; then
        echo "ERROR: the release windows-latest is missing:$missing (it has: $(printf '%s' "$GOT" | tr '\n' ' '))"
        PUBLISH_INCOMPLETE=1
    else
        echo "windows-latest has the zip, its versioned copy, the transition copy, both SHA-256 files and BUILD.txt"
    fi
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
exit "${PUBLISH_INCOMPLETE:-0}"
