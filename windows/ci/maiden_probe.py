#!/usr/bin/env python3
"""windows/ci/maiden_probe.py HOME OUT: what a browser does with maiden, from the outside, while the program runs headless on the runner.
   1. maiden answers on 127.0.0.1:5000 (API and web app)  2. a script is installed from a zip over HTTP (an accented, spaced name) and lands in dust/code  3. the norns console (websocket 5555) runs a line of Lua
   4. a page from another site is refused by the console  5. the sclang console (5556) evaluates a line.
   every result is a line 'PROBE <name> ok|FAIL <what>' in OUT. stdlib only."""
import base64, http.server, json, os, socket, sys, threading, time, urllib.request, urllib.error, zipfile, tempfile

HOME, OUT = sys.argv[1], sys.argv[2]
PORT = int(os.environ.get("NORNS_MAIDEN_PORT", "5000"))
lines = []
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
    try:
        for k in (1, 2, 3):
            up = wait_for(lambda: norns_up() and server_up(), 240)
            result("kill-%d-up" % k, up, "norns and its server answer before the kill (round %d)" % k)
            if not up: break
            r = subprocess.run(["taskkill", "/F", "/IM", "scsynth.exe"], capture_output=True, text=True)
            result("kill-%d-done" % k, r.returncode == 0, "scsynth.exe ended from outside: " + (r.stdout + r.stderr).strip()[:120])
            if k < 3:
                saw = wait_for(lambda: ("starting everything again (round %d)" % (k + 1)) in text(LOG), 90)
                result("kill-%d-restarted" % k, saw, "launcher.log says the round was started again (round %d)" % (k + 1) if saw else "no restart in launcher.log: " + repr(text(LOG)[-300:]))
                noted = wait_for(lambda: "stopped on its own, exit code" in text(LOG), 5)
                result("kill-%d-logged" % k, noted, "launcher.log names the stop and its exit code")
            else:
                gave = wait_for(lambda: "stopped on its own again" in text(LOG), 60)
                result("kill-3-gave-up", gave, "launcher.log says it does not restart again" if gave else "no 'again' line: " + repr(text(LOG)[-300:]))
                time.sleep(15)
                result("kill-3-no-round-4", "starting everything again (round 4)" not in text(LOG), "no fourth round was started")
                result("kill-3-norns-alive", norns_up(), "norns is still running and answers")
                shown = wait_for(lambda: "SuperCollider keeps stopping" in text(NLOG), 30)
                result("kill-3-message", shown, "norns.log has the plain message that it keeps stopping" if shown else "message not in norns.log")
        # the messages of the first two stops reached the norns screen
        n = text(NLOG)
        result("kill-notes", n.count("### SuperCollider stopped (error") >= 2, "norns.log has the restart message of each of the two restarts (on the screen as well)")
        result("kill-done", True, "")
    except Exception as e:
        result("kill-error", False, "%s" % e)
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
