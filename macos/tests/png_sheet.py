#!/usr/bin/env python3
"""Contact sheet of norns screen PNGs, no dependencies.

usage: python3 -I png_sheet.py <out.png> <scale> <columns> <in.png>...

reads 8-bit PNGs (gray, gray+alpha, rgb, rgba; non-interlaced), flattens alpha onto black
like the oled, scales by an integer factor and lays them out in a grid with a 2px gap.
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, idat, w = 8, b'', 0
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and interlace == 0, (path, depth, interlace)
        elif kind == b'IDAT':
            idat += body
        pos += 12 + n
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        gray = []
        for x in range(w):
            px = line[x * bpp:(x + 1) * bpp]
            v = px[0] if ctype in (0, 4) else (px[0] * 3 + px[1] * 6 + px[2]) // 10
            alpha = px[-1] if ctype in (4, 6) else 255
            gray.append(v * alpha // 255)
        rows.append(gray)
    return w, h, rows


def write_png(path, w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 9)))
        f.write(chunk(b'IEND', b''))


def main():
    out, scale, cols, paths = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
    imgs = [read_png(p) for p in paths]
    cw, ch, gap = 128 * scale, 64 * scale, 2
    n_rows = (len(imgs) + cols - 1) // cols
    W, H = cols * cw + (cols - 1) * gap, n_rows * ch + (n_rows - 1) * gap
    sheet = [[60] * W for _ in range(H)]
    for i, (w, h, rows) in enumerate(imgs):
        ox, oy = (i % cols) * (cw + gap), (i // cols) * (ch + gap)
        for y in range(min(h, 64) * scale):
            src = rows[y // scale]
            dst = sheet[oy + y]
            for x in range(min(w, 128) * scale):
                dst[ox + x] = src[x // scale]
    write_png(out, W, H, sheet)


main()
