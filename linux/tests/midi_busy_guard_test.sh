#!/usr/bin/env bash
# M37 (docs/port/phase-m37.md): everything that makes a busy MIDI port skippable sits behind NORNS_LINUX_DESKTOP (and not on Windows): the macOS build, the norns device build and the Windows build keep
# their code. checked by compiling the three device files WITHOUT the macro (no new symbol, no new text in the object), by reading the preprocessor nesting of the two shared files that register
# Lua functions, and by looking for the new names in the platform folders of macOS and Windows. run from the repo root.
cd "$(dirname "$0")/../.." || exit 1
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FLAGS="-std=gnu++14 -D_GNU_SOURCE -I matron/src -I matron/src/device -I matron/src/platform/linux $(pkg-config --cflags lua5.3 libevdev alsa libudev 2> /dev/null) -I/usr/include/libevdev-1.0"
for f in device_midi device_list device_monitor; do
    # shellcheck disable=SC2086
    g++ -c $FLAGS matron/src/device/$f.cc -o "$T/$f.o" 2> "$T/$f.err" || { bad "$f.cc does not compile without NORNS_LINUX_DESKTOP"; tail -3 "$T/$f.err"; continue; }
    if nm "$T/$f.o" | grep -q -E "dev_midi_open_failure|dev_list_midi_skipped_text|scan_thread|dev_monitor_scan_now|rawmidi_open_pair|skip_lock"; then
        bad "$f.cc without the macro still has an M37 symbol"
    elif strings "$T/$f.o" | grep -q -E "another program has it open|has not finished after|does not take data"; then
        bad "$f.cc without the macro still has an M37 sentence"
    else
        ok "$f.cc without the macro: compiles, no M37 symbol, no M37 sentence (the device and macOS builds are as before)"
    fi
done

# the Windows build: device_list.cc with NORNS_WINDOWS has no skip list (its MIDI layer says "held by another program" itself, platform/windows/midi)
# shellcheck disable=SC2086
g++ -c $FLAGS -DNORNS_LINUX_DESKTOP -DNORNS_WINDOWS -I matron/src/platform/windows matron/src/device/device_list.cc -o "$T/dl_win.o" 2> "$T/dl_win.err" || { bad "device_list.cc does not compile for Windows"; tail -3 "$T/dl_win.err"; }
if [ -f "$T/dl_win.o" ]; then
    if nm "$T/dl_win.o" | grep -q -E "dev_midi_open_failure|dev_list_midi_skipped_text|skip_lock"; then bad "device_list.cc for Windows has the Linux skip list"; else ok "device_list.cc for Windows: no skip list, no wait on the add lock (the Windows layer is as before)"; fi
fi

if grep -rq -E "midi_skipped|dev_midi_open_failure|dev_list_midi_skipped_text" matron/src/platform/macos matron/src/platform/windows; then bad "a platform folder of macOS or Windows mentions the new functions"; else ok "nothing in platform/macos or platform/windows mentions the new functions"; fi

python3 - << 'PY' || fail=1
import re, sys
# the declaration, the registration and the definition of _norns.midi_skipped in weaver.cc: inside NORNS_LINUX_DESKTOP and NOT on Windows (the block around them is compiled on Windows too)
src = open("matron/src/weaver.cc").read().split("\n")
stack, bad = [], []
for n, line in enumerate(src, 1):
    t = line.strip()
    if t.startswith("#if"):
        stack.append(t)
    elif t.startswith("#endif"):
        stack.pop()
    elif t.startswith("#else") and stack:
        stack[-1] = stack[-1] + " ELSE"
    if "midi_skipped" in line and not t.startswith("*") and not t.startswith("//"):
        inside = any(s.startswith("#ifdef NORNS_LINUX_DESKTOP") and "ELSE" not in s for s in stack)
        notwin = any(s.startswith("#ifndef NORNS_WINDOWS") and "ELSE" not in s for s in stack)
        # the registration sits in a block "#ifdef NORNS_LINUX_DESKTOP / #ifndef NORNS_WINDOWS ... #endif"; the definition in the Linux-only block of midi_in_status
        if not inside or not notwin:
            bad.append("line %d is not inside NORNS_LINUX_DESKTOP and #ifndef NORNS_WINDOWS (the Windows build compiles this block and has no skip list)" % n)
if bad:
    print("FAIL weaver.cc: " + "; ".join(bad)); sys.exit(1)
print("ok   weaver.cc: _norns.midi_skipped is inside NORNS_LINUX_DESKTOP and #ifndef NORNS_WINDOWS")
PY

[ $fail -eq 0 ] && echo "midi_busy_guard_test: all passed"
exit $fail
