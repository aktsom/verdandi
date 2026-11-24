#!/usr/bin/env bash
# linux/tests/release_publish_test.sh: windows/ci/publish-release.sh and release-notes.sh with a stand-in for gh: which releases are made with which assets and tags, that windows-latest is replaced only when no
# check failed, that a rerun replaces the release of the commit, that old per-commit releases are removed, that the notes hold the commit message, the checks and the known limits.
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

cat > "$T/gh" <<'S'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
# what is uploaded is kept (to look at the bytes): every file argument of create and upload
case "$1 $2" in "release create" | "release upload") for a in "$@"; do [ -f "$a" ] && cp "$a" "$GH_UPLOADS/$(basename "$a")"; done ;; esac
# the files of windows-latest: GH_ASSETS (a file, one name per line: STATIC, uploads and removals do not change it) or, by default, GH_STATE: a file that starts as a release of an OLD build (the versioned zips of an old
# build, the fixed names, BUILD.txt and the old-name copy of the transition), that uploads add to and delete-asset takes from (GH_NO_DELETE=1: a removal that does not work)
if [ -z "${GH_ASSETS:-}" ] && [ -n "${GH_STATE:-}" ]; then
    case "$1 $2 $3" in
        "release upload windows-latest" | "release create windows-latest") for a in "$@"; do [ -f "$a" ] && basename "$a" >> "$GH_STATE"; done; sort -u "$GH_STATE" -o "$GH_STATE" ;;
        "release delete-asset windows-latest") [ -n "${GH_NO_DELETE:-}" ] || { grep -vx -- "$4" "$GH_STATE" > "$GH_STATE.new"; mv "$GH_STATE.new" "$GH_STATE"; } ;;
    esac
fi
if [ "$1 $2" = "release view" ]; then
    case " $* " in
        *" --json "*) if [ -n "${GH_ASSETS:-}" ]; then cat "$GH_ASSETS"; else cat "$GH_STATE"; fi ;;
        *) [ -n "${LATEST_EXISTS:-}" ] && exit 0 || exit 1 ;;
    esac
fi
if [ "$1 $2" = "release edit" ]; then # keep the notes that were given
    prev=""; for a in "$@"; do [ "$prev" = "--notes-file" ] && cp "$a" "$GH_NOTES_OUT"; prev="$a"; done
fi
if [ -n "${GH_FAIL_TAGS:-}" ]; then # a token that may not make or move a tag (HTTP 403)
    case "$1 $2" in "release create") echo "HTTP 403: Resource not accessible by integration"; exit 1 ;; esac
    case " $* " in *" git/refs/tags/windows-latest "*) echo "HTTP 403"; exit 1 ;; esac
fi
if [ "$1 $2" = "release list" ]; then
    # 23 releases of commits (the newest first does not matter: the script sorts) and windows-latest
    for i in $(seq 1 23); do printf '2026-11-%02dT10:00:00Z windows-%07x\n' "$i" "$((0xabc000 + i))"; done
    # (windows-latest is in the real list too; the --jq filter of the script drops it, like every tag that is not windows-<7 hex digits>)
fi
exit 0
S
chmod +x "$T/gh"
# gh with --jq prints the already filtered lines: the stand-in above prints them directly (two columns), as the script expects them from --jq

mkdir -p "$T/zip" "$T/status"
SHA="4c8206661c6a97eacdd2b66a1c506aa43fd0d943"
VERSION="$(head -n 1 windows/VERSION | tr -d '\r ')"
head -c 2000000 /dev/zero > "$T/zip/Verdandi-windows-latest.zip" # (M22: the build makes the zip with its STATIC name; the publish step makes the copy with the version)
echo PASS > "$T/status/m1-run.status"; echo PASS > "$T/status/m1-check-lua.status"; echo "SKIP no python" > "$T/status/m1-check-screen.status"

