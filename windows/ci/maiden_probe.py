#!/usr/bin/env python3
"""windows/ci/maiden_probe.py HOME OUT: what a browser does with maiden, from the outside, while the program runs headless on the runner.
   1. maiden answers on 127.0.0.1:5000 (API and web app)  2. a script is installed from a zip over HTTP (an accented, spaced name) and lands in dust/code  3. the norns console (websocket 5555) runs a line of Lua
   4. a page from another site is refused by the console  5. the sclang console (5556) evaluates a line.
   every result is a line 'PROBE <name> ok|FAIL <what>' in OUT. stdlib only."""
import base64, http.server, json, os, socket, sys, threading, time, urllib.request, urllib.error, zipfile, tempfile

HOME, OUT = sys.argv[1], sys.argv[2]
PORT = int(os.environ.get("NORNS_MAIDEN_PORT", "5000"))
lines = []
def parse_vt_note(line):
    """M31: 'VT_NOTE mode|note|window note' -> (mode, note, window note); the window note may hold '|' and is never padded."""
    g = line[line.index("VT_NOTE ") + 8:].strip().split("|", 2)
    g += [""] * (3 - len(g))
    return g[0], g[1], g[2]


def result(name, ok, what=""):
    lines.append("PROBE %s %s %s" % (name, "ok" if ok else "FAIL", what))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

def get(path, timeout=5):
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (PORT, path), timeout=timeout) as r:
        return r.status, r.read()

