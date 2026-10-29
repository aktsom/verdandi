#!/bin/bash
# SuperCollider and the virtual /home/we (docs/port/KNOWN-ISSUES.md item 20). a real norns has /home/we; here it is only a name that lua and the launcher translate, so an engine
# that reads a folder, a file or a buffer through "/home/we/dust/..." (dronecaster: PathName(...).entries) finds nothing. the fix is sc/linux/NornsVirtualHome.sc (class extensions
# loaded only by the Linux launcher's sclang_conf.yaml). a "fake engine" script (no norns, no crone) does what engines do with such paths, headless, with sclang and scsynth:
#   - a control run WITHOUT the fix: every operation fails (this shows the bug and that the test would notice it)
#   - a run WITH the fix: the folder lists, the glob matches, files read, write and delete, a sound file opens, a script loads, a shell command sees the real path,
#     a buffer reads through Buffer.read and through a literal /b_allocRead message, a SynthDef file written there is loaded by scsynth, and paths that only look
#     alike (/home/weird, /tmp/home/we) are left alone
# SCLANG (default: sclang on the PATH) and SC_FIXTURE_JACK (default: a dummy jackd is started) can be set. no display needed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCLANG="${SCLANG:-sclang}"
command -v "$SCLANG" > /dev/null || { echo "SKIP: no sclang"; exit 0; }
T="$(mktemp -d)"
JACK_PID=""
trap '[ -n "$JACK_PID" ] && kill "$JACK_PID" 2> /dev/null; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }

H="$T/home"
mkdir -p "$H/dust/code/fake/engine/drones" "$H/dust/audio" "$H/dust/data" "$T/weird/home/we"
echo '(freq: 220)' > "$H/dust/code/fake/engine/drones/a.scd"
echo '(freq: 330)' > "$H/dust/code/fake/engine/drones/b.scd"
echo '40 + 2' > "$H/dust/code/fake/engine/answer.scd"
python3 - "$H/dust/audio/test.wav" << 'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "w"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(i * 0.1))) for i in range(4800))); w.close()
PY
echo "outside" > "$T/weird/home/we/file.txt"

cat > "$T/fake.scd" << 'SC'
var dir = "/home/we/dust/code/fake/engine/drones";
var ro = "VH_READONLY".getenv.notNil;
var t = { |k, f| var v = try { f.value } { |e| e.errorString.postln; "error" }; ("RESULT " ++ k ++ "=" ++ v).postln };
var m = { |k, f| if(ro.not) { t.value(k, f) } }; // operations that write: not in the control run, so that it never creates a real /home/we
var real = Platform.userHomeDir;
var s = Server.default, b, done, info;
t.value("entries", { PathName(dir).entries.size });
t.value("glob", { (dir +/+ "*.scd").pathMatch.size });
t.value("exists", { File.exists(dir +/+ "a.scd") });
t.value("type_dir", { File.type(dir) });
t.value("read", { File.readAllString(dir +/+ "a.scd").stripWhiteSpace });
t.value("load", { (dir ++ "/../answer.scd").load });
t.value("realpath_is_real", { File.realpath(dir) == (real ++ "/dust/code/fake/engine/drones") });
m.value("mkdir", { File.mkdir("/home/we/dust/data/made"); File.exists(real ++ "/dust/data/made") });
m.value("write_seen_by_real_path", { File.use("/home/we/dust/data/made/w.txt", "w", { |f| f.write("written") }); File.readAllString(real ++ "/dust/data/made/w.txt") });
m.value("copy", { File.copy("/home/we/dust/data/made/w.txt", "/home/we/dust/data/made/c.txt"); File.exists(real ++ "/dust/data/made/c.txt") });
m.value("deleted", { File.delete("/home/we/dust/data/made/c.txt"); File.exists(real ++ "/dust/data/made/c.txt").not });
t.value("size", { File.fileSize("/home/we/dust/audio/test.wav") });
t.value("soundfile", { SoundFile.openRead("/home/we/dust/audio/test.wav").notNil });
t.value("soundfile_collect", { SoundFile.collect("/home/we/dust/audio/*.wav").size });
m.value("shell", { "echo from-shell > /home/we/dust/data/shell.txt".systemCmd; File.exists(real ++ "/dust/data/shell.txt") });
m.value("shell_out", { "cat /home/we/dust/data/shell.txt".unixCmdGetStdOut.stripWhiteSpace });
t.value("lookalike_untouched", { File.exists("/home/weird/x").not and: { PathName("/tmp/home/we/x").fullPath == "/tmp/home/we/x" } });
t.value("literal_outside", { File.exists("@WEIRD@/home/we/file.txt") });
t.value("tilde_still_works", { "~/x".standardizePath == (real ++ "/x") });
if(ro) { 0.exit };
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
s.waitForBoot({
	t.value("buffer_read", { b = Buffer.read(s, "/home/we/dust/audio/test.wav"); s.sync; b.numFrames });
	t.value("buffer_read_channel", { b = Buffer.readChannel(s, "/home/we/dust/audio/test.wav", channels: [0]); s.sync; b.numFrames });
	t.value("literal_b_allocRead", {
		s.sendMsg("/b_allocRead", 77, "/home/we/dust/audio/test.wav");
		s.sync;
		done = Condition.new;
		OSCFunc({ |msg| info = msg[2]; done.test = true; done.signal }, '/b_info', s.addr).oneShot;
		done.test = false;
		s.sendMsg("/b_query", 77);
		done.wait;
		info
	});
	t.value("buffer_write", {
		b = Buffer.alloc(s, 4800, 1);
		s.sync;
		b.write("/home/we/dust/data/written.wav", "wav", "int16");
		s.sync;
		0.3.wait;
		File.exists(real ++ "/dust/data/written.wav")
	});
	t.value("d_load_synth", {
		File.mkdir("/home/we/dust/data/defs");
		SynthDef(\vhtest, { Out.ar(0, SinOsc.ar(440, 0, 0.1)) }).writeDefFile("/home/we/dust/data/defs");
		s.sendMsg("/d_load", "/home/we/dust/data/defs/vhtest.scsyndef");
		s.sync;
		s.sendMsg("/s_new", "vhtest", 1001, 0, 1);
		s.sync;
		done = Condition.new;
		OSCFunc({ |msg| info = msg[3]; done.test = true; done.signal }, '/status.reply', s.addr).oneShot;
		done.test = false;
		s.sendMsg("/status");
		done.wait;
		info
	});
	0.exit;
});
SC
sed -i "s|@WEIRD@|$T/weird|" "$T/fake.scd"
# the weird folder is not /home/we: "/x/home/we" must stay as it is

