#!/bin/bash
# `verdandi tidy flatten --apply` and `--undo` (docs/port/clean-layout.md section 7), on a scratch home built like a real nested one: a nested dust with scripts,
# audio files, data and links (one into the nested folder, one elsewhere, one broken), file names with spaces, a browser profile, the SuperCollider settings
# with the old path, an outer home with leftovers and a file that exists on both sides with different content.
# what it proves: nothing of norns running -> refused; the typed confirmation is needed; no file of the scratch dust/ is lost or changed (every file's content
# hash is the same, every path is the same), undo gives back exactly the first state, an interrupted run (killed) is undone by --undo, a signal and a failed
# check roll back by themselves. the tool is never pointed at anything but the scratch home.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TIDY="$REPO/linux/tidy.sh"
T="$(mktemp -d)"
trap 'chmod -R u+rwX "${T:?}" 2>/dev/null; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }

if pgrep -x "norns|sclang|scsynth|jackd|maiden" > /dev/null 2>&1 || [ -n "$(pgrep -x norns; pgrep -x sclang; pgrep -x scsynth; pgrep -x jackd; pgrep -x maiden)" ]; then
    echo "SKIP: norns, sclang, scsynth, jackd or maiden is running on this machine (the tool refuses to run then, which is what it should do)"
    exit 0
fi

# ---- the fixture ----
make_fixture() { # dir
    local U="$1" H="$1/user/Verdandi" N="$1/user/Verdandi/Verdandi"
    rm -rf "${U:?}/user" "${U:?}/elsewhere"
    mkdir -p "$N/dust/code/my script" "$N/dust/code/other" "$N/dust/audio/mac" "$N/dust/audio/tape" "$N/dust/data/my script" \
        "$N/.config/SuperCollider" "$N/.config/mozilla/firefox/profile.default" "$N/logs" "$H/dust/code" "$H/dust/audio" "$H/.config" "$H/.local" "$U/elsewhere"
    echo "print('hello')" > "$N/dust/code/my script/my script.lua"
    echo "engine.name='x'" > "$N/dust/code/other/other.lua"
    head -c 40000 /dev/urandom > "$N/dust/audio/my sample (1).wav"
    head -c 9000 /dev/urandom > "$N/dust/audio/tape/take 2.wav"
    head -c 3000 /dev/urandom > "$U/elsewhere/real.wav"
    ln -s "$N/dust/audio/my sample (1).wav" "$N/dust/audio/mac/into nested.wav" # points into the nested folder
    ln -s "$U/elsewhere/real.wav" "$N/dust/audio/mac/elsewhere.wav"            # points elsewhere
    ln -s "$U/elsewhere/gone.wav" "$N/dust/audio/mac/broken.wav"               # points to something that is not there
    echo "return {pset=1}" > "$N/dust/data/my script/my script-01.pset"
    printf '{"k":1}' > "$N/dust/data/my script/state with spaces.json"
    printf 'includePaths:\n    - "/opt/verdandi/sc/core"\n    - "%s/dust"\nexcludePaths:\n    []\n' "$N" > "$N/.config/SuperCollider/sclang_conf.yaml"
    echo "profile" > "$N/.config/mozilla/firefox/profile.default/prefs.js"
    ln -s /opt/verdandi "$N/norns"
    echo "rate=48000" > "$N/audio.conf"
    echo "brightness=1.0" > "$N/ui.conf"
    echo "nested matronrc" > "$N/matronrc.lua"
    echo "v1" > "$N/version.txt"
    echo "log of a run" > "$N/logs/norns.log"
    # the outer home: leftovers of a first run
    ln -s /opt/verdandi "$H/norns"
    echo "outer launcher" > "$H/launcher.log"
    echo "v1" > "$H/version.txt"
    echo "outer matronrc (different)" > "$H/matronrc.lua"
    echo "a leftover with spaces" > "$H/old note.txt"
    : > "$H/crash-report.txt"
    touch -d '2026-01-02 03:04:05' "$N/dust/code/my script/my script.lua" "$N/dust/audio/tape/take 2.wav"
}

