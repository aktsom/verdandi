#!/bin/bash
# linux/tests/manual_test.sh: the Linux manual (linux/manual/manual.html), the page the MANUAL button opens.
#  - the file exists, is HTML, has a table of contents whose links all resolve, and every section is in it
#  - every section has a "sources:" comment above it (what its statements come from)
#  - no external resources (no script, link, img, iframe, no src= or href= to a web address)
#  - "If something goes wrong" names the topics it must (ARM plug-ins, Pi system commands, --terminal vs maiden's console, serialosc, duplicate engines, crash reports)
#  - no removed name (SYSTEM > UI, SYSTEM > BOX, GREYS, an OUT fader, ...), no history wording, no personal word
#  - a heading "SYSTEM > NAME" for every page of the SYSTEM list (read from lua/core/menu/system.lua)
#  - an entry in the manual for every shortcut the code handles: the hints of the right-click menu and the key tests of desktop_shell_linux.cc, the F keys of screen_window.cc and
#    lua/core/keyboard.lua, the arc keys of keyboard.lua
#  - every NORNS_* name the manual mentions exists in the source, every audio.conf key is read somewhere, every repository path in a <code> exists
# (that the button opens this file is linux/tests/manual_button_test.sh, which checks it when the file exists)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="${1:-$REPO/linux/manual/manual.html}"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }

[ -s "$FILE" ] && ok "the manual exists ($FILE)" || { echo "  FAIL  the manual is missing: $FILE"; exit 1; }
RESULT="$(python3 -I - "$FILE" "$REPO" << 'PY'
import html.parser, os, re, subprocess, sys
path, repo = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
out = []
def res(name, good, detail=""):
    out.append(("ok    " if good else "FAIL  ") + name + (": " + detail if detail and not good else ""))

res("starts with a doctype and has a title", text.lstrip().lower().startswith("<!doctype html>") and "<title>" in text)

class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.hrefs, self.sections, self.bad_ext, self.tags = set(), [], [], [], []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append(tag)
        if "id" in a: self.ids.add(a["id"])
        if tag == "a" and a.get("href"): self.hrefs.append(a["href"])
        if tag == "section": self.sections.append(a.get("id"))
        for k in ("src", "href", "action", "data"):
            v = a.get(k) or ""
            if re.match(r"(?i)(https?:)?//", v) or v.lower().startswith(("http:", "https:", "ftp:")):
                self.bad_ext.append(v)
p = P(); p.feed(text)
for t in ("script", "link", "img", "iframe", "object", "embed", "form"):
    res("no <%s>" % t, t not in p.tags)
res("no link to a web address (src/href)", not p.bad_ext, ", ".join(p.bad_ext))
anchors = [h[1:] for h in p.hrefs if h.startswith("#")]
res("all #links resolve", all(a in p.ids for a in anchors), ", ".join(a for a in anchors if a not in p.ids))
res("every section is in the table of contents", all(s in anchors for s in p.sections), ", ".join(s for s in p.sections if s not in anchors))
want = ["quickstart", "window", "home", "system", "sound-midi", "shortcuts", "files", "trouble", "licenses"]
res("the 9 sections of the outline are there, in order", p.sections == want, str(p.sections))

# a sources comment right above every section
blocks = re.findall(r"<!--(.*?)-->\s*<section id=\"([a-z-]+)\"", text, re.S)
have = {sid: c for c, sid in blocks}
res("every section has a sources comment above it", all(s in have and "sources:" in have[s] for s in want), ", ".join(s for s in want if s not in have or "sources:" not in have[s]))

