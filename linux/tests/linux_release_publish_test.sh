#!/usr/bin/env bash
# linux/tests/linux_release_publish_test.sh (docs/port/phase-m36.md): linux/ci/publish-release.sh and release-notes.sh with a stand-in for gh: which releases are made with which assets and tags, that linux-latest is
# updated in place and only ever gets its own files added or replaced (the M30 rule), that the release is read back and the publish FAILS with the names when a file is missing, the 403 on the per-commit tag,
# that old per-commit releases are removed, that no call ever names a windows release, that the version in the package, in BUILD.txt and in the file names agree.
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
command -v dpkg-deb > /dev/null || { echo "SKIP linux_release_publish_test: no dpkg-deb"; exit 77; }

cat > "$T/gh" <<'S'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
if [ "$1 $2" = "release view" ]; then
    case " $* " in
        *" --json "*) # the assets of the release: GH_ASSETS (a file, one name per line) or, by default, a complete release of an old build
            if [ -n "${GH_ASSETS:-}" ]; then cat "$GH_ASSETS"; else printf '%s\n' Verdandi-linux-0.10.20-0000000.deb Verdandi-linux-0.10.21-4c82066.deb Verdandi-linux-latest.deb Verdandi-linux-latest.deb.sha256 BUILD.txt; fi; exit 0 ;;
        *) [ -n "${LATEST_EXISTS:-}" ] && exit 0 || exit 1 ;;
    esac
fi
if [ "$1 $2" = "release edit" ]; then prev=""; for a in "$@"; do [ "$prev" = "--notes-file" ] && cp "$a" "$GH_NOTES_OUT"; prev="$a"; done; fi
if [ -n "${GH_FAIL_TAGS:-}" ]; then
    case "$1 $2" in "release create") echo "HTTP 403: Resource not accessible by integration"; exit 1 ;; esac
    case " $* " in *" git/refs/tags/linux-latest "*) echo "HTTP 403"; exit 1 ;; esac
fi
if [ "$1 $2" = "release list" ]; then
    for i in $(seq 1 13); do printf '2026-11-%02dT10:00:00Z linux-%07x\n' "$i" "$((0xabc000 + i))"; done
fi
exit 0
S
chmod +x "$T/gh"

# a small real .deb with /opt/verdandi/BUILD.txt
mk_deb() { # file version upstream hash
    rm -rf "$T/d"; mkdir -p "$T/d/DEBIAN" "$T/d/opt/verdandi"
    printf 'Package: verdandi\nVersion: %s\nArchitecture: amd64\nMaintainer: t <t@localhost.invalid>\nDescription: test\n' "$2" > "$T/d/DEBIAN/control"
    printf '%s %s\npackage %s\n' "$3" "$4" "$2" > "$T/d/opt/verdandi/BUILD.txt"
    head -c 100000 /dev/zero > "$T/d/opt/verdandi/blob"
    dpkg-deb --build --root-owner-group "$T/d" "$1" > /dev/null
}
SHA="4c8206661c6a97eacdd2b66a1c506aa43fd0d943"
mk_deb "$T/verdandi.deb" 0.10.21-57 0.10.21 4c82066
run() { LATEST_EXISTS="${LATEST_EXISTS:-}" GH_NOTES_OUT="$T/notes-given.md" GH="$T/gh" GH_LOG="$T/gh.log" GITHUB_SHA="$SHA" GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID=77 DEB="${DEB:-$T/verdandi.deb}" KEEP=10 TESTS="- install: ok" COMMIT_MESSAGE="Linux: a test commit" \
    bash linux/ci/publish-release.sh > "$T/out.txt" 2>&1; }

