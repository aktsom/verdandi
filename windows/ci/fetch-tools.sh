#!/bin/bash
# windows/ci/fetch-tools.sh: the portable tools that scripts and maiden's installer use, fetched for the zip (nothing is installed on the owner's computer, no administrator rights):
#   MinGit        git for Windows' minimal portable zip (git.exe and what it needs), GPL-2.0: for scripts that `git clone` or update their data, submodules included (nb voices)
#   busybox.exe   busybox-w32 (rmyorston), GPL-2.0: sh, cp, cmp, unzip, wget (https), tar, grep, ls, mkdir -p, ... the POSIX tools norns's Lua and scripts run through os.execute (the sidecar uses busybox sh -c
#                 when busybox.exe is next to norns.exe). curl.exe is Windows' own (Windows 10 1803 and later).
# output (OUT, default ./tools-win): busybox.exe, tools/mingit/..., licenses/..., TOOLS.txt (versions and sha256 of what was fetched). environment: GH_TOKEN (the workflow's token: the API rate limit)
set -eu
OUT="${OUT:-$PWD/tools-win}"
rm -rf "$OUT"
mkdir -p "$OUT/tools" "$OUT/licenses"
T="$(mktemp -d)"
echo "== MinGit"
URL="$(curl -sSf ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} https://api.github.com/repos/git-for-windows/git/releases/latest | python3 -c '
import json,re,sys
r=json.load(sys.stdin)
for a in r["assets"]:
    if re.fullmatch(r"MinGit-[0-9.]+-64-bit\.zip", a["name"]):
        print(a["browser_download_url"]); break
')"
[ -n "$URL" ] || { echo "no MinGit 64-bit zip among the latest release's assets"; exit 1; }
echo "   $URL"
curl -sSfL -o "$T/mingit.zip" "$URL"
mkdir -p "$OUT/tools/mingit"
unzip -q "$T/mingit.zip" -d "$OUT/tools/mingit"
[ -f "$OUT/tools/mingit/cmd/git.exe" ] || { echo "MinGit has no cmd/git.exe"; ls "$OUT/tools/mingit"; exit 1; }
MG_SHA="$(sha256sum "$T/mingit.zip" | cut -d' ' -f1)"
cp "$OUT/tools/mingit/LICENSE.txt" "$OUT/licenses/MinGit-LICENSE.txt" 2> /dev/null || true
echo "== busybox-w32"
ok=0
for f in busybox64u.exe busybox64.exe; do
    if curl -sSfL --retry 3 -o "$T/busybox.exe" "https://frippery.org/files/busybox/$f"; then echo "   $f"; BB_NAME="$f"; ok=1; break; fi
done
[ "$ok" = 1 ] || { echo "busybox-w32 could not be fetched from frippery.org"; exit 1; }
[ "$(head -c 2 "$T/busybox.exe")" = "MZ" ] || { echo "the busybox download is not a Windows program"; exit 1; }
cp "$T/busybox.exe" "$OUT/busybox.exe"
BB_SHA="$(sha256sum "$T/busybox.exe" | cut -d' ' -f1)"
{
    echo "MinGit: $URL"
    echo "  sha256 $MG_SHA"
    echo "busybox-w32: https://frippery.org/files/busybox/$BB_NAME (source: https://github.com/rmyorston/busybox-w32, GPL-2.0)"
    echo "  sha256 $BB_SHA"
    echo "fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/TOOLS.txt"
cat "$OUT/TOOLS.txt"
echo "tools: done, $OUT"
