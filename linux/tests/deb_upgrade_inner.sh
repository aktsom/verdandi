#!/bin/bash
# linux/tests/deb_upgrade_inner.sh <old.deb> <new.deb> [tests dir] (docs/port/phase-m36.md): the body of the install / upgrade / remove test. runs as root INSIDE a clean Ubuntu 24.04 (a docker
# container ubuntu:24.04 in the workflow, a debootstrap root locally: linux/tests/deb_upgrade_test.sh) with nothing installed but the base system.
#   1. the old .deb is installed with apt (its Depends are all that makes it work: no library or tool is added by hand), started once as a normal user (the home ~/Verdandi, the link, the seeded packs)
#      and the owner's things are put into the fake home (a script, a mod, midimap.conf with a preset, an ext folder list) next to a second folder that stands for the test copy ~/verdandi-home
#   2. the new .deb is installed over it with apt (an upgrade): the version is higher, the home is byte for byte the same, the program is the new one
#   3. the new program is started the way the menu entry starts it (Exec of the .desktop file): norns and SuperCollider come up, the first line of its log names the build, mi-UGens / PortedPlugins are seeded
#      and compile with no class error, no second copy of a pack, the three libraries twins needs are found, a synth with them renders
#   4. an install over a running Verdandi is refused with a plain message and changes nothing
#   5. remove and purge: /opt/verdandi and the menu files go, the home and the test copy are exactly as they were
#   6. the version in the package, in /opt/verdandi/BUILD.txt, in the log line and in the program (VERDANDI_BUILD) agree
# prints "PASS ..." / "FAIL ..." lines; exit 1 on any FAIL. needs network (apt)
set -u
OLD="${1:?old .deb}"; NEW="${2:?new .deb}"; TESTS="${3:-/work/linux/tests}"
export DEBIAN_FRONTEND=noninteractive
# a network that stalls must not hang the run for ever
apt-get() { command apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60 "$@"; }
FAIL=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; FAIL=1; }
OLDV="$(dpkg-deb -f "$OLD" Version)"; NEWV="$(dpkg-deb -f "$NEW" Version)"
echo "== old $OLDV -> new $NEWV"
[ "$(. /etc/os-release; echo "$VERSION_CODENAME")" = noble ] && p "this is a clean Ubuntu 24.04 (noble)" || f "not noble: $(. /etc/os-release; echo "$PRETTY_NAME")"
dpkg-query -W -f='${Status}' verdandi 2> /dev/null | grep -q 'ok installed' && f "verdandi is already installed in this root"
dpkg --compare-versions "$NEWV" gt "$OLDV" && p "dpkg: $NEWV is newer than $OLDV" || f "dpkg: $NEWV is NOT newer than $OLDV"
mkdir -p /tmp/deb && cp "$OLD" /tmp/deb/old.deb && cp "$NEW" /tmp/deb/new.deb
apt-get update -q > /tmp/apt-update.log 2>&1 || { f "apt-get update"; tail -3 /tmp/apt-update.log; exit 1; }

# 1. the old package, from the clean base
if apt-get install -y -q /tmp/deb/old.deb > /tmp/apt-old.log 2>&1; then p "apt installs the old package ($OLDV) in the clean root with its Depends only ($(grep -c '^Setting up' /tmp/apt-old.log) packages set up)"; else f "apt could not install the old package"; tail -8 /tmp/apt-old.log; exit 1; fi
apt-get install -y -q xvfb xauth jackd2 x11-apps > /tmp/apt-tools.log 2>&1 || { f "test tools (xvfb, jackd2)"; exit 1; }
useradd -m -s /bin/bash tester 2> /dev/null
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
(Xvfb :99 -screen 0 1280x800x24 > /tmp/xvfb.log 2>&1 &)
sleep 2
H=/home/tester/Verdandi
# start the program as the tester. $1 = terminal (verdandi --terminal, with a fifo for Lua input) or menu (the Exec line of the menu entry, as a click would run it); waits until SuperCollider lists the engines
cat > /home/tester/start.sh <<'RUN'
#!/bin/bash
# start.sh terminal|menu <exec line>: leaves the pid in /tmp/pid-run and the fifo open on fd 3 only for terminal runs (the shell ends: the program keeps running)
export HOME=/home/tester DISPLAY=:99 NORNS_JACK_DRIVER=dummy SDL_AUDIODRIVER=dummy
H=/home/tester/Verdandi
rm -f "$H/logs/sclang.log" /tmp/launcher.out
if [ "$1" = terminal ]; then
    rm -f /tmp/vfifo; mkfifo /tmp/vfifo
    (sleep 100000 > /tmp/vfifo &) 
    setsid verdandi --terminal < /tmp/vfifo > /tmp/launcher.out 2>&1 &