echo "== linux-latest does not exist yet"
: > "$T/gh.log"; run; rc=$?
ck "it ends well" "[ $rc -eq 0 ]"
ck "the release of the commit is made: tag linux-4c82066, the versioned .deb, the commit as target, a prerelease" "grep -q 'release create linux-4c82066 .*Verdandi-linux-0.10.21-4c82066.deb .*--target $SHA' '$T/gh.log' && grep 'release create linux-4c82066' '$T/gh.log' | grep -q -- '--prerelease'"
ck "linux-latest is made with the versioned .deb, the fixed .deb, its SHA-256 and BUILD.txt, and it is NOT marked as the latest release of the repository (that stays with the Windows page)" "grep 'release create linux-latest ' '$T/gh.log' | grep -q 'Verdandi-linux-0.10.21-4c82066.deb' && grep 'release create linux-latest ' '$T/gh.log' | grep -q 'Verdandi-linux-latest.deb ' && grep 'release create linux-latest ' '$T/gh.log' | grep -q 'Verdandi-linux-latest.deb.sha256' && grep 'release create linux-latest ' '$T/gh.log' | grep -q 'BUILD.txt' && grep 'release create linux-latest ' '$T/gh.log' | grep -q -- '--latest=false'"
ck "it says what linux-latest has" "grep -q 'linux-latest has the .deb, its SHA-256 file, BUILD.txt and the versioned copy' '$T/out.txt'"
ck "no call ever names a windows release or tag" "! grep -qi 'windows' '$T/gh.log'"
ck "a rerun replaces: the release of the commit is deleted before it is made" "grep -q 'release delete linux-4c82066' '$T/gh.log'"
ck "the oldest per-commit releases beyond 10 are removed (3 of 13), nothing else" "[ \$(grep -c 'release delete linux-0abc00[123] ' '$T/gh.log') -eq 3 ] && [ \$(grep -c 'release delete linux-0abc0' '$T/gh.log') -eq 3 ]"

echo "== linux-latest exists: updated in place, never deleted"
: > "$T/gh.log"; LATEST_EXISTS=1 run; rc=$?
ck "the files are uploaded over the old ones (--clobber)" "grep -q 'release upload linux-latest .*--clobber' '$T/gh.log'"
ck "the tag linux-latest is moved to the commit (API, force)" "grep -q 'api -X PATCH repos/owner/repo/git/refs/tags/linux-latest -f sha=$SHA -F force=true' '$T/gh.log'"
ck "the versioned .deb of the older build is removed, the fixed names and BUILD.txt stay" "grep -q 'release delete-asset linux-latest Verdandi-linux-0.10.20-0000000.deb' '$T/gh.log' && ! grep -q 'delete-asset linux-latest BUILD.txt' '$T/gh.log' && ! grep -q 'delete-asset linux-latest Verdandi-linux-latest' '$T/gh.log'"
ck "the release is never deleted or made again" "! grep -q 'release delete linux-latest' '$T/gh.log' && ! grep -q 'release create linux-latest' '$T/gh.log'"
ck "title and notes are updated, and it is not made the latest release of the repository" "grep -q 'release edit linux-latest .*--notes-file .*--latest=false' '$T/gh.log'"
ck "no call names a windows release" "! grep -qi 'windows' '$T/gh.log'"
echo "== M30: a file on the release that is not ours is never deleted"
printf '%s\n' Verdandi-linux-0.10.20-0000000.deb Verdandi-linux-latest.deb Verdandi-linux-latest.deb.sha256 BUILD.txt notes-by-the-owner.txt Verdandi-windows-latest.zip > "$T/assets-foreign.txt"
: > "$T/gh.log"; GH_ASSETS="$T/assets-foreign.txt" LATEST_EXISTS=1 run
ck "the other files stay (only the old versioned .deb goes)" "! grep -q 'delete-asset linux-latest notes-by-the-owner.txt' '$T/gh.log' && ! grep -q 'delete-asset linux-latest Verdandi-windows' '$T/gh.log' && grep -q 'delete-asset linux-latest Verdandi-linux-0.10.20-0000000.deb' '$T/gh.log'"

