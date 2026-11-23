# M35 part B: a one-click Linux install (PLAN ONLY, nothing built, nothing published)

Base 985caf9. Everything below that says "measured" was run in this container (4 cores, Ubuntu 24.04, no sound card, no desktop); "estimate" is a guess; "not tested" needs the owner's laptop. The .deb already exists (`linux/package.sh`, Gate B, `docs/port/packaging.md`), is tested in a clean Ubuntu 24.04 root (`linux/tests/package_test.sh`) and is not built or published by any CI job today. This plan is about making it the thing the owner clicks.

## B1. What the .deb holds and needs

Measured with `linux/package.sh all` at this commit (version `0.1~git20261122.55.985caf98`): **16.3 MB** file, **65 MB** installed.

Holds, under `/opt/verdandi` (root-owned, read-only for the user): norns (matron/crone/softcut build), `lua/`, `sc/`, `doc/`, `resources/` (the fonts), libmonome 1.4.9 with the pty patch, **SuperCollider 3.14.1 without Qt** (sclang, scsynth) with **sc3-plugins**, the **mi-UGens** pack (MiPlaits, MiRings, MiBeads ... 13 plug-ins), the **PortedPlugins** pack (twins' libraries), **NamAmp**, **maiden** (built at package time, nothing is built on the user's machine), the launcher `linux/norns.sh`, the manual, the licence texts; outside `/opt`: `/usr/bin/verdandi`, the menu entry (`verdandi.desktop`), the icon, a udev rule for monome grids and arcs (`uaccess`, no group to join). Everything the checkout run needs is in it; the checkout's extras (the test scripts) are not.

