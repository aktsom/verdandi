#!/usr/bin/env python3
# a minimal websocket client for the maiden tests (stdlib only; run with -I).
# usage: ws_probe.py PORT ORIGIN|- [HOST]   ORIGIN "-": send no Origin header (like maiden-repl)
# prints: "handshake=<status>" and then "echo=<text>" if the peer sent the text back within 1.5 s,
# "closed" if it closed the connection, "silent" if neither. exit 0 always (the caller reads the words).
import base64, os, socket, struct, sys, time

port, origin = int(sys.argv[1]), sys.argv[2]
host = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1:%d" % port
key = base64.b64encode(os.urandom(16)).decode()
req = "GET / HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" % host
req += "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: bus.sp.nanomsg.org\r\n" % key
if origin != "-":
    req += "Origin: %s\r\n" % origin
s = socket.create_connection(("127.0.0.1", port), timeout=3)
s.sendall((req + "\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf:
    d = s.recv(4096)
    if not d:
        break
    buf += d
head, _, rest = buf.partition(b"\r\n\r\n")
print("handshake=" + (head.split(b" ")[1].decode() if b" " in head else "none"))
if not head.startswith(b"HTTP/1.1 101"):
    sys.exit(0)

payload = b"ping-from-test\n"
mask = os.urandom(4)
frame = bytes([0x81, 0x80 | len(payload)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
try:
    s.sendall(frame)
except OSError:
    print("closed")
    sys.exit(0)
s.settimeout(0.3)
end = time.time() + 1.5
data = rest
while time.time() < end:
    if len(data) >= 2 and data[0] & 0x0F == 1:
        n = data[1] & 0x7F
        if len(data) >= 2 + n:
            print("echo=" + data[2:2 + n].decode(errors="replace").strip())
            sys.exit(0)
    if len(data) >= 1 and data[0] & 0x0F == 8:
        print("closed")
        sys.exit(0)
    try:
        d = s.recv(4096)
    except socket.timeout:
        continue
    except OSError:
        print("closed")
        sys.exit(0)
    if not d:
        print("closed")
        sys.exit(0)
    data += d
print("silent")