def ws_connect(port, origin=None, timeout=10):
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = "GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: bus.sp.nanomsg.org\r\n" % (port, key)
    if origin:
        req += "Origin: %s\r\n" % origin
    s.sendall((req + "\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise ConnectionError("closed during the handshake: " + repr(buf))
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        raise ConnectionError(head.split(b"\r\n")[0].decode())
    return s, rest

def ws_send(s, text):
    data = text.encode()
    mask = os.urandom(4)
    hdr = bytes([0x81])
    n = len(data)
    hdr += bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + n.to_bytes(2, "big")
    s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def ws_frames(s, first=b"", seconds=10):
    """text of the frames that arrive within `seconds`"""
    s.settimeout(1.0)
    buf, out, end = first, [], time.time() + seconds
    while time.time() < end:
        while len(buf) >= 2:
            n = buf[1] & 0x7F
            off = 2
            if n == 126:
                if len(buf) < 4: break
                n, off = int.from_bytes(buf[2:4], "big"), 4
            if len(buf) < off + n: break
            out.append(buf[off:off + n].decode("utf-8", "replace"))
            buf = buf[off + n:]
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            continue
        except OSError:
            break
    return "".join(out)

def repl(port, line, want, seconds, origin=None):
    s, rest = ws_connect(port, origin)
    try:
        ws_send(s, line)
        text = ""
        end = time.time() + seconds
        while time.time() < end and want not in text:
            text += ws_frames(s, rest if not text else b"", 2)
            rest = b""
        vt = [l for l in text.splitlines() if 'VT_' in l]
        return want in text, ('\n'.join(vt) if vt else text[-200:])
    finally:
        s.close()

# VERDANDI_PROBE=twins: what the owner did with the script twins (M10): wait for the script and its engine (the real lib/engine_twins.sc), load a sample into both voices, look at the server for a while.
# nothing else of this file runs then. every result is a line 'PROBE <name> ok|FAIL <what>'
if os.environ.get("VERDANDI_PROBE") == "twins":
    WAV = "/home/we/dust/audio/ci/test.wav"
    _repl = repl
    def repl(port, line, want, seconds, origin=None):
        """the consoles take one connection at a time and sometimes refuse for a moment right after another: try again"""
        last = None
        for _ in range(8):
            try:
                return _repl(port, line, want, seconds, origin)
            except (ConnectionError, OSError) as e:
                last = e
                time.sleep(2)
        raise last
    def alive(tag, secs=30):
        try:
            ok, tail = repl(5556, '("VT_ALIVE " ++ Crone.server.serverRunning).postln;\x1b', "VT_ALIVE true", secs)
        except Exception as e:
            ok, tail = False, "sclang did not answer: %s" % e
        result(tag, ok, "the server answers (serverRunning)" if ok else "the server is not running: " + repr(tail))
        return ok
    # M10: a long file name under an [ext] folder (the owner's norns.log: "Tape Reader:: cannot open sndfile ... for input"): a wav with a 130 character name in a folder outside dust, linked as [ext] <folder>; the whole path is
    # over 260 characters. audio.file_info (matron) and the Tape Reader (crone, tape_play_open) must open it
    try:
        import wave, struct, math
        src = os.path.join(os.path.dirname(HOME.rstrip("\\/")), "long source " + "s" * 70)
        longname = ("a long sample name " * 8)[:126] + ".wav"
        def lp(p): return "\\\\?\\" + os.path.abspath(p)
        os.makedirs(lp(src), exist_ok=True)
        w = wave.open(lp(os.path.join(src, longname)), "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 330 * i / 48000))) for i in range(48000))); w.close()
        fwd = src.replace("\\", "/")
        ok, tail = repl(5555, "local ok, msg, name = _norns.ext_add('%s') print('VT_EXT ' .. tostring(ok) .. ' <<' .. tostring(name) .. '>>')\n" % fwd, "VT_EXT true", 60)
        import re
        m = re.search(r"VT_EXT true <<(.*?)>>", tail or "")
        name = m.group(1) if m else ""
        result("twins-ext-add", bool(name), "the long folder was linked as [%s]" % name if name else "ext_add: " + repr(tail))
        vpath = "/home/we/dust/audio/%s/%s" % (name, longname)
        ok, tail = repl(5555, "local ch, fr, sr = audio.file_info('%s') print('VT_INFO ' .. tostring(ch) .. ' ' .. tostring(fr) .. ' ' .. tostring(sr) .. ' len ' .. %d)\n" % (vpath, len(vpath)), "VT_INFO", 30)
        m = re.search(r"VT_INFO (\d+) (\d+) (\d+) len (\d+)", tail or "")
        good = bool(m) and int(m.group(2)) == 48000
        result("twins-longpath-info", good, "audio.file_info reads the %s character virtual path (frames %s)" % (m.group(4) if m else "?", m.group(2) if m else "?") if good else "audio.file_info could not open it: " + repr(tail))
        if os.environ.get("VERDANDI_PROBE_WAV") == "ext":
            WAV = vpath # the sample of this scenario is the file with the long name under the [ext] link
        ok, tail = repl(5555, "audio.tape_play_open('%s') audio.tape_play_start() print('VT_TAPE started')\n" % vpath, "VT_TAPE started", 30)
        time.sleep(3)
        repl(5555, "audio.tape_play_stop() print('VT_TAPE stopped')\n", "VT_TAPE stopped", 15)
        result("twins-longpath-tape", ok, "the Tape Reader was asked to play it (its log line is checked in norns.log)")
    except Exception as e:
        result("twins-longpath", False, "%s" % e)
    try:
        ok, tail = repl(5555, "print('VT_TW ' .. tostring(norns.state.name) .. ' ' .. tostring(engine.name))\n", "VT_TW twins twins", 240)
        result("twins-script", ok, "the script twins is loaded with engine twins" if ok else "twins did not load: " + repr(tail))
        ready = False
        for _ in range(60):
            ok, tail = repl(5555, "local n = 0 for _ in pairs(engine.commands or {}) do n = n + 1 end print('VT_CMDS ' .. n)\n", "VT_CMDS", 10)
            import re
            m = re.search(r"VT_CMDS (\d+)", tail or "")
            if m and int(m.group(1)) > 100:
                ready = True; result("twins-engine", True, "the engine reported %s commands" % m.group(1)); break
            time.sleep(2)
        if not ready:
            result("twins-engine", False, "the engine did not report its commands")
        alive("twins-alive-before")
        time.sleep(3)
        for v in (1, 2):
            ok, tail = repl(5555, "params:set('%dsample', '%s') print('VT_SET %d')\n" % (v, WAV, v), "VT_SET %d" % v, 30)
            result("twins-sample%d" % v, ok, "voice %d was given the wav through the script's own param (engine.read)" % v if ok else "param not set: " + repr(tail))
            time.sleep(8)
            alive("twins-alive-after-sample%d" % v)
        # run for a while, as the owner's session did
        for k in range(4):
            time.sleep(10)
            if not alive("twins-alive-%ds" % (10 * (k + 1)), 20):
                break
        result("twins-done", True, "")
    except Exception as e:
        result("twins-error", False, "%s" % e)
        try:
            import subprocess
            for im in ("norns.exe", "ws-wrapper.exe", "sclang.exe", "scsynth.exe"):
                r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + im, "/NH"], capture_output=True, text=True)
                print("PROCESS", im, "->", (r.stdout or r.stderr).strip().replace("\n", " | ")[:200])
            r = subprocess.run(["netstat", "-ano", "-p", "TCP"], capture_output=True, text=True)
            print("LISTENING 5555/5556:", [l.strip() for l in r.stdout.splitlines() if ":5555" in l or ":5556" in l][:6])
        except Exception as e2:
            print("diagnostics failed", e2)
    sys.exit(0)

# VERDANDI_PROBE=kill: the server (scsynth.exe) is ended from outside, three times (M10, docs/port/phase-m10.md). the launcher has to notice, say so in launcher.log and on the norns screen, and start everything again twice;
# the third time it says that it stops trying and leaves norns running. every step is a line 'PROBE <name> ok|FAIL <what>'
if os.environ.get("VERDANDI_PROBE") == "kill":
    import subprocess, re
    LOG = os.path.join(HOME, "logs", "launcher.log")
    NLOG = os.path.join(HOME, "logs", "norns.log")
    def text(p):
        try:
            return open(p, "r", encoding="utf-8", errors="replace").read()
        except OSError:
            return ""
    def wait_for(fn, secs, step=2):
        end = time.time() + secs
        while time.time() < end:
            try:
                if fn(): return True
            except Exception:
                pass
            time.sleep(step)
        return False
    def norns_up():
        ok, _ = repl(5555, "print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
        return ok
    def server_up():
        ok, _ = repl(5556, '("VT_ALIVE " ++ Crone.server.serverRunning).postln;\x1b', "VT_ALIVE true", 8)
        return ok
    # M21: VERDANDI_KILL_WHO=sclang ends sclang.exe itself (a crash of the language: nothing is printed in sclang.log) instead of the server
    who = os.environ.get("VERDANDI_KILL_WHO", "scsynth")
    exe = "sclang.exe" if who == "sclang" else "scsynth.exe"
    try:
        for k in (1, 2, 3):
            up = wait_for(lambda: norns_up() and server_up(), 240)
            result("kill-%d-up" % k, up, "norns and its server answer before the kill (round %d)" % k)
            if not up: break
            r = subprocess.run(["taskkill", "/F", "/IM", exe], capture_output=True, text=True)
            result("kill-%d-done" % k, r.returncode == 0, exe + " ended from outside: " + (r.stdout + r.stderr).strip()[:120])
            if k < 3:
                saw = wait_for(lambda: ("starting everything again (round %d)" % (k + 1)) in text(LOG), 90)
                more = ""
                if not saw:  # (what the processes and the log of sclang say: for a failure that has to be understood from the report alone)
                    try:
                        tl = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
                        more = " | processes: " + " ".join(l.split('","')[0].strip('"') + ":" + l.split('","')[1] for l in tl.splitlines() if any(n in l.lower() for n in ("sclang", "scsynth", "ws-wrapper", "norns", "verdandi")))
                    except Exception as e:
                        more = " | tasklist: %s" % e
                    more += " | sclang.log: " + repr(text(os.path.join(HOME, "logs", "sclang.log"))[-400:])
                result("kill-%d-restarted" % k, saw, "launcher.log says the round was started again (round %d)" % (k + 1) if saw else "no restart in launcher.log: " + repr(text(LOG)[-300:]) + more)
                noted = wait_for(lambda: ("sclang.exe itself ended on its own, exit code" if who == "sclang" else "stopped on its own, exit code") in text(LOG), 5)
                result("kill-%d-logged" % k, noted, "launcher.log names the stop and its exit code")
            else:
                gave = wait_for(lambda: "stopped on its own again" in text(LOG), 60)
                if who == "sclang": gave = gave and "sclang.exe stopped on its own again" in text(LOG)
                result("kill-3-gave-up", gave, "launcher.log says it does not restart again" if gave else "no 'again' line: " + repr(text(LOG)[-300:]))
                time.sleep(15)
                result("kill-3-no-round-4", "starting everything again (round 4)" not in text(LOG), "no fourth round was started")
                result("kill-3-norns-alive", norns_up(), "norns is still running and answers")
                shown = wait_for(lambda: ("sclang keeps stopping" if who == "sclang" else "SuperCollider keeps stopping") in text(NLOG), 30)
                result("kill-3-message", shown, "norns.log has the plain message that it keeps stopping" if shown else "message not in norns.log")
        # the messages of the first two stops reached the norns screen
        n = text(NLOG)
        result("kill-notes", n.count("### sclang (the SuperCollider language) stopped (error" if who == "sclang" else "### SuperCollider stopped (error") >= 2, "norns.log has the restart message of each of the two restarts (on the screen as well)")
        result("kill-done", True, "")
    except Exception as e:
        result("kill-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=tape (M21): a tape recording runs while norns is ended in one of the ways (VERDANDI_TAPE_END: restart = SYSTEM > RESTART, request = the launcher's restart request after a server stop, quit = the quit event,
# shutdown = SLEEP without the tape page's own stop, launcher = the launcher's end at --exit-after). the file is checked by the shell (windows/ci/wav_check.py)
if os.environ.get("VERDANDI_PROBE") == "tape":
    mode = os.environ.get("VERDANDI_TAPE_END", "restart")
    def run(line, want, seconds=30):
        # M30: the console takes one connection at a time and refuses for a moment right after another one closed (WinError 10061): the twins probes already ask again after two seconds. on f599d36 one such refusal
        # between two steps of the reopen check ended the whole check ("asio-error"), and the ASIO zip was not published a third time
        last = None
        for _ in range(8):
            try:
                return repl(5555, line, want, seconds)
            except (ConnectionError, OSError) as e:
                last = e
                time.sleep(2)
        raise last
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("tape-up", up, "norns answers (%s)" % mode)
        time.sleep(6)
        ok, tail = run("audio.tape_record_open(_path.tape .. 'm21.wav') audio.tape_record_start() print('VT_REC started')\n", "VT_REC started", 20)
        time.sleep(7)
        ok2, tail2 = run("print('VT_REC2 ' .. tostring(audio.tape_is_recording()))\n", "VT_REC2", 20)
        result("tape-recording", ok and "VT_REC2 true" in tail2, "the tape records: " + tail2.strip()[-30:])
        if mode == "restart":
            try: run("_norns.restart() print('VT_END restart')\n", "VT_END", 10)
            except Exception: pass
        elif mode == "request":
            with open(os.path.join(HOME, ".norns-request-restart"), "w") as f: f.write("1")
        elif mode == "quit":
            try: run("print('VT_END ' .. tostring(_norns.test_quit()))\n", "VT_END", 10)
            except Exception: pass
        elif mode == "shutdown":
            try: run("norns.shutdown() print('VT_END shutdown')\n", "VT_END", 10)
            except Exception: pass
        # (launcher: nothing is sent: the launcher ends norns.exe itself at --exit-after)
        time.sleep(5)
        result("tape-end-asked", True, "norns was ended the way '%s' says" % mode)
    except Exception as e:
        result("tape-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=burst: a fast turning of the drawn knobs (M11): 4000 turns of E1 in a tight Lua loop (what a MIDI encoder can do), then the window gets a few seconds to catch up. the window logs one line
# ("enc display: N turns, M draws, slowest draw ..., a turn waited ... ms in the queue at the most, the last draw ... ms after the first turn") that the CI reads from norns.log
if os.environ.get("VERDANDI_PROBE") == "burst":
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = repl(5555, "print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("burst-up", up, "norns answers")
        time.sleep(5)
        ok, tail = repl(5555, "local t0 = util.time() for i = 1, 4000 do _norns.show_control(2, 1, (i % 2 == 0) and 1 or 1) end print('VT_BURST ' .. 'sent')\n", "VT_BURST sent", 60)
        result("burst-sent", ok, "4000 turns of E1 were sent to the window")
        time.sleep(8)
        result("burst-done", True, "")
    except Exception as e:
        result("burst-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=arc (M13): the virtual arc in the real program. the program runs with VERDANDI_TEST_HOOKS=1. the arc window is opened the way its button does it (window_action "arc"), a picture of it is saved with the LEDs off, a small script
# (windows/ci/arcprobe.lua, seeded in dust/code/arcprobe) draws on the rings and counts the deltas and keys, the window is driven through the functions its mouse events call (a wheel notch, a drag round a ring, a ring press, a turn the way a MIDI-mapped
# encoder sends it), a second picture is saved, the arc is closed and opened again. the results are 'PROBE arc-... ok|FAIL' lines
if os.environ.get("VERDANDI_PROBE") == "arc":
    def run(line, want, seconds=30):
        return repl(5555, line, want, seconds)
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("arc-up", up, "norns answers")
        time.sleep(3)
        # the arc window, the way the ARC button opens it; the device must appear in the arc list a moment later
        ok, tail = run("print('VT_OPEN ' .. tostring(_norns.window_action('arc')))\n", "VT_OPEN true", 20)
        result("arc-open", ok, "the ARC action reached the window" if ok else "the window did not take the ARC action: " + repr(tail))
        found = False
        for _ in range(20):
            ok, tail = run("local n = 0 local nm = '' for _, d in pairs(arc.devices) do n = n + 1 nm = d.name end print('VT_ARCS ' .. n .. ' ' .. nm)\n", "VT_ARCS", 8)
            if ok and "VT_ARCS 1 " in tail:
                found = True; break
            time.sleep(1)
        result("arc-device", found, ("the virtual arc is in the arc list: " + tail.strip()[-60:]) if found else "no arc device after the window opened: " + repr(tail))
        # a picture with every LED off
        ok, tail = run("print('VT_SHOT0 ' .. tostring(_norns.arc_test(4, 1, 0)))\n", "VT_SHOT0", 10)
        result("arc-shot-dark", ok and "VT_SHOT0 true" in tail, "the arc window was saved with the LEDs off (arc_window_0.png)")
        # the small script
        ok, tail = run("norns.script.load('/home/we/dust/code/arcprobe/arcprobe.lua') print('VT_LOAD ' .. 'sent')\n", "VT_LOAD sent", 20)
        ready = False
        for _ in range(30):
            ok, tail = run("print('VT_READY ' .. tostring(ARCP and ARCP.ready) .. ' ' .. tostring(ARCP and ARCP.name))\n", "VT_READY", 8)
            if ok and "VT_READY true" in tail:
                ready = True; break
            time.sleep(1)
        result("arc-script", ready, "the script started and found the arc: " + tail.strip()[-70:] if ready else "the script did not start: " + repr(tail))
        time.sleep(1)
        # the window as a mouse drives it: ring 1 one wheel notch (+2), ring 2 a quarter turn round the ring (about +64), ring 3 pressed and let go (a key, no delta), ring 4 turned by 100 ticks the way a mapped encoder does (_norns.arc_turn);
        # ring 1 also gets a mapped turn of 50 on top of its notch: the sum is 52, nothing counted twice
        line = ("_norns.arc_test(1, 1, 100) _norns.arc_test(2, 2, 90) _norns.arc_test(3, 3, 1) _norns.arc_test(3, 3, 0) "
                "print('VT_TURN ' .. tostring(_norns.arc_turn(4, 100)) .. ' ' .. tostring(_norns.arc_turn(1, 50)))\n")
        ok, tail = run(line, "VT_TURN", 20)
        result("arc-input-sent", ok and "VT_TURN true true" in tail, "wheel, drag, ring press and mapped turns were sent to the window: " + tail.strip()[-40:])
        time.sleep(4)
        ok, tail = run("print('VT_RES ' .. table.concat(ARCP.sum, ',') .. ' ' .. table.concat(ARCP.msgs, ',') .. ' [' .. table.concat(ARCP.keys, ' ') .. ']')\n", "VT_RES", 20)
        m = None
        import re
        m = re.search(r"VT_RES (-?\d+),(-?\d+),(-?\d+),(-?\d+) (\d+),(\d+),(\d+),(\d+) \[([^\]]*)\]", tail)
        if m:
            s = [int(m.group(i)) for i in range(1, 5)]; c = [int(m.group(i)) for i in range(5, 9)]; keys = m.group(9)
            result("arc-wheel", s[0] == 52 and c[0] == 2, "ring 1: a wheel notch (+2) and a mapped turn (+50) arrived as %d in %d messages (52 in 2 expected: nothing counted twice)" % (s[0], c[0]))
            result("arc-drag", 60 <= s[1] <= 68, "ring 2: a quarter turn of the pointer round the ring arrived as %d ticks (64 expected, +-4)" % s[1])
            result("arc-press", keys == "3:1 3:0" and s[2] == 0, "ring 3: the press and the release reached the script as keys [%s] and no delta (%d)" % (keys, s[2]))
            result("arc-mapped", s[3] == 100, "ring 4: a mapped turn of 100 ticks arrived as %d" % s[3])
        else:
            result("arc-wheel", False, "no result line: " + repr(tail))
        # the drag up and down (ARC DRAG, Windows 0.10.5), through the functions the mouse events call, with real numbers: ring 1 up 86 points = one lap (1032 ticks, 12 a point), ring 2 down 86 = -1032, ring 3 up 86 with Shift = 258,
        # ring 4 up 20 with Ctrl = 960 (four times), ring 1 again up 200 points, which ends 110 points above the window: the drag goes on there until the release (3432 in all on ring 1). the program logs the state of the drag and of the capture
        ok, tail = run("ARCP.sum = {0, 0, 0, 0} _norns.arc_test(5, 1, 86) _norns.arc_test(5, 2, -86) _norns.arc_test(6, 3, 86) _norns.arc_test(7, 4, 20) _norns.arc_test(5, 1, 200) print('VT_UD sent')\n", "VT_UD sent", 20)
        result("arc-ud-sent", ok and "VT_UD sent" in tail, "five drags up and down were sent to the window: " + tail.strip()[-30:])
        time.sleep(4)
        ok, tail = run("print('VT_UDRES ' .. table.concat(ARCP.sum, ','))\n", "VT_UDRES", 20)
        m = re.search(r"VT_UDRES (-?\d+),(-?\d+),(-?\d+),(-?\d+)", tail)
        if m:
            u = [int(m.group(i)) for i in range(1, 5)]
            result("arc-ud-up", abs(u[0] - 3432) <= 24 and u[0] > 0, "ring 1: 86 points up (1032) and 200 points up, leaving the window (2400) arrived as %d (3432 expected, clockwise)" % u[0])
            result("arc-ud-down", abs(u[1] + 1032) <= 12, "ring 2: 86 points down arrived as %d (-1032 expected, counter-clockwise)" % u[1])
            result("arc-ud-shift", abs(u[2] - 258) <= 6, "ring 3: 86 points up with Shift arrived as %d (258 expected, a quarter)" % u[2])
            result("arc-ud-ctrl", abs(u[3] - 960) <= 12, "ring 4: 20 points up with Ctrl arrived as %d (960 expected, four times)" % u[3])
        else:
            result("arc-ud-up", False, "no result line: " + repr(tail))
        # the picture with the LEDs the script drew
        ok, tail = run("print('VT_SHOT1 ' .. tostring(_norns.arc_test(4, 1, 1)))\n", "VT_SHOT1", 10)
        result("arc-shot-lit", ok and "VT_SHOT1 true" in tail, "the arc window was saved with the script's LEDs (arc_window_1.png)")
        # closed and opened again: the device goes and comes back, the script's port is the same
        ok, tail = run("print('VT_CLOSE ' .. tostring(_norns.window_action('arc')))\n", "VT_CLOSE", 10)
        time.sleep(3)
        ok, tail = run("local n = 0 for _ in pairs(arc.devices) do n = n + 1 end print('VT_AFTERCLOSE ' .. n)\n", "VT_AFTERCLOSE", 10)
        result("arc-close", ok and "VT_AFTERCLOSE 0" in tail, "closing the window removes the arc device: " + tail.strip()[-30:])
        ok, tail = run("print('VT_REOPEN ' .. tostring(_norns.window_action('arc')))\n", "VT_REOPEN", 10)
        back = False
        for _ in range(15):
            ok, tail = run("local n = 0 local port for _, d in pairs(arc.devices) do n = n + 1 port = d.port end print('VT_BACK ' .. n .. ' port ' .. tostring(port))\n", "VT_BACK", 8)
            if ok and "VT_BACK 1 port 1" in tail:
                back = True; break
            time.sleep(1)
        result("arc-reopen", back, "opened again: the arc is back on port 1: " + tail.strip()[-30:])
    except Exception as e:
        result("arc-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=cc2 (M15, docs/port/phase-m15.md): the owner's route to cheat codes 2, in the real program. maiden installs cheat_codes_2 from the community catalog (the real list, the real repository, with the git submodule
# lib/nb that the script checks for) and nb by its address; util.file_exists is asked about those folders; cheat codes 2 is loaded with the OLD util.file_exists (io.open only: the owner's failure: its own "something is missing"
# script is loaded inside the load and the next include fails) and then with the real one (it loads). no network (the catalog does not arrive): 'PROBE cc2-network SKIP', nothing else is asked.
if os.environ.get("VERDANDI_PROBE") == "cc2":
    import urllib.parse
    def run(line, want, seconds=40):
        return repl(5555, line, want, seconds)
    def post(path, timeout=240, method="POST"):
        req = urllib.request.Request("http://127.0.0.1:%d%s" % (PORT, path), method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read().decode("utf-8", "replace")[:300]
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")[:300]
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("cc2-up", up, "norns answers")
        # the catalog: maiden fetches it when it starts
        have = False
        for _ in range(45):
            try:
                st, body = get("/api/v1/catalog/community")
                if st == 200 and b"cheat_codes_2" in body: have = True; break
            except Exception:
                pass
            time.sleep(2)
        if not have:
            lines.append("PROBE cc2-network SKIP the community catalog did not arrive (no network?): nothing asked")
            with open(OUT, "w", encoding="utf-8") as f: f.write("\n".join(lines) + "\n")
            sys.exit(0)
        result("cc2-catalog", True, "the community catalog has cheat_codes_2")
        code = os.path.join(HOME, "dust", "code")
        st, body = post("/api/v1/catalog/community/install/cheat_codes_2")
        result("cc2-install", st in (200, 201), "maiden installed cheat_codes_2 from the catalog: %s %s" % (st, body.replace("\n", " ")[:120]))
        nbfile = os.path.join(code, "cheat_codes_2", "lib", "nb", "lib", "nb.lua")
        result("cc2-submodule", os.path.isfile(nbfile) and os.path.isfile(os.path.join(code, "cheat_codes_2", "lib", "cc_pattern_time.lua")),
               "the git submodule lib/nb came with the script: %s; lib/cc_pattern_time.lua is there" % (nbfile if os.path.isfile(nbfile) else "lib/nb/lib/nb.lua is NOT there"))
        st, body = post("/api/v1/project/install?url=" + urllib.parse.quote("https://github.com/sixolet/nb", safe=""))
        result("cc2-nb-install", st in (200, 201) and os.path.isfile(os.path.join(code, "nb", "lib", "player.lua")), "maiden installed nb by its address: %s %s" % (st, body.replace("\n", " ")[:100]))
        # util.file_exists for folders, the way scripts ask
        ok, tail = run("print('VT_FE ' .. tostring(util.file_exists(_path.code .. 'cheat_codes_2/lib/nb/lib/')) .. ' ' .. tostring(util.file_exists(_path.code .. 'nb')) .. ' ' .. tostring(util.file_exists(_path.code .. 'cheat_codes_2/lib/cc_pattern_time.lua')) .. ' ' .. tostring(util.file_exists(_path.code .. 'no_such_folder/')))\n", "VT_FE", 20)
        result("cc2-file-exists", ok and "VT_FE true true true false" in tail, "util.file_exists: lib/nb/lib/ (a folder with a slash), the folder nb, a file, a missing folder: " + tail.strip()[-60:])
        # the owner's failure: the check with io.open only (the old util.file_exists)
        ok, tail = run("do local fe = util.file_exists util.file_exists = function(n) local f = io.open(n, 'r') if f ~= nil then f:close() return true end return false end norns.script.load('code/cheat_codes_2/cheat_codes_2.lua') util.file_exists = fe end print('VT_OLD ' .. tostring(norns.state.shortname))\n", "VT_OLD", 60)
        result("cc2-old-way-ran", ok, "cheat codes 2 was loaded with the old util.file_exists: " + tail.strip()[-60:])
        time.sleep(3)
        # and with the real one
        ok, tail = run("norns.script.load('code/cheat_codes_2/cheat_codes_2.lua') print('VT_NEW ' .. tostring(norns.state.shortname) .. ' ' .. tostring(nb ~= nil) .. ' ' .. tostring(type(redraw)))\n", "VT_NEW", 90)
        result("cc2-load", ok and "VT_NEW cheat_codes_2 true function" in tail, "cheat codes 2 loaded: " + tail.strip()[-80:])
        time.sleep(8)
        ok, tail = run("print('VT_STILL ' .. tostring(norns.state.shortname))\n", "VT_STILL", 20)
        result("cc2-stays", ok and "VT_STILL cheat_codes_2" in tail, "the script is still the loaded script a few seconds later: " + tail.strip()[-40:])
        # remove it again through maiden (the removal is in maiden.log)
        st, body = post("/api/v1/project/cheat_codes_2", method="DELETE")
        result("cc2-remove", st == 200, "maiden removed cheat_codes_2: %s" % st)
    except SystemExit:
        raise
    except Exception as e:
        result("cc2-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=pin (M16): the PIN button (always on top) in the real program, with real windows (the program runs WITHOUT --headless, with VERDANDI_TEST_HOOKS=1). the main window, the arc window and the detached screen window are opened, PIN is pressed the way the button
# is (the action "pin": button_action), and after every step the program writes one line "pin report N: ..." to norns.log with what SDL and Windows (WS_EX_TOPMOST) say about each window. then the MIDI action: learned from a note of a port, a note from the learned
# port toggles it, a note from another port does not. results are 'PROBE pin-... ok|FAIL' lines
if os.environ.get("VERDANDI_PROBE") == "pin":
    import re
    LOG = os.path.join(HOME, "logs", "norns.log")
    def run(line, want, seconds=30):
        return repl(5555, line, want, seconds)
    def report(tok):
        ok, tail = run("print('VT_PIN ' .. tostring(_norns.pin_report(%d)))\n" % tok, "VT_PIN", 15)
        asked = tail.strip()[-40:] if isinstance(tail, str) else repr(tail)
        end = time.time() + 12
        seen = ""
        while time.time() < end:
            for path in (os.path.join(HOME, "pin_report.log"), LOG):
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as f:
                        text = f.read()
                except OSError:
                    continue
                seen += "%s:%d " % (os.path.basename(path), len(text))
                for l in text.splitlines()[::-1]:
                    m = re.search(r"pin report %d: (.*)" % tok, l)
                    if m:
                        d = {}
                        for part in m.group(1).split():
                            k, v = part.split("=", 1)
                            d[k] = v
                        return d, m.group(1)
            time.sleep(0.5)
        return None, "no line 'pin report %d' (the call said: %s; files seen: %s; home %s)" % (tok, asked, seen[:80] or "none", HOME)
    def expect(name, tok, state, wins, what):
        d, raw = report(tok)
        if d is None:
            result(name, False, raw); return
        good = d.get("state") == str(state) and d.get("lit") == str(state)
        bad = []
        for w in ("main", "grid", "arc", "keys", "screen"):
            want = wins.get(w, "-")
            got = d.get(w, "?")
            if want == "-":
                if got != "-": good = False; bad.append("%s should be closed" % w)
            else:
                # SDL's flag / Windows's own topmost style: both must say what is wanted
                if got != "%s/%s" % (want, want): good = False; bad.append("%s is %s, wanted %s/%s" % (w, got, want, want))
        result(name, good, "%s: %s%s" % (what, raw, (" (" + "; ".join(bad) + ")") if bad else ""))
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("pin-up", up, "norns answers")
        time.sleep(3)
        expect("pin-start-off", 1, 0, {"main": 0}, "at the start it is off and only the main window is open")
        ok, tail = run("print('VT_A ' .. tostring(_norns.window_action('arc')) .. ' ' .. tostring(_norns.window_action('detach')))\n", "VT_A", 20)
        result("pin-trace-open", True, "window_action arc/detach said: " + tail.strip()[-40:])
        time.sleep(4)
        expect("pin-windows-open", 2, 0, {"main": 0, "arc": 0, "screen": 0}, "the arc and the detached screen are open, still off")
        run("print('VT_P ' .. tostring(_norns.window_action('pin')))\n", "VT_P", 20); time.sleep(2)
        expect("pin-on", 3, 1, {"main": 1, "arc": 1, "screen": 1}, "PIN on: all three windows are on top, the button is lit")
        run("print('VT_C ' .. tostring(_norns.window_action('arc')))\n", "VT_C", 20); time.sleep(3)
        expect("pin-arc-closed", 4, 1, {"main": 1, "screen": 1}, "the arc window closed: the others stay on top")
        run("print('VT_O ' .. tostring(_norns.window_action('arc')))\n", "VT_O", 20); time.sleep(3)
        expect("pin-arc-reopened", 5, 1, {"main": 1, "arc": 1, "screen": 1}, "the arc opened again while it is on: on top at once")
        run("print('VT_D ' .. tostring(_norns.window_action('detach')))\n", "VT_D", 20); time.sleep(3)
        run("print('VT_D2 ' .. tostring(_norns.window_action('detach')))\n", "VT_D2", 20); time.sleep(3)
        expect("pin-screen-reopened", 6, 1, {"main": 1, "arc": 1, "screen": 1}, "the screen window closed and opened again: on top at once")
        run("print('VT_P2 ' .. tostring(_norns.window_action('pin')))\n", "VT_P2", 20); time.sleep(2)
        expect("pin-off", 7, 0, {"main": 0, "arc": 0, "screen": 0}, "PIN off: all three windows are normal again, the button is not lit")
        # the MIDI action: learned from a note, the port stored
        line = ("_norns.midi.add(97, 'PIN PROBE PORT', 'p97') _norns.midi.add(98, 'PIN OTHER PORT', 'p98') local mm = norns.midimap local S = require 'core/midimap_settings' "
                "mm.start_listen_action('pin') _norns.midi.event(97, {0x90, 62, 100}) _norns.midi.event(97, {0x80, 62, 0}) "
                "print('VT_L ' .. tostring(S.state.actions.pin.type) .. ' ' .. tostring(S.state.actions.pin.num) .. ' ' .. tostring(S.state.actions.pin.dev)) mm.cancel()\n")
        ok, tail = run(line, "VT_L", 20)
        result("pin-midi-learn", ok and "VT_L note 62 PIN PROBE PORT" in tail, "learned from a note: " + tail.strip()[-60:])
        time.sleep(1)
        run("_norns.midi.event(98, {0x90, 62, 100}) _norns.midi.event(98, {0x80, 62, 0}) print('VT_X other')\n", "VT_X", 20); time.sleep(2)
        expect("pin-midi-other-port", 8, 0, {"main": 0, "arc": 0, "screen": 0}, "the same note from another port does nothing")
        run("_norns.midi.event(97, {0x90, 62, 100}) _norns.midi.event(97, {0x80, 62, 0}) print('VT_M1 on')\n", "VT_M1", 20); time.sleep(2)
        expect("pin-midi-on", 9, 1, {"main": 1, "arc": 1, "screen": 1}, "a note from the learned port turns PIN on: the windows and the button follow")
        time.sleep(1)
        run("_norns.midi.event(97, {0x90, 62, 100}) _norns.midi.event(97, {0x80, 62, 0}) print('VT_M2 off')\n", "VT_M2", 20); time.sleep(2)
        expect("pin-midi-off", 10, 0, {"main": 0, "arc": 0, "screen": 0}, "the second note turns it off again")
        run("_norns.midi.remove(97) _norns.midi.remove(98) print('VT_R done')\n", "VT_R", 20)
        # M28: a press while the main window is not in view brings it up and turns PIN on (never off); in view it toggles. real Windows windows: minimized, and covered by a window of our own over all of it
        def view_expect(name, tok, state, view, what):
            d, raw = report(tok)
            if d is None:
                result(name, False, raw); return
            good = d.get("state") == str(state) and d.get("view") == view and d.get("main") == "%s/%s" % (state, state)
            result(name, good, "%s: %s" % (what, raw))
        def view_only(name, tok, view, what):
            d, raw = report(tok)
            if d is None:
                result(name, False, raw); return
            result(name, d.get("view") == view, "%s: %s" % (what, raw))
        run("print('VT_W1 ' .. tostring(_norns.window_test(1)))\n", "VT_W1", 20); time.sleep(3)
        view_only("pin-view-minimized", 11, "out", "the main window is minimized: not in view")
        run("print('VT_Q1 ' .. tostring(_norns.window_action('pin')))\n", "VT_Q1", 20); time.sleep(3)
        view_expect("pin-minimized-press", 12, 1, "in", "a press while it is minimized brings it back and PIN is ON (SDL restore, then topmost)")
        run("print('VT_W2 ' .. tostring(_norns.window_test(1)))\n", "VT_W2", 20); time.sleep(3)
        run("print('VT_Q2 ' .. tostring(_norns.window_action('pin')))\n", "VT_Q2", 20); time.sleep(3)
        view_expect("pin-minimized-press-on", 13, 1, "in", "minimized with PIN already on: a press brings it back and PIN stays ON")
        run("print('VT_Q3 ' .. tostring(_norns.window_action('pin')))\n", "VT_Q3", 20); time.sleep(2)
        view_expect("pin-in-view-toggles", 14, 0, "in", "in view: a press toggles PIN off")
        run("print('VT_W3 ' .. tostring(_norns.window_test(4)))\n", "VT_W3", 20); time.sleep(3)
        view_only("pin-view-covered", 15, "out", "another window covers all of the main window: not in view")
        run("print('VT_Q4 ' .. tostring(_norns.window_action('pin')))\n", "VT_Q4", 20); time.sleep(3)
        view_expect("pin-covered-press", 16, 1, "in", "a press while it is covered brings it in front and PIN is ON")
        run("print('VT_W4 ' .. tostring(_norns.window_test(5)))\n", "VT_W4", 20); time.sleep(2)
        run("print('VT_Q5 ' .. tostring(_norns.window_action('pin')))\n", "VT_Q5", 20); time.sleep(2)
        view_expect("pin-covered-gone-toggles", 17, 0, "in", "the cover is gone, in view: a press toggles PIN off")
    except Exception as e:
        result("pin-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=extdrop (M27): a folder dropped on the window is added as an ext folder (a junction in dust\\audio), a dropped file is refused (nothing imported or copied), removing takes away only the link. the program runs with
# VERDANDI_TEST_HOOKS=1: _norns.test_drop posts the same SDL_DROPFILE event the window system sends. folders with a blank and an accent in the name. results are 'PROBE extdrop-... ok|FAIL' lines
if os.environ.get("VERDANDI_PROBE") == "extdrop":
    def run(line, want, seconds=30):
        return repl(5555, line, want, seconds)
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("extdrop-up", up, "norns answers")
        time.sleep(3)
        src = os.path.join(HOME, "extdrop-src")
        folder = os.path.join(src, u"Drop M\u00fasica")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "kick.wav"), "wb") as f: f.write(b"RIFF-kick")
        dfile = os.path.join(src, "dropped-file.wav")
        with open(dfile, "wb") as f: f.write(b"RIFF-file")
        def lua_path(p): return p.replace("\\", "/")
        link = os.path.join(HOME, "dust", "audio", u"[ext] Drop M\u00fasica")
        ok, tail = run("print('VT_R ' .. tostring(_norns.test_drop ~= nil) .. ' ' .. tostring(_norns.ext_list ~= nil) .. ' ' .. tostring(_norns.ext_legacy_list ~= nil))\n", "VT_R", 20)
        result("extdrop-registered", "VT_R true true true" in tail, "the hook and the ext functions are there: " + tail.strip()[-40:])
        run("_norns.test_drop([[%s]]) print('VT_D1 posted')\n" % lua_path(folder), "VT_D1", 20); time.sleep(4)
        ok, tail = run("local l = _norns.ext_list() print('VT_L1 ' .. #l .. ' ' .. tostring(l[1] and l[1].state))\n", "VT_L1", 20)
        result("extdrop-folder-added", "VT_L1 1 ok" in tail, "a dropped folder is an ext folder: " + tail.strip()[-30:])
        result("extdrop-junction", os.path.exists(os.path.join(link, "kick.wav")), "a file of the folder is readable through the junction in dust\\audio")
        run("_norns.test_drop([[%s]]) print('VT_D2 posted')\n" % lua_path(dfile), "VT_D2", 20); time.sleep(4)
        ok, tail = run("print('VT_L2 ' .. #_norns.ext_list())\n", "VT_L2", 20)
        result("extdrop-file-refused", "VT_L2 1" in tail and not os.path.exists(os.path.join(HOME, "dust", "audio", "dropped-file.wav")) and not os.path.exists(os.path.join(HOME, "dust", "audio", "mac", "dropped-file.wav")) and not os.path.exists(os.path.join(HOME, "dust", "code", "dropped-file.wav")), "a dropped file adds nothing and is not imported or copied: " + tail.strip()[-20:])
        # M42: the file browsers list the ext folders together at the top, A to Z by their real name, then the normal folders as the platform lists them (docs/port/phase-m42.md). the owner's Windows
        # listing after M38 had them in the bytes' order ("[ext] cymatics" before "cc2_live-audio"); this asks the real program what _norns.listdir gives and what util.scandir makes of it
        try:
            import re
            for nm in ("cymatics", "01 dropbox samples"):
                d = os.path.join(src, nm)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, "kick.wav"), "wb") as f: f.write(b"RIFF-kick")
                run("local ok, msg, name = _norns.ext_add([[%s]]) print('VT_ADD ' .. tostring(ok))\n" % lua_path(d), "VT_ADD", 20)
            for nm in ("cc2_live-audio", "dronecaster"):
                os.makedirs(os.path.join(HOME, "dust", "audio", nm), exist_ok=True)
            ok, raw = run("print('VT_RAW ' .. table.concat(_norns.listdir('/home/we/dust/audio/'), '|') .. ' VT_END')\n", "VT_END", 20)
            ok, scan = run("print('VT_SCAN ' .. table.concat(util.scandir('/home/we/dust/audio/'), '|') .. ' VT_END')\n", "VT_END", 20)
            mr = re.search(r"VT_RAW (.*?) VT_END", raw or "", re.S)
            ms = re.search(r"VT_SCAN (.*?) VT_END", scan or "", re.S)
            rawl = (mr.group(1) if mr else "").split("|")
            scanl = (ms.group(1) if ms else "").split("|")
            result("extsort-raw", True, "what _norns.listdir gives: " + " | ".join(rawl))
            result("extsort-scan", True, "what util.scandir makes of it: " + " | ".join(scanl))
            exts = [x for x in scanl if x.startswith("[ext] ")]
            normal = [x for x in scanl if not x.startswith("[ext] ")]
            grouped = len(exts) >= 3 and scanl[:len(exts)] == exts and exts[0] == "[ext] 01 dropbox samples/" and exts[1] == "[ext] cymatics/" and exts[2].startswith("[ext] Drop M")
            # the normal entries come in the order the platform gave them (the raw listing without its ext entries)
            rest_raw = [x for x in rawl if not x.startswith("[ext] ")]
            same_rest = normal == rest_raw and "cc2_live-audio/" in normal and "dronecaster/" in normal
            result("extsort-grouped", grouped and same_rest, "ext folders together at the top A to Z, the others as the platform listed them: " + " | ".join(scanl))
        except Exception as e:
            result("extsort-grouped", False, "%s" % e)
        ok, tail = run("local ok, text = _norns.ext_remove('[ext] Drop M\\xc3\\xbasica') print('VT_X ' .. tostring(ok))\n", "VT_X", 20)
        result("extdrop-removed", "VT_X true" in tail and not os.path.exists(link) and os.path.exists(os.path.join(folder, "kick.wav")), "removing took away the junction and left the files: " + tail.strip()[-20:])
    except Exception as e:
        result("extdrop-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=quitgrid (M17): two fake grids (a 128 and a 256) and the virtual arc are lit by a script (or by a metro of a "mod" with no script), then norns is ended in the way VERDANDI_QUIT_MODE says: sleep (the SLEEP row: norns.shutdown),
# sleepmod (SLEEP with no script, a metro draws: a mod; sleepmodfast: it draws every 2 ms), event (what the right-click menu's Quit and the window's close button post), launcher (the launcher stops norns.exe at the end of --exit-after: nothing is done here), restart (_norns.restart), stall (a grid whose port is busy, then SLEEP).
# the devices record every message they get (<home>/fakedev-*.log); windows/ci/grid_log_check.py reads them after the end. results: 'PROBE qg-... ok|FAIL'
if os.environ.get("VERDANDI_PROBE") == "quitgrid":
    mode = os.environ.get("VERDANDI_QUIT_MODE", "sleep").split("-")[0] # ("sleepmod-old" is sleepmod with the freeze left out: windows/ci/smoke-m1.sh)
    def run(line, want, seconds=30):
        return repl(5555, line, want, seconds)
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("qg-up", up, "norns answers (%s)" % mode)
        time.sleep(3)
        ok, tail = run("print('VT_G ' .. _norns.fake_grid(16, 8, 'fake 128') .. ' ' .. _norns.fake_grid(16, 16, 'fake 256'))\n", "VT_G", 20)
        result("qg-fake-grids", ok and "VT_G 1 2" in tail, "two fake grids were added: " + tail.strip()[-30:])
        ok, tail = run("print('VT_A ' .. tostring(_norns.window_action('arc')))\n", "VT_A", 20)
        found = False
        for _ in range(25):
            ok, tail = run("local g, a = 0, 0 for _ in pairs(grid.devices) do g = g + 1 end for _ in pairs(arc.devices) do a = a + 1 end print('VT_DEV ' .. g .. ' ' .. a)\n", "VT_DEV", 8)
            if ok and "VT_DEV 2 1" in tail:
                found = True; break
            time.sleep(1)
        result("qg-devices", found, "norns lists two grids and the arc: " + tail.strip()[-30:])
        if mode in ("sleep", "launcher", "restart"):
            ok, tail = run("norns.script.load('/home/we/dust/code/gridprobe/gridprobe.lua') print('VT_LOAD sent')\n", "VT_LOAD", 20)
            ready = False
            for _ in range(30):
                ok, tail = run("print('VT_READY ' .. tostring(GP and GP.ready) .. ' ' .. tostring(GP and GP.frames))\n", "VT_READY", 8)
                if ok and "VT_READY true" in tail:
                    ready = True; break
                time.sleep(1)
            result("qg-script", ready, "the script draws on both grids and the arc: " + tail.strip()[-30:])
        else:
            # no script: a metro that nothing clears keeps drawing, as a mod does (sidvagn on the second grid). stall: the first grid only (the busy one must not block the drawing)
            targets = "{grid.connect(1)}" if mode == "stall" else "{grid.connect(1), grid.connect(2)}"
            arc_draw = "" if mode == "stall" else "ARC = arc.connect() ARC:all(15) ARC:refresh() "
            # "fast" draws every 2 ms: a redraw is then certain to come between the all-off and the end of the process, if nothing stops it (the plain mod draws 30 times a second)
            every = "0.002" if (mode.endswith("fast") or "-old" in os.environ.get("VERDANDI_QUIT_MODE", "")) else "1 / 30"
            line = ("norns.script.clear() local gs = %s MODFRAMES = 0 MODM = metro.init(function() for _, g in ipairs(gs) do g:all(15) g:refresh() end %sMODFRAMES = MODFRAMES + 1 end, %s, -1) MODM:start() "
                    "print('VT_MOD started')\n") % (targets, arc_draw, every)
            ok, tail = run(line, "VT_MOD", 20)
            result("qg-mod", ok, "a metro draws with no script loaded: " + tail.strip()[-30:])
        time.sleep(4)
        if mode == "stall":
            ok, tail = run("print('VT_STALL ' .. tostring(_norns.fake_grid_stall(2, true)))\n", "VT_STALL", 20)
            result("qg-stall", ok and "VT_STALL true" in tail, "the second grid stopped reading and its port is busy: " + tail.strip()[-20:])
            time.sleep(2)
        with open(OUT + ".request", "w") as f:
            f.write("%f\n" % time.time())
        try:  # (norns ends while it answers: the connection may break)
            if mode in ("sleep", "sleepmod", "sleepmodfast", "stall"):
                run("norns.shutdown() print('VT_END sleep')\n", "VT_END", 10)
            elif mode == "event":
                run("print('VT_END ' .. tostring(_norns.test_quit()))\n", "VT_END", 10)
            elif mode == "restart":
                run("_norns.restart() print('VT_END restart')\n", "VT_END", 10)
        except Exception:
            pass
        result("qg-request", True, "the end was asked for the way '%s' says (the launcher's own stop: nothing is sent)" % mode)
    except Exception as e:
        result("qg-error", False, "%s" % e)
    sys.exit(0)

# VERDANDI_PROBE=asio (M19): what the program and the AUDIO page say about ASIO, with the CI's stub ASIO driver registered (windows/ci/asio_stub.c) or not. VERDANDI_ASIO_MODE says which case it is: ok, busy, nostart, none. results 'PROBE asio-... ok|FAIL'
if os.environ.get("VERDANDI_PROBE") == "asio":
    amode = os.environ.get("VERDANDI_ASIO_MODE", "ok")
    def run(line, want, seconds=30):
        return repl(5555, line, want, seconds)
    try:
        up = False
        for _ in range(100):
            try:
                ok, _t = run("print('VT_UP ' .. tostring(norns.state.name))\n", "VT_UP", 8)
                if ok: up = True; break
            except Exception:
                pass
            time.sleep(2)
        result("asio-up", up, "norns answers (%s)" % amode)
        time.sleep(8)
        line = ("local i = _norns.audio_info() local d = _norns.audio_devices():gsub('\\n', ' ~ '):gsub('\\t', ' ') "
                "print('VT_INFO ' .. tostring(i.mode) .. '|' .. tostring(i.host_api) .. '|' .. tostring(i.device) .. '|' .. tostring(i.asio_flavour) .. '|' .. tostring(i.asio_registered) .. '|' .. tostring(i.asio_usable) .. '|' .. tostring(i.card_frames) .. '|' .. tostring(i.asio_note)) "
                "print('VT_DEVS ' .. d) print('VT_APIS ' .. tostring(i.host_apis))\n")
        ok, tail = run(line, "VT_APIS", 30)
        info = ""
        devs = ""
        for l in tail.splitlines():
            if l.startswith("VT_INFO "): info = l[8:]
            if l.startswith("VT_DEVS "): devs = l[8:]
        f = info.split("|")
        f += [""] * (8 - len(f))
        mode_, api, device, flavour, registered, usable, card_frames, note = f[0], f[1], f[2], f[3], f[4], f[5], f[6], "|".join(f[7:])
        result("asio-info", ok and bool(info), "mode=%s host_api=%s device=%s flavour=%s registered=%s usable=%s card_frames=%s note=%s" % (mode_, api, device, flavour, registered, usable, card_frames, note[:160]))
        # the page, as the owner sees it
        page = ("local p = _menu.m['AUDIO'] p.init() local st = p.status_text() p.pos = 1 p.redraw() local h = table.concat(p.help_lines(), ' ') "
                "p.cfg.driver = 'asio' p.cfg.output = 'asio:Verdandi Test ASIO' local bt = p.value_text('BUFFER') p.deinit() "
                "print('VT_PAGE status=[' .. tostring(st) .. '] help=[' .. h .. '] buffer=[' .. tostring(bt) .. ']')\n")
        ok, tail = run(page, "VT_PAGE", 30)
        result("asio-page", ok, tail.strip()[-300:])
        flav = flavour == "true"
        if amode == "ok":
            result("asio-listed", "ASIO" in f[1] or "ASIO" in (tail + info), "device opened through ASIO: host_api=%s" % api)
            result("asio-running", mode_ == "device" and api.startswith("ASIO") and usable == "1" and card_frames.isdigit() and int(card_frames) > 0, "the stub driver runs the engine: mode=%s host_api=%s card callbacks of %s frames" % (mode_, api, card_frames))
            result("asio-devices", "asio:Verdandi Test ASIO" in devs and "64,2048,256,-1" in devs and " 4 4 ASIO" in devs, "the device list has the driver with 4 in, 4 out and its buffer sizes: " + devs[-200:])
            result("asio-buffer-text", ("auto  256  5.3 ms" in tail) or ("auto  256  5.8 ms" in tail), "the BUFFER row shows the driver's preferred size in frames and ms (5.3 ms at 48000 Hz, 5.8 at 44100: the stub takes both)")
        elif amode == "busy":
            result("asio-busy-said", flav and usable == "0" and registered == "1" and "refused to start" in note, "a driver that refuses to start is named with its own message: " + note[:200])
            result("asio-busy-page", "ASIO" in tail and "will not start" in tail, "the AUDIO page says the driver will not start")
        elif amode == "none":
            result("asio-none-said", flav and registered == "0" and "no ASIO driver is installed" in note, "no driver registered: " + note[:200])
            result("asio-none-page", "ASIO" in tail and "no driver installed" in tail, "the AUDIO page says no driver is installed")
        elif amode == "normal":
            result("asio-normal", (not flav) and "normal build" in note and "ASIO" not in tail.split("help=[")[-1], "the normal build says it has no ASIO and the AUDIO page does not mention it: flavour=%s note=%s" % (flavour, note[:120]))
        elif amode == "nostart":
            result("asio-nostart", flav and registered == "1", "the driver is there and starts for the probe; opening it failed at the start: mode=%s host_api=%s" % (mode_, api))
        # M20: the stream is reopened while norns runs (the AUDIO page's apply runs on the Lua thread: the thread that the owner's PC failed on), and the engine's rate against the card's
        def rate_info(tries=3):
            # M30: the program's own log lines (the clock line every 10 s) share the stream and can cut the answer line in two: nothing is found then, and asking again is harmless (it only reads). on 0.10.18 (72380cf) this cut "VT_APPLY" in the ASIO reopen check and the ASIO zip was not published
            for _ in range(tries):
                r_ = rate_info_once()
                if r_["mode"] != "?":
                    return r_
            return r_
        def rate_info_once():
            ok_, t_ = run("local i = _norns.audio_info() print('VT_RATE ' .. tostring(i.mode) .. '|' .. tostring(i.host_api) .. '|' .. tostring(i.rate) .. '|' .. tostring(i.device_rate) .. '|' .. tostring(i.card_rate) .. '|' .. tostring(i.rate_warn) .. '|' .. (tostring(i.config):gsub('\\n', ',')))\n", "VT_RATE", 30)
            for l_ in t_.splitlines():
                if "VT_RATE " in l_:  # (the program's own log lines are written to the same stream: a line can start in the middle of another)
                    g = l_[l_.index("VT_RATE ") + 8:].split("|") + [""] * 7
                    return {"mode": g[0], "api": g[1], "rate": float(g[2] or 0), "dev": float(g[3] or 0), "card": float(g[4] or 0), "warn": g[5], "cfg": "|".join(g[6:])}
            return {"mode": "?", "api": "?", "rate": 0, "dev": 0, "card": 0, "warn": "?", "cfg": ""}
        def apply_conf(out_first=1, buffer=0, output="asio:Verdandi Test ASIO", tries=3):
            # M30: when the answer line was cut in two by a log line of the program (see rate_info), the same apply is asked again: it ends in the same state, so nothing is judged from a lost answer
            for _ in range(tries):
                rc_, msg_ = apply_conf_once(out_first, buffer, output)
                if rc_ != "?":
                    return rc_, msg_
            return rc_, msg_
        def apply_conf_once(out_first=1, buffer=0, output="asio:Verdandi Test ASIO"):
            conf = "output=%s\\ninput=\\nrate=48000\\nblock=128\\nbuffer=%d\\nexclusive=0\\nout_first=%d\\nin_l=1\\nin_r=2\\n" % (output, buffer, out_first)
            ok_, t_ = run("local rc, msg = _norns.audio_apply(\"%s\") print('VT_APPLY ' .. tostring(rc) .. '|' .. tostring(msg))\n" % conf, "VT_APPLY", 60)
            for l_ in t_.splitlines():
                if "VT_APPLY " in l_:  # (the program's own log lines share the stream: this one can start in the middle of another)
                    rc_, _, msg_ = l_[l_.index("VT_APPLY ") + 9:].partition("|")
                    return rc_, msg_
            return "?", t_[-200:]
        def near(a, b, pct=2.0):
            return b > 0 and abs(a - b) <= b * pct / 100.0
        if amode == "ok":
            time.sleep(6)
            ri = rate_info()
            result("asio-rate48-engine", ri["rate"] == 48000 and ri["dev"] == 48000, "the stub card runs at 48000 Hz and so does the engine: engine %s, card (driver) %s" % (ri["rate"], ri["dev"]))
            result("asio-rate48-measured", near(ri["card"], 48000) and ri["warn"] == "0", "the rate the card really delivers, measured: %.0f Hz (warning flag %s)" % (ri["card"], ri["warn"]))
        elif amode == "rate44":
            time.sleep(6)
            ri = rate_info()
            result("asio-rate44-engine", ri["mode"] == "device" and ri["rate"] == 44100 and ri["dev"] == 44100, "the card runs at 44100 Hz (another program's setting): the engine follows it: engine %s, card (driver) %s, mode %s" % (ri["rate"], ri["dev"], ri["mode"]))
            result("asio-rate44-measured", near(ri["card"], 44100) and ri["warn"] == "0", "the rate the card really delivers, measured: %.0f Hz (warning flag %s)" % (ri["card"], ri["warn"]))
        elif amode == "reopen":
            ri = rate_info()
            result("asio-reopen-start", ri["mode"] == "device" and ri["api"].startswith("ASIO"), "it started on the ASIO driver: %s %s" % (ri["mode"], ri["api"]))
            rc_, msg_ = apply_conf(3, 128)
            ri = rate_info()
            result("asio-reopen-pair-buffer", rc_ == "0" and ri["mode"] == "device" and ri["api"].startswith("ASIO") and "out_first=3" in ri["cfg"] and "buffer=128" in ri["cfg"], "outputs 3+4 and buffer 128 while it runs: rc=%s msg=[%s] %s %s %s" % (rc_, msg_, ri["mode"], ri["api"], ri["cfg"]))
            rc_, msg_ = apply_conf(1, 0)
            ri = rate_info()
            result("asio-reopen-back", rc_ == "0" and ri["mode"] == "device" and "out_first=1" in ri["cfg"], "and back to outputs 1+2, auto buffer: rc=%s msg=[%s] %s" % (rc_, msg_, ri["cfg"]))
            rc_, msg_ = apply_conf(1, 0, output="")
            ri = rate_info()
            result("asio-reopen-refused-goes-back", ri["mode"] == "device" and ri["api"].startswith("ASIO"), "a change that cannot be made (no Windows sound card on the runner) closes the driver and opens it again as it was: rc=%s msg=[%s] %s %s" % (rc_, msg_[:120], ri["mode"], ri["api"]))
            rc_, msg_ = apply_conf(3, 256)
            ri = rate_info()
            result("asio-reopen-again", rc_ == "0" and ri["mode"] == "device" and "out_first=3" in ri["cfg"] and "buffer=256" in ri["cfg"], "and once more, outputs 3+4, buffer 256: rc=%s msg=[%s] %s" % (rc_, msg_, ri["cfg"]))
        elif amode == "fromnull":
            ri = rate_info()
            result("asio-fromnull-start", ri["mode"] in ("fallback", "null"), "there is no sound card on the runner: it started without sound (%s)" % ri["mode"])
            rc_, msg_ = apply_conf(1, 0)
            ri = rate_info()
            result("asio-fromnull-apply", rc_ == "0" and ri["mode"] == "device" and ri["api"].startswith("ASIO"), "then the ASIO driver is chosen while it runs: rc=%s msg=[%s] %s %s" % (rc_, msg_, ri["mode"], ri["api"]))
        elif amode == "hold":
            ri = rate_info()
            result("asio-hold-start", ri["mode"] in ("fallback", "null") and ri["rate"] == 48000, "it runs at 48000 Hz without a card (%s %s)" % (ri["mode"], ri["rate"]))
            rc_, msg_ = apply_conf(1, 0)
            ri = rate_info()
            result("asio-hold-refused", rc_ != "0" and ri["mode"] != "device" and "44100 Hz" in msg_ and "48000 Hz" in msg_ and "does not change" in msg_, "the card is at 44100 Hz (another program has it), the engine at 48000: not opened, the reason in plain words: rc=%s msg=[%s]" % (rc_, msg_[:300]))
        elif amode == "vanish":
            # M31: the driver vanishes while the program runs (the stub stops calling back and refuses init: the cable is pulled), then comes back
            def note_info():
                ok_, t_ = run("local a = _norns.audio_info() print('VT_NOTE ' .. tostring(a.mode) .. '|' .. tostring(a.note) .. '|' .. tostring(_menu.audio_note))\n", "VT_NOTE", 20)
                for l_ in t_.splitlines():
                    if "VT_NOTE " in l_:
                        return parse_vt_note(l_)
                return "?", "", ""
            ctl = os.environ.get("VERDANDI_STUB_CTL", "")
            ri = rate_info()
            result("asio-vanish-start", ri["mode"] == "device" and ri["api"].startswith("ASIO") and bool(ctl), "it runs on the stub ASIO driver: %s %s (control file %s)" % (ri["mode"], ri["api"], ctl))
            with open(ctl, "w") as f_:
                f_.write("vanish")
            time.sleep(18)  # (2 s without a callback, the reopen that fails, the 3 s poll of the notes)
            mode_n, note_n, win_n = note_info()
            result("asio-vanish-alive", mode_n in ("fallback", "null"), "the program is alive and says it has no sound: mode=%s" % mode_n)
            result("asio-vanish-reason", "not there" in note_n or "stopped answering" in note_n or "no sound" in note_n, "the AUDIO page has the reason: %s" % note_n[:200])
            result("asio-vanish-window", win_n.startswith("NO SOUND"), "the note on the norns window says NO SOUND: %s" % win_n[:200])
            os.remove(ctl)
            time.sleep(14)  # (the retry every 3 s opens the driver again, then the note poll)
            ri = rate_info()
            mode_b, note_b, win_b = note_info()
            result("asio-vanish-back", ri["mode"] == "device" and ri["api"].startswith("ASIO"), "the driver is back and the sound with it: %s %s" % (ri["mode"], ri["api"]))
            result("asio-vanish-note-gone", win_b in ("", "nil"), "and the note on the window is gone: [%s]" % win_b[:120])
        elif amode == "lie":
            time.sleep(12)
            ri = rate_info()
            result("asio-lie-detected", ri["mode"] == "device" and ri["rate"] == 48000 and near(ri["card"], 44100, 3.0) and ri["warn"] == "1", "the driver says 48000 Hz but delivers 44100: engine %s, measured %.0f Hz, warning flag %s" % (ri["rate"], ri["card"], ri["warn"]))
    except Exception as e:
        result("asio-error", False, "%s" % e)
    sys.exit(0)

# 1. maiden is up
up = False
for _ in range(150):
    try:
        st, body = get("/api/v1")
        up = st == 200 and b"maiden" in body
        if up: break
    except Exception:
        pass
    time.sleep(1)
result("maiden-api", up, "GET /api/v1 on 127.0.0.1:%d" % PORT)
if up:
    try:
        st, body = get("/maiden/")
        result("maiden-web", st == 200 and b"<html" in body.lower(), "the web app is served (%d bytes)" % len(body))
    except Exception as e:
        result("maiden-web", False, str(e))

    # 2. install a zip: a folder name with an accent and a space, a file with an accent
    tmp = tempfile.mkdtemp()
    zname = "Café test script-main.zip"
    zpath = os.path.join(tmp, zname)
    with zipfile.ZipFile(zpath, "w") as z:
        z.writestr("Café test script-main/café_test.lua", 'print("hello from an accented script")\n')
        z.writestr("Café test script-main/lib/helper.lua", "return {}\n")
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k): super().__init__(*a, directory=tmp, **k)
        def log_message(self, *a): pass
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    import urllib.parse
    url = "http://127.0.0.1:%d/%s" % (srv.server_address[1], urllib.parse.quote(zname))
    body = ""
    try:
        req = urllib.request.Request("http://127.0.0.1:%d/api/v1/project/install?url=%s" % (PORT, urllib.parse.quote(url, safe="")), method="POST")
        with urllib.request.urlopen(req, timeout=60) as r:
            status = r.status
    except urllib.error.HTTPError as e:
        status = e.code
        body = e.read().decode("utf-8", "replace")[:300]
    except Exception as e:
        status = str(e)
    found = None
    code = os.path.join(HOME, "dust", "code")
    for root, dirs, files in os.walk(code):
        for f in files:
            if f == "café_test.lua":
                found = os.path.join(root, f)
    result("maiden-install", status in (200, 201) and found is not None, "install answered %s %s; the accented script is %s" % (status, body.replace("\n", " "), found or "NOT in dust/code"))
    srv.shutdown()

# 3. the norns console
try:
    ok, tail = repl(5555, "print('REPL_'..(20+22))\n", "REPL_42", 60)
    result("repl-norns", ok, "matron's console on ws://127.0.0.1:5555 ran a line of Lua" if ok else "no answer: " + repr(tail))
except Exception as e:
    result("repl-norns", False, "%s" % e)

# 4. a page from another site is refused
try:
    s, rest = ws_connect(5555, "http://evil.example")
    ws_send(s, "print('REPL_EVIL')\n")
    text = ws_frames(s, rest, 3)
    s.close()
    result("repl-origin", "REPL_EVIL" not in text, "a page from another site gets no console" )
except Exception as e:
    result("repl-origin", True, "refused: %s" % e)

# 5. the sclang console
try:
    ok, tail = repl(5556, "(20+22).postln;\x1b", "42", 150) # maiden's web app ends every sclang command with ESC
    result("repl-sclang", ok, "sclang's console on ws://127.0.0.1:5556 evaluated a line" if ok else "no answer: " + repr(tail))
except Exception as e:
    result("repl-sclang", False, "%s" % e)
# 6. real SynthDefs with UGens of the plug-in packs (mi-UGens, sc3-plugins): they compile only when sclang knows the classes ("Class 'MiPlaits' not found" otherwise), and the server of crone answers
try:
    line = ('("VT_UGENS " ++ [ SynthDef(\\vt_miplaits, { Out.ar(0, MiPlaits.ar(60)) }), SynthDef(\\vt_mibraids, { Out.ar(0, MiBraids.ar(60)) }), '
            'SynthDef(\\vt_decimator, { Out.ar(0, Decimator.ar(SinOsc.ar(220), 8000, 8)) }) ].collect { |d| d.asBytes.size > 100 }.every { |x| x }).postln;\x1b')
    ok, tail = repl(5556, line, "VT_UGENS true", 60)
    result("repl-ugens", ok, "SynthDefs with MiPlaits.ar, MiBraids.ar (mi-UGens) and Decimator.ar (sc3-plugins) were built by sclang" if ok else "not built: " + repr(tail))
except Exception as e:
    result("repl-ugens", False, "%s" % e)
try:
    line = ('Routine({ var s = Crone.server; SynthDef(\\vt_decimator2, { Out.ar(0, Decimator.ar(SinOsc.ar(220, 0, 0.0), 8000, 8)) }).add; s.sync; '
            '("VT_SERVER " ++ s.serverRunning).postln; }).play(AppClock);\x1b')
    ok, tail = repl(5556, line, "VT_SERVER true", 60)
    result("repl-server", ok, "the server of crone took a SynthDef with Decimator.ar and answered (s.sync)" if ok else "the server did not answer: " + repr(tail))
except Exception as e:
    result("repl-server", False, "%s" % e)
# 7. the plug-ins (.scx) of the packs are loaded by the REAL server: a SynthDef with MiPlaits, MiBraids (mi-UGens), Decimator, MoogLadder and SawDPW (sc3-plugins) is sent, one synth of each is started and the server must
# announce every one (/n_go). before 0.8.2 the server looked for plug-ins only in its own folder: "exception in GraphDef_Recv: UGen 'MiPlaits' not installed" while s.sync still answered. NOT s.sync: five nodes
try:
    line = ('Routine({ var s = Crone.server, n = 0, fails = 0, r1, r2, defs; '
            'defs = [[\\vt_pl1, { MiPlaits.ar(60) }], [\\vt_pl2, { MiBraids.ar(60) }], [\\vt_pl3, { Decimator.ar(SinOsc.ar(220), 8000, 8) }], [\\vt_pl4, { MoogLadder.ar(SinOsc.ar(220), 800, 0.3) }], [\\vt_pl5, { SawDPW.ar(220) }]]; '
            'r1 = OSCFunc({ |m| n = n + 1 }, \'/n_go\', s.addr); r2 = OSCFunc({ |m| fails = fails + 1 }, \'/fail\', s.addr); '
            'defs.do { |d| SynthDef(d[0], { Out.ar(0, d[1].value.asArray.sum * 0.0) }).send(s) }; s.sync; '
            'defs.do { |d, i| s.sendMsg("/s_new", d[0], 3000 + i, 0, 1) }; 1.5.wait; defs.do { |d, i| s.sendMsg("/n_free", 3000 + i) }; r1.free; r2.free; '
            '("VT_PLUGINS " ++ n ++ " fails " ++ fails).postln; }).play(AppClock);\x1b')
    ok, tail = repl(5556, line, "VT_PLUGINS 5 fails 0", 90)
    result("repl-plugins", ok, "the real server started a synth of each of MiPlaits, MiBraids, Decimator, MoogLadder, SawDPW (5 nodes, no failure)" if ok else "the server did not load the plug-ins: " + repr(tail))
except Exception as e:
    result("repl-plugins", False, "%s" % e)
# 7b. M9: the three UGens the script twins needs (PortedPlugins pack), started on the REAL server with the argument shapes of twins' engine: every /n_go announced, no /fail, and the output is not NaN or inf
try:
    line = ('Routine({ var s = Crone.server, n = 0, fails = 0, r1, r2, b, got; '
            'r1 = OSCFunc({ |m| n = n + 1 }, \'/n_go\', s.addr); r2 = OSCFunc({ |m| fails = fails + 1 }, \'/fail\', s.addr); '
            'SynthDef(\\vt_ported, { var orig = SinOsc.ar(220, 0, 0.3), wet, loss, degrade; wet = AnalogChew.ar(orig, 0.5, 0.5, 0.5); loss = AnalogLoss.ar(wet, 0.5, 1, 0.5, 0.5); '
            'degrade = AnalogDegrade.ar(loss, 0.2, 0.5, 0.5, 0.5); Out.ar(0, degrade * 0.0) }).send(s); s.sync; '
            's.sendMsg("/s_new", \\vt_ported, 3100, 0, 1); 1.5.wait; s.sendMsg("/n_free", 3100); r1.free; r2.free; '
            '("VT_PORTED " ++ n ++ " fails " ++ fails).postln; }).play(AppClock);\x1b')
    ok, tail = repl(5556, line, "VT_PORTED 1 fails 0", 90)
    result("repl-ported", ok, "the real server started a synth with AnalogChew, AnalogLoss and AnalogDegrade (the ones twins needs): announced, no failure" if ok else "the server did not run the PortedPlugins UGens: " + repr(tail))
except Exception as e:
    result("repl-ported", False, "%s" % e)
# 7c. M9: twins' own library check, as the installer runs it, through norns's shell (find -printf is rewritten for the bundled busybox): the class files and the markers are found
try:
    line = ("local p = io.popen(\"find /usr/local/share/SuperCollider/Extensions /home/we/.local/share/SuperCollider/Extensions /home/we/dust/code -name .git -prune -o \\\\( -name 'AnalogChew.sc' -o -name 'AnalogChew.so' -o -name 'AnalogChew_scsynth.so' \\\\) -not -path '*ignore*' -type f -printf '%p!' 2>/dev/null\") "
            "local t = p and p:read('a') or '' if p then p:close() end print('VT_TWINSFIND ' .. (t:find('AnalogChew.sc!', 1, true) and 'sc' or 'nosc') .. ' ' .. (t:find('AnalogChew_scsynth.so!', 1, true) and 'so' or 'noso'))\n")
    ok, tail = repl(5555, line, "VT_TWINSFIND sc so", 60)
    result("repl-twinsfind", ok, "twins' find (with -printf) finds AnalogChew.sc and AnalogChew_scsynth.so" if ok else "twins' find does not find both halves: " + repr(tail))
except Exception as e:
    result("repl-twinsfind", False, "%s" % e)
# 7d. M11: every page of the menu in the REAL norns.exe: init, redraw, E1-E3 both ways, K1-K3 down and up, redraw, deinit, each call under pcall; any error is a failure. K3 is left out on the pages whose K3 does something that
# ends or changes the program (RESTART, RESET, UPDATE, SLEEP: restart / clear / update / sleep; SELECT: loads a script; CLEANUP, MODS, EXTRA, PICKER: change files); their other keys and encoders are called
try:
    line = ("local errs, n = {}, 0 local skip3 = {RESTART=1, RESET=1, UPDATE=1, SLEEP=1, SELECT=1, CLEANUP=1, MODS=1, EXTRA=1, PICKER=1} local names = {} "
            "for name in pairs(_menu.m) do names[#names + 1] = name end table.sort(names) "
            "for _, name in ipairs(names) do local p = _menu.m[name] if type(p) == 'table' then n = n + 1 "
            "local function try(what, f, ...) local ok, e = pcall(f, ...) if not ok then errs[#errs + 1] = name .. ' ' .. what .. ': ' .. tostring(e):sub(1, 110) end end "
            "if p.init then try('init', p.init) end if p.redraw then try('redraw', p.redraw) end "
            "if p.enc then for e = 1, 3 do for _, d in ipairs({1, -1, 5}) do try('enc' .. e, p.enc, e, d) end end end "
            "if p.key then for k = 1, 3 do if not (k == 3 and skip3[name]) then try('key' .. k, p.key, k, 1) try('key' .. k .. 'up', p.key, k, 0) end end end "
            "if p.redraw then try('redraw2', p.redraw) end if p.deinit then try('deinit', p.deinit) end end end "
            "print('VT_PAGES ' .. n .. ' pages ' .. #errs .. ' errors') for _, e in ipairs(errs) do print('VT_PAGE_ERR ' .. e) end print('VT_PAGES_' .. 'DONE')\n")
    ok, tail = repl(5555, line, "VT_PAGES_DONE", 120)
    import re
    m2 = re.search(r"VT_PAGES (\d+) pages (\d+) errors", tail or "")
    result("repl-menu-pages", bool(m2) and int(m2.group(2)) == 0 and int(m2.group(1)) >= 10, ("%s pages, no error in init, redraw, enc, key, deinit" % m2.group(1)) if m2 and int(m2.group(2)) == 0 else "page errors: " + repr(tail[-700:]))
except Exception as e:
    result("repl-menu-pages", False, "%s" % e)
# 7e. M12: the AUDIO page with a very long device name, drawn by the real program and saved as a picture (audio_page_long.png in the data folder of the running script; the CI copies it to its output)
try:
    line = ("local LONG = 'Digital Audio Interface (Professional Multichannel Studio Sound Card Extended Edition) 7-8' local real = _norns.audio_devices "
            "_norns.audio_devices = function() return (real() or '') .. 'wasapi:' .. LONG .. '\\t' .. LONG .. '\\t0\\t8\\tWASAPI\\t21\\t0\\t0\\n' end "
            "local p = _menu.m['AUDIO'] p.init() p.cfg.output = 'wasapi:' .. LONG p.pos = 2 p.redraw() screen.export_screenshot('audio_page_long') "
            "p.pos = 1 p.redraw() screen.export_screenshot('audio_page_short') p.deinit() _norns.audio_devices = real print('VT_SHOT ' .. 'done')\n")
    ok, tail = repl(5555, line, "VT_SHOT done", 60)
    result("repl-audio-shot", ok, "the AUDIO page with a long device name was drawn and saved (audio_page_long.png, audio_page_short.png)" if ok else "not drawn: " + repr(tail))
except Exception as e:
    result("repl-audio-shot", False, "%s" % e)
# 8. the check that the emplaitress mod makes before it downloads and unpacks a Linux copy of mi-UGens (lib/mod.lua, system_post_startup): `find /home/we/.local/share/SuperCollider/Extensions/ -name MiPlaits.sc`
# through norns's own shell. true = the mod finds the classes and does NOT copy anything (no second copy, no duplicate classes at the next start)
try:
    line = ("local a, b, c = os.execute('test -n \"$(find /home/we/.local/share/SuperCollider/Extensions/ -name MiPlaits.sc)\"') print('VT_MODCHECK ' .. tostring(a) .. ' ' .. tostring(b) .. ' ' .. tostring(c)) "
            "local p = io.popen('find /home/we/.local/share/SuperCollider/Extensions/ -name MiPlaits.sc 2>&1') print('VT_MODFIND ' .. tostring(p and p:read('a')))\n")
    ok, tail = repl(5555, line, "VT_MODCHECK true", 60)
    result("repl-modcheck", ok, "the mod's own check finds MiPlaits.sc in the per-user extensions folder (it will not download or copy anything)" if ok else "the mod's check says no: " + repr(tail))
except Exception as e:
    result("repl-modcheck", False, "%s" % e)
result("done", True, "")