# paths, types, sizes, modes, link targets and (for files) times and content hashes: everything but the backups/flatten-* folders and directory times
snapshot() { # dir -> stdout
    (cd "$1" && { find user \( -path 'user/Verdandi/backups' \) -prune -o -type d -printf '%p\td\t0\t%m\t\n'; find user \( -path 'user/Verdandi/backups' \) -prune -o ! -type d -printf '%p\t%y\t%s\t%m\t%l\n'; } | sort
     find user \( -path 'user/Verdandi/backups' \) -prune -o -type f -printf '%p\t%T@\n' | sort
     find user \( -path 'user/Verdandi/backups' \) -prune -o -type f -exec md5sum {} + | sort -k2)
}
dust_content() { # dust dir -> relative path + md5 per file, relative path + target per link
    (cd "$1" && find . -type f -exec md5sum {} + | sort -k2; find . -type l -printf '%p -> %l\n' | sort)
}

U="$T/a"
mkdir -p "$U"
make_fixture "$U"
H="$U/user/Verdandi"
N="$H/Verdandi"
export HOME="$U/user" NORNS_INSTALLED=1
snapshot "$U" > "$T/first"
dust_content "$N/dust" > "$T/dust-first"
# every content hash of the fixture, to find each file again wherever it ends up
(cd "$U" && find user -type f -exec md5sum {} + | cut -d' ' -f1 | sort -u) > "$T/all-hashes"
confirm="flatten $N into $H"
run() { # stdin text, args... -> output in $T/out, status in $T/rc
    local input="$1"; shift
    printf '%s' "$input" | "$TIDY" flatten "$@" > "$T/out" 2>&1
    echo $? > "$T/rc"
}
rc() { cat "$T/rc"; }
out_has() { grep -qF -- "$1" "$T/out"; }

echo "== the dry run names the links"
"$TIDY" flatten > "$T/dry" 2>&1
grep -qF "broken: dust/audio/mac/broken.wav -> $U/elsewhere/gone.wav" "$T/dry" && ok "the broken link is named with its target" || { bad "broken link not named"; grep -n "link" "$T/dry"; }
grep -qF "elsewhere: dust/audio/mac/elsewhere.wav -> $U/elsewhere/real.wav" "$T/dry" && ok "a link that points elsewhere is named with its target" || bad "elsewhere link not named"
grep -qF "elsewhere: norns -> /opt/verdandi" "$T/dry" && ok "the norns link is named too" || bad "norns link not named"
grep -qF "into the nested folder: dust/audio/mac/into nested.wav" "$T/dry" && ok "the link into the nested folder is named" || bad "link into nested not named"
grep -q "3 link(s) point elsewhere" "$T/dry" && grep -q "1 already broken" "$T/dry" && ok "and the counts are still said" || bad "counts"
snapshot "$U" | cmp -s - "$T/first" && ok "the dry run changed nothing" || bad "the dry run changed something"

echo "== refusals (nothing changes)"
mkdir -p "$T/bin"; cp "$(command -v sleep)" "$T/bin/norns"
"$T/bin/norns" 60 & FAKE=$!
sleep 0.3
run "$confirm
yes
" --apply
[ "$(rc)" != 0 ] && out_has "norns" && out_has "running" && ok "--apply refuses while a norns is running" || { bad "no refusal for a running norns"; cat "$T/out"; }
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null
snapshot "$U" | cmp -s - "$T/first" && [ ! -e "$H/backups" ] && ok "...and nothing was changed or created" || bad "the refusal changed something"
run "$confirm
yes
" --undo
[ "$(rc)" != 0 ] && out_has "nothing to undo" && ok "--undo with nothing done says so" || { bad "undo without a backup"; cat "$T/out"; }

run "" --apply
[ "$(rc)" != 0 ] && out_has "confirm" && ok "--apply without the typed confirmation refuses" || { bad "no confirmation needed"; cat "$T/out"; }
run "flatten something else
yes
" --apply
[ "$(rc)" != 0 ] && ok "a wrong typed confirmation refuses" || bad "wrong confirmation accepted"
snapshot "$U" | cmp -s - "$T/first" && [ ! -e "$H/backups" ] && ok "...nothing changed or created" || bad "a refusal changed something"