# the virtual MIDI device and its two JACK ports are in the manual
for what, pat in (("the virtual device", r"<strong>virtual</strong>"), ("Verdandi:midi_in", r"Verdandi:midi_in"), ("Verdandi:midi_out", r"Verdandi:midi_out"), ("midi_out_to", r"<code>midi_out_to</code>"), ("the ALSA port Verdandi out", r"<strong>Verdandi out</strong>"), ("alsa_midi", r"<code>alsa_midi</code>"), ("alsa_midi_out_to", r"<code>alsa_midi_out_to</code>"), ("the VIRMIDI page", r"DEVICES &gt; VIRMIDI"), ("snd-virmidi", r"modprobe snd-virmidi"), ("Reset all MIDI devices", r"Reset all MIDI devices")):
    res("manual: " + what, re.search(pat, text) is not None)
# the troubleshooting section
m = re.search(r'<section id="trouble">(.*?)</section>', text, re.S)
lim = m.group(1) if m else ""
for what, pat in (("ARM plug-ins", r"32-bit ARM"), ("Raspberry Pi system commands", r"sudo"), ("--terminal and maiden's console", r"--terminal.*5555|5555.*--terminal"), ("serialosc", r"serialosc"),
                  ("duplicate engines", r"DUPLICATE ENGINES"), ("SuperCollider fail", r"SUPERCOLLIDER FAIL"), ("crash reports", r"logs/crash"), ("where the logs are", r"logs/norns\.log")):
    res("if something goes wrong: " + what, re.search(pat, lim, re.S) is not None)

# mi-UGens: what ships, which scripts it serves, how to turn it off, where the version is shown (SYSTEM > CLEAN UP), what a copy of the Raspberry Pi build does
m = re.search(r'<section id="home">(.*?)</section>', text, re.S)
home_sec = m.group(1) if m else text
for what, pat in (("the pack ships with Verdandi", r"mi-UGens.{0,400}(ships|shipped|comes) with"), ("Emplaitress and Terrarium named", r"Emplaitress.*Terrarium|Terrarium.*Emplaitress"),
                  ("no download or manual copy needed", r"no(thing to)? (download|install)|without (a )?download|never downloads?"), ("the off switch", r"<code>mi_ugens=0</code>"),
                  ("where the version is shown", r"CLEAN UP.{0,200}(MI-UGENS|mi-UGens)|(MI-UGENS|mi-UGens).{0,300}CLEAN UP"), ("a copy of its own is left alone", r"(not|never) (overwrit|replac|touch|delet)")):
    res("manual (HOME): mi-UGens, " + what, re.search(pat, home_sec, re.S | re.I) is not None)
res("manual: audio.conf key mi_ugens", re.search(r"<code>mi_ugens</code>", text) is not None)
res("manual: audio.conf key mi_ugens_heal", re.search(r"<code>mi_ugens_heal</code>", text) is not None)
for what, pat in (("a Raspberry Pi download is moved aside by itself", r"moves? (them|it|those|the files?) aside.{0,200}(start|restart)|(start|restart).{0,200}moves? (them|it|those|the files?) aside"),
                  ("the window note", r"A script downloaded Raspberry Pi mi-UGens"), ("nothing is deleted, restore by tidy", r"verdandi tidy restore"),
                  ("only with the own copy intact", r"(own copy|own pack|Verdandi.s own).{0,200}(missing|changed|intact)|(missing|changed|intact).{0,200}(own copy|own pack)"),
                  ("a download while norns runs: restart", r"(while norns runs|while it runs).{0,300}restart|restart.{0,300}(while norns runs|while it runs)")):
    res("manual (HOME and troubleshooting): mi-UGens heal, " + what, re.search(pat, home_sec + lim, re.S | re.I) is not None)
for what, pat in (("a class SuperCollider cannot find", r"could not find class|class .{0,40}(missing|not found)"), ("a class defined twice", r"duplicate class|classes twice|same pack twice")):
    res("if something goes wrong: " + what, re.search(pat, lim, re.S | re.I) is not None)

