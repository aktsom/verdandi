#!/bin/bash
# the .deb version must go up with every commit (dpkg --compare-versions), also across a date and when two commits share a day;
# the same commit gives the same version (reproducible). uses throw-away git repos, not this one's history.
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
vers=()
commit() { # <iso date>
    echo "$RANDOM" >>f
    git add f
    GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q -m c
    vers+=("$(PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)")
}
# three commits on one day (hashes are random, so any order of the hash letters must not matter), then two later days
commit "2026-01-05T10:00:00Z"
commit "2026-01-05T11:00:00Z"
commit "2026-01-05T12:00:00Z"
commit "2026-01-06T09:00:00Z"
commit "2026-03-01T09:00:00Z"
for v in "${vers[@]}"; do
    echo "version: $v"
    case "$v" in 0.1~git[0-9]*.[0-9]*.*) ;; *) bad "unexpected form: $v" ;; esac
done
for ((i = 1; i < ${#vers[@]}; i++)); do
    dpkg --compare-versions "${vers[i]}" gt "${vers[i-1]}" || bad "${vers[i]} is not newer than ${vers[i-1]}"
done
# the same commit twice: the same version
a="$(PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)"
b="$(PACKAGE_GIT_REPO="$W/r" bash "$PKG" print-version)"
[ "$a" = "$b" ] || bad "two runs on one commit differ: $a $b"
[ "$a" = "${vers[-1]}" ] || bad "print-version differs from the version at commit time"
# a valid debian version, and the development tilde sorts before a 0.1 release
dpkg --compare-versions "$a" lt "0.1" || bad "$a should sort before 0.1"
[ $fail -eq 0 ] && echo "package_version_test: all passed"
exit $fail
