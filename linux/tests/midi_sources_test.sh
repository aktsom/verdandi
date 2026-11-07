#!/bin/bash
# linux/tests/midi_sources_test.sh: where a MIDI device can come from (KNOWN-ISSUES 40: the virtual MIDI card snd-virmidi must never be listed or opened by norns). a source scan of the
# code, so that a new path that opens or lists a card cannot be added without passing the ignore rule: the only raw-port open is device_midi.cc, the only ALSA card source is
# device_monitor.cc's add_dev_sound behind midi_card_ignored, the sequencer is used for output only, and the pages that list devices (MIDI MAP, ANY, params MAP, keys and
# grid windows) read what the list has. prints "name: ok" / "name: FAIL ...", exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
SRC="matron/src"
raw="$(grep -rln 'snd_rawmidi_open' $SRC --include=*.cc --include=*.c --include=*.h | grep -v '/macos/' | sort | tr '\n' ' ')"
[ "$raw" = "matron/src/device/device_midi.cc " ] && ok "the raw MIDI port is opened in one place: device_midi.cc" || bad "raw open sites" "$raw"
adds="$(grep -rn 'dev_list_add(DEV_TYPE_MIDI,' $SRC --include=*.cc --include=*.c | grep -v '/macos/' | cut -d: -f1 | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
[ "$adds" = " 1 matron/src/device/device_monitor.cc; 1 matron/src/platform/linux/jack_midi_in.cc; 1 matron/src/platform/linux/keys_midi.cc;" ] && ok "MIDI devices are added by the device monitor (ALSA cards), JACK MIDI and the keys window only" || bad "dev_list_add sites" "$adds"
# in the monitor the ALSA add sits behind the ignore rule
awk '/^void add_dev_sound/ { f = 1 } f && /midi_card_ignored/ { seen = 1 } f && /dev_list_add\(DEV_TYPE_MIDI/ { exit (seen ? 0 : 1) } END { if (!f) exit 1 }' matron/src/device/device_monitor.cc && ok "add_dev_sound asks midi_card_ignored before it adds a card" || bad "add_dev_sound" "the ignore check does not come first"
# the periodic sweep: the same rule, and the release of a card that is listed
awk '/^void dev_monitor_midi_check/ { f = 1 } f && /midi_card_ignored/ { a = 1 } f && /add_dev_sound/ { exit (a ? 0 : 1) } END { if (!f) exit 1 }' matron/src/device/device_monitor.cc && ok "the periodic card sweep asks midi_card_ignored before add_dev_sound" || bad "sweep" "no ignore check"
grep -q 'dev_list_midi_release' matron/src/device/device_monitor.cc && ok "...and releases a listed card that has to be ignored" || bad "release" "no release call"
# the ALSA sequencer is used to send only: no input subscription from another client (the virtual card's sequencer clients are never read)
sub="$(grep -rn 'snd_seq_connect_from' $SRC --include=*.cc --include=*.c --include=*.h | grep -v '/macos/'; grep -rn 'snd_seq_port_subscribe_set_sender\|snd_seq_subscribe_port' $SRC --include=*.cc --include=*.c --include=*.h | grep -v '/macos/' | grep -v 'platform/linux/aseq_out.cc')"
[ -z "$sub" ] && ok "no code subscribes to another ALSA sequencer client's output (only aseq_out.cc, and only with its own port as the sender: snd_seq_connect_to)" || bad "seq input" "$sub"
# Lua: devices come from midi.devices / midi.vports (fed by the monitor's events); nothing reads the sound cards itself
lua_other="$(grep -rln '/proc/asound\|/dev/snd\|amidi\|aconnect\|arecordmidi' lua --include=*.lua | grep -v 'core/virmidi.lua\|core/menu/devices.lua' | tr '\n' ' ')"
[ -z "$lua_other" ] && ok "no Lua module outside the VIRMIDI page reads /proc/asound, /dev/snd or runs amidi / aconnect" || bad "lua card readers" "$lua_other"
for f in lua/core/menu/midimap.lua lua/core/midimap.lua lua/core/menu/params.lua; do
    grep -q 'midi\.devices\|midi\.vports' "$f" && ok "$f lists devices from midi.devices / midi.vports only" || bad "$f" "does not use the device list"
done
# the virtual card's page reads /proc only to show names (never opens a port)
grep -q 'snd_rawmidi\|io.open("/dev/snd' lua/core/virmidi.lua && bad "virmidi.lua" "opens a device" || ok "the VIRMIDI page only reads /proc/asound names, it opens no port"
exit $FAIL
