# SuperCollider 3.14.1 (bundled) against the distribution's 3.13.0: do the engines run?

The owner asked (Gate B decisions) to check that the bundled **SuperCollider 3.14.1 with sc3-plugins** loads and runs every engine
of this repository **and** the engines of the owner's engine list (PolySub, SimplePassThru, PolyPerc, Orgn, TestSine, Eterna),
and to say what differs from the Ubuntu SuperCollider 3.13.0.

## What was run

Two variants, same machine, same norns, same test (`docs/port/packaging/engine-check/engcheck.sh`):

| | sclang / scsynth | sc3-plugins |
|---|---|---|
| **apt** | Ubuntu 24.04 `supercollider-*` **3.13.0** (with Qt) | Ubuntu `sc3-plugins-*` 3.9.1 (repack) |
| **bundled** | **3.14.1** built by `linux/package.sh sc` (no Qt, no IDE, no Supernova, no Link, final prefix `/opt/verdandi/supercollider`) | sc3-plugins at the commit pinned in `macos/setup-deps.sh` (`b80a41b7`), built by the same script |

For each variant: norns boots headless (Xvfb + dummy JACK driver), then for each of the six engines `engine.load(name, callback)`,
a trigger, and a small JACK client (`meter.c`) that reports the **peak of `crone:output_1/2`** for four seconds. After the run
`sclang.log` is searched for `not installed`, `FAILURE IN SERVER`, `ERROR`, `exception`. The two engines of the owner's list
that are not in this repository were cloned from their sources: **Orgn** (`andr-ew/orgn`, `lib/Engine_Orgn.sc`) and **Eterna**
(`etsuko-fm/eterna`, `lib/supercollider/*.sc`; it needs a sample, a generated 1 s sine was loaded with `load_channel_to_buffer`).

## Result

| engine | 3.13.0 + apt sc3-plugins | 3.14.1 + built sc3-plugins | what was triggered |
|---|---|---|---|
| PolyPerc | loads, peak 0.095 | loads, peak 0.091 | `engine.hz(220)` |
| PolySub | loads, peak 0.538 | loads, peak 0.545 | `engine.start(0,220)` |
| TestSine | loads, peak 0.632 | loads, peak 0.633 | `engine.hz(330)` |
| SimplePassThru | loads, peak 0.000015 | loads, peak 0.000015 | nothing (it passes the input, which is silence on the dummy driver: **load test only**) |
| Orgn | loads, peak 0.071 | loads, peak 0.074 | `engine.noteOn(1,220,1,0)` |
| Eterna | loads, peak 0.006 | loads, peak 0.005 | sample load, `voice_channel(0,0)`, `voice_trigger(0)` |

No error line in `sclang.log` in either run (files: `docs/port/packaging/engine-check/result-*.txt`).
The small differences of the peaks are timing (a note is triggered while the meter has already started). **All six engines run on 3.14.1.**

**A mistake found on the way, now fixed.** My first bundled run failed Orgn and Eterna with `UGen 'EnvFollow' not installed` and `UGen 'SVF' not installed`
(file `result-bundled-3.14.1-first-run-no-plugin-binaries.txt`): the sc3-plugins **classes** were installed but not the plug-in **binaries** (on Linux
`cmake --install` puts the `.so` files in `lib/SuperCollider/plugins`, which my script had not copied). `linux/package.sh sc` now installs both and
stops with an error when the binaries are missing. The two engines are exactly the ones that need sc3-plugins (Orgn: Decimator, EnvFollow, Crackle; Eterna: SVF, ESVF), so the check is meaningful.

## What differs from 3.13.0 (plainly)

**Of this package, not of SuperCollider itself (my build flags, the same as the Mac port):**
- **No Qt**: no IDE, no help browser, no Qt GUI classes (`QView` and friends are absent), no WebEngine. norns uses none of them; a script that built a SuperCollider GUI would fail. Not tested: whether any script in the community catalog does. The apt sclang is 238 MB with its dependencies, the bundled one about 18 MB.
- **No Supernova** (the multicore server), **no Ableton Link**, no emacs/vim/gedit editors, no help files. norns runs `scsynth` only.
- sclang and scsynth read their data from `/opt/verdandi/supercollider` (compiled in, not movable) and the plug-ins from there. The apt SuperCollider and its extensions in `/usr/share/SuperCollider` are **not** used by Verdandi's launcher once installed (it puts `/opt/verdandi/supercollider/bin` first on `PATH`), so extensions installed system-wide for the distribution's SuperCollider are not seen; extensions in the norns home (`<norns home>/.local/share/SuperCollider/Extensions`, as on a norns) are.
- **sc3-plugins is a newer one** (the commit of the Mac port) than Ubuntu's 3.9.1 repack: 197 plug-in binaries against 100 in total, SuperCollider's own included (HOA ambisonics UGens, NHHall, QuantityUGens are new). Only one apt plug-in has no counterpart: **UIUGens** (Qt-related). Not every UGen of every sc3-plugins version was compared; only the ones the six engines use were exercised.

**Of SuperCollider 3.14 against 3.13 (from `CHANGELOG.md`, 3.13.1 / 3.14.0 / 3.14.1):**
- *Breaking changes the changelog lists:* `Phasor` no longer ignores the trigger on its first sample; `mod` for negative integer moduli is fixed (`modSeaside` restores the old result); `Splay` and `SplayAz` level compensation changed (the overall level may change); `SetResetFF` is now marked unipolar (`.range(0,1)` results change); `Set.remove` returns the removed item; `Dictionary.trueAt` changed for non-boolean values.
- *UGen initialisation fixes* (EnvGen, TDelay, Trig/Trig1, Delay1/2, Decay/Decay2, LFUGens, TriggerUGens): the **first sample** of these UGens is different. A script or engine that depended on the old first-sample behaviour could sound slightly different at note starts. None of the six engines showed an error or a silent output; I did not compare waveforms sample by sample, so a *tiny* difference at an attack is possible and unmeasured.
- sclang gains `**kwargs` collection; FluCoMa UGens built for 3.13 do not load in 3.14 (not used by these engines).
- Windows/macOS/Linux build changes (Qt 6, boost), tests: not relevant at runtime here.

**Not checked:** engines outside these six (the engines of the community scripts that need other UGens: the Raspberry Pi plug-in bundles are ARM and the launcher already reports them); real audio hardware (the dummy driver was used); a long run; the per-sample comparison above.
