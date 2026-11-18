# M23: is the known-failures list "old failures only"? (a check, no program change, no release)

Date of the runs: 2026-11-18. After M22 the Linux test job is green on all six shards only because 35 tests are on `linux/tests/known-failures.txt` (36 failing runs: the auto-connect entry covers two cases). Only one of them (the list code font test) had been shown to fail on the old code. This note shows the rest by a run.

## Method

1. Two scratch branches on the fork (never `main`, no release, no tag):
   - `scratch-baseline-736123b`: the program code **exactly as at 736123b** (before M22), with only the test side taken from head: `linux/tests/` (all test scripts, `run_all.sh`, `known-failures.txt`) and `.github/workflows/linux-tests.yml` (six shards). Checked by diff: outside the test side the tree is identical to 736123b (`git diff 736123b <scratch> -- . (minus linux/tests, the one workflow, docs, STATUS.md)` is empty). Against head the same tree differs in 19 files, all of M22's Windows work (`windows/…` and the Windows workflow); nothing under `matron/`, `crone/`, `lua/`, `sc/`, `macos/`, `linux/*.sh` differs between 736123b and head.
   - `scratch-head-compare`: head with the same workflow, to compare the same lines on both.
   - Both carried one extra change in `run_all.sh`: for each known failure it prints one line `SIG <name> :: <first failing line> :: <last line>`, and `PASSES NOW:` for a listed test that passed. That change is not on `linux-port`.
2. The workflow on the scratch branches runs on pushes to those branches only (`on.push.branches`), the six test shards only (`lua`, `native`, `windows-0`, `windows-1`, `heavy-0`, `heavy-1`): no Windows build job, no release step, no publish. Checked before pushing by reading the file, and after pushing by the runs: each run had exactly six jobs named `tests (...)`. The Windows workflows (`windows-m0`, `windows-m1`) trigger only on `linux-port`/`windows-port`.
3. Each run was complete on the first try: **0 reruns** of the six shards (runs 44338295424 old, 44338301480 head).

## Results (36 failing runs, 35 list entries)

- **34 entries FAIL ON OLD**, with the same first failing line as on head.
- **1 entry PASSES ON OLD**: `midi:the virtual MIDI device sends through JACK MIDI`. It passed in the old-code run and failed in the head run ("a client that is not connected must get nothing"). Details below.
- FAILS ON OLD DIFFERENTLY: none (the first failing line and last line are the same on old and head for all 34).
- SKIPPED / NOT RUN on both runs (not counted as confirmed, none of them is on the list): c:gif and objc tests, clock PipeWire, ALSA sequencer end to end, JACK MIDI out stress, namamp princeton boot, scsynth bridge, PortAudio backend on Linux, mi-UGens heal and Emplaitress, namamp offline render, clean-root build and install.
- Failing on old, **not** on the list: 6 tests, all for M22 features that do not exist in the old code (UTF-8 manifest folders, assembling the two flavours, busy console ports, console port choice, update-and-run, publishing a build). Expected on old code, not a flaw of the list.
- Failing on head but **not** on the list: none (all six head shards: 0 unexpected failures). So the list is not hiding a flaky test beyond the one below.

The reason in each list line is the first failing line that the run printed; where the cause is not known the line says "reason not known". Several earlier guesses in the list (a "timing count on a loaded runner", "a different cairo or freetype", "the clone from GitHub") were not confirmed by this run and are no longer stated as reasons.

## The one that passed on old code

- Program code between 736123b and head is identical for everything this test touches (`git diff 736123b HEAD` over `matron/`, `crone/`, `lua/`, `sc/`, `macos/`, `linux/*.sh` is empty), and both runs used the same test. So no M22 change can have broken it; the result differs run to run.
- A repeat of just this test six times on each scratch branch (a second round of runs) did not finish: both jobs reached the 4-hour job limit (the install step alone took 1.5 hours on one runner) and were cancelled with no round printed. Not counted as a result.
- A local run on head, in this build environment, passes (`PASS ... it is on known-failures and passes now`).
- Severity: low. It is a test of the JACK MIDI output port when a listening client is not connected; nothing in M22 touches it. Judged intermittent in CI, not a regression, but not proven by repeats. Smallest suggested fix: none to the program; if it stays intermittent, give the test a retry or a longer wait for the port, and take it off the list when a few CI runs in a row pass. It stays on the list for now.

## Cleanup

Both scratch branches were deleted locally. Deleting them on the fork from this environment failed (the connection to GitHub was cut on every `git push --delete` attempt), so they may still exist there: `scratch-baseline-736123b` and `scratch-head-compare`. They hold only old code with test files; nothing on them runs unless pushed to again. The owner can delete them in the GitHub branch list.
