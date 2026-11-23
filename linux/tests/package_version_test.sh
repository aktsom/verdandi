#!/bin/bash
# the .deb version (docs/port/phase-m36.md): <the Windows number, first line of windows/VERSION>-<commit count>. it must be newer than every package built before (0.1~git<date>.<count>.<hash>, no epoch),
# go up with every commit (also under the same Windows number, and when the Windows number goes up), be the same twice for one commit, and start with the real windows/VERSION of this repository.
# uses throw-away git repos, not this one's history.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/../package.sh"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cd "$W"
git init -q r && cd r
git config user.email t@localhost.invalid && git config user.name t
echo 0.10.21 > "$W/VERSION"
vers=()
commit() { # <iso date>
    echo "$RANDOM" >>f
    git add f
    GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q -m c
    vers+=("$(PACKAGE_VERSION_FILE="$W/VERSION" PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)")
}
commit "2026-01-05T10:00:00Z"
commit "2026-01-05T11:00:00Z"
commit "2026-01-06T09:00:00Z"
echo 0.10.22 > "$W/VERSION"
commit "2026-03-01T09:00:00Z"
for v in "${vers[@]}"; do
    echo "version: $v"
done
case "${vers[0]}" in 0.10.21-[0-9]*) ;; *) bad "unexpected form: ${vers[0]}" ;; esac
case "${vers[3]}" in 0.10.22-[0-9]*) ;; *) bad "after the Windows number went up: ${vers[3]}" ;; esac
for ((i = 1; i < ${#vers[@]}; i++)); do
    dpkg --compare-versions "${vers[i]}" gt "${vers[i-1]}" || bad "${vers[i]} is not newer than ${vers[i-1]}"
done
# the same commit twice: the same version
a="$(PACKAGE_VERSION_FILE="$W/VERSION" PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)"
b="$(PACKAGE_VERSION_FILE="$W/VERSION" PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)"
[ "$a" = "$b" ] || bad "two runs on one commit differ: $a $b"
[ "$a" = "${vers[-1]}" ] || bad "print-version differs from the version at commit time"
# the packages built before M36 (the owner's laptop has one of them): every one is older, with no epoch
for old in 0.1~git20260106.4.8317553 0.1~git20260301.5.c3917be 0.1~git20261122.55.985caf98 0.1~git20301231.9999.fffffff; do
    for v in "${vers[@]}"; do
        dpkg --compare-versions "$v" gt "$old" || bad "$v is not newer than the old package $old"
    done
done
# an "older" test package made with PACKAGE_REVISION is older than the build it is upgraded to
o="$(PACKAGE_REVISION=1 PACKAGE_VERSION_FILE="$W/VERSION" PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)"
[ "$o" = 0.10.22-1 ] && dpkg --compare-versions "$a" gt "$o" || bad "PACKAGE_REVISION: $o"
# this repository: the version starts with the real windows/VERSION
want="$(head -n 1 "$HERE/../../windows/VERSION" | tr -d '\r ')"
real="$(bash "$PKG" print-version)"
case "$real" in "$want"-[0-9]*) echo "this repository: $real" ;; *) bad "print-version is $real, windows/VERSION is $want" ;; esac
[ $fail -eq 0 ] && echo "package_version_test: all passed"
exit $fail
