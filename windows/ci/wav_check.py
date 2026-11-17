#!/usr/bin/env python3
"""windows/ci/wav_check.py FILE MIN_FRAMES (M21): is FILE a WAV file whose header is final? (libsndfile writes the sizes when the file is closed: a recording that was cut off has a header that says 0 frames)
prints one line; exit 0 = a valid WAV with at least MIN_FRAMES frames and a header that matches the file, 1 = not."""
import struct, sys, os

def main():
    path, minf = sys.argv[1], int(sys.argv[2])
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            h = f.read(4096)
    except OSError as e:
        print("NOT FOUND: %s (%s)" % (path, e))
        return 1
    if h[:4] != b"RIFF" or h[8:12] != b"WAVE":
        print("NOT A WAV: %s (%d bytes)" % (path, size))
        return 1
    i, ch, bits, data_len, data_at = 12, 2, 24, None, None
    while i + 8 <= len(h):
        tag, ln = h[i:i + 4], struct.unpack("<I", h[i + 4:i + 8])[0]
        if tag == b"fmt ":
            ch, = struct.unpack("<H", h[i + 10:i + 12])
            bits, = struct.unpack("<H", h[i + 22:i + 24])
        if tag == b"data":
            data_len, data_at = ln, i + 8
            break
        i += 8 + ln + (ln & 1)
    if data_len is None:
        print("NO DATA CHUNK: %s" % path)
        return 1
    fb = ch * bits // 8
    actual = (size - data_at) // fb
    claimed = data_len // fb
    riff = struct.unpack("<I", h[4:8])[0]
    ok = claimed == actual and claimed >= minf and riff == size - 8
    print("%s: %s: the header says %d frames, the file has %d (need at least %d), riff size %d of %d" % ("found" if ok else "NOT VALID", os.path.basename(path), claimed, actual, minf, riff, size - 8))
    return 0 if ok else 1

sys.exit(main())