else
    setsid bash -c "$2" > /tmp/launcher.out 2>&1 < /dev/null &
fi
echo $! > /tmp/pid-run
n=0
until grep -aq 'engines: \[' "$H/logs/sclang.log" 2> /dev/null; do
    n=$((n + 1)); [ $n -gt 600 ] && exit 1
    sleep 0.2
done
sleep 3
exit 0
RUN
cat > /home/tester/stop.sh <<'RUN'
#!/bin/bash
pkill -TERM -u tester -f 'norns.sh' 2> /dev/null
pkill -TERM -u tester -x norns 2> /dev/null
pkill -TERM -u tester -f 'sleep 100000' 2> /dev/null
n=0; while pgrep -u tester -f 'norns|sclang|scsynth|jackd|maiden' > /dev/null && [ $n -lt 100 ]; do n=$((n + 1)); sleep 0.2; done
pkill -KILL -u tester -f 'norns|sclang|scsynth|jackd|maiden' 2> /dev/null
exit 0
RUN
chmod 755 /home/tester/start.sh /home/tester/stop.sh
runuser -u tester -- /home/tester/start.sh terminal && p "the old program boots as a normal user" || { f "the old program did not boot"; tail -20 /tmp/launcher.out; }
runuser -u tester -- /home/tester/stop.sh
[ "$(readlink $H/norns)" = /opt/verdandi ] && p "~/Verdandi/norns leads to /opt/verdandi" || f "norns link: $(readlink $H/norns)"
# the owner's things (never in the package): a script, a mod, MIDI MAP settings with a preset, the ext folders list, settings; and a second folder that stands for the test copy
as_t() { runuser -u tester -- "$@"; }
as_t mkdir -p $H/dust/code/myscript $H/dust/code/mymod/lib $H/dust/data/myscript /home/tester/verdandi-home/norns/linux /home/tester/ext-folder
as_t sh -c "echo 'print(\"my script\")' > $H/dust/code/myscript/myscript.lua; echo 'local mod = require \"core/mods\"' > $H/dust/code/mymod/lib/mod.lua; echo 'a saved setting' > $H/dust/data/myscript/state.data; printf 'global.dev=ANY\nglobal.ch=0\npreset=MY PRESET\n' > $H/midimap.conf; printf 'mine\n' > $H/dust/data/ext.conf; echo 'audio.conf of the owner' > $H/audio.conf; echo 'the test copy' > /home/tester/verdandi-home/norns/linux/norns.sh; echo x > /home/tester/ext-folder/file.txt"
snap() { (cd /home/tester && find Verdandi verdandi-home ext-folder -not -path 'Verdandi/logs/*' -not -path 'Verdandi/cache/*' -not -path 'Verdandi/.config/*' -not -path 'Verdandi/.local/share/SuperCollider/*' -not -path 'Verdandi/disabled/*' -print0 | sort -z | xargs -0 stat -c '%n %F %s %Y %N' 2> /dev/null; find Verdandi/dust verdandi-home ext-folder Verdandi/midimap.conf Verdandi/audio.conf -type f -print0 2> /dev/null | sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1; }
SNAP0="$(snap)"
EXT0="$(cd $H/.local/share/SuperCollider 2> /dev/null && find Extensions -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"

# 2. the upgrade
if apt-get install -y -q /tmp/deb/new.deb > /tmp/apt-new.log 2>&1; then p "apt upgrades to the new package"; else f "the upgrade failed"; tail -10 /tmp/apt-new.log; fi
[ "$(dpkg-query -W -f='${Version}' verdandi)" = "$NEWV" ] && p "dpkg says the installed version is $NEWV" || f "installed version is $(dpkg-query -W -f='${Version}' verdandi)"
[ "$(dpkg-query -W -f='${Status}' verdandi)" = "install ok installed" ] && p "the package is cleanly installed" || f "package state: $(dpkg-query -W -f='${Status}' verdandi)"
[ "$(snap)" = "$SNAP0" ] && p "after the upgrade the home is exactly as before: the script, the mod, the saved data, midimap.conf with its preset, audio.conf, the ext folder and its files, the norns link, the test copy" || f "the upgrade changed something in the home or the test copy"
[ "$(cd $H/.local/share/SuperCollider && find Extensions -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)" = "$EXT0" ] && p "the seeded packs in the extension folder were not touched by the upgrade (the launcher does that at its next start)" || p "(the extension folder changed at the upgrade)"
[ "$(readlink $H/norns)" = /opt/verdandi ] && p "the norns link still leads to /opt/verdandi" || f "norns link: $(readlink $H/norns)"
[ -f /opt/verdandi/BUILD.txt ] && p "/opt/verdandi/BUILD.txt is there: $(head -n 1 /opt/verdandi/BUILD.txt)" || f "no /opt/verdandi/BUILD.txt after the upgrade"
dpkg -L verdandi | grep -q '^/opt/verdandi/supercollider/bin/sclang$' && p "the new program holds SuperCollider" || f "no sclang in the package"

# 3. the new program, started the way the menu entry starts it
EXEC="$(sed -n 's/^Exec=//p' /usr/share/applications/verdandi.desktop | head -n 1 | sed 's/ *%[a-zA-Z]//g')"
[ "$EXEC" = verdandi ] && p "the menu entry runs: $EXEC" || f "the menu entry runs '$EXEC'"
runuser -u tester -- /home/tester/start.sh menu "$EXEC" && p "the new program started from the menu entry's command: SuperCollider lists the engines" || { f "the new program did not come up"; tail -20 $H/logs/launcher.log; }
L="$H/logs/launcher.log"
UPV="${NEWV%%-*}"
sed -n 's/^norns.sh: build //p' "$L" | head -n 1 | grep -q "^$UPV [0-9a-f]\{7\}$" && p "the log says which build runs: $(sed -n 's/^norns.sh: build //p' "$L" | head -n 1)" || f "no 'norns.sh: build $UPV <hash>' in $L: $(head -3 "$L")"
grep -aq 'startup_status.ok\|engines: \[' $H/logs/sclang.log && grep -a 'engines: \[' $H/logs/sclang.log | head -1 | grep -q PolyPerc && p "SuperCollider is up and lists the engines" || f "no engine list"
grep -aqi 'FAIL' $H/logs/sclang.log && f "the sclang log has FAIL: $(grep -ai FAIL $H/logs/sclang.log | head -2)" || p "no FAIL message in the SuperCollider log"
if grep -aqi 'duplicate Class\|not understood\|ERROR: Class not defined\|wrong ELF\|cannot open shared' $H/logs/sclang.log; then f "class or plug-in error in the SuperCollider log: $(grep -ai 'duplicate Class\|not understood\|ERROR: Class not defined\|wrong ELF\|cannot open shared' $H/logs/sclang.log | head -3)"; else p "no duplicate class, no 'not understood', no wrong plug-in in the SuperCollider log"; fi
EXTD=$H/.local/share/SuperCollider/Extensions
for pack in mi-UGens:mi-ugens PortedPlugins:portedplugins; do
    n="${pack%%:*}"; d="${pack##*:}"; src=/opt/verdandi/$d/$n
    # the stamp names the serial and the commit of the pack; the launcher replaces a seeded pack only when the serial of the package is higher (so an older package's copy with the same serial stays: one copy, never two)
    st() { sed -n "s/^$2=//p" "$1/.verdandi-stamp"; }
    [ -f "$EXTD/$n/.verdandi-stamp" ] && [ "$(st "$EXTD/$n" serial)" = "$(st "$src" serial)" ] && [ "$(st "$EXTD/$n" commit)" = "$(st "$src" commit)" ] && (cd "$EXTD/$n" && sha256sum --quiet -c .verdandi-files) && p "$n is seeded in the extension folder (serial $(st "$src" serial), commit $(st "$src" commit | cut -c1-7)), intact" || f "$n is not seeded like the installed package ($(st "$EXTD/$n" serial) / $(st "$src" serial))"
done
[ -f "$EXTD/princeton/NamAmp.so" ] || [ -d /opt/verdandi/namamp/NamAmp ] && p "NamAmp is in the package (seeded when the script princeton is installed)" || f "no NamAmp"
cnt="$(find "$EXTD" /opt/verdandi/supercollider/share/SuperCollider/Extensions "$H/dust/code" -name 'MiPlaits.sc' -o -name 'AnalogChew.sc' 2> /dev/null | wc -l)"
[ "$cnt" = 2 ] && p "one copy of each pack's classes on SuperCollider's path (MiPlaits.sc, AnalogChew.sc)" || f "$cnt copies of MiPlaits.sc / AnalogChew.sc on the path"
runuser -u tester -- /home/tester/stop.sh
# the real sclang and scsynth with the home of the tester: the classes of both packs, and a synth that uses them is rendered (twins' libraries and MiPlaits/MiRings)
SC=/opt/verdandi/supercollider/bin
RUNSC() { runuser -u tester -- env HOME=$H QT_QPA_PLATFORM=offscreen PATH=$SC:$PATH LD_LIBRARY_PATH=/opt/verdandi/lib:/opt/verdandi/supercollider/lib timeout 150 "$SC/sclang" -D "$@"; }
if [ -f "$TESTS/twins_ugens.scd" ] && [ -f "$TESTS/mi_ugens.scd" ]; then
    cp "$TESTS/twins_ugens.scd" "$TESTS/mi_ugens.scd" /tmp/ && chmod 644 /tmp/*.scd
    RUNSC /tmp/twins_ugens.scd /tmp/tw.wav AnalogChew AnalogLoss AnalogDegrade > /tmp/tw.log 2>&1
    grep -q '^CLASS AnalogChew true' /tmp/tw.log && grep -q '^CLASS AnalogLoss true' /tmp/tw.log && grep -q '^CLASS AnalogDegrade true' /tmp/tw.log && p "twins' three libraries (AnalogChew, AnalogLoss, AnalogDegrade) are found by sclang" || f "twins libraries: $(grep -a 'CLASS\|ERROR' /tmp/tw.log | head -4 | tr '\n' ' ')"
    grep -q '^RENDERED' /tmp/tw.log && p "scsynth loads twins' three plug-ins and renders a synth with them" || f "twins render: $(tail -3 /tmp/tw.log)"
    RUNSC /tmp/mi_ugens.scd /tmp/mi.wav MiPlaits MiRings MiBeads > /tmp/mi.log 2>&1
    grep -q '^CLASS MiPlaits true' /tmp/mi.log && grep -q '^CLASS MiRings true' /tmp/mi.log && grep -q '^RENDERED' /tmp/mi.log && p "MiPlaits and MiRings are found and rendered (the mods emplaitress and fx_resonator)" || f "mi-UGens: $(grep -a 'CLASS\|ERROR\|RENDER' /tmp/mi.log | head -4 | tr '\n' ' ')"
    grep -qi 'duplicate' /tmp/tw.log /tmp/mi.log && f "duplicate class in a plain sclang run" || p "no duplicate class in a plain sclang run with both packs"
else
    f "the sclang test scripts are not in $TESTS"
fi
SNAP1="$(snap)"
# the new program also in terminal mode: the program's own version line (the string the home page of the norns window shows)
runuser -u tester -- /home/tester/start.sh terminal && p "the new program boots in terminal mode" || f "no boot in terminal mode"
runuser -u tester -- timeout 10 bash -c "echo 'print(\"VERSION-LINE=\" .. tostring(os.getenv(\"VERDANDI_BUILD\")))' > /tmp/vfifo"
sleep 3
grep -a 'VERSION-LINE=' /tmp/launcher.out | head -1 | grep -q "VERSION-LINE=$UPV [0-9a-f]\{7\}\$" && p "the program's version line is '$UPV $(sed -n 's/^.* \([0-9a-f]\{7\}\)$/\1/p' /opt/verdandi/BUILD.txt | head -1)': the same number as the package ($NEWV) and BUILD.txt ($(head -n 1 /opt/verdandi/BUILD.txt))" || f "the program's version line: $(grep -a 'VERSION-LINE=' /tmp/launcher.out | head -1)"
[ "$(head -n 1 /opt/verdandi/BUILD.txt | cut -d' ' -f1)" = "$UPV" ] && p "the version in the package ($NEWV), in BUILD.txt and in the program agree: $UPV" || f "version mismatch: package $NEWV, BUILD.txt $(head -n 1 /opt/verdandi/BUILD.txt)"
# 4. an install over a running Verdandi is refused and changes nothing
BEFORE="$(dpkg-query -W -f='${Version}' verdandi); $(sha256sum /opt/verdandi/BUILD.txt)"
apt-get install -y -q --reinstall /tmp/deb/new.deb > /tmp/apt-running.log 2>&1; rc=$?
[ $rc != 0 ] && grep -q 'Verdandi is running. Close Verdandi' /tmp/apt-running.log && p "an install over a running Verdandi is refused with: Close Verdandi" || f "install over a running Verdandi: rc=$rc $(tail -3 /tmp/apt-running.log)"
[ "$BEFORE" = "$(dpkg-query -W -f='${Version}' verdandi); $(sha256sum /opt/verdandi/BUILD.txt)" ] && [ -x /opt/verdandi/linux/norns.sh ] && p "...and the installed files are as they were" || f "the refused install changed the program"
apt-get remove -y -q verdandi > /tmp/apt-rm-running.log 2>&1; rc=$?
[ $rc != 0 ] && [ -x /opt/verdandi/linux/norns.sh ] && p "a removal while Verdandi runs is refused too" || f "remove while running: rc=$rc"
runuser -u tester -- /home/tester/stop.sh
apt-get install -y -q --reinstall /tmp/deb/new.deb > /tmp/apt-re.log 2>&1 && p "after closing it, the same install goes through" || { f "reinstall after closing"; tail -5 /tmp/apt-re.log; }
SNAP2="$(snap)"
cp $H/midimap.conf /tmp/midimap.snap
# 5. remove and purge
apt-get remove -y -q verdandi > /tmp/apt-rm.log 2>&1 && p "apt remove verdandi" || { f "remove failed"; tail -5 /tmp/apt-rm.log; }
[ ! -e /opt/verdandi ] && [ ! -e /usr/bin/verdandi ] && [ ! -e /usr/share/applications/verdandi.desktop ] && [ ! -e /usr/share/icons/hicolor/256x256/apps/verdandi.png ] && p "/opt/verdandi, the command, the menu entry and the icon are gone" || f "files left after remove: $(ls /opt/verdandi 2>&1 | head -3)"
[ "$(snap)" = "$SNAP2" ] && p "after the removal the home and the test copy are exactly as they were (scripts, mod, presets, settings; the norns link stays, now dangling)" || f "the removal changed the home"
apt-get purge -y -q verdandi > /tmp/apt-purge.log 2>&1 || true
[ "$(snap)" = "$SNAP2" ] && p "after purge too: nothing in the home changed" || f "purge changed the home"
for x in $H/dust/code/myscript/myscript.lua $H/dust/code/mymod/lib/mod.lua $H/dust/data/myscript/state.data $H/midimap.conf $H/audio.conf /home/tester/verdandi-home/norns/linux/norns.sh /home/tester/ext-folder/file.txt; do [ -f "$x" ] || f "gone: $x"; done
cmp -s $H/midimap.conf /tmp/midimap.snap && p "midimap.conf (MIDI MAP settings and presets) is byte for byte what the program left before the removal" || f "midimap.conf changed"
: "$SNAP1"
echo "== done: $([ $FAIL = 0 ] && echo 'all passed' || echo 'FAILED')"
exit $FAIL
