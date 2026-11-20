#!/usr/bin/env python3
"""twins_check.py: does Verdandi ship every SuperCollider library the script twins needs? (docs/port/phase-m29.md, item 4)

twins is updated often. This reads what twins asks for and says plainly when something is not shipped:
  - the installer's `requirements` and `bundled` lists (twins.lua, the line with installer = include("lib/installer/installer"):new{...})
  - every UGen class its engine (lib/engine_twins.sc) calls: Name.ar / Name.kr / Name.ir
and resolves each class with the real sclang, in an empty norns home into which the shipped PortedPlugins pack is seeded (the same copy norns.sh makes); the classes of SuperCollider
itself and of sc3-plugins come with that sclang. A `bundled` library is the script's own (its source and prebuilt files travel inside twins), so it is not asked of Verdandi; it is
checked that the script has an x86_64 file for it.

  twins_check.py --source <twins clone>    the lists are read from that clone (or: --live, a shallow clone of the current twins is made; needs the network)
  twins_check.py --pin <dir>               the lists are read from the pinned copy (names only; the commit they were read from is in <dir>/COMMIT)
  twins_check.py --source <clone> --refresh-pin <dir>   writes the pin from the clone
  --pack <dir>   the PortedPlugins pack (default: build/linux/portedplugins/PortedPlugins)
exit 0: nothing missing; 1: something twins needs is not shipped (the text says what and where it comes from); 2: cannot run; 77: no sclang / no pack / no network (SKIP)
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSES_SCD = os.path.join(REPO, "linux", "tests", "twins_classes.scd")
SEED = os.path.join(REPO, "linux", "portedplugins-seed.sh")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def lists_from_source(src):
    lua = read(os.path.join(src, "twins.lua"))
    m = re.search(r'installer\s*=\s*include\("lib/installer/installer"\)\s*:new\s*\{(.*?)\}\s*$', lua, re.S | re.M)
    line = None
    for ln in lua.splitlines():
        if 'include("lib/installer/installer")' in ln and "requirements" in ln:
            line = ln
            break
    if line is None:
        raise SystemExit("twins_check: cannot find the installer line (requirements = ...) in twins.lua: twins changed its layout, this check has to be updated")
    req = re.search(r"requirements\s*=\s*\{([^}]*)\}", line)
    requirements = re.findall(r'"([A-Za-z0-9_]+)"', req.group(1)) if req else []
    bun = re.search(r"bundled\s*=\s*\{([^}]*)\}", line)
    bundled = re.findall(r"([A-Za-z0-9_]+)\s*=", bun.group(1)) if bun else []
    zipm = re.search(r'zip\s*=\s*"([^"]+)"', line)
    engine = read(os.path.join(src, "lib", "engine_twins.sc"))
    ugens = sorted(set(re.findall(r"\b([A-Z][A-Za-z0-9]*)\.(?:ar|kr|ir)\b", engine)))
    return {"requirements": requirements, "bundled": bundled, "zip": zipm.group(1) if zipm else "", "ugens": ugens}


def lists_from_pin(pin):
    def lines(name):
        p = os.path.join(pin, name)
        return [x.strip() for x in read(p).splitlines() if x.strip()] if os.path.exists(p) else []
    return {"requirements": lines("requirements.txt"), "bundled": lines("bundled.txt"), "zip": (lines("ZIP.txt") or [""])[0], "ugens": lines("ugens.txt")}


def write_pin(pin, lists, commit):
    os.makedirs(pin, exist_ok=True)
    for name, key in (("requirements.txt", "requirements"), ("bundled.txt", "bundled"), ("ugens.txt", "ugens")):
        with open(os.path.join(pin, name), "w") as f:
            f.write("\n".join(lists[key]) + "\n")
    with open(os.path.join(pin, "ZIP.txt"), "w") as f:
        f.write(lists["zip"] + "\n")
    with open(os.path.join(pin, "COMMIT"), "w") as f:
        f.write(commit + "\n")


def resolve_classes(names, pack):
    """Which of the names does sclang know in an empty home with the shipped pack seeded? returns (known set, log text)"""
    sclang = subprocess.run(["sh", "-c", "command -v sclang"], capture_output=True, text=True).stdout.strip()
    if not sclang:
        print("SKIP twins_check: no sclang (supercollider-language)")
        raise SystemExit(77)
    home = tempfile.mkdtemp(prefix="twins-check-")
    seed = subprocess.run([SEED, "seed", pack, home], capture_output=True, text=True)
    if "seeded" not in seed.stdout:
        print("twins_check: the PortedPlugins pack was not seeded into the empty home: " + (seed.stdout + seed.stderr).strip())
        raise SystemExit(2)
    env = dict(os.environ, HOME=home, QT_QPA_PLATFORM="offscreen", QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox")
    try:
        r = subprocess.run([sclang, "-D", CLASSES_SCD] + sorted(names), env=env, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        print("twins_check: sclang did not answer in 180 s")
        raise SystemExit(2)
    out = r.stdout + r.stderr
    known = set(re.findall(r"^CLASS ([A-Za-z0-9_]+) true$", out, re.M))
    return known, out


def main(argv):
    src = pin = refresh = None
    live = False
    pack = os.path.join(REPO, "build", "linux", "portedplugins", "PortedPlugins")
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--source":
            src = argv[i + 1]; i += 2
        elif a == "--pin":
            pin = argv[i + 1]; i += 2
        elif a == "--refresh-pin":
            refresh = argv[i + 1]; i += 2
        elif a == "--pack":
            pack = argv[i + 1]; i += 2
        elif a == "--live":
            live = True; i += 1
        else:
            print(__doc__); return 2
    tmp = None
    commit = ""
    if live:
        tmp = tempfile.mkdtemp(prefix="twins-live-")
        r = subprocess.run(["git", "clone", "-q", "--depth", "1", "https://github.com/danielrigler/twins", os.path.join(tmp, "twins")], capture_output=True, text=True)
        if r.returncode != 0:
            print("SKIP twins_check: the current twins could not be cloned (no network?)")
            return 77
        src = os.path.join(tmp, "twins")
    if src:
        lists = lists_from_source(src)
        commit = subprocess.run(["git", "-C", src, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        what = "the current twins (commit %s)" % (commit[:7] or "unknown")
    elif pin:
        lists = lists_from_pin(pin)
        commit = (read(os.path.join(pin, "COMMIT")).strip() if os.path.exists(os.path.join(pin, "COMMIT")) else "")
        what = "the pinned list of twins (commit %s)" % (commit[:7] or "unknown")
    else:
        print(__doc__); return 2
    if refresh:
        if not src:
            print("twins_check: --refresh-pin needs --source or --live"); return 2
        write_pin(refresh, lists, commit)
        print("twins_check: pin written to %s from commit %s: %d requirements, %d bundled, %d UGens" % (refresh, commit[:7], len(lists["requirements"]), len(lists["bundled"]), len(lists["ugens"])))
    if not os.path.isfile(os.path.join(pack, ".verdandi-stamp")):
        print("SKIP twins_check: no stamped PortedPlugins pack at %s (linux/build.sh, or --pack)" % pack)
        return 77
    bundled = set(lists["bundled"])
    names = set(lists["ugens"]) | set(lists["requirements"])
    to_resolve = sorted(names - bundled)
    known, out = resolve_classes(to_resolve, pack)
    problems = []
    for n in to_resolve:
        if n not in known:
            where = ""
            if n in lists["requirements"] and lists["zip"]:
                where = " (the installer fetches it from %s)" % lists["zip"]
            problems.append("twins needs the SuperCollider library %s%s and nothing Verdandi ships provides it" % (n, where))
    # the installer's two halves for every requirement: the pack must hold the class file AND the plug-in
    for n in lists["requirements"]:
        if n in bundled:
            continue
        cls = os.path.join(pack, "Classes", n + ".sc")
        so = [os.path.join(pack, n + "_scsynth.so"), os.path.join(pack, n + ".so")]
        if n in known and not (os.path.isfile(cls) and any(os.path.isfile(p) for p in so)):
            # known from sclang but not from our pack: SuperCollider or sc3-plugins has the class; the installer still wants a plug-in file of that name
            problems.append("the installer of twins asks for %s (class file and plug-in file named %s.sc and %s_scsynth.so or %s.so) and the PortedPlugins pack does not have those two files" % (n, n, n, n))
    if src:
        for n in sorted(bundled):
            has_sc = os.path.isfile(os.path.join(src, "lib", "ugens", n + ".sc.in"))
            has_so = os.path.isfile(os.path.join(src, "lib", "ugens", "x86_64", n + ".so.in"))
            if not (has_sc and has_so):
                problems.append("twins bundles %s but has no x86_64 file for it (lib/ugens/%s.sc.in and lib/ugens/x86_64/%s.so.in): Verdandi on Linux cannot copy it, the engine falls back to its built-in grains" % (n, n, n))
    print("twins_check: %s: %d requirements (%s), bundled (%s), %d UGen classes in the engine" % (what, len(lists["requirements"]), " ".join(lists["requirements"]), " ".join(sorted(bundled)) or "none", len(lists["ugens"])))
    if pin and src is None:
        pass
    elif pin is None and os.path.isdir(os.path.join(REPO, "linux", "tests", "twins-pin")):
        old = lists_from_pin(os.path.join(REPO, "linux", "tests", "twins-pin"))
        new_names = sorted((names | bundled) - (set(old["ugens"]) | set(old["requirements"]) | set(old["bundled"])))
        if new_names:
            print("twins_check: note: twins now uses libraries that were not in the pinned list: %s (refresh the pin after looking: twins_check.py --live --refresh-pin linux/tests/twins-pin)" % " ".join(new_names))
    if problems:
        print("")
        for p in problems:
            print("twins_check: FAIL: " + p)
        print("twins_check: what to do: build or ship the library for Linux (linux/portedplugins-build.sh / linux/package.sh) and for Windows (windows/ci/build-sc3plugins.sh), or ask the twins author; docs/port/phase-m29.md says where each library comes from")
        return 1
    print("twins_check: ok: every library twins needs is shipped (%d resolved by sclang with the shipped pack)" % len(to_resolve))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
