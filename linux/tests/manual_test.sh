#!/bin/bash
# linux/tests/manual_test.sh: the Linux manual (linux/manual/manual.html), the page the MANUAL button opens.
#  - the file exists, is HTML, has a table of contents whose links all resolve, and every section is in it
#  - every section has a "sources:" comment above it (what its statements come from)
#  - no external resources (no script, link, img, iframe, no src= or href= to a web address)
#  - the known limitations section names the four topics it must (ARM plug-ins, Pi system commands, --terminal vs maiden's console, serialosc)
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
want = ["what-this-is", "install", "first-start", "window", "audio", "midi-grid", "maiden", "scripts", "files", "settings", "troubleshooting", "differences", "limitations", "licenses"]
res("the 14 sections of the outline are there, in order", p.sections == want, str(p.sections))

# a sources comment right above every section
blocks = re.findall(r"<!--(.*?)-->\s*<section id=\"([a-z-]+)\"", text, re.S)
have = {sid: c for c, sid in blocks}
res("every section has a sources comment above it", all(s in have and "sources:" in have[s] for s in want), ", ".join(s for s in want if s not in have or "sources:" not in have[s]))

# limitations
m = re.search(r'<section id="limitations">(.*?)</section>', text, re.S)
lim = m.group(1) if m else ""
for what, pat in (("ARM plug-ins", r"32-bit ARM"), ("Raspberry Pi system commands", r"sudo"), ("--terminal and maiden's console", r"--terminal.*5555|5555.*--terminal"), ("serialosc", r"serialosc")):
    res("limitations: " + what, re.search(pat, lim, re.S) is not None)

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
keys = ["in_ports", "out_ports", "input", "output", "rate", "period", "sys_monitor", "midi_in_from", "plugin_check", "serialosc_check"]
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
