#!/usr/bin/env python3
"""the two diagrams of docs/port/plugin-feasibility.md (drawn with Pillow; no data in them, only the structure the note recommends). usage: make_diagrams.py [OUTDIR]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
F = lambda s, b=False: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if b else ""), s)
BG, INK = (250, 250, 247), (30, 32, 36)
C_DAW, C_SHM, C_HELP, C_EXT, C_NEW = (222, 232, 246), (255, 236, 196), (221, 240, 222), (236, 236, 236), (250, 218, 214)

def box(d, xy, fill, title, lines=(), tfont=None, lfont=None, outline=INK, w=2, radius=10):
    d.rounded_rectangle(xy, radius, fill=fill, outline=outline, width=w)
    x0, y0, x1, y1 = xy
    d.text((x0 + 12, y0 + 8), title, font=tfont or F(17, True), fill=INK)
    y = y0 + 8 + 26
    for l in lines:
        d.text((x0 + 14, y), l, font=lfont or F(14), fill=INK); y += 20

def arrow(d, a, b, label="", both=False, color=INK, off=(0, -16), width=3):
    d.line([a, b], fill=color, width=width)
    import math
    def head(p, q):
        ang = math.atan2(q[1] - p[1], q[0] - p[0])
        for s in (-0.45, 0.45):
            d.line([q, (q[0] - 14 * math.cos(ang + s), q[1] - 14 * math.sin(ang + s))], fill=color, width=width)
    head(a, b)
    if both: head(b, a)
    if label:
        mx, my = (a[0] + b[0]) / 2 + off[0], (a[1] + b[1]) / 2 + off[1]
        d.text((mx - d.textlength(label, font=F(13)) / 2, my), label, font=F(13), fill=color)

# ---------------------------------------------------------------- 1. architecture
im = Image.new("RGB", (1500, 1000), BG); d = ImageDraw.Draw(im)
d.text((20, 12), "Recommended: one plug-in, a helper process group per instance, shared memory between them", font=F(22, True), fill=INK)
d.text((20, 44), "(option A2 of the note: the DAW never runs norns code; a crash in the helpers cannot take the DAW down)", font=F(15), fill=INK)
# DAW process
d.rounded_rectangle((20, 90, 470, 930), 16, fill=C_DAW, outline=INK, width=3)
d.text((36, 98), "DAW process (Ableton Live, Reaper, ...)", font=F(18, True), fill=INK)
box(d, (44, 140, 446, 330), (255, 255, 255), "Verdandi.vst3  (thin shim)", ["audio thread: copy in/out of shared memory,", "  no locks, no allocation, no norns code", "reports latency L (plug-in delay compensation)", "passes audio through (delayed by L) when the", "  engine is not running or too slow"], lfont=F(13))
box(d, (44, 350, 446, 510), (255, 255, 255), "supervisor thread (not realtime)", ["starts / watches / stops the helper group", "heartbeat, restart after a crash, clear message", "instance id: its own ports, home, shm name"], lfont=F(13))
box(d, (44, 530, 446, 690), (255, 255, 255), "host-facing parts", ["parameters: connection status, bypass, \"show norns\"", "state: script, params, psets, data -> one blob", "  saved and restored with the DAW project", "tempo, play state, position -> control block"], lfont=F(13))
box(d, (44, 710, 446, 800), (255, 255, 255), "DAW keyboard", ["no keys needed here: the norns window is its", "own top-level window, owned by the helpers"], lfont=F(13))
d.text((44, 850), "bundled: the plug-in file (VST3 SDK, MIT)", font=F(13), fill=INK)
# shared memory
d.rounded_rectangle((510, 300, 780, 760), 16, fill=C_SHM, outline=INK, width=3)
d.text((528, 308), "shared memory", font=F(18, True), fill=INK)
d.text((528, 334), "(one segment per instance)", font=F(13), fill=INK)
for i, (t, l) in enumerate([("audio ring  in", "DAW -> norns, stereo, float"), ("audio ring  out", "norns -> DAW, stereo, float"), ("control block", "tempo, play, position (ppq),"), ("MIDI ring", "events with sample offsets"), ("state blob + version", "instance id, heartbeat")]):
    y = 370 + i * 76
    d.rounded_rectangle((530, y, 760, y + 64), 8, fill=(255, 255, 255), outline=INK, width=2)
    d.text((540, y + 6), t, font=F(14, True), fill=INK); d.text((540, y + 28), l, font=F(12), fill=INK)
# helpers
d.rounded_rectangle((820, 90, 1480, 930), 16, fill=C_HELP, outline=INK, width=3)
d.text((836, 98), "helper process group (per instance, started by the plug-in)", font=F(18, True), fill=INK)
box(d, (844, 140, 1456, 440), (255, 255, 255), "norns engine process  (today's `norns` program + libscsynth)", ["matron: Lua scripts, clock, params, devices, the screen window (SDL)", "crone + softcut: today's JACK clients, driven by the host pump instead", "libscsynth in the same process: patched external audio driver   [NEW]", "  -> one thread runs input -> crone -> scsynth -> crone/softcut -> output,", "     once per block, sample-synchronous, no JACK, no resampling", "host clock source in matron: tempo, play, position from the control block   [NEW]", "per-instance ports and home (today fixed: 8888, 9999, 57120, ...)   [CHANGED]"], lfont=F(13))
box(d, (844, 460, 1160, 600), (255, 255, 255), "sclang", ["engines, mods, norns SC classes", "talks OSC to libscsynth", "(norns already has", " `useRemoteServer`)"], lfont=F(13))
box(d, (1180, 460, 1456, 600), (255, 255, 255), "maiden + ws-wrapper", ["web editor, script catalog", "own port per instance", "opens in the browser"], lfont=F(13))
box(d, (844, 620, 1160, 760), (255, 255, 255), "devices", ["MIDI ports, grid, arc, crow", "(serial / COM ports),", "virtual grid / arc / keys,", "file dialogs (native)"], lfont=F(13))
box(d, (1180, 620, 1456, 760), (255, 255, 255), "norns window", ["own top-level window:", "keyboard and mouse go", "straight to it, the host", "never sees the keys"], lfont=F(13))
d.text((844, 885), "[NEW] / [CHANGED] = code that does not exist today (see the effort table).", font=F(13), fill=(150, 30, 30))
d.text((844, 907), "Everything else is the norns the owner runs today.", font=F(13), fill=INK)
# arrows
arrow(d, (446, 240), (510, 400), "audio", both=True)
arrow(d, (446, 600), (510, 600), "clock, state", both=True, off=(0, -34))
arrow(d, (446, 430), (510, 690), "")
arrow(d, (780, 420), (844, 290), "audio", both=True)
arrow(d, (780, 540), (844, 330), "tempo", both=False, off=(-30, 6))
arrow(d, (1000, 440), (1000, 460), "OSC")
# outside
box(d, (844, 775, 1456, 868), C_EXT, "outside", ["audio interface (ASIO) is owned by the DAW only; the helpers never open it", "hardware grids and the browser (maiden) connect to the helpers directly"], lfont=F(13))
im.save(os.path.join(OUT, "architecture.png"))

# ---------------------------------------------------------------- 2. data flow
im = Image.new("RGB", (1500, 900), BG); d = ImageDraw.Draw(im)
d.text((20, 12), "Audio and clock: one host callback, one block, one pass through norns", font=F(22, True), fill=INK)
lanes = [("DAW audio thread\n(any block size N)", 90, C_DAW), ("shared memory", 270, C_SHM), ("engine pump thread\n(helper process)", 450, C_HELP), ("matron clock / Lua", 700, C_HELP)]
for t, y, c in lanes:
    h = 160 if y < 700 else 150
    d.rounded_rectangle((20, y, 1480, y + h), 12, fill=c, outline=INK, width=2)
    d.multiline_text((34, y + 10), t, font=F(15, True), fill=INK)
def blk(x, y, w, t, fill=(255, 255, 255), h=46):
    d.rounded_rectangle((x, y, x + w, y + h), 7, fill=fill, outline=INK, width=2); d.text((x + 8, y + 12), t, font=F(13), fill=INK)
blk(240, 110, 230, "1. get N input frames"); blk(500, 110, 270, "2. write in-ring + control block"); blk(1080, 110, 170, "6. read out-ring"); blk(1270, 110, 190, "7. add to the track")
blk(240, 190, 640, "reports latency L = pipeline depth + norns internal; the host compensates (PDC)", fill=(255, 250, 235))
blk(240, 290, 250, "control block: tempo, play, ppq", fill=(255, 245, 220)); blk(500, 290, 270, "in-ring (float, stereo)", fill=(255, 245, 220)); blk(1080, 290, 250, "out-ring (float, stereo)", fill=(255, 245, 220))
blk(800, 360, 640, "fill levels watched: a short ring is padded with silence and counted, never waited for", fill=(255, 250, 235))
blk(500, 470, 270, "3. pull one block (semaphore wake)"); blk(800, 470, 250, "4. crone in -> scsynth (64-frame\nsub-blocks) -> crone / softcut", h=60); blk(1080, 470, 250, "5. push the result to the out-ring")
blk(500, 570, 560, "same clock as the host: no JACK, no resampler, no drift (the pump follows the callback)", fill=(255, 250, 235))
blk(240, 720, 300, "host source: tempo + ppq -> beats"); blk(570, 720, 330, "tick events at sample offsets in the block"); blk(930, 720, 300, "clock.run / clock.sync in Lua")
arrow(d, (370, 156), (370, 290), "")
arrow(d, (635, 156), (635, 290), "")
arrow(d, (635, 336), (635, 470), "")
arrow(d, (1205, 470), (1205, 336), "")
arrow(d, (1205, 290), (1165, 156), "")
arrow(d, (1250, 133), (1270, 133), "")
arrow(d, (770, 493), (800, 493), "")
arrow(d, (1050, 493), (1080, 493), "")
arrow(d, (370, 336), (370, 720), "")
d.text((240, 790), "today (standalone): the clock comes from MIDI clock ticks timed by the system clock; no song position, no continue (docs/port/clock-notes.md)", font=F(13), fill=INK)
d.text((240, 812), "plug-in: matron is told the host's tempo and position directly, so Start, Stop, Continue, loops and jumps are exact", font=F(13), fill=INK)
d.text((20, 870), "Measured on this machine (virtual, not realtime): the wake-up of a second process takes about 0.1 to 0.2 ms, 1 to 2.5 ms at the 99th percentile, with rare spikes of 25 to 30 ms (see the note).", font=F(13), fill=INK)
im.save(os.path.join(OUT, "dataflow.png"))
print("ok")
