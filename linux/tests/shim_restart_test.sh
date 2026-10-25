#!/bin/bash
# linux/tests/shim_restart_test.sh <log>: a script's "sudo systemctl restart norns-*" through os.execute restarts norns (see probe_shim.lua)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_shim.lua" "$LOG" > /dev/null 2>&1
cp "$H/probe.marks.crone" "$LOG.crone" 2> /dev/null
exit 0
