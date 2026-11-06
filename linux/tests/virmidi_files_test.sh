#!/bin/bash
# linux/tests/virmidi_files_test.sh: the opt-in files of the ALSA raw MIDI route (linux/virmidi/): what they say, that the package ships them as examples only (usr/share/doc/verdandi/examples/) and installs nothing into /etc or
# loads nothing by itself, and that the manual names them and the commands that make them permanent.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
M="$REPO/linux/virmidi/verdandi-virmidi.modules-load.conf"
O="$REPO/linux/virmidi/verdandi-virmidi.modprobe.conf"
[ "$(grep -v '^#' "$M" | grep -v '^$')" = "snd-virmidi" ] && ok "modules-load.d file: the module name and nothing else" || bad "modules-load.d file: the only active line must be snd-virmidi"
[ "$(grep -v '^#' "$O" | grep -v '^$')" = "options snd-virmidi midi_devs=1" ] && ok "modprobe.d file: the one option" || bad "modprobe.d file: the only active line must be 'options snd-virmidi midi_devs=1'"
[ ! -x "$M" ] && [ ! -x "$O" ] && ok "neither file is executable" || bad "a file is executable"
grep -q 'virmidi' "$REPO/linux/package.sh" && ok "package.sh knows the files" || bad "package.sh does not install the examples"
grep -q 'usr/share/doc/verdandi\|\$doc/examples' "$REPO/linux/package.sh" && grep -q 'verdandi-virmidi.modules-load.conf' "$REPO/linux/package.sh" && ok "they go to the documentation examples" || bad "they must go under usr/share/doc/verdandi/examples"
if grep -nE 'STAGE/etc|etc/modules-load.d|etc/modprobe.d' "$REPO/linux/package.sh" | grep -v '^\s*#' | grep -vE '^[0-9]+:\s*#' | grep -q .; then bad "the package must not install into /etc (a package does not load kernel modules or add MIDI ports unasked)"; else ok "nothing is installed into /etc, nothing is loaded by the package"; fi
grep -q 'modprobe' "$REPO/linux/package.sh" && grep -nE 'postinst' "$REPO/linux/package.sh" > /dev/null && { sed -n '/cat > "\$D\/postinst"/,/^POST/p' "$REPO/linux/package.sh" | grep -q 'modprobe' && bad "the postinst must not modprobe" || ok "the postinst does not modprobe"; }
H="$REPO/linux/manual/manual.html"
grep -q '/etc/modules-load.d/' "$H" && grep -q '/etc/modprobe.d/' "$H" && grep -q 'usr/share/doc/verdandi/examples' "$H" && ok "the manual names the files and where the examples are" || bad "the manual must name /etc/modules-load.d, /etc/modprobe.d and the examples"
[ $FAILS -eq 0 ] && echo "virmidi_files_test: all passed" || echo "virmidi_files_test: failed"
[ $FAILS -eq 0 ]
