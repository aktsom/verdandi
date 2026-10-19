#!/usr/bin/env python3
"""Draw the app icon (no dependencies): a dark tile with a 2:1 screen showing a pixel
waveform, and three encoders. writes a 1024x1024 RGBA PNG.

usage: python3 -I make-icon.py <out.png>
"""
import math
import struct
import sys
import zlib

N = 1024


def clamp(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def rounded_rect(px, py, cx, cy, hw, hh, r):
    dx = abs(px - cx) - (hw - r)
    dy = abs(py - cy) - (hh - r)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    return outside + min(max(dx, dy), 0.0) - r


def circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def ring(px, py, cx, cy, r, w):
    return abs(math.hypot(px - cx, py - cy) - r) - w / 2


def cover(d):
    return clamp(0.5 - d)


# the screen: 128x64 "pixels" scaled into a 2:1 rect
SX, SY, SW, SH = 192, 250, 640, 320
PIX = SW / 32.0  # 32x16 coarse pixels


def screen_pixel(px, py):
    """brightness of the pixel waveform at a point inside the screen (0..1)"""
    gx = int((px - SX) / PIX)
    gy = int((py - SY) / PIX)
    if gx < 0 or gx >= 32 or gy < 0 or gy >= 16:
        return 0.0
    wave = 8 + 5.5 * math.sin(gx / 31.0 * 2 * math.pi * 1.5) * math.cos(gx / 31.0 * math.pi * 0.5)
    if abs(gy - round(wave)) == 0:
        return 1.0
    if gy == 15 and gx < 10:
        return 0.35  # a dim status line
    return 0.0


def shade(px, py):
    # background tile
    d_tile = rounded_rect(px, py, 512, 512, 448, 448, 190)
    a = cover(d_tile)
    if a == 0:
        return (0, 0, 0, 0)
    # subtle vertical gradient
    base = 26 + 14 * (1 - py / N)
    r = g = b = base
    # screen bezel and glass
    d_bezel = rounded_rect(px, py, SX + SW / 2, SY + SH / 2, SW / 2 + 22, SH / 2 + 22, 30)
    c = cover(d_bezel)
    r, g, b = r + (8 - r) * c, g + (8 - g) * c, b + (8 - b) * c
    if SX <= px < SX + SW and SY <= py < SY + SH:
        v = screen_pixel(px, py)
        lit = 235 * v
        r, g, b = max(r, lit), max(g, lit), max(b, lit * 0.96)
    # encoders
    for ex in (322, 512, 702):
        d_ring = ring(px, py, ex, 742, 62, 12)
        cr = cover(d_ring)
        r, g, b = r + (200 - r) * cr, g + (200 - g) * cr, b + (200 - b) * cr
        d_dot = circle(px, py, ex + 30, 742 - 30, 9)
        cd = cover(d_dot)
        r, g, b = r + (235 - r) * cd, g + (235 - g) * cd, b + (235 - b) * cd
    return (int(r), int(g), int(b), int(255 * a))


def main():
    rows = []
    for y in range(N):
        row = bytearray(b'\x00')
        for x in range(N):
            row += bytes(shade(x + 0.5, y + 0.5))
        rows.append(bytes(row))

    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)

    with open(sys.argv[1], 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(b''.join(rows), 9)))
        f.write(chunk(b'IEND', b''))


main()
