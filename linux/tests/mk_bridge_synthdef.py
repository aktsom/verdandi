"""linux/tests/mk_bridge_synthdef.py OUTFILE: writes the SynthDef  vd_bridge_test = Out.ar(0, (SinOsc.ar(440) * 0.5 + In.ar(<first input bus>)) ! 2)  as a .scsyndef (format version 2)
without sclang, for the scsynth bridge test. The input bus index is 2: scsynth is started with 2 outputs and 2 inputs (-o 2 -i 2)."""
import struct
import sys


def pstr(s):
    b = s.encode()
    return struct.pack(">B", len(b)) + b


consts = [440.0, 0.0, 0.5, 2.0, 0.0]


def u(name, rate, inputs, n_out, special=0):
    out = pstr(name)
    out += struct.pack(">b", rate)
    out += struct.pack(">i", len(inputs))
    out += struct.pack(">i", n_out)
    out += struct.pack(">h", special)
    for (a, b) in inputs:
        out += struct.pack(">ii", a, b)
    out += struct.pack(">b", 2) * n_out
    return out


AR = 2
ugens = [
    u("SinOsc", AR, [(-1, 0), (-1, 1)], 1),
    u("BinaryOpUGen", AR, [(0, 0), (-1, 2)], 1, 2),  # *
    u("In", AR, [(-1, 3)], 1),
    u("BinaryOpUGen", AR, [(1, 0), (2, 0)], 1, 0),  # +
    u("Out", AR, [(-1, 4), (3, 0), (3, 0)], 0),
]
d = pstr("vd_bridge_test")
d += struct.pack(">i", len(consts)) + b"".join(struct.pack(">f", c) for c in consts)
d += struct.pack(">i", 0) + struct.pack(">i", 0)
d += struct.pack(">i", len(ugens)) + b"".join(ugens)
d += struct.pack(">h", 0)
data = b"SCgf" + struct.pack(">i", 2) + struct.pack(">h", 1) + d
open(sys.argv[1], "wb").write(data)
