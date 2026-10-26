#!/bin/bash
# needs: ENG_ORGN, ENG_ETERNA (clones of github.com/andr-ew/orgn and github.com/etsuko-fm/eterna), meter (gcc meter.c -ljack -lm), burst.wav (1 s sine)
# bundled = build/package/stage (linux/package.sh sc) bind-mounted at /opt/verdandi/supercollider in a private mount namespace
# engcheck.sh apt|bundled OUTDIR: boot norns headless, load and trigger each engine, meter crone's outputs
V="$1"; O="$2"; S="$(cd "$(dirname "$0")" && pwd)"; REPO=/home/user/verdandi
mkdir -p "$O"
H="$O/home"; rm -rf "$H"; mkdir -p "$H/dust/code" "$H/dust/audio"
cp -r "${ENG_ORGN:?clone andr-ew/orgn}" "$H/dust/code/orgn"; cp -r "${ENG_ETERNA:?clone etsuko-fm/eterna}" "$H/dust/code/eterna"
cp "$S/burst.wav" "$H/dust/audio/burst.wav"
ln -s "$REPO" "$H/norns"
export METER="$S/meter"
{
echo 'print("PROBE-START")'
for E in 'PolyPerc|engine.hz(220)' 'PolySub|engine.start(0,220)' 'TestSine|engine.hz(330)' 'SimplePassThru|' 'Orgn|engine.noteOn(1,220,1,0)' \
         'Eterna|engine.load_channel_to_buffer(_path.audio.."burst.wav",0,0) ; engine.voice_channel(0,0) ; engine.voice_trigger(0)'; do
  N="${E%%|*}"; T="${E#*|}"
  echo "engine.load('$N', function() print('ENG_LOADED $N') end)"
  echo "#sleep 9"
  echo 'print("ENG_NAME "..tostring(engine.name))'
  echo "#sh ( \"\$METER\" 4 | sed 's/^/METER $N /' >> \"\$MARKS\" ) &"
  echo "#sleep 1"
  if [ "$N" = Eterna ]; then
    echo "engine.load_channel_to_buffer(_path.audio..'burst.wav',0,0)"; echo "#sleep 2"
    echo "engine.voice_channel(0,0)"; echo "engine.voice_trigger(0)"
  elif [ -n "$T" ]; then echo "$T"; fi
  echo "#sleep 5"
done
echo 'print("PROBE-END")'
} > "$O/cmds.lua"
if [ "$V" = bundled ]; then
  mkdir -p /opt/verdandi/supercollider
  unshare -m bash -c "mount --bind $REPO/build/package/stage/opt/verdandi/supercollider /opt/verdandi/supercollider && PATH=/opt/verdandi/supercollider/bin:\$PATH NORNS_HOME=$H bash $REPO/linux/tests/norns_probe.sh $O/cmds.lua $O/norns.log" > "$O/probe.out" 2>&1
else
  NORNS_HOME="$H" bash "$REPO/linux/tests/norns_probe.sh" "$O/cmds.lua" "$O/norns.log" > "$O/probe.out" 2>&1
fi
cp "$H/sclang.log" "$O/sclang.log" 2>/dev/null; cp "$H/probe.marks" "$O/marks.txt" 2>/dev/null
echo "== $V"; grep -a "Welcome to SuperCollider\|^compiling class\|sc3-plugins\|Extensions" "$O/sclang.log" | head -5
grep -a "ENG_LOADED\|ENG_NAME" "$O/norns.log"; cat "$O/marks.txt"
echo "-- errors in sclang.log:"; grep -aiE "not installed|FAILURE|ERROR|exception|doesNotUnderstand" "$O/sclang.log" | sort | uniq -c | head -20
