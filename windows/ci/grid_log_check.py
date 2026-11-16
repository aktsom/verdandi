#!/usr/bin/env python3
"""windows/ci/grid_log_check.py LOG [--dead]: reads what a fake grid or arc of the CI was sent (<home>/fakedev-*.log, one line per message: "<ms> leds lit=N bytes=B", "connected", "closed").
   passes when the device was lit at some point (the script or the mod really drew) and its LAST message is an "all off" (lit=0): nothing lit it again afterwards. --dead: the device does not answer (a busy port), nothing is demanded of it.
   prints one line of what it saw. stdlib only."""
import sys

path = sys.argv[1]
dead = "--dead" in sys.argv[2:]
try:
    lines = [l.split() for l in open(path, encoding="utf-8", errors="replace").read().splitlines() if l.strip()]
except OSError as e:
    print("NOT FOUND: %s: %s" % (path, e)); sys.exit(1)
leds = [(int(l[0]), int(l[2].split("=")[1])) for l in lines if len(l) >= 3 and l[1] == "leds"]
closed = [int(l[0]) for l in lines if len(l) >= 2 and l[1] == "closed"]
lit_n = sum(1 for _, n in leds if n > 0)
if dead:
    print("found: %s: %d messages (a device that did not answer: nothing demanded)" % (path, len(leds))); sys.exit(0)
if not leds or lit_n == 0:
    print("NOT FOUND: %s was never lit (%d messages): the check would prove nothing" % (path, len(leds))); sys.exit(1)
last_t, last_n = leds[-1]
last_lit_t = max(t for t, n in leds if n > 0)
if last_n != 0:
    print("NOT FOUND: %s: the LAST message left %d LEDs lit (%d messages, %d of them lit; the port %s closed)" % (path, last_n, len(leds), lit_n, "was" if closed else "was not")); sys.exit(1)
print("found: %s: lit in %d of %d messages, the last message (%d ms after the last lit one) is all off%s" % (path, lit_n, len(leds), last_t - last_lit_t, "; the port was closed after it" if closed and closed[-1] >= last_t else ""))
sys.exit(0)
