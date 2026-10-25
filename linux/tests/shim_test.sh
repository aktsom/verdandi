#!/bin/bash
# linux/tests/shim_test.sh: the sudo and systemctl shims of linux/shims (norns prepends that folder to PATH for itself): a script that runs
# "sudo systemctl restart norns-*.service" must get a restart request, at once, without sudo, without a password prompt. fake sudo and systemctl
# on the PATH record what reaches them. exit 1 if anything fails.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SHIMS="$REPO/linux/shims"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/real" "$T/home"
# the "real" programs: record their arguments; the real sudo would wait for a password, so this one sleeps if asked without -n
cat > "$T/real/sudo" <<'S'
#!/bin/bash
echo "sudo $*" >> "$FAKELOG"
case "$1" in -n) exit 0 ;; *) sleep 30 ;; esac
S
cat > "$T/real/systemctl" <<'S'
#!/bin/bash
echo "systemctl $*" >> "$FAKELOG"
S
cat > "$T/real/pkill" <<'S'
#!/bin/bash
echo "pkill $*" >> "$FAKELOG"
S
chmod +x "$T/real"/*
export FAKELOG="$T/calls.log" HOME="$T/home" NORNS_SHIM_WATCHDOG=2
export PATH="$SHIMS:$T/real:$PATH"
FAIL=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }
reset() { : > "$FAKELOG"; rm -f "$HOME/.norns-request-restart" "$HOME/.norns-restart"; }
timed() { # seconds command...: run, report if it took longer
    local s=$1; shift
    local t0=$(date +%s.%N)
    "$@" > "$T/out" 2> "$T/err"
    RC=$?
    local t1=$(date +%s.%N)
    ELAPSED=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }')
    awk -v e="$ELAPSED" -v s="$s" 'BEGIN { exit !(e < s) }'
}

reset
timed 1 sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service
[ $? = 0 ] && [ $RC = 0 ] && ok "sudo systemctl restart norns-*: exit 0 in $ELAPSED s" || bad "sudo systemctl restart norns-*: rc=$RC took $ELAPSED s"
[ -f "$HOME/.norns-request-restart" ] && ok "a restart request is left for norns" || bad "no restart request"
[ ! -s "$FAKELOG" ] && ok "neither the real sudo nor the real systemctl was called" || bad "reached the real programs: $(cat "$FAKELOG")"
[ "$(wc -l < "$T/err")" = 1 ] && grep -q "norns-jack.service" "$T/err" && grep -q "restart" "$T/err" && ok "one clear line on stderr" || bad "stderr: $(cat "$T/err")"
grep -q "no systemd" "$T/err" && grep -qi "restart" "$T/err" && ok "the line says what was done and why" || bad "message: $(cat "$T/err")"

reset
timed 1 systemctl restart norns-matron.service
[ $? = 0 ] && [ $RC = 0 ] && [ -f "$HOME/.norns-request-restart" ] && [ ! -s "$FAKELOG" ] && ok "systemctl restart norns-matron.service (no sudo)" || bad "systemctl restart: rc=$RC log=$(cat "$FAKELOG")"
reset
timed 1 sudo -n systemctl --no-block restart norns-sclang.service
[ $? = 0 ] && [ -f "$HOME/.norns-request-restart" ] && ok "options before the verb are skipped (sudo -n, --no-block)" || bad "options: rc=$RC"
reset
timed 1 sudo systemctl start norns-main.service
[ $? = 0 ] && [ $RC = 0 ] && [ ! -f "$HOME/.norns-request-restart" ] && [ ! -s "$FAKELOG" ] && ok "start norns-*: already running, no restart, exit 0" || bad "start: rc=$RC"
reset
timed 1 sudo systemctl stop norns-matron.service
[ $? = 0 ] && [ $RC = 1 ] && [ ! -f "$HOME/.norns-request-restart" ] && grep -q "not supported" "$T/err" && ok "stop norns-*: refused with a line, exit 1, nothing stopped" || bad "stop: rc=$RC err=$(cat "$T/err")"

# other units go to the real systemctl; other sudo commands never wait for a password
reset
timed 1 systemctl restart nginx.service
[ "$(cat "$FAKELOG")" = "systemctl restart nginx.service" ] && [ ! -f "$HOME/.norns-request-restart" ] && ok "another unit: the real systemctl, unchanged" || bad "other unit: $(cat "$FAKELOG")"
reset
timed 1 systemctl status serialosc.service
[ "$(cat "$FAKELOG")" = "systemctl status serialosc.service" ] && ok "systemctl status: the real systemctl" || bad "status: $(cat "$FAKELOG")"
reset
timed 5 sudo systemctl restart serialosc.service
[ "$(cat "$FAKELOG")" = "sudo -n systemctl restart serialosc.service" ] && ok "sudo for another unit: real sudo with -n (never asks for a password)" || bad "sudo other unit: $(cat "$FAKELOG")"
reset
timed 5 sudo apt-get install -y something
[ $? = 0 ] && [ "$(cat "$FAKELOG")" = "sudo -n apt-get install -y something" ] && ok "any other sudo command: -n added, returned in $ELAPSED s instead of waiting" || bad "other sudo: rc=$RC took $ELAPSED log=$(cat "$FAKELOG")"
reset
timed 5 sudo -n -u root true
[ "$(cat "$FAKELOG")" = "sudo -n -u root true" ] && ok "an own -n is not doubled" || bad "doubled -n: $(cat "$FAKELOG")"

# the safety net: if nobody takes the request, the shim itself restarts norns after the watchdog time (touch .norns-restart, end norns)
reset
timed 1 sudo systemctl restart norns-crone.service
sleep 3.5
[ -f "$HOME/.norns-restart" ] && [ ! -f "$HOME/.norns-request-restart" ] && grep -q "pkill -TERM -x norns" "$FAKELOG" && ok "watchdog: an unanswered request restarts norns after $NORNS_SHIM_WATCHDOG s" || bad "watchdog: restart mark $( [ -f "$HOME/.norns-restart" ] && echo yes || echo no ) log=$(cat "$FAKELOG")"
reset
timed 1 sudo systemctl restart norns-crone.service
rm -f "$HOME/.norns-request-restart"   # norns took the request
sleep 3.5
[ ! -f "$HOME/.norns-restart" ] && [ ! -s "$FAKELOG" ] && ok "watchdog: a request that was taken is left alone" || bad "watchdog fired although the request was taken"
# the shim leaves no process holding the caller's output (a sidecar waits for the pipe to close)
reset
out="$(timeout 5 sh -c 'sudo systemctl restart norns-x.service' 2>&1)"
[ $? = 0 ] && ok "the output pipe closes at once (the watchdog does not hold it)" || bad "output pipe held"
exit $FAIL
