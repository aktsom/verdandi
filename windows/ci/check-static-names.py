#!/usr/bin/env python3
"""windows/ci/check-static-names.py ZIP EXPECTED_ZIP_NAME EXPECTED_FOLDER (M22): the download has the static name, and the zip holds exactly one top-level folder with the fixed name (no version in it), with
VERSION.txt and BUILD.txt in it. so an exclusion in Windows Defender for the folder keeps working for every build. exit 0 = ok. a plain line says what was found."""
import os, sys, zipfile

def main():
    path, want_zip, want_dir = sys.argv[1:4]
    bad = 0
    if os.path.basename(path) != want_zip:
        print("NOT FOUND: the zip is called %r, the static name is %r" % (os.path.basename(path), want_zip)); bad = 1
    else:
        print("found: the zip has the static name %s" % want_zip)
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    tops = sorted({n.split("/")[0] for n in names if n.strip("/")})
    if tops != [want_dir]:
        print("NOT FOUND: the zip holds %r at the top, wanted exactly [%r]" % (tops, want_dir)); bad = 1
    else:
        print("found: the zip holds exactly one folder, %s (no version in its name)" % want_dir)
    for f in ("Verdandi.exe", "BUILD.txt", "VERSION.txt", "norns.exe"):
        if want_dir + "/" + f not in names:
            print("NOT FOUND: %s/%s in the zip" % (want_dir, f)); bad = 1
    print("found: Verdandi.exe, norns.exe, BUILD.txt and VERSION.txt are in the folder" if not bad else "")
    return bad

sys.exit(main())