echo "== apply"
run "$confirm
yes
" --apply
cat "$T/out" | sed 's/^/        | /'
[ "$(rc)" = 0 ] && ok "--apply succeeds" || bad "--apply failed (status $(rc))"
B="$(ls -d "$H"/backups/flatten-* 2>/dev/null | head -1)"
[ -n "$B" ] && ok "a backup folder backups/flatten-<time>/ exists" || bad "no backup folder"
[ -f "$B/before.tree" ] && [ -s "$B/before.tree" ] && ok "before.tree was written" || bad "no before.tree"
grep -qF "dust/code/my script/my script.lua" "$B/before.tree" && ok "before.tree lists the paths (names with spaces too)" || bad "before.tree content"
[ -f "$B/MANIFEST" ] && grep -q "^move	" "$B/MANIFEST" && ok "the manifest lists the moves" || bad "no manifest"
[ "$(cat "$B/STATE" 2>/dev/null)" = done ] && ok "STATE is done" || bad "STATE: $(cat "$B/STATE" 2>/dev/null)"
[ -d "$B/dust-links" ] && [ "$(stat -c %h "$B/dust-links/code/other/other.lua")" -ge 2 ] && ok "the backup of dust/ is a hard-link copy (no extra space)" || bad "no hard-link backup"
[ ! -e "$N" ] && ok "the nested folder is gone" || bad "the nested folder is still there: $(ls -A "$N")"
[ -d "$H/dust/code/my script" ] && ok "dust/ is in the home now" || bad "no dust in the home"
dust_content "$H/dust" | sed "s|$H/dust/audio/my sample (1).wav|$N/dust/audio/my sample (1).wav|" > "$T/dust-after"
cmp -s "$T/dust-first" "$T/dust-after" && ok "every file of dust/ has the same path and the same content hash; the links are the same (the one into the nested folder was rewritten)" || { bad "dust/ differs"; diff "$T/dust-first" "$T/dust-after" | head; }
[ "$(readlink "$H/dust/audio/mac/into nested.wav")" = "$H/dust/audio/my sample (1).wav" ] && ok "the link into the nested folder now points into the home" || bad "link not rewritten: $(readlink "$H/dust/audio/mac/into nested.wav")"
[ "$(readlink "$H/dust/audio/mac/elsewhere.wav")" = "$U/elsewhere/real.wav" ] && [ "$(readlink "$H/dust/audio/mac/broken.wav")" = "$U/elsewhere/gone.wav" ] && ok "the other links are unchanged" || bad "other links changed"
[ "$(stat -c %Y "$H/dust/code/my script/my script.lua")" = "$(date -d '2026-01-02 03:04:05' +%s)" ] && ok "file times are kept (rename, not copy)" || bad "file time changed"
[ -f "$H/audio.conf" ] && [ -f "$H/ui.conf" ] && [ "$(cat "$H/audio.conf")" = "rate=48000" ] && ok "audio.conf and ui.conf are in the home, unchanged" || bad "settings files"
grep -qF "\"$H/dust\"" "$H/.config/SuperCollider/sclang_conf.yaml" && ! grep -qF "$N" "$H/.config/SuperCollider/sclang_conf.yaml" && ok "sclang_conf.yaml names the new dust path" || { bad "sclang_conf.yaml"; cat "$H/.config/SuperCollider/sclang_conf.yaml"; }
grep -qF "$N/dust" "$H/.config/SuperCollider/sclang_conf.yaml.old" && ok "the old file is kept as sclang_conf.yaml.old" || bad "no .old"
grep -qF "/opt/verdandi/sc/core" "$H/.config/SuperCollider/sclang_conf.yaml" && ok "the other lines of the settings are kept" || bad "settings lines lost"
[ "$(cat "$H/matronrc.lua")" = "nested matronrc" ] && [ "$(cat "$B/outer/matronrc.lua")" = "outer matronrc (different)" ] && ok "a file on both sides: the nested one is in place, the outer one is in backups/.../outer (never overwritten)" || bad "conflict handling"
[ "$(cat "$H/old note.txt")" = "a leftover with spaces" ] && [ -f "$H/launcher.log" ] && ok "outer files that are not in the nested home stay where they are (a name with spaces too)" || bad "outer leftover lost"
[ -f "$B/outer/version.txt" ] && [ -L "$B/outer/norns" ] && ok "the outer twins of nested names are in backups/.../outer (same content or not, none is overwritten)" || bad "outer twins"
[ -d "$H/.config/mozilla/firefox/profile.default" ] && ok "the browser profile came along (a plain move)" || bad "mozilla profile"
# nothing lost: every content hash of the fixture still exists somewhere under the user folder
(cd "$U" && find user -type f -exec md5sum {} + | cut -d' ' -f1 | sort -u) > "$T/hashes-after"
missing="$(comm -23 "$T/all-hashes" "$T/hashes-after" | grep -v 'd41d8cd98f00b204e9800998ecf8427e' | head -3)"
# (the sclang_conf.yaml before the rewrite is the .old file, the empty crash-report.txt moved with the outer leftovers: both counted above)
[ -z "$missing" ] && ok "no file content of the scratch home is gone anywhere (all hashes found again)" || bad "a content hash is gone: $missing"
out_has "undo" && out_has "flatten --undo" && ok "the summary says how to undo" || bad "summary without undo"
out_has "$B" && ok "the summary names the backup folder" || bad "summary without backup folder"
out_has "files and links" && ok "the summary gives the counts of dust/" || bad "summary counts"

