#!/usr/bin/env python3
"""windows/ci/dump_report.py DUMP...: what a Windows minidump (made by WER LocalDumps, DumpType 1 or 2) says about the crash, without a debugger:
   the exception (code, address, for an access violation what was touched), the module and offset of the instruction, the modules that were loaded, and the words of the crashed thread's stack that point into a
   module (a poor man's stack: module+offset, the nearest ones to the stack pointer first). stdlib only."""
import struct, sys

def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]

def report(path):
    b = open(path, "rb").read()
    print("== %s (%d bytes)" % (path, len(b)))
    if b[:4] != b"MDMP":
        print("not a minidump"); return
    n, dirrva = u32(b, 8), u32(b, 12)
    streams = {}
    for i in range(n):
        t, size, rva = struct.unpack_from("<III", b, dirrva + 12 * i)
        streams[t] = (size, rva)
    mods = []
    if 4 in streams:
        cnt = u32(b, streams[4][1])
        for i in range(cnt):
            o = streams[4][1] + 4 + 108 * i
            base, size = u64(b, o), u32(b, o + 8)
            nrva = u32(b, o + 20)
            nlen = u32(b, nrva)
            name = b[nrva + 4:nrva + 4 + nlen].decode("utf-16le", "replace")
            mods.append((base, size, name.replace("\\", "/").split("/")[-1], name))
    def where(addr):
        for base, size, name, _ in mods:
            if base <= addr < base + size:
                return "%s+0x%x" % (name, addr - base)
        return None
    if 6 not in streams:
        print("no exception stream (a dump of a running process?)"); return
    o = streams[6][1]
    tid = u32(b, o)
    code, flags, _rec, addr, npar = struct.unpack_from("<IIQQI", b, o + 8)
    info = [u64(b, o + 8 + 32 + 8 * k) for k in range(min(npar, 15))]
    cres, crva = u32(b, o + 8 + 152), u32(b, o + 8 + 156)
    print("thread %d, exception 0x%08X at 0x%x = %s" % (tid, code, addr, where(addr) or "(not in a loaded module)"))
    if code == 0xC0000005 and len(info) >= 2:
        print("access violation: %s address 0x%x" % ({0: "reading", 1: "writing", 8: "executing (DEP)"}.get(info[0], "?"), info[1]))
    rsp = rip = 0
    if cres >= 0xF8 + 8:
        rsp, rip = u64(b, crva + 0x98), u64(b, crva + 0xF8)
        print("context: rip=0x%x (%s) rsp=0x%x" % (rip, where(rip), rsp))
    # the memory around the stack pointer
    ranges = []
    if 5 in streams:
        c = u32(b, streams[5][1])
        for i in range(c):
            s, sz, rva = struct.unpack_from("<QII", b, streams[5][1] + 4 + 16 * i)
            ranges.append((s, sz, rva))
    if 9 in streams:
        c, base_rva = u64(b, streams[9][1]), u64(b, streams[9][1] + 8)
        off = base_rva
        for i in range(c):
            s, sz = struct.unpack_from("<QQ", b, streams[9][1] + 16 + 16 * i)
            ranges.append((s, sz, off)); off += sz
    print("modules loaded: %d; plug-ins among them: %s" % (len(mods), ", ".join(sorted(m[2] for m in mods if m[2].lower().endswith(".scx"))) or "none"))
    for s, sz, rva in ranges:
        if s <= rsp < s + sz:
            end = min(s + sz, rsp + 16384)
            words, k = [], rsp
            while k + 8 <= end and len(words) < 60:
                v = u64(b, rva + (k - s))
                w = where(v)
                if w and not w.lower().startswith(("ntdll", "kernelbase", "kernel32")):
                    words.append("rsp+0x%x: %s" % (k - rsp, w))
                k += 8
            print("words on the stack that point into modules (nearest first):")
            for w in words[:40]: print("   " + w)
            break
    else:
        print("the stack of the crashed thread is not in the dump")

for p in sys.argv[1:]:
    try:
        report(p)
    except Exception as e:
        print("could not read %s: %s" % (p, e))
