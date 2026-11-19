#!/bin/bash
# linux/tests/tape_end_test.sh (M25): a tape recording that runs when norns ends is closed first, whichever way norns ends: Ctrl+Q, the window's close button, SIGTERM, SIGHUP, SIGINT, SYSTEM > RESTART,
# the shutdown action and the SLEEP page. the real norns (Xvfb, jackd dummy) records for a few seconds, then ends the way HOW says; the file must be a WAV whose header says what the file holds (libsndfile
# writes the sizes when it closes the file: a process that is ended by a signal while it records leaves a header with length 0). HOWS="term hup" runs some of them; KEEP=1 keeps the homes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
for how in ${HOWS:-quit close term hup int restart shutdown sleep}; do
    T="$(mktemp -d)"
    mkdir -p "$T/dust/audio/tape"
    ln -s "$REPO" "$T/norns"
    P="$T/probe.lua"
    {
        echo "#sleep 2"
        echo "audio.tape_record_open(_path.tape .. 'm25.wav') audio.tape_record_start()"
        echo "#sleep 4"
        echo "print('PROBE recording', audio.tape_is_recording())"
        case "$how" in
        quit) echo "#sh xdotool search --name '^Verdandi.Linux\$' windowfocus key ctrl+q" ;;
        close) echo "#sh '$HERE/detach_check.sh' close '^Verdandi.Linux\$'" ;;
        term) echo '#sh kill -TERM "$(pgrep -x norns | head -1)"' ;;
        hup) echo '#sh kill -HUP "$(pgrep -x norns | head -1)"' ;;
        int) echo '#sh kill -INT "$(pgrep -x norns | head -1)"' ;;
        restart) echo "_norns.restart()" ;;
        shutdown) echo "norns.shutdown()" ;;
        sleep) echo "require('core/menu/sleep').key(3, 1)" ;;
        esac
        echo "#sleep 6"
    } > "$P"
    NORNS_MAIDEN="$T/none" NORNS_HOME="$T" "$HERE/norns_probe.sh" "$P" "$T/log" > /dev/null 2>&1
    W="$T/dust/audio/tape/m25.wav"
    # (the file below is the proof that the tape recorded: a tape that never started leaves no file. the probe's own print is not asked for: on the CI runner norns' prints do not always reach the log)
    grep -aq "PROBE.recording.true" "$T/log" && echo "  note  $how: the probe saw the tape recording"
    out="$(python3 "$REPO/windows/ci/wav_check.py" "$W" 96000 2>&1)"
    case "$out" in found*) ok "$how: $out" ;; *) bad "$how: $out" ;; esac
    [ -n "${KEEP:-}" ] && echo "kept $T" || rm -rf "$T"
done
[ $FAILS -eq 0 ] && echo "tape_end_test: all passed" || echo "tape_end_test: $FAILS failed"
[ $FAILS -eq 0 ]
