# princeton and its NamAmp plug-in: findings and plan

Status: **investigation and plan only. No product code was written.** Everything that was built or run is in a scratch directory (appendix A has the commands and the scratch wrapper so the work can be repeated). Date of the findings: 2026-11-08.

## 0. Verdict

- **princeton can work on x86_64.** Its NAM amp needs one SuperCollider plug-in, `NamAmp.so`, which is committed to the script's repository as a **32-bit ARM** binary (Raspberry Pi build). Its source is **not published** (only the binary and a list of the libraries it contains). A plug-in with the same interface, **built for x86_64 against the bundled SuperCollider 3.14.1 headers from NeuralAmpModelerCore, Eigen and nlohmann/json**, builds in about 20 seconds, is about 1.0 MB, loads in the real princeton engine, and its output matches the NAM core's own rendering of the same model to 6.5e-4 (peak difference) on a standard WaveNet capture.
- **It is not a "download".** princeton does not fetch anything: its Lua copies the ARM file from its own checkout (`dust/code/princeton/lib/nam/NamAmp.so`) to `~/Verdandi/.local/share/SuperCollider/Extensions/princeton/NamAmp.so` **at every script load when the two files differ** (`cmp -s`). That has a consequence for any fix (section 4.4): a seeded x86_64 copy is overwritten by the ARM one the first time the script loads.
- **Recommendation:** ship an x86_64 `NamAmp` the way mi-UGens is shipped (own wrapper, pinned dependencies, licences, stamp, seeded before SuperCollider starts), **and** make the script's own install step see it as installed, without editing the user's script folder (a `cmp` / `cp` shim for exactly that case, option A in section 4.4). Generalise the self-healing so that any wrong-architecture plug-in that would stop SuperCollider is moved aside at the start with a plain note, and replaced by Verdandi's x86_64 copy when there is one (section 5). Effort: about 2 to 3 days (a guess, labelled as one).
- **What was not verified:** the sound of the original binary (it cannot run here: no ARM emulation), real amp captures (the test models are the NAM core's examples), the meaning of the second argument of the `namLoad` command and the original's gain staging, long runs on a real sound card. See section 3.5.

## 1. What princeton needs

Read from a fresh clone of the script's repository (single commit `b74d0a7`, "README rewritten in chain order ..."):

| item | finding |
|---|---|
| what it is | a guitar-oriented multi-effect script: input, pedals, an analog-style amp (a small American combo), cabinet and microphone, tape, looper, rack effects, modulation. `princeton.lua` (177 KB), `lib/Engine_Princeton.sc` and about 30 Lua and SuperCollider files |
| the NAM part | **optional**: "NAM mode" plays Neural Amp Modeler captures (`.nam` files) through the amp slot. Without the plug-in the analog amp works |
| the plug-in | `lib/nam/NamAmp.so` (1,030,684 bytes): `ELF 32-bit LSB shared object, ARM, EABI5`, built on Raspbian with GCC 10.2.1, needs glibc 2.29, libstdc++. It exports the SuperCollider plug-in entry points (`api_version`, `server_type`, `load`), registers a UGen `NamAmp` and the plug-in command `namLoad`, and prints `NamAmp: loaded %s (gain %.2f)`, `NamAmp: failed to load %s: %s`, `NamAmp: %d underruns` (the underrun counter suggests that the original runs the model on a worker thread, as a Raspberry Pi needs) |
| the class | `lib/NamAmp.sc`: `NamAmp : UGen { *ar { |in = 0, active = 1| ^this.multiNew('audio', in, active) } }`. sclang finds it because it compiles `dust/code/**/*.sc` |
| the engine | `Engine_Princeton.sc` line 41: `nam_ok` is true when `Platform.userExtensionDir/princeton/NamAmp.so` exists **and is older than the start of sclang**; then it builds the NAM path `NamAmp.ar(in * volume_gain, nam_fade > 0.0001)` with bass, mid and treble EQ and crossfades it against the analog amp. Commands: `nam_load <path>` (sends the plug-in command `/cmd namLoad path 1.0`) and `nam_on`, and the parameters `nam_cal`, `nam_mid`, `nam_mid_freq` |
| the install / detection | `lib/nam.lua` `install()`: if the source file is missing: status "missing"; if `DST` does not exist **or `cmp -s SRC DST` is not true**: `mkdir -p` and `cp SRC DST`, status "restart"; else if `DST` is newer than the start of sclang: "restart"; else "ok". NAM is available only when the status is "ok" and there is at least one `.nam` file. The README says: "On every start princeton checks its NamAmp plugin ... copies it there if it is missing or has changed. After a copy, restart norns once" |
| the models | `.nam` files in `dust/data/princeton/nam/` (created at the first start); one list entry per file; princeton reads `"gear_type"` from the file's metadata to decide whether the capture already contains the cabinet. Captures are the user's to download (the README points to TONE3000); none are shipped |
| other classes | nothing beyond the core class library and the usual UGens: the engine loaded in the headless run below with the bundled SuperCollider and sc3-plugins, and without mi-UGens |
| licences | the **script has no licence file** (the README has credits, no licence statement). `lib/nam/THIRD_PARTY_LICENSES.md` says `NamAmp.so` is "compiled from princeton's own wrapper together with" NeuralAmpModelerCore (MIT, commit `0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842`) and nlohmann/json (MIT); the README adds Eigen (MPL-2.0). The wrapper itself carries no stated licence and its source is not in the repository |

A fork of the script that predates the NAM part exists; it has no plug-in.

## 2. The plug-in's source

- **The wrapper source is not published** (the repository has only the binary and the licence list). A search for a published SuperCollider UGen around NeuralAmpModelerCore found none; the nearest precedent is a SuperCollider port of a TorchScript runner (a different technology), and NAM exists as VST3/AU/LV2 plug-ins and in a hardware-synth engine list, none of which is a UGen.
- **What a replacement has to provide is small and public:** the class and the engine file show the whole interface: `NamAmp.ar(in, active)` with one output, and the plug-in command `namLoad` with a path and a float. The wrapper is a thin layer (about 100 lines, appendix B) over NeuralAmpModelerCore, which does all the work.
- **Dependencies (all header-only or compiled from source, no system libraries):**

| part | version | licence | size |
|---|---|---|---|
| NeuralAmpModelerCore (the NAM runtime: WaveNet A1 and A2, LSTM, convolutional, linear, slimmable) | commit `0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842` (2026-09-18, after v0.6.0), the same commit the original lists | MIT | 488 KB of source, 17 files with `wavenet/` |
| Eigen (matrices) | 5.0.1, the commit pinned by that NAM core (`bc3b39870ecb690a623a3f49149a358b95c5781d`) | MPL-2.0 | header only, 8.3 MB of source, not shipped |
| nlohmann/json | the single header that NeuralAmpModelerCore vendors (`Dependencies/nlohmann/json.hpp`) | MIT | header only |
| SuperCollider plug-in headers | 3.14.1 (the bundled source in `build/package/cache/supercollider`) | GPL-3.0-or-later | not shipped |
| AudioDSPTools (a submodule of the NAM core) | not needed (the build does not use it) | | |

  Needs a C++20 compiler (the NAM core sets `CMAKE_CXX_STANDARD 20`); GCC 13.3 of Ubuntu 24.04 does it.

## 3. What was built and run (scratch, nothing in the repository)

### 3.1 The build

Seventeen NAM core sources plus the scratch wrapper, `g++ -std=c++20 -O3 -fPIC -DNDEBUG -DNAM_SAMPLE_FLOAT` (float samples, as a plug-in for a float audio server wants), baseline x86-64 (no `-march`):

- **time:** 19 seconds on 4 jobs; **size:** 1,206,752 bytes, **1,015,920 bytes stripped** (the ARM original is 1,030,684);
- **links:** libstdc++, libm, libgcc_s, libc; the symbols need **glibc 2.38** (built on Ubuntu 24.04, which is also the package's base: fine for the package, not for older systems);
- exports `api_version`, `server_type`, `load`, as SuperCollider requires; no undefined symbols (`--no-undefined` links).
- A build with `-march=x86-64-v3` (AVX2 and FMA) is 15 to 30 percent faster (below) and would need a cpu check; not needed for the common models.

### 3.2 Rendered offline with the bundled SuperCollider 3.14.1 (`scsynth` NRT, the package build)

A 110 Hz sine at amplitude 0.1 (rms 0.0707) through `NamAmp.ar(in, 1)` after `/cmd namLoad path 1.0`, 48 kHz, 64-sample blocks, compared with the same model rendered by the NAM core alone (no SuperCollider) in float:

| model (the NAM core's example models; real captures were not available) | output rms | peak | max abs difference to the core's own render | rms difference |
|---|---|---|---|---|
| standard WaveNet (A1) | 0.488 | 0.697 | 6.5e-4 | 9.2e-5 |
| A2 | 0.209 | 0.357 | 1.9e-4 | 4.0e-5 |
| LSTM | 0.0054 | 0.0085 | 2.3e-6 | 9.0e-7 |

- No NaN; the first 0.45 s (before the synth starts) is exactly 0; the harmonics at 2x to 5x are 27 to 36 dB below the fundamental for A1 (the model distorts, as an amp does).
- The remaining difference comes from SuperCollider's table-interpolated `SinOsc` against a plain sine in the reference, not from the plug-in.
- `active = 0`: exactly silent. A missing file: one line `NamAmp: failed to load ...: file does not exist` and silence (no crash).
- **CPU** (the NAM core's `process`, load and warm-up included, one thread of a 2.1 GHz server CPU with AVX2 and AVX-512; the baseline build): standard WaveNet 0.55 s for 3 s of audio = **18 % of one core**; A2 8.5 %; LSTM and the small WaveNet about 1 %. With `-march=x86-64-v3`: 16 % and 6.3 %.

### 3.3 The real princeton in a headless norns

`linux/tests/norns_probe.sh` (Xvfb, jackd with the dummy driver) with a scratch norns home that holds the script, two captures in `dust/data/princeton/nam/` and the x86_64 plug-in:

1. **The owner's failure, reproduced** with the original ARM file in `Extensions/princeton/`: the launcher says `SuperCollider plug-in in .../Extensions/princeton: NamAmp.so (32-bit ARM); this machine is x86_64 ... SuperCollider will not start`, `sclang.log` has `dlopen ... wrong ELF class: ELFCLASS32`, and norns shows `SCRIPT ERROR: SUPERCOLLIDER FAIL`.
2. **With the x86_64 plug-in** (and the script's own bundled copy replaced by it, so that its `cmp` finds them equal): the engines are `PolySub, SimplePassThru, PolyPerc, Princeton, TestSine, None`; the script loads; `princeton: NAM available`; `engine.nam_load` and `engine.nam_on` exist; `NamAmp: loaded ...wavenet_a1_standard.nam (gain 1.00, expected sample rate -1, loudness 0.0 dB)` and `... A2.nam (gain 1.00, expected sample rate 48000, loudness -26.4 dB)` are printed by the plug-in. A 110 Hz tone (0.1) fed into the engine's input ports and the output peak read with `jack_peak`: NAM off 0.48, A1 on 1.02, A2 on 0.77, off again 0.62. These peaks show that the NAM path changes the sound and produces signal; they are not calibrated levels (the tone, the amp stage and the crossfades are all in the path).
3. **The finding that decides the design:** with the **x86_64 copy only in the extension folder** and the script's own copy still ARM (the real situation), loading the script ran `cmp` (different), `cp`, and the extension folder then held the **ARM file again** (checked with `file`). The running session is unaffected (the plug-in was already loaded; `princeton: NAM available`), but the next start would stop SuperCollider again, and the script's own status would read "restart" instead of "ok" for as long as the two files differ, so its NAM mode never becomes available.

### 3.4 Where the owner's report and the code differ

The report says the script "downloads" the plug-in. It copies a committed binary. The effect on SuperCollider is the same; the cure differs (no download to block, a file to keep from being overwritten).

### 3.5 What could not be verified here

- The **sound quality** against the original ARM binary: it cannot be run (no ARM emulation here), and no recording of it exists.
- **Real amp captures** (they need an account at the sharing site); only the NAM core's example models were used. Model files up to NAM file version 0.7.0 are accepted by this core.
- The **second argument of `namLoad`** (princeton sends `1.0`; the original prints it as "gain") and whether the original normalises by the model's loudness: the scratch wrapper treats it as an output gain multiplier. princeton's own `nam_cal` (default +1.8 dB) is applied in the engine, so the levels of the two plug-ins may differ by a constant; this must be settled by listening on the owner's machine.
- **Long runs, xruns and many instances** on a real sound card; princeton uses one instance. The scratch wrapper has one global model, no per-instance state, and a minimal retire slot: it is a feasibility harness, not the design.
- Sample rates other than 48 kHz (A1 models do not know their training rate; A2 declares it).
- The rest of princeton (looper, rack effects, mods, display, controls) beyond "the engine builds and the script loads".

## 4. Recommendation: ship NamAmp or not

### 4.1 Shipping is justified

- The scope is one small plug-in plus the same machinery as mi-UGens: a pinned source build in `linux/package.sh`, licences and notices in `DEPS.md` and `/opt/verdandi/licenses/`, a stamped copy (`.verdandi-stamp`, `.verdandi-files`) that the launcher seeds before SuperCollider starts, and the existing tests' pattern (seed cases, headless boot, package install).
- It makes **every** script that wants NAM profiles on this build work, not only princeton. (Other scripts that ship an ARM NAM plug-in under another name are not known; the generalised healing in section 5 covers them by the policy rather than by a table entry.)
- Licence-wise it is clean: our own wrapper (GPL-3.0-or-later like the rest of Verdandi), NeuralAmpModelerCore (MIT) and nlohmann/json (MIT) are compatible and need only their notices; Eigen (MPL-2.0) is compatible, header-only, and its notice and source location go into `DEPS.md`. The wrapper must be **written by us**: the original wrapper is unpublished and unlicensed, so its binary must not be copied or converted; the interface is public in the script's `.sc` files and engine, so a re-implementation of the interface is fine.

### 4.2 If the owner prefers not to ship

Delete the script, or keep it and move the file aside by hand: the CLEAN UP page and the PLUGINS note already do that after one confirmation, and the engine then runs without NAM (the analog amp). Nothing breaks except the NAM mode. The script re-copies the ARM file at its next load, so this would repeat after every load and restart, unless section 5 is built.

### 4.3 What to build (a plan, in the order that keeps tests first)

1. **A wrapper of our own** (`linux/namamp/NamAmp.cpp` or similar): per-instance model state; the model is loaded off the audio thread (an asynchronous plug-in command), swapped in with a retire pool so that nothing is freed on the audio thread; input and output as float; a sample-rate check (resample or refuse with a plain log line when the model's training rate and the server's differ and the model cannot adapt); `active` and the load command as princeton uses them; the gain argument defined and documented after listening to the original. About 200 lines.
2. **`linux/package.sh` stage `namamp`** next to `mi`: clone the NAM core at the pinned commit with its Eigen submodule, build against `build/package/cache/supercollider` (the bundled 3.14.1 headers), strip, stamp (serial, upstream commits, date, Verdandi version) and put it in `/opt/verdandi/namamp/`; licences for the NAM core (MIT), nlohmann/json (MIT), Eigen (MPL-2.0 with its source URL) and the wrapper in `/opt/verdandi/licenses/namamp/`, and the SOURCES.txt and copyright stanza. A `linux/namamp.pin` with the commits and a serial, as for mi-UGens.
3. **Seeding:** `linux/mi-ugens-seed.sh` becomes a general "seed a stamped plug-in" script, driven by a small table: pack name, source folder, target path, condition. For NamAmp: target `~/Verdandi/.local/share/SuperCollider/Extensions/princeton/NamAmp.so` (the exact place princeton and its engine look), condition: the script's folder `dust/code/princeton` exists (so no file appears for people who do not use it) and the target is absent or is a wrong-architecture file; replaced by the same rules as the mi-UGens copy (older stamp, untouched).
4. **Keep the script from overwriting it** (section 4.4).
5. **Tests:** seed cases (as `mi_seed_test.sh`); a wrong-architecture file next to it is replaced; `NamAmp` renders a model and matches the NAM core's own render (a fixture model from the core's example models, MIT, a few KB: the `lstm` and `wavenet` ones are 2 to 4 KB); `active = 0` and a missing file are silent and say so; a headless boot with the princeton engine file (a small fake engine that builds the same SynthDef shape, since the script is not ours to ship) or with the real script when a clone is given (`NORNS_PRINCETON=<dir>`, skipped otherwise, as the Emplaitress test does); the package install test.
6. **Docs:** manual (a short section: NAM in princeton works out of the box, where captures go), KNOWN-ISSUES, HARDWARE-CHECKLIST (listen: A1, A2, an LSTM capture of a real amp, no xruns at the usual period, compare with the Raspberry Pi if available), STATUS, DEPS.

### 4.4 The script overwrites the seeded copy: three ways out

The script's `install()` compares **its own bundled file** with the extension folder's copy and copies on a difference, so the seeded x86_64 file loses at every script load (section 3.3, item 3).

- **A. Make the script's own check pass, without touching the user's files (recommended).** Verdandi already puts `linux/shims` first on the `PATH` of every command that a script runs (the `sudo` and `systemctl` shims). A `cmp` shim and a `cp` shim that act **only** in this exact case (the destination is the seeded target of a stamped Verdandi pack and the source is a wrong-architecture binary of the same name): `cmp -s SRC DST` answers "equal" (exit 0), `cp SRC DST` does nothing and exits 0; every other call goes straight to the real tool. Then the script's status is "ok", NAM is available, and nothing in `dust/` is edited. Cost: two small shims and their tests; risk: a shim that answers "equal" for two different files is a deliberate lie that must be limited to the pack table and said once in `norns.log` (`norns: princeton's NamAmp.so is Verdandi's x86_64 copy`).
- **B. Replace the script's bundled file** `dust/code/princeton/lib/nam/NamAmp.so` with the x86_64 copy (the original moved to `disabled/` with a manifest line, restorable). Simple, and the script's check passes. But it edits a tracked file of a script that maiden updates with git: the next update then fails on a modified file, or restores the ARM file; and the "never touch files outside the extension folders" rule would need an exception. Not recommended; usable as the fallback if A proves fragile.
- **C. Do nothing about the script** and re-seed at every start: SuperCollider starts, NAM works in the running session, but the script says "restart" at every load and reports NAM as unavailable (its status stays "restart" until the files are equal). It works only by accident; not acceptable.

### 4.5 Decisions for the owner

Ship NamAmp (section 4.1) or leave it; A or B for the overwrite (4.4); whether an AVX2 build with a cpu check is wanted (15 to 30 percent less CPU, not needed for the models measured); whether the wrapper's gain argument may be defined by listening on the owner's machine.

## 5. Generalising the self-healing

Today (KNOWN-ISSUES 37): foreign mi-UGens files that are the wrong architecture are moved aside at the start when Verdandi's own pack is intact; the PLUGINS note and CLEAN UP handle everything else after one confirmation. The princeton case shows the general problem: **any** script can leave a wrong-architecture plug-in in an extension folder, and SuperCollider stops at the first one. Proposal (not built):

1. **One policy, two outcomes, at every start, before sclang** (next to the seed and the plug-in check):
   - **a. A Verdandi x86_64 alternative exists** (the pack table: mi-UGens, NamAmp, later others): move the foreign file aside and put the alternative in its place (seed) with the one line and the plain note: *"A script installed a Raspberry Pi plug-in (NamAmp.so). Verdandi's own x86-64 copy is in use."*
   - **b. No alternative, and it would stop SuperCollider** (every wrong-architecture `.so` or `.scx` in the extension folders and the `*_scsynth.so` and `.scx` in `dust/code`: the plug-in check already finds them; a wrong-architecture plug-in can never load, so SuperCollider's start can never succeed with it there): move it aside into `disabled/` with a manifest line (what, from where, when, why, restore command), and say plainly: *"A script installed a Raspberry Pi plug-in (X, for script Y). Moved aside so that SuperCollider can start; Y's own engine that needs it will not work."* Nothing is deleted. The class check (missing classes) then names what is missing, and the script's engine fails the way it does without the plug-in.
   - Anything else (x86-64 files, non-ELF files, Lua libraries, a script's own files, anything outside the two places) is **never** touched.
2. **While norns runs** (a script's install step at its load, like princeton's `cp`): the same detection every few seconds (the scan built for mi-UGens, widened to every plug-in file name); only the note and a CLEAN UP line ("ARM PLUG-INS"), moved after one confirmation. Two facts for that rule: a wrong-architecture file cannot be mapped by sclang (it failed to load), so moving it is safe with respect to sclang; the confirmation stays because the script may be writing the file and because a move changes what the next start does. The next start applies policy 1 again, so nothing needs the confirmation to keep SuperCollider startable.
3. **Scripts that copy at every load** (princeton): the heal runs at every start; the note would repeat. Say it once per file and per day (a small state file in the norns home), and always log the line.
4. **Setting:** `plugin_heal=0` in `audio.conf` / `NORNS_PLUGIN_HEAL=0` turns the whole thing off (the existing `mi_ugens_heal` and `plugin_check` keep their meaning); the PLUGINS note and CLEAN UP stay.
5. **Scope and safety:** the heal acts only inside the user's SuperCollider extension folder and the script folders of `dust/code` (the plug-in check's two places), only on plug-in file names (`.so` and `.scx` in the extension folders; `*_scsynth.so` and `.scx` in `dust/code`), only through `verdandi tidy disable`, never on system folders (those are reported, not moved), and never when the file is not ELF or is the right architecture.
6. **Tests:** the scanner on fake folders (every kind of file in section 5.1), the launcher step (moved with a manifest line, restore through tidy, idempotent, off, nothing moved when the plug-in is the right architecture), the once-per-day note, a headless boot with a wrong-architecture plug-in of an arbitrary name (SuperCollider starts, the note shows, the class check names the missing UGen), and the seed table with the NamAmp case.
7. **Effort:** the policy and the generalised scanner about 1 day on top of the mi-UGens code; with the NamAmp pack and the shims the whole of sections 4 and 5 about 2 to 3 days (a guess, labelled as one).

The risk to weigh: policy 1b moves a plug-in that a script copied on purpose; but that plug-in cannot load on this machine and stops SuperCollider, so it can only make things worse where it stays. The cost of moving it wrongly is one `verdandi tidy restore`.

## Appendix A: how this was reproduced (scratch, all under one temp directory)

```
git clone <the princeton repository> princeton                     # one commit; lib/nam/NamAmp.so is the ARM binary
git clone https://github.com/sdatkinson/NeuralAmpModelerCore core && cd core
git checkout 0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842
git submodule update --init Dependencies/eigen Dependencies/AudioDSPTools
# 17 sources: NAM/*.cpp NAM/wavenet/*.cpp  + the wrapper (appendix B)
g++ -std=c++20 -O3 -fPIC -DNDEBUG -DNAM_SAMPLE_FLOAT -I core -I core/NAM -I core/Dependencies/nlohmann \
    -I core/Dependencies/eigen -I $SC/include/plugin_interface -I $SC/include/common \
    -I $SC/server/plugin_interface -I $SC/common -c <file> -o obj/<name>.o
g++ -shared -o NamAmp.so obj/*.o -Wl,--no-undefined -lstdc++ ; strip --strip-unneeded NamAmp.so
```

- The offline render: `sclang` (the package's no-Qt build in `build/package/cache/sc-build`) with the class library of `build/package/cache/supercollider/SCClassLibrary` and the script's `NamAmp.sc`, `Score.recordNRT` with that build's `scsynth` and `-U` pointing at the plug-in folder; the score is `/d_recv`, `/cmd namLoad <model> 1.0`, `/s_new` at 0.5 s, 4 s at 48 kHz, float WAV; the analysis is numpy.
- The reference: a 20-line program that loads the same model with the NAM core and processes the same sine in 64-frame blocks.
- The headless boot: a scratch norns home (`dust/code/princeton`, `dust/data/princeton/nam/*.nam`, `.local/share/SuperCollider/Extensions/princeton/NamAmp.so`), `linux/tests/norns_probe.sh` with a probe that loads the script, a small JACK sine client connected to the engine's input ports, `engine.nam_load` / `engine.nam_on`, and `linux/tests/jack_peak.c` on the engine's output ports.

## Appendix B: the scratch wrapper (a feasibility harness, **not** the design)

It shows how small the interface is. Known shortcomings: one global model for all instances, a one-slot retire, no sample-rate handling, the second argument taken as an output gain.

```cpp
#include "SC_PlugIn.hpp"
#include "NAM/get_dsp.h"
#include <atomic>
#include <memory>
#include <string>
#include <vector>

static InterfaceTable *ft;
static std::atomic<nam::DSP *> g_new{nullptr};
static std::atomic<nam::DSP *> g_retired{nullptr};
static std::atomic<float> g_gain{1.0f};

struct NamAmp : public SCUnit {
    nam::DSP *model = nullptr;
    std::vector<NAM_SAMPLE> inbuf, outbuf;
    NamAmp() {
        inbuf.assign(4096, 0); outbuf.assign(4096, 0);
        mCalcFunc = make_calc_function<NamAmp, &NamAmp::next>();
        next(1);
    }
    void next(int n) {
        nam::DSP *p = g_new.exchange(nullptr);
        if (p) { nam::DSP *old = model; model = p; if (old) g_retired.exchange(old); }
        const float *src = in(0); float *dst = out(0);
        const bool active = in0(1) > 0.5f;
        if (!model || !active || n > (int)inbuf.size()) { for (int i = 0; i < n; i++) dst[i] = 0.f; return; }
        for (int i = 0; i < n; i++) inbuf[i] = (NAM_SAMPLE)src[i];
        NAM_SAMPLE *ip = inbuf.data(), *op = outbuf.data();
        model->process(&ip, &op, n);
        const float g = g_gain.load();
        for (int i = 0; i < n; i++) dst[i] = (float)op[i] * g;
    }
};
struct LoadData { std::string path; float gain; nam::DSP *model; double sr; };
static bool loadStage2(World *, void *data) {              // not the audio thread
    LoadData *d = (LoadData *)data;
    try { auto m = nam::get_dsp(std::filesystem::path(d->path)); m->Reset(d->sr, 1024); d->model = m.release(); }
    catch (const std::exception &e) { Print("NamAmp: failed to load %s: %s\n", d->path.c_str(), e.what()); d->model = nullptr; }
    return true;
}
static bool loadStage3(World *, void *data) {              // the model goes to the unit
    LoadData *d = (LoadData *)data;
    if (d->model) {
        delete g_retired.exchange(nullptr); g_gain.store(d->gain);
        delete g_new.exchange(d->model);
        Print("NamAmp: loaded %s (gain %.2f)\n", d->path.c_str(), d->gain);
    }
    return true;
}
static bool loadStage4(World *, void *) { return false; }
static void loadCleanup(World *, void *data) { delete (LoadData *)data; }
static void cmdLoad(World *world, void *, struct sc_msg_iter *args, void *replyAddr) {
    LoadData *d = new LoadData; d->path = args->gets(""); d->gain = args->getf(1.0f); d->model = nullptr; d->sr = world->mSampleRate;
    DoAsynchronousCommand(world, replyAddr, "namLoad", d, loadStage2, loadStage3, loadStage4, loadCleanup, 0, nullptr);
}
PluginLoad(NamAmp) {
    ft = inTable;
    registerUnit<NamAmp>(ft, "NamAmp");
    DefinePlugInCmd("namLoad", cmdLoad, nullptr);
}
```

## Sources

- the script's forum thread, which links its repository (the community catalog does not list it): <https://llllllll.co/t/princeton-a-guitar-focused-multi-effect-script-for-norns/74416>
- NeuralAmpModelerCore (MIT): <https://github.com/sdatkinson/NeuralAmpModelerCore>; Eigen (MPL-2.0): <https://gitlab.com/libeigen/eigen>; nlohmann/json (MIT): <https://github.com/nlohmann/json>
- the earlier work on shipped plug-ins and healing: `docs/port/mi-ugens.md`, `docs/port/KNOWN-ISSUES.md` items 37 and 40
