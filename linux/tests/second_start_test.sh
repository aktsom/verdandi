#!/bin/bash
# a second start of Verdandi (docs: the Linux manual, "Starting it a second time"): the launcher does not start a second copy; it asks the running one to bring its
# window to the front through a small control file in the norns home (.norns-raise, answered by .norns-raise.done), and shows no dialog when that worked. when the
# running one does not answer, or has no window, it says so in one plain sentence (the dialog of before). nothing of the running instance's data is touched (no logs
# rotated, no settings written). a leftover control file of a crashed norns does not block a new start. here with fake "norns" processes (a copy of sleep named norns),
# no display, no sound server: the launcher's check comes before everything else (NORNS_CHECK_RUNNING_ONLY=1 stops right after it when nothing runs).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
FAIL=0
FAKES=""
cleanup() { for p in $FAKES; do kill "$p" 2> /dev/null; done; rm -rf "${T:?}"; }
trap cleanup EXIT
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }

if pgrep -x norns > /dev/null; then echo "SKIP: a norns is running on this machine (the launcher would talk to it)"; exit 0; fi

H="$T/home"
mkdir -p "$H/dust/code/a" "$H/logs" "$T/bin" "$T/fake"
ln -s "$REPO" "$H/norns"
echo "print(1)" > "$H/dust/code/a/a.lua"
echo "rate=48000" > "$H/audio.conf"
echo "the running norns writes here" > "$H/logs/norns.log"
echo "older run" > "$H/logs/norns.1.log"
echo "x" > "$H/matronrc.lua"
cp "$(command -v sleep)" "$T/fake/norns"
# a dialog stub: records that it was called and what it said
cat > "$T/bin/zenity" <<S
#!/bin/sh
printf '%s\n' "\$*" >> "$T/zenity.log"
S
chmod +x "$T/bin/zenity"

snapshot() { (cd "$H" && { find . -path './.norns-raise*' -prune -o -type d -printf '%p d\n'; find . -path './.norns-raise*' -prune -o ! -type d -printf '%p %y %s %T@\n'; } | sort; find . -type f ! -name '.norns-raise*' -exec md5sum {} + | sort); }
launcher() { # env... -> output in $T/out, status in $T/rc; no terminal, so the dialog would show
    env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/user" NORNS_HOME="$H" NORNS_RAISE_WAIT=1 "$@" "$REPO/linux/norns.sh" > "$T/out" 2>&1 < /dev/null
    echo $? > "$T/rc"
}
mkdir -p "$T/user"
rc() { cat "$T/rc"; }
count_norns() { pgrep -xc norns; }

echo "== nothing running: the check lets the first start through (and a leftover request of a crashed norns is no lock)"
echo stale > "$H/.norns-raise"
echo stale > "$H/.norns-raise.done"
before="$(snapshot)"
launcher NORNS_CHECK_RUNNING_ONLY=1
[ "$(rc)" = 0 ] && grep -q "no Verdandi is running" "$T/out" && ok "no norns running: the launcher goes on (the check hook says so)" || { bad "first start blocked"; cat "$T/out"; }
[ ! -s "$T/zenity.log" ] && ok "no dialog" || bad "a dialog was shown"
[ "$(snapshot)" = "$before" ] && ok "the check itself changed nothing in the home" || bad "the check changed the home"
rm -f "$H/.norns-raise" "$H/.norns-raise.done"

