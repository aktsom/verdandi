#!/bin/bash
# linux/tests/class_note_test.sh <log>: a headless boot (norns_probe.sh) and the note and log line for a class defined twice (probe_class_note.lua)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
NORNS_HOME="$H" NORNS_MI_UGENS=0 "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_class_note.lua" "$1" > /dev/null 2>&1
exit 0
