#!/usr/bin/env python3
"""Static compatibility scan of the norns community catalog.

usage: python3 -I scan_catalog.py <norns-root> <out.json>

<norns-root> is the project folder holding catalog/src (one clone per catalog
entry, from fetch_one.sh) and upstream/{norns,supercollider,sc3-plugins,mi-UGens}.
Nothing from the catalog is executed; files are only read.
"""
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(sys.argv[1])
OUT = Path(sys.argv[2])
SRC = ROOT / "catalog" / "src"
UP = ROOT / "upstream"

CLASS_DEF = re.compile(r"^\s*([A-Z]\w*)\s*(?::\s*\w+\s*)?\{", re.M)
UGEN_USE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\.\s*(?:ar|kr|ir)\b")
ENGINE_NAME = re.compile(r"""\bengine\.name\s*=\s*["']([^"']+)["']""")
SHELL_CALL = re.compile(
    r"""\b(os\.execute|util\.os_capture|io\.popen|norns\.system_cmd|os\.capture)\s*\(\s*(.{0,120})""")
LUA_COMMENT = re.compile(r"--(?!\[\[).*$", re.M)
SC_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
NATIVE_EXT = (".so", ".scx", ".dylib", ".a", ".o")


def classes_in(*dirs):
    found = set()
    for d in dirs:
        for f in Path(d).rglob("*.sc"):
            try:
                found.update(CLASS_DEF.findall(SC_COMMENT.sub("", f.read_text(errors="replace"))))
            except OSError:
                pass
    return found


CORE = classes_in(UP / "supercollider", UP / "norns" / "sc")
SC3 = classes_in(UP / "sc3-plugins") - CORE
MI = classes_in(UP / "mi-UGens") - CORE
BUILTIN_ENGINES = {c[len("Engine_"):] for c in CORE if c.startswith("Engine_")}


def shell_command(arg):
    """First command word of a shell call's literal argument, or a marker."""
    if arg[:1] in "\"'" and arg:
        text = arg[1:].split(arg[0], 1)[0]
    elif arg.startswith("[["):
        text = arg[2:].split("]]", 1)[0]
    else:
        return "<dynamic>"
    words = text.strip().split()
    while words and words[0] in ("sudo", "nohup", "exec", "env"):
        words = words[1:]
    if not words:
        return "<dynamic>"
    w = words[0]
    return Path(w).name if "/" in w and not w.startswith("/home/we") else w


def scan_repo(d):
    r = {"repo": d.name, "engines": set(), "engine_defs": set(), "ugens": Counter(),
         "shell": Counter(), "home_we": 0, "native": [], "lua_files": 0}
    defined = set()
    for f in d.rglob("*"):
        if ".git" in f.parts or not f.is_file():
            continue
        rel = str(f.relative_to(d))
        if f.suffix == ".lua":
            r["lua_files"] += 1
            t = LUA_COMMENT.sub("", f.read_text(errors="replace"))
            r["engines"].update(ENGINE_NAME.findall(t))
            r["home_we"] += t.count("/home/we")
            for fn, arg in SHELL_CALL.findall(t):
                r["shell"][shell_command(arg)] += 1
        elif f.suffix in (".sc", ".scd"):
            t = SC_COMMENT.sub("", f.read_text(errors="replace"))
            defs = CLASS_DEF.findall(t) if f.suffix == ".sc" else []
            defined.update(defs)
            r["engine_defs"].update(c[len("Engine_"):] for c in defs if c.startswith("Engine_"))
            r["ugens"].update(UGEN_USE.findall(t))
    # executables and native libraries, from the full tree listing (incl. not-checked-out blobs)
    tree = d / ".tree.txt"
    if tree.exists():
        for line in tree.read_text(errors="replace").splitlines():
            meta, _, path = line.partition("\t")
            mode = meta.split()[0] if meta else ""
            if path.endswith(NATIVE_EXT):
                r["native"].append(path)
            elif mode == "100755" and not path.endswith((".lua", ".sh", ".py", ".md", ".txt")):
                p = d / path
                kind = ""
                if p.exists():
                    kind = subprocess.run(["file", "-b", str(p)], capture_output=True,
                                          text=True).stdout.strip()
                if not p.exists() or "ELF" in kind or "Mach-O" in kind:
                    r["native"].append(f"{path} [{kind[:60] or 'not checked out'}]")
    ug = {}
    for name, n in r["ugens"].items():
        if name in CORE:
            kind = "core"
        elif name in defined:
            kind = "repo"
        elif name in MI:
            kind = "mi-ugens"
        elif name in SC3:
            kind = "sc3-plugins"
        else:
            kind = "unknown"
        ug[name] = kind
    r["ugen_kinds"] = ug
    r["defined_classes"] = sorted(defined)
    return r


def main():
    repos = [scan_repo(d) for d in sorted(SRC.iterdir()) if d.is_dir()]
    all_engine_defs = defaultdict(list)
    for r in repos:
        for e in r["engine_defs"]:
            all_engine_defs[e].append(r["repo"])
    # classes defined anywhere in the catalog (a script may use another script's UGen classes)
    catalog_classes = defaultdict(set)
    for r in repos:
        for c in r["defined_classes"]:
            catalog_classes[c].add(r["repo"])
    for r in repos:
        eng = {}
        for e in r["engines"]:
            if e in BUILTIN_ENGINES:
                eng[e] = "builtin"
            elif e in r["engine_defs"]:
                eng[e] = "own"
            elif e in all_engine_defs:
                eng[e] = "other-repo:" + ",".join(sorted(all_engine_defs[e]))
            else:
                eng[e] = "missing"
        r["engine_kinds"] = eng
        for name, kind in r["ugen_kinds"].items():
            if kind == "unknown" and name in catalog_classes:
                r["ugen_kinds"][name] = "other-repo"
        reasons = []
        if r["home_we"]:
            reasons.append("path")
        if r["shell"]:
            reasons.append("shell")
        if r["native"]:
            reasons.append("native")
        if any(k in ("sc3-plugins", "mi-ugens") for k in r["ugen_kinds"].values()):
            reasons.append("ugen-plugins")
        if any(k == "unknown" for k in r["ugen_kinds"].values()):
            reasons.append("ugen-unknown")
        if any(k == "missing" for k in r["engine_kinds"].values()):
            reasons.append("engine-missing")
        r["needs"] = reasons
        for k in ("engines", "engine_defs"):
            r[k] = sorted(r[k])
        r["ugens"] = dict(r["ugens"])
        r["shell"] = dict(r["shell"])
    OUT.write_text(json.dumps({"builtin_engines": sorted(BUILTIN_ENGINES), "repos": repos},
                              indent=1, ensure_ascii=False))
    print(f"repos={len(repos)} written {OUT}")


main()
