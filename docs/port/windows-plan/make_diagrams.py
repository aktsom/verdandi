#!/usr/bin/env python3
"""the two diagrams of docs/port/windows-plan.md (Pillow; structure only, nothing measured). usage: make_diagrams.py [OUTDIR]"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
F = lambda s, b=False: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if b else ""), s)
BG, INK = (250, 250, 247), (30, 32, 36)
BLUE, GREEN, AMBER, GREY, RED = (222, 232, 246), (221, 240, 222), (255, 236, 196), (236, 236, 236), (250, 218, 214)

def box(d, xy, fill, title, lines=(), lf=13):
    d.rounded_rectangle(xy, 9, fill=fill, outline=INK, width=2)
    d.text((xy[0] + 10, xy[1] + 7), title, font=F(15, True), fill=INK)
    y = xy[1] + 31
    for l in lines:
        d.text((xy[0] + 12, y), l, font=F(lf), fill=INK); y += 19

def arrow(d, a, b, label="", both=False, off=(0, -16), color=INK, w=3):
    d.line([a, b], fill=color, width=w)
    def head(p, q):
        ang = math.atan2(q[1] - p[1], q[0] - p[0])
        for s in (-0.45, 0.45):
            d.line([q, (q[0] - 13 * math.cos(ang + s), q[1] - 13 * math.sin(ang + s))], fill=color, width=w)
    head(a, b)
    if both: head(b, a)
    if label:
        mx, my = (a[0] + b[0]) / 2 + off[0], (a[1] + b[1]) / 2 + off[1]
        d.text((mx - d.textlength(label, font=F(12)) / 2, my), label, font=F(12), fill=color)

# ---------------------------------------------------------------- 1. architecture
im = Image.new("RGB", (1500, 860), BG); d = ImageDraw.Draw(im)
d.text((20, 10), "Verdandi for Windows: one application, one audio callback, no JACK", font=F(22, True), fill=INK)
d.text((20, 42), "boxes marked NEW are code that does not exist today; everything else is the Linux program with a Windows platform layer", font=F(14), fill=INK)
d.rounded_rectangle((20, 80, 1010, 840), 14, fill=GREEN, outline=INK, width=3)
d.text((36, 88), "Verdandi (installed in %LOCALAPPDATA%\\Programs\\Verdandi, user data in %USERPROFILE%\\Verdandi)", font=F(16, True), fill=INK)
box(d, (40, 125, 520, 235), AMBER, "Verdandi.exe  (launcher, NEW)", ["starts and watches everything below (job object: one close ends all)", "one instance only: raises the window on a second start", "problem notes in plain words; \"report a problem\" zip"])
box(d, (40, 255, 520, 560), (255, 255, 255), "norns.exe  (matron + crone + softcut + sidecar)", ["Lua scripts, clock, params, devices, SDL window", "crone and softcut: today's code, driven by one callback", "audio backend (NEW): PortAudio, ASIO or WASAPI", "  the callback also pumps scsynth, once per block:", "  input -> crone -> scpump.dll -> crone -> output", "clock sources: internal, MIDI, Ableton Link", "devices: COM grids and arcs, MIDI, HID, file dialogs", "sidecar: shell commands through the bundled tools (NEW)"])
box(d, (540, 255, 990, 400), (255, 255, 255), "scpump.dll  (NEW, built with MSVC)", ["SuperCollider 3.14.1 as a library: scsynth's World", "with an external audio driver (a small patch)", "no scsynth process, no audio device of its own", "plug-ins: Windows DLLs only (sc3-plugins, mi-UGens)"])
box(d, (540, 420, 990, 560), (255, 255, 255), "sclang.exe  (built from source, no Qt)", ["engines, mods, norns SC classes", "talks OSC to scpump (Crone.useRemoteServer)", "NornsVirtualHome and the SynthDef compat layer"])
box(d, (40, 580, 520, 700), (255, 255, 255), "maiden.exe + ws-wrapper.exe  (on demand)", ["web editor in the browser, script catalog", "port chosen by the launcher, loopback only"])
box(d, (540, 580, 990, 700), (255, 255, 255), "bundled tools", ["busybox (sh, ls, cp, mv, unzip, ...), curl, tar", "for scripts and mods that run shell commands"])
box(d, (40, 720, 990, 825), (255, 255, 255), "files", ["program: read only.  data: %USERPROFILE%\\Verdandi\\dust (scripts, samples, data), logs, audio.conf, ui.conf, box.conf, box-presets", "the CLEAN UP page keeps it tidy; /home/we inside scripts is translated to this folder (virtual home)"], lf=13)
# outside
box(d, (1050, 125, 1480, 235), BLUE, "Ableton Live", ["owns the Fireface ASIO driver", "Link on, tempo and transport", "MIDI to the loopMIDI port"], lf=13)
box(d, (1050, 255, 1480, 365), GREY, "RME Fireface UC + TotalMix FX", ["ASIO multi-client (to verify), routing", "the loop that brings norns' audio", "back into Ableton"], lf=13)
box(d, (1050, 385, 1480, 475), GREY, "monome grids (2) on COM ports", ["found by Verdandi itself; serialosc", "is optional"], lf=13)
box(d, (1050, 495, 1480, 585), GREY, "MIDI: loopMIDI or Windows MIDI Services", ["virtual port for notes and clock", "(Link makes it optional)"], lf=13)
box(d, (1050, 605, 1480, 695), GREY, "browser", ["maiden at http://localhost:..."], lf=13)
for y, lab in ((180, "Link, MIDI"), (310, "ASIO channels"), (430, "COM ports"), (540, "MIDI"), (650, "HTTP")):
    arrow(d, (1050, y), (1012, y), lab, both=True, off=(0, -17))
im.save(os.path.join(OUT, "architecture.png"))

# ---------------------------------------------------------------- 2. audio routing
im = Image.new("RGB", (1500, 760), BG); d = ImageDraw.Draw(im)
d.text((20, 10), "Audio with Ableton owning the Fireface: the recommended route and its two fallbacks", font=F(22, True), fill=INK)
box(d, (40, 70, 420, 200), BLUE, "Ableton Live", ["ASIO driver: RME Fireface (the only one it uses)", "tracks: outputs to the main pair,", "an audio track records \"Ext. In\" (norns)"], lf=13)
box(d, (40, 250, 420, 400), GREEN, "Verdandi", ["PortAudio ASIO: the same driver, as a second client", "follows the rate and buffer that Ableton set", "output: a channel pair that nothing else uses", "input: line/mic pair, or the Ableton route"], lf=13)
box(d, (500, 120, 1000, 380), GREY, "RME ASIO driver and TotalMix FX", ["multi-client: both programs at once, same sample rate", "(RME manuals: yes for RME interfaces; the UC model", " and driver version: to be verified)", "", "TotalMix FX routes channels:", "  a software LOOPBACK (if the UC has it), or", "  a digital loop: SPDIF or ADAT out cabled to in, or", "  an analog loop: out 7 cabled to in 7"], lf=13)
box(d, (1060, 120, 1480, 250), AMBER, "recommended (default)", ["multi-client ASIO + TotalMix route.", "the in-app audio doctor finds the pair,", "plays a test tone, listens for the loop", "and says what to change, in words"], lf=13)
box(d, (1060, 270, 1480, 390), AMBER, "fallback 1", ["the interface's Windows (WDM / WASAPI) devices", "beside ASIO: the same TotalMix route", "(RME drivers are said to allow this: verify)"], lf=13)
box(d, (1060, 410, 1480, 540), RED, "fallback 2", ["a hardware loop cable, or a virtual cable program:", "a virtual cable cannot reach Ableton while", "Ableton uses one ASIO driver (my knowledge,", "not verified); Voicemeeter-type tools can"], lf=13)
arrow(d, (420, 150), (500, 200), "ASIO", both=True, off=(0, -16))
arrow(d, (420, 320), (500, 300), "ASIO", both=True, off=(0, 10))
box(d, (40, 450, 1000, 560), (255, 255, 255), "clock and notes (no audio)", ["Ableton Link: tempo and start/stop, nothing to install (norns already has Link, GPL-2.0-or-later).", "fallback: MIDI clock and notes through a virtual MIDI port (loopMIDI, or Windows MIDI Services)."], lf=13)
box(d, (40, 590, 1000, 730), (255, 255, 255), "input modes in the app", ["MIC: the chosen input channels.   OFF: silence.", "SYS: what Windows plays (WASAPI loopback of the default output): NOT Ableton's ASIO audio, which bypasses Windows' mixer.", "APP: one program's audio (per-process loopback on recent Windows 10 and 11), same limit for ASIO programs.", "AUX (new): an ASIO channel pair, for the Ableton route."], lf=13)
im.save(os.path.join(OUT, "audio-routing.png"))
print("ok")
