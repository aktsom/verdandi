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
        return want in text, text[-200:]
    finally:
        s.close()

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
result("done", True, "")