# the virtual MIDI card: never opened by norns, the setting, the page that follows the load
snd = home_sec + text
res("manual: audio.conf key midi_ignore", re.search(r"<code>midi_ignore</code>", text) is not None)
for what, pat in (("norns never opens the virtual card as a controller", r"(never|not) (opens?|lists?).{0,120}(VirMIDI|virtual MIDI card)|(VirMIDI|virtual MIDI card).{0,200}(never|not) (opened|listed|opens|lists)"),
                  ("the default list", r"VirMIDI;Virtual Raw MIDI"), ("a raw port has one reader", r"one reader|only one program|one program at a time"),
                  ("Reaper's error text", r"could not be opened"), ("the VIRMIDI page follows the load by itself", r"(by itself|on its own|without a key).{0,200}(loaded|load)|(loaded|load).{0,200}(by itself|on its own|without a key)"),
                  ("the Reaper entry hw:VirMIDI,<device>", r"hw:VirMIDI,"), ("a closed password dialog is said in plain words", r"(closed|cancel).{0,160}(dialog|password)|(dialog|password).{0,160}(closed|cancel)")):
    res("manual: virtual MIDI card, " + what, re.search(pat, text, re.S | re.I) is not None)

# plain text of the page (tags removed, entities decoded)
plain = html.unescape(re.sub(r"<[^>]+>", " ", text[text.index("<body>"):]))
plain = re.sub(r"\s+", " ", plain)
# removed names and words that do not belong in a manual
for what, pat, flags in (("SYSTEM > UI", r"SYSTEM > UI\b", 0), ("SYSTEM > BOX", r"SYSTEM > BOX\b", 0), ("the UI page", r"\bUI page\b|\bUI\b", 0), ("GREYS", r"\bGREYS\b", 0),
                         ("an OUT fader or slider", r"OUT (fader|slider)|output (fader|slider)", re.I), ("a SCREEN button", r"SCREEN button", 0), ("the HEX row of SCREEN", r"SCREEN.{0,3}s HEX|SCREEN HEX", 0),
                         ("history wording", r"was called|earlier version|first version|older version|used to be", re.I), ("a personal word", r"\bowner\b", re.I), ("the old name of the virtual MIDI device", r"JACK in", 0)):
    hit = re.search(pat, plain, flags)
    res("no removed name or history wording: " + what, hit is None, hit.group(0) if hit else "")

# a heading for every SYSTEM page
sysl = open(os.path.join(repo, "lua", "core", "menu", "system.lua")).read()
blocks_l = re.findall(r"m\.list = \{(.*?)\}", sysl, re.S)
pages = [x.strip() for x in re.findall(r'"([^"]+)"', blocks_l[-1])] if blocks_l else []
pages = [re.sub(r"\s*>\s*$", "", x) for x in pages]
res("the SYSTEM list was read from system.lua (%d pages)" % len(pages), len(pages) >= 9, str(pages))
h3 = [html.unescape(re.sub(r"<[^>]+>", "", h)) for h in re.findall(r"<h3[^>]*>(.*?)</h3>", text, re.S)]
nohead = [pg for pg in pages if "SYSTEM > " + pg not in h3]
res("every SYSTEM page has a heading 'SYSTEM > NAME' (%d)" % len(pages), not nohead, ", ".join(nohead))

# every shortcut the code handles is in the manual
def kbd(combo):
    return "+".join("<kbd>%s</kbd>" % k for k in combo.split("+"))
combos = set()
shell = open(os.path.join(repo, "matron", "src", "platform", "linux", "desktop_shell_linux.cc")).read()
for line in shell.splitlines():
    if "add_item(" in line:
        lits = re.findall(r'"([^"]*)"', line)
        if lits and lits[-1]:
            combos.add(lits[-1])
    m2 = re.search(r"ctrl\s*&&.*scancode == SDL_SCANCODE_([A-Z])\b", line)
    if m2:
        combos.add("Ctrl+" + ("Shift+" if re.search(r"(?<!!)shift\s*&&", line) else "") + m2.group(1))
