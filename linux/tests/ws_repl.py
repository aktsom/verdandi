#!/usr/bin/env python3
"""linux/tests/ws_repl.py PORT LINE WANT [SECONDS] (M25): one connection to a console websocket of ws-wrapper (norns 5555, sclang 5556), LINE is sent (\\x1b and \\n are understood), the answer is read until it holds WANT.
exit 0 and 'ok: ...' when it did, 1 and 'FAIL: ...' when not. the handshake asks for nng's sub-protocol (bus.sp.nanomsg.org), as maiden's page does"""
import base64, os, socket, sys, time

def connect(port, timeout=10):
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n"
               "Sec-WebSocket-Protocol: bus.sp.nanomsg.org\r\n\r\n" % (port, key)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise ConnectionError("closed during the handshake")
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        raise ConnectionError(head.split(b"\r\n")[0].decode())
    return s, rest

def send(s, text):
    data = text.encode()
    mask = os.urandom(4)
    hdr = bytes([0x81]) + (bytes([0x80 | len(data)]) if len(data) < 126 else bytes([0x80 | 126]) + len(data).to_bytes(2, "big"))
    s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def frames(s, first, seconds):
    s.settimeout(1.0)
    buf, out, end = first, [], time.time() + seconds
    while time.time() < end:
        while len(buf) >= 2:
            n, off = buf[1] & 0x7F, 2
            if n == 126:
                if len(buf) < 4:
                    break
                n, off = int.from_bytes(buf[2:4], "big"), 4
            if len(buf) < off + n:
                break
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

def main():
    port, line, want = int(sys.argv[1]), sys.argv[2].encode().decode("unicode_escape"), sys.argv[3]
    seconds = float(sys.argv[4]) if len(sys.argv) > 4 else 20
    last = None
    end = time.time() + seconds
    while time.time() < end:
        try:
            s, rest = connect(port)
        except (ConnectionError, OSError) as e:
            last = e
            time.sleep(1)
            continue
        try:
            text = ""
            sent_at = 0
            while time.time() < end and want not in text:
                if time.time() - sent_at > 8: # a line sent while the program is still starting may be answered with the wrong state (sclang: no server yet): it is sent again
                    send(s, line)
                    sent_at = time.time()
                text += frames(s, rest if not text else b"", 2)
                rest = b""
            if want in text:
                print("ok: port %d answered %r" % (port, want))
                return 0
            last = "no %r in %r" % (want, text[-200:])
        finally:
            s.close()
    print("FAIL: port %d: %s" % (port, last))
    return 1

sys.exit(main())
