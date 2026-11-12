#!/bin/bash
# the CI probe of the Windows build (windows/ci/maiden_probe.py) against the Linux stack, so that the probe itself is tested: the real maiden and ws-wrapper, two fake consoles (a python program that answers like
# matron and sclang would). maiden answers, an accented, spaced script is installed from a zip over HTTP, the consoles answer, a page from another site gets no console.
# SKIPPED (not passed) when maiden or ws-wrapper is not built. ports 5000, 5555, 5556 must be free.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_HOME="${NORNS_HOME:-$(dirname "$REPO")}"
MD="$NORNS_HOME/maiden"; WSW="$REPO/build/ws-wrapper/ws-wrapper"
[ -x "$MD/maiden" ] && [ -x "$WSW" ] || { echo "SKIP: maiden or ws-wrapper is not built"; exit 0; }
for p in 5000 5555 5556; do ss -ltn 2> /dev/null | grep -q ":$p " && { echo "SKIP: port $p is in use"; exit 0; }; done
T="$(mktemp -d)"; PIDS=""
trap 'for p in $PIDS; do kill $p 2> /dev/null; done; wait 2> /dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/dust/code" "$T/dust/data/sources" "$T/dust/data/catalogs" "$T/doc"
cat > "$T/fake.py" <<'PY'
import os, sys
while True:
    d = os.read(0, 4096)
    if not d: break
    if b"REPL_" in d: print("REPL_42", flush=True)
    elif b"postln" in d: print("-> 42", flush=True)
PY
O="http://127.0.0.1:5000,http://localhost:5000"
for port in 5555 5556; do
    WS_WRAPPER_ALLOWED_ORIGINS="$O" "$WSW" "ws://127.0.0.1:$port" python3 -u "$T/fake.py" < /dev/null > "$T/w$port.log" 2>&1 & PIDS="$PIDS $!"
done
(cd "$MD" && HOME="$T" exec ./maiden server --host 127.0.0.1 --port 5000 --app ./app/build --data "$T/dust" --doc "$T/doc" --config "$MD/maiden.yaml" < /dev/null > "$T/m.log" 2>&1) & PIDS="$PIDS $!"
sleep 3
timeout 150 python3 -I "$HERE/../../windows/ci/maiden_probe.py" "$T" "$T/out.txt"
cat "$T/out.txt" | cut -c1-150
FAILS=$(grep -c " FAIL " "$T/out.txt")
OKS=$(grep -c " ok " "$T/out.txt")
[ "$FAILS" = 0 ] && [ "$OKS" -ge 7 ] && { echo "maiden probe: all ok"; exit 0; }
echo "maiden probe: $FAILS failures, $OKS ok"; exit 1