echo "== the notes"
VERSION=0.10.21 PACKAGE_VERSION=0.10.21-57 SHORT=4c82066 SHA="$SHA" RUN_URL="https://github.com/owner/repo/actions/runs/77" REPO=owner/repo TESTS="- install ok" COMMIT_MESSAGE="Linux: a test commit message" bash linux/ci/release-notes.sh > "$T/notes.md"
ck "the notes name the version and the build" "grep -q '^# Verdandi Linux 0.10.21 (4c82066)' '$T/notes.md'"
ck "the notes say what to download, to double-click it, that ~/Verdandi is not touched, and to close Verdandi first" "grep -q 'Verdandi-linux-latest.deb' '$T/notes.md' && grep -q 'Double-click' '$T/notes.md' && grep -q '~/Verdandi' '$T/notes.md' && grep -q 'Close Verdandi' '$T/notes.md'"
ck "the notes hold the commit message, the checks and the package version" "grep -q '> Linux: a test commit message' '$T/notes.md' && grep -q 'install ok' '$T/notes.md' && grep -q '0.10.21-57' '$T/notes.md'"
ck "the notes say what is not covered (other systems, the unsigned file, the real Mint installer)" "grep -q 'Ubuntu 22.04' '$T/notes.md' && grep -q 'not signed' '$T/notes.md' && grep -q 'Linux Mint desktop' '$T/notes.md'"

echo "== M30: the release must be complete afterwards"
printf '%s\n' Verdandi-linux-latest.deb BUILD.txt > "$T/assets-nosha.txt"
: > "$T/gh.log"; GH_ASSETS="$T/assets-nosha.txt" LATEST_EXISTS=1 run; rc=$?
ck "a release without the .sha256 and the versioned copy fails the publish and names them" "[ $rc -ne 0 ] && grep -q 'linux-latest is missing: Verdandi-linux-latest.deb.sha256 Verdandi-linux-0.10.21-4c82066.deb' '$T/out.txt'"
printf '%s\n' Verdandi-linux-latest.deb.sha256 BUILD.txt "Verdandi-linux-0.10.21-4c82066.deb" > "$T/assets-nodeb.txt"
: > "$T/gh.log"; GH_ASSETS="$T/assets-nodeb.txt" LATEST_EXISTS=1 run; rc=$?
ck "a release without the fixed .deb fails and names it" "[ $rc -ne 0 ] && grep -q 'linux-latest is missing: Verdandi-linux-latest.deb ' '$T/out.txt'"

echo "== the version in the package, in BUILD.txt and in the names must agree"
mk_deb "$T/other.deb" 0.10.22-9 0.10.21 4c82066
: > "$T/gh.log"; DEB="$T/other.deb" run; rc=$?
ck "a package whose version does not start with the number in its BUILD.txt is refused, nothing is published" "[ $rc -ne 0 ] && grep -q 'does not start with the number in BUILD.txt' '$T/out.txt' && ! grep -q 'release create' '$T/gh.log'"
mk_deb "$T/other.deb" 0.10.21-57 0.10.21 abcdef0
: > "$T/gh.log"; DEB="$T/other.deb" run; rc=$?
ck "a package built from another commit than this run is refused" "[ $rc -ne 0 ] && grep -q 'was built from abcdef0, this run is 4c82066' '$T/out.txt' && ! grep -q 'release create' '$T/gh.log'"
: > "$T/gh.log"; DEB="$T/none.deb" run; rc=$?
ck "a missing .deb stops it with a message" "[ $rc -ne 0 ] && grep -q 'does not exist' '$T/out.txt'"

echo "== the token may not make or move a tag (403): no per-commit release, linux-latest is still updated in place and says so"
: > "$T/gh.log"; LATEST_EXISTS=1 GH_FAIL_TAGS=1 run; rc=$?
ck "the publish step does not fail" "[ $rc -eq 0 ]"
ck "the files of linux-latest were uploaded over the old ones" "grep -q 'release upload linux-latest' '$T/gh.log'"
ck "the tag was not moved, the notes were updated and say so" "! grep -q 'refs/tags/linux-latest' '$T/gh.log' && grep -q 'release edit linux-latest' '$T/gh.log' && grep -q 'did not let the workflow move the tag' '$T/notes-given.md'"
ck "the output says that the per-commit release was skipped" "grep -q 'per-commit release is skipped' '$T/out.txt'"
echo "== linux-latest does not exist and no tag can be made: that is a failure"
: > "$T/gh.log"; LATEST_EXISTS= GH_FAIL_TAGS=1 run; rc=$?
ck "it fails (nothing could be published)" "[ $rc -ne 0 ]"
exit $fail
