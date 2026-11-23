#!/usr/bin/env python3
# M31: the vanish probe reads "VT_NOTE mode|note|window note"; the window note must come back exactly (no padding bars),
# or "the note is gone" (nil) is never seen as gone. Fails with the old parser (it returned "nil|||").
import importlib.util, sys, os
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("maiden_probe_m31", os.path.join(here, "..", "..", "windows", "ci", "maiden_probe.py"))
src = open(spec.origin).read()
ns = {}
start = src.index("def parse_vt_note")
end = src.index("\n\n\n", start)
exec(src[start:end], ns)
f = ns["parse_vt_note"]
cases = [
    ("VT_NOTE device|nil|nil", ("device", "nil", "nil")),
    ("VT_NOTE fallback|no sound: x|NO SOUND. x", ("fallback", "no sound: x", "NO SOUND. x")),
    ("VT_NOTE null|a|b|c", ("null", "a", "b|c")),
    ("VT_NOTE device|", ("device", "", "")),
]
bad = [(i, f(i), want) for i, want in cases if f(i) != want]
if bad:
    print("FAIL", bad); sys.exit(1)
print("PASS vt_note_parse")
