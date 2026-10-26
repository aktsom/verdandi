#!/usr/bin/env python3
# listening.py PORT...: the TCP sockets in LISTEN state on these ports, from /proc ("ip:port", sorted, one line).
# (ss may not be installed.) run with -I.
import socket, sys
ports = {int(a) for a in sys.argv[1:]}
out = []
for f, v6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
    try:
        lines = open(f).read().splitlines()[1:]
    except OSError:
        continue
    for l in lines:
        c = l.split()
        if c[3] != "0A":
            continue
        addr, port = c[1].split(":")
        if int(port, 16) not in ports:
            continue
        b = bytes.fromhex(addr)
        a = socket.inet_ntop(socket.AF_INET6, b"".join(b[i:i + 4][::-1] for i in range(0, 16, 4))) if v6 else socket.inet_ntoa(b[::-1])
        out.append("%s:%d" % (a, int(port, 16)))
print(" ".join(sorted(out)))
