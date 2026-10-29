#!/usr/bin/env python3
"""linux/scan-shell-paths.py FOLDER [--json OUT]: which Lua scripts under FOLDER (one folder per script) run shell commands that name a norns path (the virtual /home/we or _path.*)
(docs/port/KNOWN-ISSUES.md item 22). it only READS. comments are skipped. per script it prints each line and what the line does:
  reads output   os.capture / util.os_capture / io.popen / norns.system_cmd: the answer comes back to the script (this is where a command's stderr matters: since item 22 it is no longer part of the answer)
  runs           os.execute: only the exit status comes back
  builds         a string that starts with a shell command (ls, curl, unzip ...) and names such a path; the call is on another line
a script is not listed when none of its Lua lines does this. every command already gets /home/we translated to the real home (lua/core/virtual_home.lua)."""
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
LONG_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.S)
LINE_COMMENT = re.compile(r"--[^\n]*")
PATH = re.compile(r"(?<![\w.-])/home/we(?![\w.-])|\b_path\.\w+|\bpaths\.\w+")
READS = re.compile(r"os\.capture|os_capture|io\.popen|system_cmd|\bcapture\s*\(")
RUNS = re.compile(r"os\.execute|\bexecute\s*\(")
VERB = re.compile(r"""["'](?:sudo\s+)?(ls|cp|mv|rm|mkdir|curl|wget|unzip|zip|tar|cat|find|touch|sox|soxi|ffmpeg|aplay|arecord|convert|chmod|du|df|rsync|git|echo|grep|sed|awk|ln|basename|dirname|file|mpg123|lame|flac|oggenc|ogg123|youtube-dl|yt-dlp|python3?|bash|sh|which|test|head|tail|sort|wc|readlink|stat)\b""")
res = {}
for f in sorted(root.rglob("*.lua")):
    if not f.is_file():
        continue
    try:
        raw = f.read_text(errors="replace")
    except OSError:
        continue
    text = LONG_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), raw)
    text = LINE_COMMENT.sub("", text)
    script = f.relative_to(root).parts[0]
    for n, line in enumerate(text.splitlines(), 1):
        if not PATH.search(line):
            continue
        if READS.search(line):
            kind = "reads output"
        elif RUNS.search(line):
            kind = "runs"
        elif VERB.search(line):
            kind = "builds"
        else:
            continue
        res.setdefault(script, []).append({"file": str(f.relative_to(root)), "line": n, "kind": kind, "text": line.strip()[:160]})
print("scanned %s: %d script(s) run shell commands that name a norns path" % (root, len(res)))
for script, hits in sorted(res.items()):
    kinds = sorted({h["kind"] for h in hits})
    print("\n%s  (%d line(s): %s)" % (script, len(hits), ", ".join(kinds)))
    for h in hits[:6]:
        print("   %s:%d  [%s]  %s" % (h["file"], h["line"], h["kind"], h["text"]))
    if len(hits) > 6:
        print("   ... %d more" % (len(hits) - 6))
if out:
    Path(out).write_text(json.dumps(res, indent=1))
