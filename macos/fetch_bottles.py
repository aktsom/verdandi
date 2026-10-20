#!/usr/bin/env python3
"""Homebrew's bottles of the packages norns.app bundles, built for the oldest macOS the app
supports (macos/MACOS_MIN).

homebrew installs the bottles of the running macOS, and those need that macOS (a tahoe
bottle says minos 26). norns compiles against the installed ones and make-app.sh bundles
the same packages built for the oldest macOS, fetched here from homebrew's public API
(formulae.brew.sh, ghcr.io), checked against homebrew's sha256 and unpacked into
<out>/<formula>/<version>/ (libraries and programs only). their runtime dependencies come
along.

usage: python3 -I fetch_bottles.py <out dir> [formula ...]
       python3 -I fetch_bottles.py --where <out dir>   (the folder for this macOS, printed)
"""
import hashlib
import json
import os
import shutil
import sys
import tarfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
# what the app bundles from homebrew: libraries of norns, crone, SuperCollider and the
# sc3-plugins, jackd and its drivers, SDL3, the GNU userland (macos/make-app.sh)
TOP = ['jack', 'liblo', 'libsndfile', 'cairo', 'sdl2-compat', 'sdl3', 'fftw', 'readline', 'yaml-cpp',
       'boost', 'libsamplerate', 'coreutils', 'findutils', 'gnu-sed', 'grep']
# built from source by setup-deps.sh (into <out>/<tag>/<formula>/<version>-source): their
# bottle needs a newer macOS than its tag says (jack's: 15.7). their dependencies are fetched
SOURCE = {'jack'}
TAGS = {'13': 'arm64_ventura', '14': 'arm64_sonoma', '15': 'arm64_sequoia', '26': 'arm64_tahoe'}


def tag():
    with open(os.path.join(HERE, 'MACOS_MIN')) as f:
        major = f.read().strip().split('.')[0]
    return TAGS[major]


def formula(name, cache={}):
    if name not in cache:
        with urllib.request.urlopen('https://formulae.brew.sh/api/formula/%s.json' % name) as r:
            cache[name] = json.load(r)
    return cache[name]


def closure(names):
    seen, order = set(), []
    def walk(n):
        if n in seen:
            return
        seen.add(n)
        for d in formula(n).get('dependencies', []):
            walk(d)
        order.append(n)
    for n in names:
        walk(n)
    return order


def version(f):
    v = f['versions']['stable']
    return v + ('_%d' % f['revision'] if f.get('revision') else '')


def fetch(name, out, t):
    f = formula(name)
    files = f['bottle']['stable']['files']
    entry = files.get(t) or files.get('all')
    if entry is None:
        raise SystemExit('fetch_bottles: %s has no %s bottle (%s)' % (name, t, ', '.join(files)))
    dest = os.path.join(out, name, version(f))
    if os.path.isdir(dest):
        return dest, False
    req = urllib.request.Request(entry['url'], headers={'Authorization': 'Bearer QQ=='})
    tmp = os.path.join(out, '.%s.tar.gz' % name)
    h = hashlib.sha256()
    with urllib.request.urlopen(req) as r, open(tmp, 'wb') as w:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            h.update(b)
            w.write(b)
    if h.hexdigest() != entry['sha256']:
        os.remove(tmp)
        raise SystemExit('fetch_bottles: %s: sha256 mismatch' % name)
    # the bottle is <name>/<version>/...
    with tarfile.open(tmp) as tf:
        tf.extractall(out, filter='tar')
    os.remove(tmp)
    if not os.path.isdir(dest):
        raise SystemExit('fetch_bottles: %s: no %s in the bottle' % (name, dest))
    return dest, True


LICENSE_NAMES = ('copying', 'license', 'licence', 'copyright', 'notice', 'lgpl', 'gpl', 'unlicense')


def is_license(name):
    return name.lower().startswith(LICENSE_NAMES)


def prune(dest):
    """only what make-app.sh bundles: dylibs, programs (headers, docs, static libraries and
    the many small files with them would only take room: on exFAT a file takes 1 MB)"""
    for sub in ('include', 'share', 'etc', 'var', 'Frameworks'):
        shutil.rmtree(os.path.join(dest, sub), ignore_errors=True)
    # of the files at the top only the licenses (make-app.sh bundles them): AUTHORS, README,
    # ChangeLog ... name people who have nothing to do with this
    for f in os.listdir(dest):
        p = os.path.join(dest, f)
        if os.path.isfile(p) and not is_license(f):
            os.remove(p)
    lib = os.path.join(dest, 'lib')
    for d, dirs, files in os.walk(lib, topdown=True):
        for x in ('cmake', 'pkgconfig', 'python3', 'girepository-1.0', 'gio', 'glib-2.0'):
            if x in dirs:
                shutil.rmtree(os.path.join(d, x))
                dirs.remove(x)
        for f in files:
            if f.endswith(('.a', '.la', '.cmake', '.pc', '.py')):
                os.remove(os.path.join(d, f))


def main():
    if sys.argv[1] == '--where':
        print(os.path.join(os.path.abspath(sys.argv[2]), tag()))
        return
    out = os.path.abspath(sys.argv[1])
    names = sys.argv[2:] or TOP
    t = tag()
    out = os.path.join(out, t)
    os.makedirs(out, exist_ok=True)
    for n in closure(names):
        if n in SOURCE:
            print('  %-14s built from source (setup-deps.sh)' % n)
            # a bottle of it fetched before would be bundled in its place
            for v in os.listdir(os.path.join(out, n)) if os.path.isdir(os.path.join(out, n)) else []:
                if not v.endswith('-source'):
                    shutil.rmtree(os.path.join(out, n, v))
            continue
        dest, new = fetch(n, out, t)
        prune(dest)
        print('  %-14s %s%s' % (n, os.path.basename(dest), '' if new else ' (had it)'))
        # an older version next to it: gone, make-app.sh takes the one there is
        for v in os.listdir(os.path.join(out, n)):
            if v != os.path.basename(dest):
                shutil.rmtree(os.path.join(out, n, v))
    print('fetch_bottles: %s in %s' % (t, out))


main()