mkdir -p "$T/uploads"
printf '%s\n' Verdandi-windows-0.1.0-0000000.zip BUILD.txt Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 Verdandi-windows-asio-0.1.0-0000000.zip Verdandi-windows-asio-latest.zip Verdandi-windows-asio-latest.zip.sha256 > "$T/state-start.txt"
run() { cp "$T/state-start.txt" "$T/state.txt"; GH_STATE="$T/state.txt" GH_UPLOADS="$T/uploads" GH_NEWNAME="Verdandi-windows-$VERSION-4c82066.zip" LATEST_EXISTS="${LATEST_EXISTS:-}" GH_NOTES_OUT="$T/notes-given.md" GH="$T/gh" GH_LOG="$T/gh.log" GITHUB_SHA="$SHA" GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID=77 ZIP_DIR="$T/zip" STATUS_DIR="$T/status" KEEP=20 COMMIT_MESSAGE="Windows: a test commit message" \
    bash windows/ci/publish-release.sh > "$T/out.txt" 2>&1; }

echo "== all checks passed, windows-latest does not exist yet"
: > "$T/gh.log"; run; head -5 "$T/out.txt"
ck "the release of the commit is made with tag windows-4c82066, the zip and the commit as target" "grep -q 'release create windows-4c82066 .*Verdandi-windows-$VERSION-4c82066.zip .*--target $SHA' '$T/gh.log'"
ck "windows-latest is made (it did not exist)" "grep -q 'release create windows-latest ' '$T/gh.log' && ! grep -q 'release delete windows-latest' '$T/gh.log'"
ck "windows-latest holds the named zip, the fixed name, its SHA-256 and BUILD.txt" "grep 'release create windows-latest ' '$T/gh.log' | grep -q 'Verdandi-windows-$VERSION-4c82066.zip' && grep 'release create windows-latest ' '$T/gh.log' | grep -q 'Verdandi-windows-latest.zip ' && grep 'release create windows-latest ' '$T/gh.log' | grep -q 'Verdandi-windows-latest.zip.sha256' && grep 'release create windows-latest ' '$T/gh.log' | grep -q 'BUILD.txt'"
ck "the per-commit release is a prerelease, windows-latest is the latest" "grep 'release create windows-4c82066' '$T/gh.log' | grep -q -- '--prerelease' && grep 'release create windows-latest' '$T/gh.log' | grep -q -- '--latest'"
ck "a rerun replaces: the release of the commit is deleted before it is made" "grep -n 'release delete windows-4c82066' '$T/gh.log' | head -1 | cut -d: -f1 | grep -q ."
ck "the oldest per-commit releases beyond 20 are removed, windows-latest and the newest are kept" "[ \$(grep -c 'release delete windows-0abc00[123] ' '$T/gh.log') -eq 3 ] && [ \$(grep -c 'release delete windows-0abc0' '$T/gh.log') -eq 3 ]"
ck "nothing but the workflow token is used: no other token or login in the calls" "! grep -q -i 'token\\|auth login' '$T/gh.log'"
echo "== windows-latest exists: updated in place, never deleted"
: > "$T/gh.log"; LATEST_EXISTS=1 run
ck "the files are uploaded over the old ones (--clobber)" "grep -q 'release upload windows-latest .*--clobber' '$T/gh.log'"
ck "the tag windows-latest is moved to the commit (API, force)" "grep -q 'api -X PATCH repos/owner/repo/git/refs/tags/windows-latest -f sha=$SHA -F force=true' '$T/gh.log'"
ck "the file of the old build is removed from the release, the others stay" "grep -q 'release delete-asset windows-latest Verdandi-windows-0.1.0-0000000.zip' '$T/gh.log' && ! grep -q 'delete-asset windows-latest BUILD.txt' '$T/gh.log'"
ck "title and notes are updated, it is the latest" "grep -q 'release edit windows-latest .*--notes-file .*--latest' '$T/gh.log'"
ck "the release is never deleted (a cancelled run leaves it standing)" "! grep -q 'release delete windows-latest' '$T/gh.log' && ! grep -q 'release create windows-latest' '$T/gh.log'"
# the notes
NOTES_FILE="$(grep -o -- '--notes-file [^ ]*' "$T/gh.log" | head -1 | cut -d' ' -f2)"
echo "== the notes"
WORK_NOTES="$T/notes.md"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" RUN_URL="https://github.com/owner/repo/actions/runs/77" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="Windows: a test commit message" bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes name the version and the build" "grep -q '^# Verdandi for Windows $VERSION (4c82066)' '$WORK_NOTES'"
ck "the notes hold the commit message" "grep -q '> Windows: a test commit message' '$WORK_NOTES'"
ck "the notes list the checks that passed (2 passed, 0 failed, 1 skipped) and the skipped one" "grep -q '2 passed, 0 failed, 1 skipped' '$WORK_NOTES' && grep -q 'm1-check-lua' '$WORK_NOTES' && grep -q 'm1-check-screen (no python)' '$WORK_NOTES'"
ck "the notes hold the known limits and how to start" "grep -q 'ASIO' '$WORK_NOTES' && grep -q 'update-and-run.cmd' '$WORK_NOTES' && grep -q 'releases/tag/windows-latest' '$WORK_NOTES'"
: "$NOTES_FILE"

