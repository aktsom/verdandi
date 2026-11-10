"""windows/ci/resolve_crash.py: turn the offsets of a norns crash report into function names.
usage: python resolve_crash.py NORNS_EXE OFFSET [OFFSET ...]      (offsets as in the report: norns.exe+0x8102f, or 0x8102f, or the absolute address with --base 0x7ff6a77f0000)
       python resolve_crash.py NORNS_EXE --report crash-....txt   (every "norns.exe+0x..." line of a report)
NORNS_EXE must be the exe of the SAME build (the artifact m1-norns-bin of the workflow run of that commit; its sha256 is the artifact's digest). Windows builds keep the COFF symbol table, so no PDB is needed.
Pure Python 3, no packages; mangled C++ names are passed through c++filt when it is installed."""
import bisect
import re
import shutil
import struct
import subprocess
import sys


def read_symbols(path):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec, = struct.unpack_from("<H", d, pe + 6)
    symoff, nsym = struct.unpack_from("<II", d, pe + 12)
    optsize, = struct.unpack_from("<H", d, pe + 20)
    secs = []
    so = pe + 24 + optsize
    for i in range(nsec):
        name, vsize, va, rawsize, rawptr = struct.unpack_from("<8sIIII", d, so + 40 * i)
        secs.append((name.rstrip(b"\0").decode(), va, vsize))
    strtab = symoff + nsym * 18
    out = []
    i = 0
    while i < nsym:
        e = symoff + i * 18
        name8, value, secno, typ, cls, aux = struct.unpack_from("<8sIhHBB", d, e)
        if secno > 0 and cls in (2, 3) and (typ & 0xF0) == 0x20:
            if name8[:4] == b"\0\0\0\0":
                off = struct.unpack_from("<I", name8, 4)[0]
                end = d.index(b"\0", strtab + off)
                name = d[strtab + off:end].decode("latin1")
            else:
                name = name8.rstrip(b"\0").decode("latin1")
            out.append((secs[secno - 1][1] + value, name))
        i += 1 + aux
    out.sort()
    return out


def lookup(syms, addrs, rva):
    i = bisect.bisect_right(addrs, rva) - 1
    if i < 0 or rva - syms[i][0] > 0x100000:
        return "(no symbol)", 0
    return syms[i][1], rva - syms[i][0]


def demangle(names):
    cf = shutil.which("c++filt")
    if not cf:
        return names
    try:
        r = subprocess.run([cf], input="\n".join(names) + "\n", capture_output=True, text=True, timeout=30)
        out = r.stdout.split("\n")
        return out[: len(names)] if len(out) >= len(names) else names
    except Exception:
        return names


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    exe, rest = argv[1], argv[2:]
    base = None
    offs = []
    if "--base" in rest:
        k = rest.index("--base")
        base = int(rest[k + 1], 16)
        rest = rest[:k] + rest[k + 2:]
    if rest and rest[0] == "--report":
        for line in open(rest[1], errors="replace"):
            for m in re.finditer(r"norns\.exe\+(0x[0-9a-fA-F]+)", line):
                offs.append(int(m.group(1), 16))
    else:
        for a in rest:
            m = re.search(r"(0x[0-9a-fA-F]+)$", a)
            v = int(m.group(1), 16) if m else int(a, 16)
            offs.append(v - base if base is not None else v)
    syms = read_symbols(exe)
    addrs = [a for a, _ in syms]
    found = [lookup(syms, addrs, o) for o in offs]
    names = demangle([n for n, _ in found])
    for o, (n, off), dm in zip(offs, found, names):
        print("0x%x  %s+0x%x" % (o, dm, off))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
