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
if [ "$1 $2" = "release view" ]; then
    case " $* " in
        *" --json "*) echo "Verdandi-windows-0.1.0-0000000.zip"; echo "BUILD.txt"; echo "Verdandi-windows-latest.zip" ;; # (the assets of the old build)
        *) [ -n "${LATEST_EXISTS:-}" ] && exit 0 || exit 1 ;;
    esac
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
head -c 2000000 /dev/zero > "$T/zip/Verdandi-windows-$VERSION-4c82066.zip"
echo PASS > "$T/status/m1-run.status"; echo PASS > "$T/status/m1-check-lua.status"; echo "SKIP no python" > "$T/status/m1-check-screen.status"

run() { LATEST_EXISTS="${LATEST_EXISTS:-}" GH="$T/gh" GH_LOG="$T/gh.log" GITHUB_SHA="$SHA" GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID=77 ZIP_DIR="$T/zip" STATUS_DIR="$T/status" KEEP=20 COMMIT_MESSAGE="Windows: a test commit message" \
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

echo "== the ASIO build is part of the run"
mkdir -p "$T/asiozip"; head -c 2500000 /dev/zero > "$T/asiozip/Verdandi-windows-asio-$VERSION-4c82066.zip"
: > "$T/gh.log"; ASIO_ZIP_DIR="$T/asiozip" LATEST_EXISTS=1 run
ck "the per-commit release has both zips" "grep 'release create windows-4c82066 ' '$T/gh.log' | grep -q 'Verdandi-windows-$VERSION-4c82066.zip' && grep 'release create windows-4c82066 ' '$T/gh.log' | grep -q 'Verdandi-windows-asio-$VERSION-4c82066.zip'"
ck "windows-latest gets the ASIO zip, its fixed name and its SHA-256 too" "grep 'release upload windows-latest' '$T/gh.log' | grep -q 'Verdandi-windows-asio-latest.zip ' && grep 'release upload windows-latest' '$T/gh.log' | grep -q 'Verdandi-windows-asio-latest.zip.sha256'"
ck "the default zip (WASAPI only) is still the fixed Verdandi-windows-latest.zip" "grep 'release upload windows-latest' '$T/gh.log' | grep -q 'Verdandi-windows-latest.zip '"
ck "an ASIO zip of an older build in windows-latest is not removed while this run has one" "! grep -q 'delete-asset windows-latest Verdandi-windows-asio' '$T/gh.log'"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="x" HAVE_ASIO=1 bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes say which zip is the default and point to the ASIO notice" "grep -q 'WASAPI only, the default' '$WORK_NOTES' && grep -q 'ASIO-NOTICE.txt' '$WORK_NOTES'"
echo "== the ASIO build failed in this run: the release has the default zip only"
: > "$T/gh.log"; LATEST_EXISTS=1 run
ck "no ASIO zip is uploaded and the notes say so" "! grep -q 'asio' '$T/gh.log' && grep -q 'no ASIO build in this release' '$T/out.txt'"
VERSION="$VERSION" SHORT=4c82066 SHA="$SHA" STATUS_DIR="$T/status" REPO=owner/repo COMMIT_MESSAGE="x" bash windows/ci/release-notes.sh > "$WORK_NOTES"
ck "the notes say that this release has only the WASAPI zip" "grep -q 'only the WASAPI zip' '$WORK_NOTES'"
echo "== the zip is missing"
rm -f "$T/zip/"*.zip
run; rc=$?
ck "it stops with a message that names the missing zip" "[ $rc -ne 0 ] && grep -q 'is not in' '$T/out.txt'"
exit $fail
