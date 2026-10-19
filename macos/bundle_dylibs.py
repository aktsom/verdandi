#!/usr/bin/env python3
"""Make an app bundle self-contained: copy every non-system dylib its Mach-O files use
into <libdir>, point all references at @rpath/<name>, give each file a relative rpath to
<libdir>, drop absolute rpaths, and ad-hoc sign everything.

usage: python3 -I bundle_dylibs.py <bundle root> <libdir inside it>
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(sys.argv[1])
LIBDIR = os.path.abspath(sys.argv[2])
SYSTEM = ('/usr/lib/', '/System/')
MACHO_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe'}


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def is_macho(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    with open(path, 'rb') as f:
        return f.read(4) in MACHO_MAGIC


def deps(path):
    """install names a Mach-O file links against (without its own id)"""
    lines = run('otool', '-L', path).splitlines()[1:]
    names = [l.strip().split(' (')[0] for l in lines if l.strip()]
    own_id = run('otool', '-D', path).splitlines()[1:]
    return [n for n in names if not own_id or n != own_id[0].strip()]


def rpaths(path):
    out, lines = [], run('otool', '-l', path).splitlines()
    for i, l in enumerate(lines):
        if l.strip() == 'cmd LC_RPATH':
            out.append(lines[i + 2].split('path ', 1)[1].rsplit(' (offset', 1)[0])
    return out


def resolve(name, origin):
    """real file for an install name as seen from origin (the file that references it)"""
    base = os.path.dirname(origin)
    if name.startswith('@loader_path/') or name.startswith('@executable_path/'):
        return os.path.realpath(os.path.join(base, name.split('/', 1)[1]))
    if name.startswith('@rpath/'):
        leaf = name[len('@rpath/'):]
        for rp in rpaths(origin):
            rp = rp.replace('@loader_path', base).replace('@executable_path', base)
            cand = os.path.join(rp, leaf)
            if os.path.exists(cand):
                return os.path.realpath(cand)
        cand = os.path.join(LIBDIR, os.path.basename(leaf))
        return cand if os.path.exists(cand) else None
    return os.path.realpath(name) if os.path.exists(name) else None


def main():
    os.makedirs(LIBDIR, exist_ok=True)
    files = []
    for d, _, names in os.walk(ROOT):
        for n in names:
            p = os.path.join(d, n)
            if is_macho(p):
                files.append(p)

    # copy dependencies (transitively) into LIBDIR; leaf name = basename of the install name
    queue, seen, origin_of = list(files), set(files), {}
    while queue:
        f = queue.pop()
        for name in deps(f):
            if name.startswith(SYSTEM):
                continue
            leaf = os.path.basename(name)
            dest = os.path.join(LIBDIR, leaf)
            if dest in seen or (dest.startswith(ROOT) and os.path.exists(dest) and dest in files):
                continue
            src = resolve(name, origin_of.get(f, f))
            if src is None:
                if not os.path.exists(dest):
                    print('bundle_dylibs: cannot resolve %s (from %s)' % (name, f), file=sys.stderr)
                continue
            if not src.startswith(ROOT) or src != dest:
                if not os.path.exists(dest):
                    shutil.copy2(src, dest)
                    os.chmod(dest, 0o755)
            origin_of[dest] = src
            seen.add(dest)
            queue.append(dest)
            files.append(dest)

    # rewrite references, ids and rpaths
    for f in sorted(set(files)):
        args = []
        for name in deps(f):
            if not name.startswith(SYSTEM) and not name.startswith('@rpath/' + os.path.basename(name)):
                args += ['-change', name, '@rpath/' + os.path.basename(name)]
            elif name.startswith('@rpath/') and '/' in name[len('@rpath/'):]:
                args += ['-change', name, '@rpath/' + os.path.basename(name)]
        own_id = run('otool', '-D', f).splitlines()[1:]
        if own_id and not own_id[0].strip().startswith('@rpath/'):
            args += ['-id', '@rpath/' + os.path.basename(f)]
        for rp in rpaths(f):
            if not rp.startswith('@'):
                args += ['-delete_rpath', rp]
        want = '@loader_path/' + os.path.relpath(LIBDIR, os.path.dirname(f))
        if want not in rpaths(f):
            args += ['-add_rpath', want]
        if args:
            # install_name_tool refuses some combinations in one call on older toolchains; go stepwise
            run('install_name_tool', *args, f)

    for f in sorted(set(files), key=lambda p: -p.count('/')):
        run('codesign', '--force', '--sign', '-', f)
    print('bundle_dylibs: %d files, %d libraries in %s' % (len(set(files)), len(os.listdir(LIBDIR)), LIBDIR))


main()