# a dummy jackd for the server part
if [ -z "${SC_FIXTURE_JACK:-}" ]; then
    jackd -d dummy -r 48000 -p 1024 > "$T/jackd.log" 2>&1 &
    JACK_PID=$!
    sleep 2
fi

run_sc() { # name, include paths (space separated) -> $T/<name>.out
    local name="$1"; shift
    { echo "includePaths:"; for p in "$@"; do echo "    - \"$p\""; done; echo "excludePaths:"; echo "    []"; echo "postInlineWarnings: false"; } > "$T/$name.yaml"
    env ${VH_RO:+VH_READONLY=1} HOME="$H" JACK_NO_START_SERVER=1 QT_QPA_PLATFORM=offscreen QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox \
        timeout 120 "$SCLANG" -D -l "$T/$name.yaml" "$T/fake.scd" > "$T/$name.out" 2>&1 < /dev/null
}
res() { sed -n "s/^RESULT $2=//p" "$T/$1.out" | head -n 1; }

echo "== without the fix (what the owner's laptop does): nothing is found"
VH_RO=1; run_sc control; VH_RO=
[ "$(res control entries)" = 0 ] && [ "$(res control glob)" = 0 ] && [ "$(res control exists)" = false ] && [ "$(res control soundfile)" = false ] && ok "PathName(...).entries, pathMatch, File.exists and SoundFile find nothing under /home/we (the bug)" || { bad "the control run does not show the bug"; grep RESULT "$T/control.out" | head; }

echo "== with sc/linux/NornsVirtualHome.sc"
run_sc fixed "$REPO/sc/linux"
grep -q "RESULT" "$T/fixed.out" || { bad "no result at all"; tail -20 "$T/fixed.out"; }
chk() { # name expected
    local got; got="$(res fixed "$1")"
    [ "$got" = "$2" ] && ok "$1 = $2" || bad "$1: got '$got', want '$2'"
}
chk entries 2
chk glob 2
chk exists true
chk type_dir directory
chk read '(freq: 220)'
chk load 42
chk realpath_is_real true
chk write_seen_by_real_path written
chk copy true
chk deleted true
chk size 9644
chk soundfile true
chk soundfile_collect 1
chk shell true
chk shell_out from-shell
chk lookalike_untouched true
chk literal_outside true
chk tilde_still_works true
chk buffer_read 4800
chk buffer_read_channel 4800
chk literal_b_allocRead 4800
chk buffer_write true
chk d_load_synth 1
grep -q "^ERROR" "$T/fixed.out" && { bad "an ERROR in the fixed run"; grep "^ERROR" "$T/fixed.out" | head -5; } || ok "no ERROR line in the fixed run"
[ -z "$(find "$H/dust" -newer "$T/fake.scd" -path '*home/we*' 2> /dev/null)" ] && [ ! -e /home/we ] && ok "nothing was created at a literal /home/we" || bad "a literal /home/we exists or was written"

[ $FAIL = 0 ] && echo "sc_virtual_home_test: all passed"
exit $FAIL
