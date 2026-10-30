#!/bin/bash
# `verdandi tidy` (linux/tidy.sh, docs/port/clean-layout.md): disable and restore with the manifest, list, remove-older (and what it never touches), log rotation
# and caps, crash report pruning. a fixture norns home; nothing outside it.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
H="$T/home"
tidy() { NORNS_HOME="$H" "$REPO/linux/tidy.sh" "$@"; }
snap() { (cd "$H" && find dust audio.conf ui.conf -printf '%p %y %s\n' 2>/dev/null | sort; find dust audio.conf ui.conf -type f -exec md5sum {} + 2>/dev/null | sort); }

mkdir -p "$H/dust/code/a script/lib" "$H/dust/audio" "$H/dust/data" "$H/.local/share/SuperCollider/Extensions/mi-UGens"
echo "print(1)" > "$H/dust/code/a script/a.lua"
head -c 2000 /dev/urandom > "$H/dust/audio/s.wav"
echo "rate=48000" > "$H/audio.conf"
echo "brightness=1.0" > "$H/ui.conf"
printf "detached=0\n" > "$H/screen-window.conf"
printf "style=pixel\n" > "$H/box.conf"
mkdir -p "$H/box-presets"
printf "verdandi-box=1\n" > "$H/box-presets/mine.box"
echo "so" > "$H/.local/share/SuperCollider/Extensions/mi-UGens/MiPlaits.so"
snap > "$T/user-before"

# ---- disable ----
OUT="$(tidy disable "$H/.local/share/SuperCollider/Extensions/mi-UGens" "32-bit ARM plug-ins on x86_64" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "disable works" || { bad "disable failed: $OUT"; }
[ ! -e "$H/.local/share/SuperCollider/Extensions/mi-UGens" ] && ok "the folder is gone from its place" || bad "the folder is still there"
ID="$(printf '%s' "$OUT" | sed -n 's/.*(id \([^)]*\)).*/\1/p')"
[ -n "$ID" ] && [ -f "$H/disabled/$ID/mi-UGens/MiPlaits.so" ] && ok "it is in disabled/<id>/<original name> with its content" || bad "not stored as disabled/<id>/mi-UGens ($ID)"
M="$H/disabled/MANIFEST.tsv"
[ "$(head -n 1 "$M" | tr '\t' ',')" = "id,what,from,when_utc,why,stored,size,status,restore" ] && ok "the manifest header: id what from when why stored size status restore" || bad "manifest header"
LINE="$(sed -n 2p "$M")"
F() { printf '%s' "$LINE" | cut -f"$1"; }
[ "$(F 1)" = "$ID" ] && [ "$(F 2)" = "folder mi-UGens" ] && [ "$(F 3)" = "$H/.local/share/SuperCollider/Extensions/mi-UGens" ] && ok "the manifest says what and from where" || bad "manifest what/from: $LINE"
printf '%s' "$(F 4)" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' && ok "when: a UTC time" || bad "when: $(F 4)"
[ "$(F 5)" = "32-bit ARM plug-ins on x86_64" ] && [ "$(F 8)" = disabled ] && ok "why and status" || bad "why/status"
printf '%s' "$(F 9)" | grep -q "^mv '.*/disabled/$ID/mi-UGens' '.*/mi-UGens'$" && ok "how to restore: a plain mv that works without the tool" || bad "restore column: $(F 9)"
[ -z "$(ls "$H/disabled" | grep -v "^$ID$\|MANIFEST.tsv")" ] && [ ! -e "$H/disabled/MANIFEST.tsv.tmp" ] && ok "no stray files (no temporary manifest)" || bad "stray files in disabled/"

# ---- the things it refuses to move ----
for p in "$H/dust" "$H/dust/code" "$H/audio.conf" "$H/ui.conf" "$H/screen-window.conf" "$H/box.conf" "$H/box-presets" "$H/box-presets/mine.box" "$H" "$H/disabled"; do
    if tidy disable "$p" "test" > /dev/null 2>&1; then bad "disable moved $p"; else ok "disable refuses $(basename "$p")"; fi
done
mkdir -p "$T/outside" && echo x > "$T/outside/f"
tidy disable "$T/outside/f" "test" > /dev/null 2>&1 && bad "disable moved a file outside the home" || ok "disable refuses a path outside the home"
[ -d "$H/dust" ] && [ -f "$H/audio.conf" ] && [ -f "$H/ui.conf" ] && ok "the refusals moved nothing" || bad "something was moved"

# ---- list ----
LIST="$(tidy list 2>&1)"
printf '%s' "$LIST" | grep -q "mi-UGens" && printf '%s' "$LIST" | grep -q "32-bit ARM" && ok "list shows the disabled item with its reason" || bad "list: $LIST"
tidy list --tsv | grep -q "^disabled	$ID	folder mi-UGens	[0-9]*	[0-9]*	32-bit" && ok "list --tsv: group, id, name, epoch, bytes, why" || bad "list --tsv"

