# Scratch harness for docs/port/multi-instance.md

Not part of the product and not run by `run_all.sh`. The scripts were written and run in a scratch folder (`/tmp/claude-0/multi`, paths are inside the scripts), outside the repository; they change no repository file. To rerun they need that folder (or edited paths), the built `build/norns/norns`, jackd, sclang, Xvfb and root (namespaces).

- `inst.sh N MODE`: one headless instance. MODE `shared` (one JACK server, port flags only), `jack` (its own JACK server name, port flags), `sandbox` (own network + mount namespace, default ports).
- `measure.py N MODE`: starts N instances (`SEQUENTIAL=1`: each when the previous is ready), waits for readiness, reports start time, idle CPU and PSS over 20 s, bound ports, JACK clients, clash lines in the logs. `runall.sh N MODE` writes `out-MODE-N.txt`.
- `lo_up.py`: brings the loopback interface up inside a new network namespace (no `ip` tool here).
- Results: `shared-2.txt`, `jack-2.txt`, `jack-4b.txt`, `sandbox-1.txt`, `sandbox-2.txt`, `sandbox-4.txt`, `sandbox-1-per-process.txt` (the SuperCollider error traces were filtered out of these copies).
