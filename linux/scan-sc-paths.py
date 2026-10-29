#!/usr/bin/env python3
"""linux/scan-sc-paths.py FOLDER [--json OUT]: which SuperCollider files (.sc, .scd) of the scripts under FOLDER name the virtual path /home/we (docs/port/KNOWN-ISSUES.md item 20).
FOLDER holds one folder per script (your dust/code, or a folder of clones). it only READS. comments are skipped. it prints the affected scripts, each file and line, and what the
line does with the path as far as a word on the same line says so (folder listing, file read or write, buffer, load, a shell command, only text). a script whose .sc files never
name /home/we is not listed: SuperCollider code that builds a path from Platform.userHomeDir, thisProcess.nowExecutingPath or Document.current.path already got the real folder.
(since sc/linux/NornsVirtualHome.sc is loaded by the launcher, an affected script now finds its files; the list is what depends on that file.)"""
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
VHOME = re.compile(r"(?<![\w.-])/home/we(?![\w.-])")  # whole path component, as the launcher and lua layer match it
COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
KINDS = [
    ("folder listing", re.compile(r"PathName|pathMatch|\.entries|\.files|\.folders|SoundFile\.collect|listDir")),
    ("buffer / sound file", re.compile(r"Buffer\.|b_allocRead|b_read|b_write|SoundFile|\.read\(|\.write\(|loadToFloatArray")),
    ("loads code", re.compile(r"\.load\b|loadRelative|executeFile|\.interpret|\.loadPaths|thisProcess\.interpreter")),
    ("file read/write", re.compile(r"File[\.\(]|readAllString|\.exists|\.delete|\.mkdir|writeDefFile|writeArchive|readArchive")),
    ("shell command", re.compile(r"unixCmd|systemCmd|unixCmdGetStdOut|Pipe")),
]
res = {}
for f in sorted(root.rglob("*")):
    if f.suffix not in (".sc", ".scd") or not f.is_file():
        continue
    try:
        raw = f.read_text(errors="replace")
    except OSError:
        continue
    text = COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), raw)
    script = f.relative_to(root).parts[0]
    for n, line in enumerate(text.splitlines(), 1):
        if VHOME.search(line):
            kind = next((k for k, rx in KINDS if rx.search(line)), "only text (a variable or an argument; look at its uses)")
            res.setdefault(script, []).append({"file": str(f.relative_to(root)), "line": n, "kind": kind, "text": line.strip()[:140]})
print("scanned %s: %d script folder(s) with a .sc or .scd file naming /home/we" % (root, len(res)))
for script in sorted(res):
    kinds = sorted({e["kind"] for e in res[script]})
    print("\n%s  (%d line(s): %s)" % (script, len(res[script]), "; ".join(kinds)))
    for e in res[script][:6]:
        print("   %s:%d  [%s]  %s" % (e["file"], e["line"], e["kind"], e["text"]))
    if len(res[script]) > 6:
        print("   ... %d more" % (len(res[script]) - 6))
if out:
    json.dump(res, open(out, "w"), indent=1)