echo "== a check failed"
echo "FAIL 1" > "$T/status/m1-check-keyboard.status"
: > "$T/gh.log"; run
ck "the release of the commit is still made" "grep -q 'release create windows-4c82066 ' '$T/gh.log'"
ck "windows-latest is NOT replaced (not deleted, not made)" "! grep -q 'windows-latest' '$T/gh.log'"
ck "it says so" "grep -q 'windows-latest is left as it was' '$T/out.txt'"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="x" bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes carry a warning that names the failed check" "grep -q 'WARNING: 1 check' '$WORK_NOTES' && grep -q 'm1-check-keyboard' '$WORK_NOTES'"

echo "== the cycle test is red: it blocks windows-latest like every other check (the list of non-blocking checks is empty by default)"
rm -f "$T/status/m1-check-keyboard.status"; echo "FAIL 1" > "$T/status/m2-check-cycles.status"
: > "$T/gh.log"; LATEST_EXISTS=1 run
ck "windows-latest is NOT updated when m2-check-cycles is red" "! grep -q 'windows-latest' '$T/gh.log' && grep -q 'windows-latest is left as it was' '$T/out.txt'"
ck "the notes carry the warning that names it" "grep -q 'WARNING: 1 check' '$T/notes_cycles.md' 2> /dev/null || { VERSION='$VERSION' SHORT=4c82066 SHA='$SHA' STATUS_DIR='$T/status' REPO=owner/repo COMMIT_MESSAGE=x bash windows/ci/release-notes.sh | grep -q 'WARNING: 1 check.*m2-check-cycles'; }"
echo "== a check can still be named as not blocking (the mechanism stays, for a new check's first runs)"
: > "$T/gh.log"; NONBLOCKING_CHECKS="m2-check-cycles" LATEST_EXISTS=1 run
ck "windows-latest is updated although the named check is red" "grep -q 'release upload windows-latest' '$T/gh.log' && grep -q 'check m2-check-cycles is red, but it is on the list' '$T/out.txt'"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="x" NONBLOCKING_CHECKS="m2-check-cycles" bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes name it as a known red check that does not hold the build back" "grep -q 'Known red check, not holding this build back' '$WORK_NOTES' && ! grep -q 'WARNING' '$WORK_NOTES'"
echo "== another check fails together with the named one: windows-latest is NOT updated"
echo "FAIL 1" > "$T/status/m1-check-keyboard.status"
: > "$T/gh.log"; NONBLOCKING_CHECKS="m2-check-cycles" LATEST_EXISTS=1 run
ck "a blocking red check still holds windows-latest back" "! grep -q 'windows-latest' '$T/gh.log'"
rm -f "$T/status/m1-check-keyboard.status" "$T/status/m2-check-cycles.status"

