#!/bin/bash
# linux/tests/launcher_test.sh: the audio server and device decisions of linux/norns.sh, with stub
# jack_lsp / pw-cli / pw-jack / wpctl (NORNS_DECIDE_ONLY=1 prints the decision and exits).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
BIN="$T/bin"
mkdir -p "$BIN" "$T/home"
ln -s "$REPO" "$T/home/norns"

# stubs, steered by STUB_* variables
cat > "$BIN/jack_lsp" <<'S'
#!/bin/bash
[ "${STUB_JACK:-0}" = 1 ] || exit 1
printf '%s\n' ${STUB_JACK_PORTS:-system:capture_1}
S
cat > "$BIN/pw-cli" <<'S'
#!/bin/bash
[ "${STUB_PW:-0}" = 1 ]
S
cat > "$BIN/wpctl" <<'S'
#!/bin/bash
case "$2" in
@DEFAULT_AUDIO_SINK@) [ -n "${STUB_SINK:-}" ] && printf 'id 50, type PipeWire:Interface:Node\n    node.description = "%s"\n' "$STUB_SINK" ;;
@DEFAULT_AUDIO_SOURCE@) [ -n "${STUB_SOURCE:-}" ] && printf 'id 51, type PipeWire:Interface:Node\n    node.description = "%s"\n' "$STUB_SOURCE" ;;
esac
exit 0
S
cat > "$BIN/pw-metadata" <<'S'
#!/bin/bash
[ "${STUB_PW:-0}" = 1 ] && echo "update: id:0 key:'clock.rate' value:'${STUB_RATE:-48000}' type:''"
exit 0
S
cat > "$BIN/pw-jack" <<'S'
#!/bin/bash
exit 0
S
# a pw-jack that behaves like the real one (a shell script): PipeWire now answers, the working directory is
# somewhere else, and it really execs the command it was given
cat > "$BIN/pw-jack-real" <<'S'
#!/bin/bash
cd "${STUB_PWJACK_CWD:-/}" || exit 1
export STUB_JACK=1
exec "$@"
S
chmod +x "$BIN"/*

FAIL=0
decide() { # env assignments..., prints the DECIDE line
    env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" NORNS_HOME="$T/home" NORNS_DECIDE_ONLY=1 "$@" \
        "$REPO/linux/norns.sh" 2>&1 | grep '^DECIDE ' || echo "DECIDE (none)"
}
decide_more() { # env assignments..., prints the line that starts with $1 (first argument)
    local key="$1"
    shift
    env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" NORNS_HOME="$T/home" NORNS_DECIDE_ONLY=1 "$@" \
        "$REPO/linux/norns.sh" 2>&1 | grep "^$key" || echo "$key (none)"
}
expect() { # name, expected, actual
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "       want: $2"; echo "       got:  $3"; FAIL=1; fi
}

expect "no pipewire, no jack: start jackd" \
    "DECIDE action=start-jackd server=jackd in= out=" "$(decide)"
expect "a jack server answers: use it" \
    "DECIDE action=use-running server=jack in= out=" "$(decide STUB_JACK=1)"
expect "pipewire runs, no jack: re-run under pw-jack" \
    "DECIDE action=reexec-pw-jack server=pipewire in= out=" "$(decide STUB_PW=1)"
expect "pipewire runs, pw-jack missing: say so" \
    "DECIDE action=need-pw-jack server=pipewire in= out=" "$(decide STUB_PW=1 NORNS_PW_JACK=/nonexistent/pw-jack)"
expect "under pw-jack (second run): use it" \
    "DECIDE action=use-running server=pipewire in= out=" "$(decide STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1)"
expect "pipewire's midi bridge ports mark an unknown server as pipewire" \
    "DECIDE action=use-running server=pipewire in= out=" "$(decide STUB_PW=1 STUB_JACK=1 'STUB_JACK_PORTS=system:capture_1 Midi-Bridge:Midi_Through:(capture_0)')"
expect "NORNS_JACK_DRIVER given: own jackd even under pipewire" \
    "DECIDE action=start-jackd server=jackd in= out=" "$(decide STUB_PW=1 NORNS_JACK_DRIVER=dummy)"
expect "NORNS_AUDIO_SERVER=jackd: own jackd" \
    "DECIDE action=start-jackd server=jackd in= out=" "$(decide STUB_PW=1 NORNS_AUDIO_SERVER=jackd)"
expect "NORNS_AUDIO_SERVER=pipewire without pipewire running: say so" \
    "DECIDE action=need-pw-jack server=pipewire in= out=" "$(decide NORNS_AUDIO_SERVER=pipewire)"
expect "NORNS_AUDIO_SERVER=pipewire: re-run under pw-jack" \
    "DECIDE action=reexec-pw-jack server=pipewire in= out=" "$(decide STUB_PW=1 STUB_JACK=0 NORNS_AUDIO_SERVER=pipewire)"

# the re-run itself: relative path of the script, another working directory, a pw-jack that really execs.
# (NORNS_DECIDE_ONLY=reexec lets the re-run happen and prints the decision of the second run)
for how in relative absolute viash; do
    case "$how" in
    relative) cmd=(linux/norns.sh) ;;
    absolute) cmd=("$REPO/linux/norns.sh") ;;
    viash) cmd=(bash linux/norns.sh) ;;
    esac
    got="$(cd "$REPO" && env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" NORNS_HOME="$T/home" NORNS_DECIDE_ONLY=reexec \
        STUB_PW=1 NORNS_PW_JACK="$BIN/pw-jack-real" STUB_PWJACK_CWD=/ "${cmd[@]}" 2>&1 | grep -E '^DECIDE |not found|No such' | head -2)"
    expect "re-run under pw-jack really starts the script again ($how path, other working directory)" \
        "DECIDE action=use-running server=pipewire in= out=" "$got"
done

# devices: the default sink / source of the session become the port prefixes under pipewire
expect "default sink and source become the prefixes" \
    "DECIDE action=use-running server=pipewire in=Built-in Audio Analog Stereo out=AudioQuest DragonFly Black v1.5 Analog Stereo" \
    "$(decide STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1 'STUB_SINK=AudioQuest DragonFly Black v1.5 Analog Stereo' 'STUB_SOURCE=Built-in Audio Analog Stereo')"
expect "a monitor as default source is not an input choice" \
    "DECIDE action=use-running server=pipewire in= out=Card" \
    "$(decide STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1 STUB_SINK=Card 'STUB_SOURCE=Monitor of Card')"
printf 'in_ports=USB Mic\nout_ports=Other DAC\n' > "$T/home/audio.conf"
expect "audio.conf beats the session default" \
    "DECIDE action=use-running server=pipewire in=USB Mic out=Other DAC" \
    "$(decide STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1 STUB_SINK=Card STUB_SOURCE=Card)"
expect "the environment beats audio.conf" \
    "DECIDE action=use-running server=pipewire in=USB Mic out=Env DAC" \
    "$(decide STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1 'NORNS_OUT_PORTS=Env DAC')"
rm -f "$T/home/audio.conf"
expect "plain jack: no session default is asked" \
    "DECIDE action=use-running server=jack in= out=" \
    "$(decide STUB_JACK=1 STUB_SINK=Card STUB_SOURCE=Card)"

# audio settings of SYSTEM > AUDIO (audio.conf), own jackd
printf 'input=hw:CARD=Mic\noutput=hw:CARD=Dac\nrate=44100\nperiod=256\n' > "$T/home/audio.conf"
expect "jackd alsa: devices, rate and period from audio.conf" \
    "DECIDE-JACKD -d alsa -r 44100 -p 256 -C hw:CARD=Mic -P hw:CARD=Dac" "$(decide_more DECIDE-JACKD)"
expect "jackd: the environment beats audio.conf" \
    "DECIDE-JACKD -d alsa -r 96000 -p 256 -C hw:CARD=Mic -P hw:CARD=Dac" "$(decide_more DECIDE-JACKD NORNS_JACK_RATE=96000)"
expect "jackd dummy: no device arguments" \
    "DECIDE-JACKD -r -d dummy -r 44100 -p 256" "$(decide_more DECIDE-JACKD NORNS_JACK_DRIVER=dummy)"
printf 'input=hw:CARD=Mic\n' > "$T/home/audio.conf"
expect "jackd alsa: one device chosen, the other side is hw:0" \
    "DECIDE-JACKD -d alsa -r 48000 -p 1024 -C hw:CARD=Mic -P hw:0" "$(decide_more DECIDE-JACKD)"
rm -f "$T/home/audio.conf"
expect "jackd alsa without audio.conf: the old defaults" \
    "DECIDE-JACKD -d alsa -r 48000 -p 1024" "$(decide_more DECIDE-JACKD)"
# pipewire: the quantum is a request (experimental), rate is the system's
expect "pipewire: system rate" "DECIDE-RATE 48000" "$(decide_more DECIDE-RATE STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1)"
expect "pipewire: other system rate" "DECIDE-RATE 44100" "$(decide_more DECIDE-RATE STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1 STUB_RATE=44100)"
expect "pipewire: no period in audio.conf, no quantum request" "DECIDE-QUANTUM " "$(decide_more DECIDE-QUANTUM STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1)"
printf 'period=256\nin_ports=X\n' > "$T/home/audio.conf"
expect "pipewire: period from audio.conf becomes PIPEWIRE_QUANTUM" "DECIDE-QUANTUM 256/48000" \
    "$(decide_more DECIDE-QUANTUM STUB_PW=1 STUB_JACK=1 NORNS_REEXEC=1)"
rm -f "$T/home/audio.conf"
exit $FAIL