Needs from apt (`Depends`, measured): the libraries `dpkg-shlibdeps` finds (libasound2t64, libc6 >= 2.38, libcairo2, libnng1, liblo7, libsdl2, libavahi-compat-libdnssd1 ...), `pipewire-jack | jackd2`, `zenity | xdg-desktop-portal` (file picker), `xdg-utils`. `Recommends: curl, unzip` (scripts such as mx.samples run them).
- **One change for a real click:** GDebi and the Software Manager install `Depends` but do not always install `Recommends`. Move `curl` and `unzip` to `Depends` (a few hundred KB; both are on almost every Mint anyway).
- What could still need a command, none of it found by a test: (a) a Mint that runs PulseAudio without PipeWire: then `pipewire-jack` is pulled in but there is no PipeWire daemon and the launcher says "no JACK server answers" (the owner's laptop has PipeWire; not tested on a plain Mint install); (b) a script that downloads something and needs a tool not in the list; (c) a monome device whose USB ids the udev rule does not know (rule not verified against hardware). Nothing needs `sudo` after the install, no group, no `setup-deps.sh`.

## B2. Which Ubuntu base for Linux Mint

The owner can tell me with: `cat /etc/os-release` (Mint 22.x shows `UBUNTU_CODENAME=noble`; Mint 21.x shows `jammy`; LMDE shows Debian).
- **Mint 22.x = Ubuntu 24.04 (noble): the package as built today works** (not tested on Mint itself).
- **One package cannot serve 22.04 (Mint 21) and 24.04**: the package needs glibc >= 2.38 (24.04 has 2.39, 22.04 has 2.35) and its library names are the 24.04 ones (`libasound2t64`, `libglib2.0-0t64`, `libreadline8t64`; 22.04 has `libasound2`, ...). A 22.04 package would have different `Depends` and would be a second build. Debian 12 / LMDE 6 (glibc 2.36) is the same problem.
- CI today: the tests run on `ubuntu-24.04` runners (`linux-tests.yml`, six shards); the package would be built on the same runner type, so nothing changes there. The bundled SuperCollider means the package does not depend on the runner's SuperCollider.

## B3. Building it in CI and publishing ONE file

**Time (measured here, 4 cores):** SuperCollider 3.14.1 + sc3-plugins from source **2 min 39 s**; everything else of `package.sh all` (mi-UGens 17 s, PortedPlugins, NamAmp, libmonome, maiden, tree, .deb, privacy scan) **3 min 36 s**; `setup-deps.sh` 2.5 min, `build.sh` 1 min. About **6 minutes** of package work. A hosted runner is slower and the first run downloads sources; **estimate 15 to 25 minutes**, nowhere near the 4-hour limit (the test job allows 240 minutes). A cache (the `cache/` folder, 546 MB, keyed on the pins) could take it to a few minutes; not needed now.

**Design (the same as Windows, M30 lessons applied):**
- A new workflow `linux-package.yml`, separate from `linux-tests.yml` and from the Windows workflows. Release tag **`linux-latest`**, a release of its own, never touching `windows-latest`.
- Files on it: `Verdandi-linux-latest.deb` (the fixed name, the link the owner keeps), its `.sha256`, a versioned copy `Verdandi-linux-<version>-<hash>.deb`, `BUILD.txt` (commit, version, run link, test result).
- Publishing is `windows/ci/publish-release.sh` adapted: it **only adds or replaces its own files** and **reads the release afterwards, failing with the names if the fixed `.deb`, its `.sha256` or `BUILD.txt` is missing**. One publishing job, one concurrency group (`linux-release`), `contents: write` only on that job.
- What runs when: the existing test job is untouched (still on every push to `linux-port`, still the six shards). The package workflow runs **by hand (workflow_dispatch) and on a tag**, not on every push; plus a light check on pushes that change `linux/package.sh`, the pins or the launcher, which builds the .deb and runs the install test below but publishes nothing. So the usual push costs no extra minutes.

## B4. Upgrade behaviour

- Same package name `verdandi`, a higher version. Today's version is `0.1~git<date>.<count>.<hash>`; the plan is the number of the Windows version line (`0.10.22`, `0.10.23` ...), so one number names both builds. `0.10.x` is higher than `0.1~git...`, so a test .deb installed earlier is upgraded by it. Needs a small change in `package.sh` (a version from `windows/VERSION`, still overridable for the tests).
- Installing a newer .deb (double-click in GDebi / Software Manager, or `sudo apt install ./Verdandi-linux-latest.deb`) makes dpkg replace the files in `/opt/verdandi`, and remove files the new version no longer ships. **`/opt/verdandi` is the only folder it replaces.**
- Not touched, because the package contains nothing there and its scripts do nothing there: `~/Verdandi` (dust, scripts, samples, audio and other settings, `midimap.conf`, presets, logs) and the link `~/Verdandi/norns -> /opt/verdandi` (same target before and after). The scripts are the existing `postinst` / `postrm`: they only reload udev rules. The packs that go into the user's SuperCollider extension folder (mi-UGens, PortedPlugins, NamAmp) are refreshed by the launcher at the next start, by serial, never over a folder that is not Verdandi's (existing seed rules). `remove` leaves `~/Verdandi` (and a dangling link) alone; `purge` too: no script deletes user data.
- **Data-loss risks found:** none that delete data. Real risks: (1) upgrading **while Verdandi runs** replaces files under a running program (sclang loads classes at start: a half-old state until restart). Plan: a `prerm`/`preinst` check that refuses with a plain message "close Verdandi first" when a norns process of this install runs (small; needs a test). (2) a user who edited files **inside** `/opt/verdandi` loses them on upgrade (the tree is read-only for users; not a supported place). (3) a failed upgrade half way: dpkg's own rollback.
- **`~/verdandi-home` (the test copy) is unaffected:** it is a git checkout with `NORNS_HOME=~/verdandi-home`, its own `norns` link to the checkout and its own SuperCollider extension folder (the launcher sets HOME to the norns home). The installed Verdandi uses `~/Verdandi`. Two copies can be installed side by side; only one runs at a time (the JACK/ports are shared).

## B5. Tests in CI without the owner

`package_test.sh` already installs the .deb in a clean `debootstrap` Ubuntu 24.04 (minbase) root, starts it headless as a normal user, checks no library is missing, the engines are listed, the tree is read-only. To add:
1. **Install, start, log:** also check `sclang.log` has no error and no "not understood", MiPlaits and MiRings are found by the real sclang from the seeded folder (the M35 boot test, on the installed layout), twins' libraries are found.
2. **Upgrade keeps data:** build two .debs with different versions (needs the version override above), install the older, start once, put a marker in `~/Verdandi/dust/code/x`, `audio.conf`, `midimap.conf`, install the newer, check every marker, the link, the new version and a second start.
3. **Remove and purge:** `/opt/verdandi` gone, `~/Verdandi` complete.
4. **Upgrade while running:** refused with the message (if the guard is built).
Not testable in CI: a real desktop and the double-click (GDebi / Software Manager), real PipeWire and a sound card, real grids and arcs, Reaper, Mint itself. Those go into `HARDWARE-CHECKLIST.md` for the owner.

## B6. Size, signing, repository

16.3 MB download, 65 MB installed (measured). The .deb is **unsigned**: dpkg and GDebi do not check a signature for a local file, so there is no warning; the browser may warn about a download from GitHub like any file, and the published `.sha256` lets the owner check it. **An apt repository later** (a signed repository on GitHub Pages, so "Update Manager" offers new versions) is the right step after the single file works: it adds a signing key to look after, so not now.

## B7. Decisions for the owner (recommendation first), cost

1. **Version number of the .deb: the Windows number (0.10.22, ...)? Recommended: yes.** Cost: about half an hour (`package.sh`, a test), no CI minutes.
2. **When is a .deb published: by hand or tag (recommended), or at every green push like Windows?** By hand/tag keeps the test job as fast as today and costs about 15 to 25 CI minutes only when used (estimate); every push would add about 15 to 25 minutes to each green run and replace the file you installed from at every push. Cost of the workflow, the publish script, the tests of section B5 and the two small package changes (Depends, version override, the "close Verdandi first" guard): about one to two days.
3. **Only Ubuntu 24.04 / Mint 22 (recommended), or also Ubuntu 22.04 / Mint 21?** The second needs a different build with its own `Depends` (and an older glibc check): estimate one more day and about 20 more CI minutes per publish, and the owner's laptop does not need it (answer `cat /etc/os-release` first).

Nothing is built until the owner says yes. This phase makes no new Windows zip and republishes nothing.