echo "== M31/M31b: one zip; the old-name copy is no longer made and is retired from windows-latest, explicitly"
rm -rf "$T/uploads"; mkdir -p "$T/uploads"
: > "$T/gh.log"; LATEST_EXISTS=1 run; rc=$?
ck "it ends well and says that the old-name copy is gone" "[ $rc -eq 0 ] && grep -q 'windows-latest has the zip, its versioned copy, its SHA-256 file and BUILD.txt; the old-name copy is gone' '$T/out.txt'"
ck "windows-latest gets the one zip, its versioned copy, its SHA-256 and BUILD.txt" "u=\$(grep 'release upload windows-latest' '$T/gh.log'); for f in Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 Verdandi-windows-$VERSION-4c82066.zip BUILD.txt; do case \"\$u\" in *\"\$f\"*) ;; *) exit 1;; esac; done"
ck "NO copy under the old name is made or uploaded (nothing is sent to GitHub under Verdandi-windows-asio-latest*)" "! ls '$T/uploads' | grep -q 'asio-latest' && ! grep -E 'release (create|upload) ' '$T/gh.log' | grep -q 'asio-latest'"
ck "the SHA-256 file of the one zip is right" "(cd '$T/uploads' && sha256sum -c Verdandi-windows-latest.zip.sha256) > '$T/sha.txt' 2>&1 && grep -q 'OK' '$T/sha.txt'"
ck "the per-commit release has the one zip only" "grep 'release create windows-4c82066 ' '$T/gh.log' | grep -q 'Verdandi-windows-$VERSION-4c82066.zip' && ! grep 'release create windows-4c82066 ' '$T/gh.log' | grep -q 'asio'"
ck "the two old-name files ARE removed from windows-latest, each by its exact name" "grep -q 'release delete-asset windows-latest Verdandi-windows-asio-latest.zip --repo owner/repo --yes' '$T/gh.log' && grep -q 'release delete-asset windows-latest Verdandi-windows-asio-latest.zip.sha256 --repo owner/repo --yes' '$T/gh.log'"
ck "the removal comes AFTER the upload of the new files (a working zip is on the release first)" "u=\$(grep -n 'release upload windows-latest' '$T/gh.log' | head -1 | cut -d: -f1); d=\$(grep -n 'delete-asset windows-latest Verdandi-windows-asio-latest.zip ' '$T/gh.log' | head -1 | cut -d: -f1); [ -n \"\$u\" ] && [ -n \"\$d\" ] && [ \$u -lt \$d ]"
ck "nothing else is removed: the versioned ASIO zip of the earlier build, the fixed names and BUILD.txt stay; only the versioned zip of the OLD build of the one zip is replaced (M30)" "[ \$(grep -c 'delete-asset windows-latest' '$T/gh.log') -eq 3 ] && grep -q 'delete-asset windows-latest Verdandi-windows-0.1.0-0000000.zip' '$T/gh.log' && ! grep -q 'delete-asset windows-latest Verdandi-windows-asio-0.1.0' '$T/gh.log' && ! grep -q 'delete-asset windows-latest BUILD.txt' '$T/gh.log' && ! grep -q 'delete-asset windows-latest Verdandi-windows-latest' '$T/gh.log'"
ck "the release ends with exactly: the one zip, its SHA-256, BUILD.txt, the versioned copy and the earlier ASIO versioned zip" "[ \"\$(sort '$T/state.txt' | tr '\n' ' ')\" = \"BUILD.txt Verdandi-windows-$VERSION-4c82066.zip Verdandi-windows-asio-0.1.0-0000000.zip Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 \" ]"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="x" bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes say there is ONE zip and that the old name is gone (no 'Transition' that promises it)" "grep -q 'ONE zip' '$WORK_NOTES' && grep -q 'The old name is gone' '$WORK_NOTES' && ! grep -q 'SAME file again' '$WORK_NOTES' && ! grep -q 'Two zips' '$WORK_NOTES'"
echo "== run again when the old names are already gone: nothing to remove, nothing removed by mistake"
printf '%s\n' Verdandi-windows-0.1.0-0000000.zip BUILD.txt Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 Verdandi-windows-asio-0.1.0-0000000.zip > "$T/state-start2.txt"
cp "$T/state-start.txt" "$T/state-start.keep"; cp "$T/state-start2.txt" "$T/state-start.txt"
: > "$T/gh.log"; LATEST_EXISTS=1 run; rc=$?
cp "$T/state-start.keep" "$T/state-start.txt"
ck "it ends well and removes no old-name file (there is none)" "[ $rc -eq 0 ] && ! grep -q 'delete-asset windows-latest Verdandi-windows-asio-latest' '$T/gh.log' && ! grep -q 'retiring' '$T/out.txt'"
echo "== a file of the release that is not ours is never deleted (M30)"
printf '%s\n' Verdandi-windows-0.1.0-0000000.zip BUILD.txt Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256 Verdandi-windows-asio-latest.zip Verdandi-windows-asio-latest.zip.sha256 "Verdandi-windows-$VERSION-4c82066.zip" notes-by-the-owner.txt > "$T/assets-foreign.txt"
: > "$T/gh.log"; GH_ASSETS="$T/assets-foreign.txt" LATEST_EXISTS=1 run
ck "the other files stay (the retired two are asked for by name; the static list stands in for the release)" "! grep -q 'delete-asset windows-latest notes-by-the-owner.txt' '$T/gh.log' && ! grep -q 'delete-asset windows-latest Verdandi-windows-asio-0' '$T/gh.log'"
echo "== M30/M31: the release must be complete afterwards: the publish step FAILS and names the files, and nothing is retired from an incomplete release"
printf '%s\n' Verdandi-windows-0.1.0-0000000.zip BUILD.txt "Verdandi-windows-$VERSION-4c82066.zip" Verdandi-windows-asio-latest.zip Verdandi-windows-asio-latest.zip.sha256 > "$T/assets-no-default.txt"
: > "$T/gh.log"; GH_ASSETS="$T/assets-no-default.txt" LATEST_EXISTS=1 run; rc=$?
ck "a release without the one zip fails and names it" "[ $rc -ne 0 ] && grep -q 'windows-latest is missing: Verdandi-windows-latest.zip Verdandi-windows-latest.zip.sha256' '$T/out.txt'"
ck "and the old-name files are NOT removed from it (no moment without a working zip)" "! grep -q 'delete-asset windows-latest Verdandi-windows-asio-latest' '$T/gh.log' && grep -q 'nothing is retired from it' '$T/out.txt'"
echo "== a removal that does not work: the step fails and names the file"
: > "$T/gh.log"; GH_NO_DELETE=1 LATEST_EXISTS=1 run; rc=$?
ck "the step fails" "[ $rc -ne 0 ]"
ck "it names the retired files that are still there" "grep -q 'still has the retired file Verdandi-windows-asio-latest.zip' '$T/out.txt' && grep -q 'still has the retired file Verdandi-windows-asio-latest.zip.sha256' '$T/out.txt'"
echo "== the zip is missing"
rm -f "$T/zip/"*.zip
run; rc=$?
ck "it stops with a message that names the missing zip" "[ $rc -ne 0 ] && grep -q 'is not in' '$T/out.txt'"
head -c 2000000 /dev/zero > "$T/zip/Verdandi-windows-latest.zip"
echo "== the token may not make or move a tag (403): no per-commit release, windows-latest is still updated in place, and says so"
: > "$T/gh.log"; LATEST_EXISTS=1 GH_FAIL_TAGS=1 run; rc=$?
ck "the publish step does not fail" "[ $rc -eq 0 ]"
ck "the files of windows-latest were uploaded over the old ones" "grep -q 'release upload windows-latest' '$T/gh.log'"
ck "the tag of windows-latest was not moved (no API call for it that succeeds is needed), and the title and notes were updated" "! grep -q 'refs/tags/windows-latest' '$T/gh.log' && grep -q 'release edit windows-latest' '$T/gh.log'"
ck "the notes say that the tag was not moved" "grep -q 'did not let the workflow move the tag' '$T/notes-given.md'"
ck "the output says that the per-commit release was skipped" "grep -q 'per-commit release is skipped' '$T/out.txt'"
echo "== windows-latest does not exist and no tag can be made: that is a failure"
: > "$T/gh.log"; LATEST_EXISTS= GH_FAIL_TAGS=1 run; rc=$?
ck "it fails (nothing could be published)" "[ $rc -ne 0 ]"
exit $fail