# ---- restore ----
mkdir -p "$H/.local/share/SuperCollider/Extensions/mi-UGens"   # the place is taken again
tidy restore "$ID" > "$T/r.out" 2>&1 && bad "restore overwrote a taken place" || ok "restore refuses when the original place exists"
grep -q "exists again" "$T/r.out" && ok "and says why in plain words" || bad "restore message: $(cat "$T/r.out")"
rmdir "$H/.local/share/SuperCollider/Extensions/mi-UGens"
tidy restore "$ID" > /dev/null 2>&1 && [ -f "$H/.local/share/SuperCollider/Extensions/mi-UGens/MiPlaits.so" ] && ok "restore puts it back" || bad "restore failed"
[ "$(sed -n 2p "$M" | cut -f8)" = restored ] && [ ! -e "$H/disabled/$ID" ] && ok "the manifest says restored and the item folder is gone" || bad "status after restore"
tidy restore "$ID" > /dev/null 2>&1 && bad "a second restore worked" || ok "a second restore is refused"
tidy restore nonexistent > /dev/null 2>&1 && bad "restore of an unknown id worked" || ok "an unknown id is refused"

# ---- remove-older: only what is older, only the five groups, never anything else ----
tidy disable "$H/.local/share/SuperCollider/Extensions/mi-UGens" "old one" > /dev/null
ID2="$(tail -n 1 "$M" | cut -f1)"
# make it 100 days old in the manifest and put "not ours" things around
sed -i "s/^\($ID2\t[^\t]*\t[^\t]*\t\)[^\t]*/\12020-01-01T00:00:00Z/" "$M"
mkdir -p "$H/disabled/by-hand" && echo mine > "$H/disabled/by-hand/f"
mkdir -p "$H/logs/crash" "$H/cache/x"
for n in 1 2; do echo old > "$H/logs/norns.$n.log"; done
echo cur > "$H/logs/norns.log"
echo c > "$H/logs/crash/crash-1000-1.txt"; echo c > "$H/logs/crash/crash-2000-1.txt"
touch -d "200 days ago" "$H/logs/norns.2.log" "$H/logs/crash/crash-1000-1.txt" "$H/cache/x/old.bin"; echo n > "$H/cache/x/new.bin"
touch -d "200 days ago" "$H/logs/norns.log"   # a CURRENT log, however old: never removed
touch -d "200 days ago" "$H/dust/audio/s.wav" "$H/audio.conf" "$H/ui.conf"   # yours: never removed
mkdir -p "$H/.local/share/SuperCollider/Extensions/foreign"; echo x > "$H/.local/share/SuperCollider/Extensions/foreign/F.sc"; touch -d "200 days ago" "$H/.local/share/SuperCollider/Extensions/foreign"
snap > "$T/user-before2"
DRY="$(tidy remove-older 90 2>&1)"
printf '%s' "$DRY" | grep -q "nothing was removed" && ok "without --yes nothing is removed" || bad "dry run: $DRY"
[ -d "$H/disabled/$ID2" ] && [ -f "$H/logs/norns.2.log" ] && [ -f "$H/logs/crash/crash-1000-1.txt" ] && [ -f "$H/cache/x/old.bin" ] && ok "and everything is still there" || bad "the dry run removed something"
printf '%s' "$DRY" | grep -q "older than 90 days: disabled" && printf '%s' "$DRY" | grep -q "norns.2.log" && printf '%s' "$DRY" | grep -q "crash-1000-1.txt" && printf '%s' "$DRY" | grep -q "cache" && ok "it lists exactly the old items of the groups" || bad "the list: $DRY"
printf '%s' "$DRY" | grep -q "norns.1.log\|crash-2000\|new.bin\|norns.log  \|by-hand\|s.wav\|foreign" && bad "the list names something it must not: $DRY" || ok "the new items, the current log, the unlisted item, yours and the unstamped extension are not listed"
tidy remove-older 90 --yes > "$T/rm.out" 2>&1
[ ! -e "$H/disabled/$ID2" ] && [ ! -e "$H/logs/norns.2.log" ] && [ ! -e "$H/logs/crash/crash-1000-1.txt" ] && [ ! -e "$H/cache/x/old.bin" ] && ok "--yes removes exactly the old items" || bad "old items still there: $(ls "$H/disabled" "$H/logs" "$H/cache/x" 2>&1 | tr "\n" " ")"
[ -f "$H/logs/norns.1.log" ] && [ -f "$H/logs/norns.log" ] && [ -f "$H/logs/crash/crash-2000-1.txt" ] && [ -f "$H/cache/x/new.bin" ] && ok "newer items and the current log stay" || bad "a newer item was removed"
[ -f "$H/disabled/by-hand/f" ] && ok "a thing in disabled/ that is not in the manifest is never removed" || bad "by-hand was removed"
[ -f "$H/.local/share/SuperCollider/Extensions/foreign/F.sc" ] && ok "an extension without our stamp is never removed" || bad "foreign extension removed"
[ "$(grep -c "$ID2.*removed" "$M")" = 1 ] && ok "the manifest says removed" || bad "manifest after removal"
snap > "$T/user-after2"
cmp -s "$T/user-before2" "$T/user-after2" && ok "dust/, audio.conf and ui.conf: not one byte changed" || bad "user files changed"

