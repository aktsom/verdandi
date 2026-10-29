#!/bin/bash
# `verdandi tidy flatten` (docs/port/clean-layout.md section 7), the DRY RUN: it reports what is in a nested home and changes NOTHING (every path, size, mode,
# time and content hash is the same before and after). a fixture home with the things that matter: user data, links into the nested folder, an outer leftover,
# a name on both sides, a settings file with the old path. the real move (--apply) is not built and must refuse.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }

H="$T/user/Verdandi"
N="$H/Verdandi"
mkdir -p "$N/dust/code/ascript" "$N/dust/audio/mac" "$N/dust/data/ascript" "$N/.config/SuperCollider" "$H/dust/code" "$H/.config/SuperCollider" "$H/.local"
echo "print('hi')" > "$N/dust/code/ascript/ascript.lua"
head -c 5000 /dev/urandom > "$N/dust/audio/sample.wav"
ln -s "$N/dust/audio/sample.wav" "$N/dust/audio/mac/sample.wav"
ln -s /nonexistent/elsewhere.wav "$N/dust/audio/mac/elsewhere.wav"
echo "return {}" > "$N/dust/data/ascript/ascript-01.pset"
printf 'includePaths:\n  - "%s/dust"\n' "$N" > "$N/.config/SuperCollider/sclang_conf.yaml"
ln -s /opt/verdandi "$N/norns"
ln -s /opt/verdandi "$H/norns"
echo "rate=48000" > "$N/audio.conf"
echo "x" > "$H/launcher.log"
echo "same" > "$H/version.txt"; echo "same" > "$N/version.txt"
echo "outer" > "$H/matronrc.lua"; echo "nested" > "$N/matronrc.lua"

snapshot() { (cd "$T" && find user -printf '%p %y %s %m %T@ %l\n' | sort; find user -type f -exec md5sum {} + | sort) ; }
snapshot > "$T/before"

OUT="$(HOME="$T/user" NORNS_INSTALLED=1 "$REPO/linux/tidy.sh" flatten 2>&1)"
rc=$?
echo "$OUT" | sed 's/^/        | /' | head -60
[ $rc -eq 0 ] && ok "exit status 0" || bad "exit status $rc"

snapshot > "$T/after"
cmp -s "$T/before" "$T/after" && ok "the dry run changed nothing (paths, sizes, modes, times, content hashes)" || { bad "the dry run changed something"; diff "$T/before" "$T/after" | head; }

has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
has "DRY RUN" && ok "says it is a dry run" || bad "no DRY RUN line"
has "nested home: $N" && ok "names the nested home" || bad "nested home not named"
has "dust/ (yours): 5 files and links" && ok "counts the user's files and links in dust/ (3 files, 2 links)" || bad "dust file count"
has "scripts 1, audio files 1, data files 1" && ok "counts scripts, audio, data" || bad "scripts/audio/data counts"
has "dust/audio/mac/sample.wav" && has "points into the nested folder" && ok "reports the link that points into the nested folder" || bad "link into the nested folder not reported"
has "2 link(s) point elsewhere" && ok "counts the links that point elsewhere (the norns link and one other)" || bad "link elsewhere count"
has "already broken" && ok "counts broken links" || bad "broken links"
has ".config/SuperCollider/sclang_conf.yaml" && has "sclang_conf.yaml.old" && ok "reports the settings file with the old path and what happens to it" || bad "settings file with the old path"
has "launcher.log" && ok "lists the outer leftovers" || bad "outer leftovers"
has "version.txt: identical" && ok "a name on both sides with the same content is called identical" || bad "identical name"
has "matronrc.lua: different" && ok "a name on both sides with other content is called different" || bad "different name"
has "norns: identical (the same link)" && ok "the same link on both sides is identical" || bad "same link"
has "same file system" && ok "checks the file system" || bad "file system check"
has "RESULT ready" && ok "result: ready" || bad "no RESULT ready"
has "nothing happens before that" && ok "says nothing happens before the owner answers" || bad "no confirmation sentence"

# the same through the launcher's entry point
OUT2="$(HOME="$T/user" NORNS_INSTALLED=1 "$REPO/linux/norns.sh" tidy flatten 2>&1)"
[ "$OUT" = "$OUT2" ] && ok "linux/norns.sh tidy flatten gives the same" || bad "norns.sh tidy differs"
snapshot > "$T/after2"; cmp -s "$T/before" "$T/after2" && ok "still nothing changed" || bad "changed by the second run"

# --apply refuses: the real move is not built
OUT3="$(HOME="$T/user" NORNS_INSTALLED=1 "$REPO/linux/tidy.sh" flatten --apply 2>&1)"; rc3=$?
[ $rc3 -ne 0 ] && printf '%s' "$OUT3" | grep -q "not built yet" && ok "--apply refuses (not built)" || bad "--apply did not refuse"
snapshot > "$T/after3"; cmp -s "$T/before" "$T/after3" && ok "the refusal changed nothing" || bad "changed by --apply"

# a home that is not nested
mkdir -p "$T/flat/Verdandi/dust"
OUT4="$(HOME="$T/flat" NORNS_INSTALLED=1 "$REPO/linux/tidy.sh" flatten 2>&1)"
printf '%s' "$OUT4" | grep -q "RESULT nothing-to-do" && ok "a home that is not nested: nothing to do" || bad "flat home"
# a folder called Verdandi that is not a norns home is left alone
mkdir -p "$T/odd/Verdandi/Verdandi/docs"
OUT5="$(HOME="$T/odd" NORNS_INSTALLED=1 "$REPO/linux/tidy.sh" flatten 2>&1)"
printf '%s' "$OUT5" | grep -q "does not look like a norns home" && ok "an unrelated Verdandi folder is left alone" || bad "odd folder"

[ $FAIL -eq 0 ] && echo "tidy_flatten_test: all passed"
exit $FAIL
