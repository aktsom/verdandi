"""windows/ci/osc_status.py: ask a running scsynth for /status over UDP and print what it says (M1 smoke test).
usage: python osc_status.py PORT [--quit]    exit 0 when /status.reply came, 1 when not within 10 s.
prints: ugens synths groups defs avgcpu peakcpu nominal_sr actual_sr   (actual_sr close to the nominal rate = the null audio clock runs)"""
import socket
import struct
import sys
import time


def pad(b):
    return b + b"\0" * (4 - len(b) % 4)


def msg(addr):
    return pad(addr.encode()) + pad(b",")


def status(port, timeout=10.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(1.0)
    end = time.time() + timeout
    while time.time() < end:
        s.sendto(msg("/status"), ("127.0.0.1", port))
        try:
            d, _ = s.recvfrom(4096)
        except socket.timeout:
            continue
        i = d.index(b",")
        v = struct.unpack(">iiiiiffdd", d[i + 12 : i + 12 + 4 * 5 + 8 + 16])
        return v
    return None


if __name__ == "__main__":
    port = int(sys.argv[1])
    v = status(port)
    if v is None:
        print("no /status.reply from scsynth on port %d within 10 s" % port)
        sys.exit(1)
    time.sleep(1.0)
    v2 = status(port) or v
    print("status: ugens %d synths %d groups %d defs %d avgcpu %.2f peakcpu %.2f nominal %.1f actual %.1f" % (v2[1], v2[2], v2[3], v2[4], v2[5], v2[6], v2[7], v2[8]))
    if "--quit" in sys.argv:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.sendto(pad(b"/quit") + pad(b","), ("127.0.0.1", port))
    ok = abs(v2[8] - v2[7]) < 0.05 * v2[7]
    print("null audio clock runs at the nominal rate: %s" % ("yes" if ok else "NO"))
    sys.exit(0 if ok else 1)