echo "== a norns is running and does not answer (an old build, another home, or still starting)"
"$T/fake/norns" 300 & FAKES="$FAKES $!"
sleep 0.3
before="$(snapshot)"
launcher
[ "$(rc)" != 0 ] && grep -q "already running" "$T/out" && grep -q "did not answer" "$T/out" && ok "no answer: it says Verdandi is running and did not answer, and stops" || { bad "no-answer message"; cat "$T/out"; }
[ "$(count_norns)" = 1 ] && ok "no second norns was started" || bad "norns count $(count_norns)"
grep -q "already running" "$T/zenity.log" 2> /dev/null && ok "the dialog shows the same one plain sentence" || bad "no dialog with the sentence ($(cat "$T/zenity.log" 2> /dev/null))"
[ "$(snapshot)" = "$before" ] && ok "the running instance's data is untouched (logs not rotated, nothing rewritten, same files and times)" || { bad "the home changed"; diff <(echo "$before") <(snapshot) | head; }
[ ! -e "$H/.norns-raise" ] && ok "its request file is removed again (an unanswered request would be raised later by a norns that starts afterwards)" || bad "the request file is left"

echo "== it answers: raised, no dialog"
: > "$T/zenity.log"
( while :; do if [ -f "$H/.norns-raise" ]; then mv "$H/.norns-raise" "$H/.norns-raise.claimed"; echo ok > "$H/.norns-raise.done.tmp"; mv "$H/.norns-raise.done.tmp" "$H/.norns-raise.done"; fi; sleep 0.1; done ) &
RESP=$!
before="$(snapshot)"
launcher NORNS_RAISE_WAIT=3
[ "$(rc)" = 0 ] && grep -q "brought" "$T/out" && ok "answered ok: exit 0 and it says the window was brought to the front" || { bad "raise ok"; cat "$T/out"; }
[ ! -s "$T/zenity.log" ] && ok "no dialog when it worked" || bad "a dialog was shown: $(cat "$T/zenity.log")"
[ "$(count_norns)" = 1 ] && ok "no second norns" || bad "second norns"
[ "$(snapshot)" = "$before" ] && ok "the home is untouched" || bad "the home changed"
[ ! -e "$H/.norns-raise" ] && [ ! -e "$H/.norns-raise.done" ] && ok "the launcher cleared the request and the answer" || bad "control files left: $(ls -a "$H" | grep norns-raise)"
kill "$RESP" 2> /dev/null; wait "$RESP" 2> /dev/null
rm -f "$H"/.norns-raise*

echo "== it answers: no window"
: > "$T/zenity.log"
( while :; do if [ -f "$H/.norns-raise" ]; then mv "$H/.norns-raise" "$H/.norns-raise.claimed"; echo no-window > "$H/.norns-raise.done.tmp"; mv "$H/.norns-raise.done.tmp" "$H/.norns-raise.done"; fi; sleep 0.1; done ) &
RESP=$!
launcher NORNS_RAISE_WAIT=3
[ "$(rc)" != 0 ] && grep -q "no window" "$T/out" && ok "no window: one plain sentence says so, and it stops" || { bad "no-window message"; cat "$T/out"; }
grep -q "no window" "$T/zenity.log" 2> /dev/null && ok "the dialog shows it" || bad "no dialog"
[ "$(count_norns)" = 1 ] && ok "no second norns" || bad "second norns"
kill "$RESP" 2> /dev/null; wait "$RESP" 2> /dev/null
rm -f "$H"/.norns-raise*

echo "== a stale answer of an earlier request does not count"
echo ok > "$H/.norns-raise.done"
: > "$T/zenity.log"
launcher
[ "$(rc)" != 0 ] && grep -q "did not answer" "$T/out" && ok "an old .done file is not taken as the answer to this request" || { bad "stale answer taken"; cat "$T/out"; }
rm -f "$H"/.norns-raise*

echo "== the running norns crashes: no lock is left that blocks a new start"
kill -9 $FAKES 2> /dev/null; wait 2> /dev/null; FAKES=""
sleep 0.3
echo stale > "$H/.norns-raise"
launcher NORNS_CHECK_RUNNING_ONLY=1
[ "$(rc)" = 0 ] && grep -q "no Verdandi is running" "$T/out" && ok "after a crash (kill -9) the next start goes on, whatever files were left" || { bad "blocked after a crash"; cat "$T/out"; }

[ $FAIL = 0 ] && echo "second_start_test: all passed"
exit $FAIL
