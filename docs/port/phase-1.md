# Phase 1: headless Linux build and boot (approach, written before code changes)

Gate A decided: option 1, platform folders in this fork (`matron/src/platform/linux/` later;
shared files stay in `platform/macos/` until a separate move commit once Linux works).

## Approach
1. `linux/setup-deps.sh` (Ubuntu 24.04, apt + libmonome 1.4.9 from source + waf 2.1.9 built from
   the GitLab tag, because the bundled waf 2.0.14 imports `imp`, removed in python 3.12, and
   waf.io is not reachable from the sandbox) and `linux/build.sh` (submodules, waf configure
   `--desktop`, build).
2. Build the unmodified upstream desktop path first; fix only what breaks, with the smallest
   change that keeps macOS and the Pi build unchanged (guards, not rewrites).
3. `linux/norns.sh` (headless boot: Xvfb, `jackd -d dummy`, crone, matron) and
   `linux/tests/norns_probe.sh` in the style of `macos/tests/norns_probe.sh`.
4. Run the tests that do not need macOS frameworks; record results and failures below.

Not in scope: SDL desktop layer, skins in the window, packaging (Phases 2-4).