echo "== a second --apply on a home that is no longer nested"
run "$confirm
yes
" --apply
out_has "nothing-to-do" || out_has "not nested" && ok "says nothing to do" || { bad "second apply"; cat "$T/out"; }

echo "== undo"
run "" --undo
cat "$T/out" | sed 's/^/        | /' | tail -12
[ "$(rc)" = 0 ] && ok "--undo succeeds" || bad "--undo failed (status $(rc))"
snapshot "$U" | cmp -s - "$T/first" && ok "the whole home is exactly as before (paths, sizes, modes, link targets, file times, content hashes)" || { bad "the state after undo differs"; snapshot "$U" | diff "$T/first" - | head -12; }
[ "$(cat "$B/STATE")" = undone ] && ok "STATE is undone" || bad "STATE after undo: $(cat "$B/STATE")"
out_has "dust/" && out_has "files and links" && ok "undo says it checked the count of dust/" || bad "undo without a check"
run "" --undo
[ "$(rc)" != 0 ] && out_has "nothing to undo" && ok "a second undo finds nothing to undo" || bad "second undo"

echo "== an interrupted run (the process is killed after 3 moves), then --undo"
cat > "$T/kill-hook" <<'H'
#!/bin/bash
# called as: hook EVENT N; kills the tool after the Nth move, the way a power cut would
[ "$1" = after-move ] && [ "$2" = 3 ] && kill -9 "$PPID"
exit 0
H
chmod +x "$T/kill-hook"
printf '%s\nyes\n' "$confirm" | TIDY_FLATTEN_HOOK="$T/kill-hook" "$TIDY" flatten --apply > "$T/out" 2>&1
B2="$(ls -dt "$H"/backups/flatten-* 2>/dev/null | head -1)"
[ -n "$B2" ] && [ "$(cat "$B2/STATE")" = in-progress ] && ok "a killed run leaves STATE in-progress" || bad "STATE after kill: $(cat "${B2:-/nonexistent}/STATE" 2>&1)"
[ -d "$N" ] && [ "$(grep -c '^move	' "$B2/MANIFEST")" -ge 3 ] && ok "part of the work is done and listed in the manifest" || bad "manifest after kill"
run "$confirm
yes
" --apply
[ "$(rc)" != 0 ] && out_has "interrupted" && out_has "--undo" && ok "a new --apply refuses and says to run --undo" || { bad "apply after an interrupted run"; cat "$T/out"; }
run "" --undo
[ "$(rc)" = 0 ] && ok "--undo after the interruption succeeds" || { bad "undo after kill failed"; cat "$T/out"; }
snapshot "$U" | cmp -s - "$T/first" && ok "the home is exactly as before the interrupted run" || { bad "state after undo of an interrupted run differs"; snapshot "$U" | diff "$T/first" - | head -12; }

echo "== a signal during the run rolls back by itself"
cat > "$T/term-hook" <<'H'
#!/bin/bash
[ "$1" = after-move ] && [ "$2" = 4 ] && kill -TERM "$PPID" && sleep 1
exit 0
H
chmod +x "$T/term-hook"
printf '%s\nyes\n' "$confirm" | TIDY_FLATTEN_HOOK="$T/term-hook" "$TIDY" flatten --apply > "$T/out" 2>&1
[ "$?" != 0 ] && grep -qi "rolled back" "$T/out" && ok "SIGTERM: says it rolled back" || { bad "no rollback message after SIGTERM"; cat "$T/out"; }
snapshot "$U" | cmp -s - "$T/first" && ok "...and the home is exactly as before" || { bad "state after a rolled-back signal differs"; snapshot "$U" | diff "$T/first" - | head -12; }