# ---- seeded packs: ours carry a stamp ----
mkdir -p "$H/.local/share/SuperCollider/Extensions/seeded"; echo "pack 1" > "$H/.local/share/SuperCollider/Extensions/seeded/.verdandi-pack"; touch -d "300 days ago" "$H/.local/share/SuperCollider/Extensions/seeded/.verdandi-pack"
tidy list --tsv | grep -q "^seeded	seeded" && ok "a stamped pack is listed as seeded" || bad "seeded not listed"
tidy remove-older 90 --yes > /dev/null 2>&1
[ ! -e "$H/.local/share/SuperCollider/Extensions/seeded" ] && [ -d "$H/.local/share/SuperCollider/Extensions/foreign" ] && ok "an old seeded pack goes, the foreign folder stays" || bad "seeded/foreign handling"

# ---- rotate: 5 runs, the current log fresh, launcher.log capped, crash reports pruned ----
rm -rf "${H:?}/logs"
mkdir -p "$H/logs/crash"
for i in 1 2 3 4 5 6 7; do
    tidy rotate norns sclang > /dev/null 2>&1
    echo "run $i" > "$H/logs/norns.log"
done
[ "$(cat "$H/logs/norns.1.log")" = "run 7" ] || [ "$(cat "$H/logs/norns.1.log")" = "run 6" ] && ok "the previous run is norns.1.log" || bad "norns.1.log: $(cat "$H/logs/norns.1.log")"
ls "$H/logs" | grep -c "^norns\." | grep -q "^5$" && ok "norns.log and four older runs: 5 files" || bad "files: $(ls "$H/logs")"
[ -f "$H/logs/norns.5.log" ] && bad "a fifth old run is kept" || ok "no norns.5.log"
[ -f "$H/logs/sclang.log" ] && [ ! -s "$H/logs/sclang.log" ] && ok "the new current log exists and is empty" || bad "sclang.log not fresh"
head -c 1100000 /dev/zero | tr '\0' 'x' > "$H/logs/launcher.log"
tidy rotate norns > /dev/null 2>&1
[ -f "$H/logs/launcher.1.log" ] && [ ! -f "$H/logs/launcher.log" ] || [ ! -s "$H/logs/launcher.log" ] && ok "launcher.log over 1 MB is moved aside" || bad "launcher.log not rotated"
for i in 1 2 3 4 5 6 7 8; do echo c > "$H/logs/crash/crash-$((1000 + i))-1.txt"; touch -d "$((10 - i)) days ago" "$H/logs/crash/crash-$((1000 + i))-1.txt"; done
tidy rotate norns > /dev/null 2>&1
[ "$(ls "$H/logs/crash" | wc -l)" = 5 ] && [ -f "$H/logs/crash/crash-1008-1.txt" ] && [ ! -f "$H/logs/crash/crash-1001-1.txt" ] && ok "the last 5 crash reports stay, the oldest go" || bad "crash pruning: $(ls "$H/logs/crash")"
tidy rotate "bad name" > /dev/null 2>&1 && bad "a bad log name was accepted" || ok "a bad log name is refused"

# ---- cap: a running log over 10 MB is cut to its last megabyte ----
head -c 11000000 /dev/zero | tr '\0' 'y' > "$H/logs/sclang.log"
echo "the last line" >> "$H/logs/sclang.log"
tidy cap > /dev/null 2>&1
SZ="$(stat -c %s "$H/logs/sclang.log")"
[ "$SZ" -lt 1200000 ] && [ "$SZ" -gt 1000000 ] && tail -n 1 "$H/logs/sclang.log" | grep -q "the last line" && ok "cap cuts a log over 10 MB to its last megabyte and keeps the end" || bad "cap: size $SZ"
head -n 1 "$H/logs/sclang.log" | grep -q "cut to its last megabyte" && ok "and says so in the log" || bad "no cut note"
echo "small" > "$H/logs/jackd.log"; tidy cap > /dev/null 2>&1; [ "$(cat "$H/logs/jackd.log")" = small ] && ok "a small log is left alone" || bad "small log changed"

# ---- the page's and the launcher's entry point ----
OUT="$(NORNS_HOME="$H" "$REPO/linux/norns.sh" tidy list 2>&1)"; printf '%s' "$OUT" | grep -q "the norns home" && ok "linux/norns.sh tidy list works" || bad "norns.sh tidy: $OUT"
tidy bogus > /dev/null 2>&1 && bad "an unknown command was accepted" || ok "an unknown command is refused"

[ $FAIL -eq 0 ] && echo "tidy_test: all passed"
exit $FAIL