for f in re.findall(r"SDL_SCANCODE_(F\d+)", shell):
    combos.add(f)
sw = open(os.path.join(repo, "matron", "src", "platform", "linux", "screen_window.cc")).read()
for f in re.findall(r"SDL_SCANCODE_(F\d+)", sw):
    combos.add(f)
    if f == "F11" and "KMOD_SHIFT" in sw:
        combos.add("Shift+F11")
kb = open(os.path.join(repo, "lua", "core", "keyboard.lua")).read()
for f in re.findall(r'c=="(F\d+)"', kb):
    combos.add(f)
arc = re.search(r"^local hw_arc = \{(.*)\}\s*$", kb, re.M)
arckeys = re.findall(r"(?:\['(\w)'\]|\b([A-Z]))=\{", arc.group(1)) if arc else []
arckeys = [a1 or a2 for a1, a2 in arckeys]
res("the shortcuts were read from the code (%d keys and %d arc keys)" % (len(combos), len(arckeys)), len(combos) >= 14 and len(arckeys) == 8, str(sorted(combos)) + str(arckeys))
shortcuts = re.search(r'<section id="shortcuts">(.*?)</section>', text, re.S)
sc = shortcuts.group(1) if shortcuts else ""
missing_sc = [c for c in sorted(combos) if kbd(c) not in sc]
res("every shortcut the code handles is in the shortcut table (%d)" % len(combos), not missing_sc, ", ".join(missing_sc))
missing_arc = [k for k in arckeys if "<kbd>%s</kbd>" % k not in sc]
res("every arc key is in the shortcut table", not missing_arc, ", ".join(missing_arc))

# the code is the source of the names
src = ""
for d in ("linux", "matron", "lua", "crone", "ws-wrapper", "maiden-repl"):
    for root, _, files in os.walk(os.path.join(repo, d)):
        if root.startswith(os.path.join(repo, "linux", "manual")) or os.sep + "tests" + os.sep in root + os.sep and False:
            continue
        for f in files:
            if f.endswith((".sh", ".c", ".cc", ".cpp", ".h", ".lua", ".py")) or f in ("sudo", "systemctl"):
                if os.path.join(root, f) == path: continue
                try: src += open(os.path.join(root, f), errors="replace").read()
                except OSError: pass
code = re.findall(r"<code>(.*?)</code>", text, re.S)
env = sorted(set(re.findall(r"\b(NORNS_[A-Z_]+|WS_WRAPPER_[A-Z_]+|PIPEWIRE_QUANTUM|XDG_PICTURES_DIR)\b", " ".join(code))))
missing = [e for e in env if e not in src]
res("every environment variable named (%d) is in the source" % len(env), not missing, ", ".join(missing))
keys = ["in_ports", "out_ports", "input", "output", "rate", "period", "sys_monitor", "midi_in_from", "midi_out_to", "alsa_midi", "alsa_midi_out_to", "plugin_check", "serialosc_check"]
nokey = [k for k in keys if ("conf_get " + k) not in src and (k + "=") not in src]
res("every audio.conf key in the table is read or written by the code", not nokey, ", ".join(nokey))
paths = sorted(set(c for c in code if re.match(r"(linux|docs|matron|lua|macos|ws-wrapper|maiden-repl)/[A-Za-z0-9_./*-]+$", c) and "*" not in c and "&" not in c))
gone = [c for c in paths if not os.path.exists(os.path.join(repo, c.rstrip("/")))]
res("every repository path in a <code> exists (%d)" % len(paths), not gone, ", ".join(gone))
print("\n".join(out))
PY
)"
echo "$RESULT" | sed 's/^/  /'
echo "$RESULT" | grep -q "^FAIL" && FAILS=$((FAILS + 1))
[ $FAILS -eq 0 ] && echo "manual_test: all passed" || echo "manual_test: failed"
[ $FAILS -eq 0 ]
