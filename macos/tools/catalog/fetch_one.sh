#!/bin/bash
# fetch_one.sh <url> <destroot>: shallow, blob-less clone into <destroot>/<owner>__<repo>;
# only sources + executables are checked out (no audio). Safe on exFAT (no symlinks, no mode bits).
url="${1%/}"; url="${url%.git}"; root="$2"
name="$(basename "$(dirname "$url")")__$(basename "$url")"; d="$root/$name"
[ -f "$d/.tree.txt" ] && exit 0
G="git -c core.symlinks=false -c core.fileMode=false"
GIT_TERMINAL_PROMPT=0 $G clone -q --depth 1 --filter=blob:none --no-checkout "$url" "$d" 2>/dev/null || { echo "FAIL $url"; exit 0; }
git -C "$d" config core.symlinks false; git -C "$d" config core.fileMode false
{ printf '%s\n' '*.lua' '*.sc' '*.scd' '*.sh' '*.py' '*.go' 'Makefile' '*.c' '*.cpp' '*.h'
  git -C "$d" ls-tree -r -l HEAD | awk '$1=="100755"{sub(/^[^\t]*\t/,""); print "/"$0}'; } > "$d/.sparse"
git -C "$d" sparse-checkout set --no-cone --stdin < "$d/.sparse" 2>/dev/null
GIT_TERMINAL_PROMPT=0 git -C "$d" checkout -q 2>/dev/null || echo "COFAIL $url"
git -C "$d" ls-tree -r -l HEAD > "$d/.tree.txt"
