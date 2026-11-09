"""windows/ci/png_nonblank.py: is this PNG a picture or an empty screen? standard library only.
usage: python png_nonblank.py FILE.png [MIN_DISTINCT]   exit 0 when the image has at least MIN_DISTINCT (default 2) different pixel values and some lit pixels,
prints: width x height, bit depth, colour type, number of distinct byte values in the pixel data, share of non-zero bytes."""
import struct
import sys
import zlib


def main():
    path = sys.argv[1]
    need = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        print("not a PNG")
        return 1
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + n]
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + n
    if ihdr is None or not idat:
        print("no image data")
        return 1
    w, h, depth, ctype = ihdr[0], ihdr[1], ihdr[2], ihdr[3]
    raw = zlib.decompress(idat)
    # skip the filter byte of every row (the filters do not change whether a picture has content)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype, 1)
    row = 1 + (w * channels * depth + 7) // 8
    pix = b"".join(raw[i * row + 1 : (i + 1) * row] for i in range(h))
    distinct = len(set(pix))
    lit = sum(1 for b in pix if b) / max(1, len(pix))
    print("%dx%d depth %d colour type %d, %d distinct byte values, %.1f%% non-zero bytes" % (w, h, depth, ctype, distinct, lit * 100))
    return 0 if distinct >= need and lit > 0.001 else 1


if __name__ == "__main__":
    sys.exit(main())
