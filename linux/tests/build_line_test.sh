#!/bin/bash
# the version line of an installed Verdandi (docs/port/phase-m36.md): /opt/verdandi/BUILD.txt has "<version> <hash>" as its first line (the same as the Windows BUILD.txt); linux/norns.sh gives that line to the program
# (VERDANDI_BUILD: the home page of the norns window) and says it as the first line of its own output (the launcher log). a checkout has no BUILD.txt: nothing is set, nothing is said (as before).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
mkdir -p "$T/tree" "$T/home" "$T/bin"
ln -s "$REPO/linux" "$T/tree/linux"
for t in jack_lsp pw-cli pw-jack wpctl; do printf '#!/bin/sh\nexit 1\n' > "$T/bin/$t"; chmod +x "$T/bin/$t"; done
run() { env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T" NORNS_HOME="$T/home" NORNS_DECIDE_ONLY=1 NORNS_INSTALLED="${INST:-1}" "$@" "$T/tree/linux/norns.sh" 2>&1; }
printf '0.10.21 4c82066\npackage 0.10.21-57\ncommit x\n' > "$T/tree/BUILD.txt"
out="$(run)"
ck "with BUILD.txt the program is given the first line as its version line" "printf '%s\n' \"$out\" | grep -qx 'DECIDE-BUILD 0.10.21 4c82066'"
rm "$T/tree/BUILD.txt"
out="$(run)"
ck "without BUILD.txt (a checkout) there is no version line" "printf '%s\n' \"$out\" | grep -qx 'DECIDE-BUILD '"
printf '0.10.21 4c82066\n' > "$T/tree/BUILD.txt"
out="$(VERDANDI_BUILD='mine 1' run env VERDANDI_BUILD='mine 1')"
ck "a VERDANDI_BUILD that is already set is kept" "printf '%s\n' \"$out\" | grep -qx 'DECIDE-BUILD mine 1'"
# the first line of the output of a real start (no decide-only): norns.sh stops soon after at the missing program, but the line is first
out="$(env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T" NORNS_HOME="$T/home" NORNS_INSTALLED=1 NORNS_HAVE_TTY=1 timeout 20 "$T/tree/linux/norns.sh" 2>&1 | head -n 40)"
ck "the output of a start says 'norns.sh: build 0.10.21 4c82066' once" "[ \$(printf '%s\n' \"\$out\" | grep -cx 'norns.sh: build 0.10.21 4c82066') = 1 ]"
[ $fails -eq 0 ] && echo "build_line_test: all passed"
exit $fails