echo "== a failed check (a file of dust/ vanishes after the moves) rolls back by itself"
cat > "$T/lose-hook" <<'H'
#!/bin/bash
# after all moves: delete one file of the moved dust/ (what a bug or a full disk could do). the tool must notice and roll back
[ "$1" = after-moves ] && rm -f "${TIDY_TEST_VICTIM:?}"
exit 0
H
chmod +x "$T/lose-hook"
printf '%s\nyes\n' "$confirm" | TIDY_TEST_VICTIM="$H/dust/code/other/other.lua" TIDY_FLATTEN_HOOK="$T/lose-hook" "$TIDY" flatten --apply > "$T/out" 2>&1
rcx=$?
[ $rcx != 0 ] && grep -qi "rolled back" "$T/out" && grep -qi "does not match\|mismatch\|differ" "$T/out" && ok "the count/size check fails and says it rolled back" || { bad "no rollback after a failed check"; cat "$T/out"; }
snapshot "$U" | cmp -s - "$T/first" && ok "...and nothing is lost: the home is exactly as before (the vanished file came back from the backup)" || { bad "state after a failed check differs"; snapshot "$U" | diff "$T/first" - | head -12; }
grep -qi "restored 1 missing" "$T/out" && ok "it says it restored the missing file from the backup copy" || bad "no restore message"

echo "== the link rewrite is optional: answering no leaves the links as they are"
rm -rf "${U:?}/user"; make_fixture "$U"
snapshot "$U" > "$T/first-b"
run "$confirm
no
" --apply
[ "$(rc)" = 0 ] && ok "--apply works with the answer no" || { bad "apply with no failed"; cat "$T/out"; }
[ "$(readlink "$H/dust/audio/mac/into nested.wav")" = "$N/dust/audio/my sample (1).wav" ] && ok "the link into the nested folder was left alone" || bad "link was rewritten"
out_has "into nested.wav" && out_has "broken" && ok "the summary names the link that is now broken" || bad "summary without the broken link"
run "" --undo
[ "$(rc)" = 0 ] && snapshot "$U" | cmp -s - "$T/first-b" && ok "undo gives back exactly the first state" || { bad "undo after the no-answer differs"; cat "$T/out" | tail -5; }

echo "== a full copy on request"
run "$confirm
yes
" --apply --full-copy
[ "$(rc)" = 0 ] && ok "--apply --full-copy works" || { bad "full copy failed"; cat "$T/out"; }
B3="$(ls -dt "$H"/backups/flatten-* | head -1)"
[ "$(stat -c %h "$B3/dust-links/code/other/other.lua" 2>/dev/null)" = 1 ] || [ "$(stat -c %h "$B3/dust-copy/code/other/other.lua" 2>/dev/null)" = 1 ] && ok "the backup is a real copy (its files are not hard-linked)" || bad "full copy is hard-linked"
run "" --undo
[ "$(rc)" = 0 ] && snapshot "$U" | cmp -s - "$T/first-b" && ok "undo works for the full copy too" || bad "undo after full copy"

echo "== an existing name is never overwritten (a conflict stops the move and rolls back)"
rm -rf "${U:?}/user"; make_fixture "$U"
snapshot "$U" > "$T/first-c"
# a hook that creates the destination name right before the 3rd rename, the way something else writing to the home would
cat > "$T/race-hook" <<'H'
#!/bin/bash
[ "$1" = before-rename ] && [ "$2" = 3 ] && echo "appeared" > "$3"
exit 0
H
chmod +x "$T/race-hook"
printf '%s\nyes\n' "$confirm" | TIDY_FLATTEN_HOOK="$T/race-hook" "$TIDY" flatten --apply > "$T/out" 2>&1
[ $? != 0 ] && grep -q "FAILED" "$T/out" && grep -q "nothing is overwritten" "$T/out" && ok "a name that appeared during the move stops it (it tries to roll back and says what is in the way)" || { bad "conflict not handled"; cat "$T/out"; }
appeared="$(grep -rlx appeared "$H" -s 2>/dev/null | head -1)"
[ -n "$appeared" ] && ok "the file that appeared was not overwritten" || bad "the new file was overwritten"
grep -qi "look at them by hand\|ROLLBACK INCOMPLETE" "$T/out" && ok "the rollback does not guess either: it says what is in the way" || bad "no message about the thing in the way"
# the thing in the way is removed by hand (it is the test's own file), and --undo finishes the job
rm -f "$appeared"
run "" --undo
[ "$(rc)" = 0 ] && snapshot "$U" | cmp -s - "$T/first-c" && ok "--undo finishes the rollback: the home is exactly as before" || { bad "state after the conflict and undo differs"; cat "$T/out"; snapshot "$U" | diff "$T/first-c" - | head; }

[ $FAIL -eq 0 ] && echo "tidy_flatten_apply_test: all passed"
exit $FAIL
