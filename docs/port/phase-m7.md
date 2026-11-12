# Phase M7: SuperCollider plug-in packs for Windows (sc3-plugins, mi-UGens, NamAmp)

Status: **built in CI and tested on Linux for what can be; the first CI run decides what compiles.** The results (which parts compiled, zip growth) are filled in section 6 after the first run.

## 1. Why
A script whose engine uses a UGen that the Windows build lacks (owner test of 0.7.0: engine Autumn needs `Decimator`) cannot start. On Linux and on the device these UGens come with the system packages / the norns image. On Windows nothing provides them, so the build ships them.

## 2. What is shipped (owner decision)
- **The whole sc3-plugins collection** (https://github.com/supercollider/sc3-plugins, GPL-2.0-or-later; a few directories carry other free licences, their files are copied to `licenses\sc3-plugins\`), built for Windows x86-64 with MSVC against the headers of SuperCollider 3.14.1. Every plug-in directory is built on its own (`ninja -k 0`), so a directory that does not compile never blocks the others. What builds ships; what does not is listed in `extensions-seed\BUILD-REPORT.txt` and in section 6 with the first error and what it would need (an extra library, a POSIX-only call, ...).
- **mi-UGens** (https://github.com/v7b1/mi-UGens, MIT code of Emilie Gillet and v7b1's GPL-3.0-compatible parts; its licence files are copied), built the same way. (A Windows release zip exists upstream, but some releases carry empty `Classes` folders; building ourselves gives a matching ABI and classes.)
- **NamAmp**: **not built yet.** I could not identify the repository that defines the NamAmp UGen (a search finds the Neural Amp Modeler project and VST3 plug-ins, no SuperCollider UGen). The job builds it as soon as the CI variable `NAMAMP_URL` (Settings > Secrets and variables > Actions > Variables) names the git URL. It also needs: the licence of that code, and whether it needs the NAM core library or a model file (`.nam`) shipped.

## 3. How it gets to the user (the M6 seed mechanism, unchanged)
`windows/ci/build-sc3plugins.sh` (job `plugins`, not blocking) writes `seed/<pack>/` with `plugins\*.scx` and the class files. `assemble-m1.sh` copies each pack that has at least one `.scx` to `extensions-seed\<pack>`; the launcher copies it to `<home>\extensions\<pack>` at the next start when the folder is not there yet, and never overwrites (so a user's own newer copy wins). The plug-in heal of M6 keeps non-x64 files out. Licence texts go to `licenses\<pack>\`; `SOURCE-OFFER.txt` of the zip names each repository and the exact commit (the `SOURCE-REVISION.txt` of the pack) as the written offer of the corresponding source.

## 4. The start-up check and the failed engine
- `lua/core/sc_class_check.lua` (read only, reads the end of `logs\sclang.log`) now also runs on Windows (extensions folder `<home>\extensions`) and reads `Class Decimator not found` as well as the quoted form. At start-up norns prints each finding and ONE line naming all missing classes: `SuperCollider classes missing: Decimator (sc3-plugins or another extension), ...; engines that use them will not start`.
- `lua/core/engine_fail.lua` (owner request 2): while a script waits for its engine the log is read from where it was at the start of the load; when sclang prints the error trace of `Engine_<name>:alloc` the load stops within a second, the log gets `engine Autumn failed: class Decimator is missing; this needs sc3-plugins`, the norns screen (and so the window) shows the same in five short lines until a key is pressed, and the next script loads normally. Test with a fake failing engine: `linux/tests/engine_fail_test.lua`.

## 5. Effort, risks, what is needed from the owner
- Effort after the first CI report: small if most of sc3-plugins compiles (the packs are just copied); for each directory that fails, one fix or one entry on the list of exclusions with the reason. Parts that typically need more: those using POSIX-only headers or large external libraries (for example the ones with `fftw`, `libsamplerate`, `libusb`); each is judged from the CI log, not guessed.
- Zip size: see section 6 (measured by the job, "all packs zipped").
- Licence obligations: the notices and source offers are in the zip as above. GPL-2.0-or-later code combined in one folder with GPL-3.0 Verdandi is compatible (it stays a separate program loaded by scsynth).
- Needed from the owner: (a) the git URL of NamAmp and its licence (set `NAMAMP_URL`), (b) after the first run, a look at section 6 to say whether any not-built part matters to the scripts in use, (c) on a Windows PC: install a script that needs Decimator (for example the one whose engine Autumn failed) and send `logs\sclang.log` and `norns.log`.

## 6. Results of the first CI run
(filled in after the run: built / failed per plug-in directory, size of the zip before and after)
