# Packaging and launching the Linux version (Gate B)

Status: **investigation only. No product code was changed** (no launcher, build or setup script). The experiments ran in a scratch folder outside the repository; the scripts and the last output are copied into `docs/port/packaging/`. Every claim says whether it was **read** in the code, **measured/run** here, or is **expected / from general knowledge, not checked**. Section 6 lists what I could not check. `macos/` was not touched.

## 0. The answer in short

- **Recommendation: a `.deb` package first** (Ubuntu 24.04 and Linux Mint 22, the owner's laptop), built from this repository's own build plus a bundled SuperCollider **without Qt**, installed with `apt install ./verdandi_<version>_amd64.deb`, started from the application menu. **Flatpak is not recommended** (the permissions this app needs undo the sandbox, several current features go blind or break inside one, and I could not build or test one here). **An AppImage is a possible second artifact later** (it has real problems of its own: no FUSE by default on Ubuntu 24.04, a SuperCollider that is not relocatable, the plug-in cannot find a moving file).
- **Evidence that matters** (all run here):
  1. norns **boots from a read-only program tree** with the home in a separate folder, nothing written into the program folder (what a package or squashfs image needs).
  2. **SuperCollider built from source without Qt** (the recipe the Mac port already uses) boots norns and lists the engines; its library closure is **18 MB instead of 238 MB** (Ubuntu's `sclang` pulls in Qt WebEngine, 128 MB by itself).
  3. In a **clean minimal Ubuntu 24.04**, `apt-get install ./verdandi.deb` (dependencies computed with `dpkg-shlibdeps`) resolves everything, no library is missing, and norns **boots headless and lists its engines**.
  4. **Not relocatable:** SuperCollider's class-library path is compiled in (`SC_DATA_DIR`); moved to another folder it fails to compile the class library. A `.deb` with a fixed prefix is fine; an AppImage (path changes at every run) needs a workaround.
- **Smallest first step** (section 5): make the launcher "installed mode" aware (home in the user's folder, program read-only), write `linux/package.sh` that builds the `.deb` in a clean container, and test it in a clean root as I did by hand. About two to three days of work (a guess).

## 1. What the package contains, and where data lives

### 1.1 Program (read-only, replaced on update)

Measured sizes (this repository's build, Ubuntu 24.04): the runtime tree is small, the dependencies are not.

| part | what | size here | notes |
|---|---|---|---|
| norns binaries | `build/norns/norns` (matron + crone + softcut + sidecar), `ws-wrapper`, `maiden-repl`, `audio_devices`, `plugin_arch_check` | about 2 MB + a few small tools | built by `linux/build.sh` |
| Lua and SuperCollider code of norns | `lua/` 1.4 MB, `sc/` (norns' own class files, `sc/core`, `sc/engines`) 120 KB, `doc/` 1.1 MB (maiden's `--doc`), `update/version.txt` | about 3 MB | read at runtime |
| fonts | `resources/` | 14 MB | matron loads `$HOME/norns/resources/*.ttf` (`screen.cc:271`) |
| launcher and helpers | `linux/norns.sh`, `linux/shims/`, `matronrc.lua` | 0.5 MB | |
| **libmonome 1.4.9 with this repository's pty patch** | `libmonome.so.1` (38 KB) | not in Ubuntu: `apt-cache policy libmonome-dev libmonome1` finds nothing; `dpkg-shlibdeps` errors "no dependency information found for /usr/local/lib/libmonome.so.1" | must be bundled (own RUNPATH or `LD_LIBRARY_PATH`) |
| **SuperCollider** (sclang, scsynth, class library, plug-ins) | Ubuntu's 3.13.0: sclang drags `libQt5WebEngineCore` (128 MB) and ICU data (29 MB): **sclang closure 238 MB**, scsynth 17 MB. Built from the tag `Version-3.14.1` with `-DAUDIOAPI=jack -DSC_QT=OFF -DSC_IDE=OFF -DNO_X11=ON ...` (the flags of `macos/setup-deps.sh:156`): **11 MB installed, sclang closure 18 MB** | measured | built here, `build-supercollider-no-qt.sh` |
| sc3-plugins | built from the pinned commit (recipe in `macos/setup-deps.sh`) | not built here (about 10 to 20 MB, an estimate) | the Ubuntu package is built for 3.13; whether it loads in 3.14.1 is not checked |
| **maiden** | the built Go binary and web app, 26 MB (`~/verdandi-home/maiden` today), built at **package build time**, not on the user's machine | measured | no Go, node or yarn on the user's machine |
| the manual | `linux/manual/manual.html` | small | |
| libraries | everything else comes from **apt** in a `.deb` (the dependency list computed by `dpkg-shlibdeps`: libasound2t64, libavahi-compat-libdnssd1, libcairo2, libevdev2, libfreetype6, libglib2.0-0t64, liblo7, liblua5.3-0, libncurses6, libnng1, libreadline8t64, libsdl2-2.0-0, libsndfile1, libudev1, libjack, libyaml-cpp0.8 for the Qt-less SuperCollider, and so on). Norns' own closure is 32 MB; scsynth 17 MB | measured | in an AppImage or Flatpak they would have to be bundled |

Expected total installed size of a `.deb` with maiden and sc3-plugins: about **70 MB** (norns 29 MB measured including the Qt-less SuperCollider, plus maiden 26 MB, plus sc3-plugins; an estimate). The experimental package without maiden and sc3-plugins was **6 MB** compressed, 29 MB installed.

**Layout.** A tree shaped like the repository, under a fixed prefix, e.g. `/opt/verdandi/` (a folder the package owns): `build/…` (binaries), `lua/`, `sc/`, `resources/`, `linux/`, `doc/`, `update/`, `lib/` (libmonome), **`supercollider/`** (the bundled SuperCollider; **not `sc/`, which is norns' own class folder**: my first experimental package put it there, the two collided and SuperCollider failed), `maiden/`, `manual/`. The launcher already uses `$REPO`-relative paths, so this tree works with it **unchanged**: tested (section 3). `/usr/bin/verdandi` is a one-line wrapper; `/usr/share/applications/verdandi.desktop` and an icon give the menu entry (`macos/make-icon.py` draws the icon; it is this repository's own work, so no license question).

### 1.2 Data (the user's folders, never in the package)

The **norns home** is a normal user folder. Read in the code: `matron` hard-codes `$HOME/norns/lua/core/config.lua` (`weaver.cc:739`), fonts under `$HOME/norns/resources`, `matronrc.lua` in `$HOME`: so the home must contain a **link `norns` to the program tree** (the Mac app does exactly this, `macos/app-launcher.sh`). The launcher creates the link at each start (a package update that moves the program keeps working).

| in the home | what |
|---|---|
| `dust/` (code, audio, data, catalogs) | the user's scripts and samples: the visible part |
| `audio.conf`, `matronrc.lua`, `.norns-input`, `.mic-off`, `.vgrid-size` | settings and choices |
| `norns.log`, `sclang.log`, `maiden.log`, `.plugin-mismatch`, `disabled-plugins/` | logs and the plug-in check's files |
| `.config/SuperCollider/`, `.local/share/SuperCollider/Extensions` | SuperCollider configuration and user extensions |
| `norns` → `/opt/verdandi` | the link to the program |

**Where:** my proposal is a visible folder, `~/Verdandi` (like `~/norns` on the Mac), with the hidden files inside; the alternative is `~/.local/share/verdandi` (clean, but the scripts folder is then hard to find). The window's right-click menu already has "Show dust folder". An open decision (section 5).

**Update without touching the home:** `apt` (or `dpkg -i`) replaces the files under `/opt/verdandi`; the home is only read and written by norns. Verified in the experiment that the program tree can be **read-only** and norns does not write into it (section 3, test 1). One thing to fix: the launcher writes `sclang_conf.yaml` (the SuperCollider include paths, absolute) only **if it is missing** (`linux/norns.sh`), so a package that changes its prefix would leave stale paths; the launcher should rewrite it when the program path differs.

## 2. The candidates

For each: what works, what breaks, what could not be tested here, effort, how the VST3 plug-in (`docs/port/linux-vst3.md`) would find and start norns.

### 2.1 `.deb`

- **What works (run here):** the package builds with `dpkg-deb` (no external tool); `apt-get install -s ./verdandi.deb` on this machine (a development container with most libraries installed) wants 48 packages, of which only `libyaml-cpp0.8` and `xdg-utils` (with its Perl and X11 helper dependencies) are not already here; in a **clean Ubuntu 24.04** (a minimal debootstrap root, 135 MB) `apt-get install ./verdandi.deb` ran to the end (**350 new packages in the first run**, mostly the PipeWire and Perl dependencies of `pipewire-jack` and `xdg-utils` on a minimal system; a desktop has most of them), `ldd` found **no missing library** for norns and for the bundled SuperCollider, and norns **booted headless and listed its engines** (`startup_status.ok`, `engines: [PolySub, SimplePassThru, PolyPerc, TestSine, None]`).
  Everything the app does today uses the system as it is: **PipeWire and JACK** (the launcher's `pw-jack`/`wpctl`/`pw-cli` logic, no sandbox), **USB serial devices** (`/dev/ttyACM*`, through libmonome and udev, as now), **ALSA sequencer and rawmidi**, **libudev hotplug**, the **serialosc check** (it scans `/proc` and sees the host's processes), the **plug-in check**, the **file dialogs** (portal, zenity, kdialog: `file_picker.cc`), `xdg-open` for the manual and maiden, **maiden on 127.0.0.1**. Nothing is isolated, so nothing needs a permission.
- **What breaks / costs:** only Debian-family systems (Mint, Ubuntu; other distributions need their own package or an AppImage). Installing needs root (`sudo apt install ./file.deb`). No automatic updates unless an apt repository is hosted somewhere (a new file by hand otherwise; the owner decides whether that is acceptable: for one user on one laptop it probably is). Users still need the `audio` and `dialout` groups for real-time audio and serial devices: Phase 3 documented that (`phase-3.md:160`); a `.deb` can add a **udev rule** so that monome devices are usable without `dialout` (a proposal; the exact rule is not written or tested). `libjack` must stay the **host's** (see the AppImage note: never bundle it).
- **SuperCollider:** build it at the fixed prefix of the package (`-DCMAKE_INSTALL_PREFIX=/opt/verdandi/supercollider`); I proved the problem and a workaround: the compiled-in path (`SC_DATA_DIR`, `strings` shows `…/share/SuperCollider`) is why it failed after being moved; patching the prefix string in `sclang` and `scsynth` (same length, padded with slashes) made it work in the clean root. A rebuild with the right prefix is the clean way.
- **Untestable here:** the real laptop (Mint desktop integration, the menu entry's icon and window grouping: the SDL window class vs `StartupWMClass` is not checked), PipeWire with a real card, real USB devices.
- **Effort:** low to moderate: launcher installed mode, a package script, bundled SuperCollider and sc3-plugins and maiden built in a container, `copyright` file, a test in a clean root. A guess: two to three days.
- **The plug-in:** the VST3 can go to the system path `/usr/lib/vst3/Verdandi.vst3` (whether Reaper scans it is **unverified**; otherwise the launcher links it into `~/.vst3` at the first start), and it finds norns at the **fixed command `/usr/bin/verdandi`**: no configuration file needed. The simplest of the four.

### 2.2 AppImage

- **What it bundles:** the same program tree and the libraries that are not guaranteed on the host (norns' closure 32 MB, scsynth 17, a Qt-less sclang 18, libmonome); **it must not bundle `libjack`**: under PipeWire `pw-jack` puts PipeWire's `libjack` first, and a bundled one would make norns talk to a separate JACK server (expected; the AppImage project's own exclude list is a place to check). Host needs: PipeWire or jackd, a file dialog helper (portal/zenity), udev, `xdg-open`; the audio stack is the host's.
- **What works (run here):** the program tree on a **read-only mount** (what a squashfs image is) boots fine; the glibc floor is **2.38** (`objdump -T` on norns and on Ubuntu's `sclang`/`scsynth`: the highest `GLIBC_` symbol; the Qt-less SuperCollider's floor was not measured), so an image built on 24.04 runs on Mint 22 and newer, not on older systems; all hardware access is the host's (like the `.deb`).
- **What breaks:**
  1. **SuperCollider is not relocatable** (measured above): an AppImage is mounted at a different path at every start (`/tmp/.mount_XXXX`). Workarounds: patch the prefix string to a short fixed path and make the launcher bind the image there (needs a mount namespace, i.e. user namespaces, which Ubuntu may restrict for ordinary users: unchecked), or a patch to SuperCollider's path lookup: not in the recipe, new maintenance.
  2. **FUSE:** AppImages need `libfuse2` to mount themselves; Ubuntu 24.04 does not install it by default (general knowledge, not checked on Mint); the alternative `--appimage-extract-and-run` unpacks to a temporary folder each time: slow start, again a changing path.
  3. **No menu entry by itself**: needs a helper (AppImageLauncher, `appimaged`) or a first-run script that writes a `.desktop` file pointing at the file's path; **moving the file breaks it**.
  4. **The plug-in cannot find norns reliably**: the path of the AppImage is the user's choice; the first run would have to write `~/.config/verdandi/launcher.json` with it, and the plug-in starts it from there; if the file moves, the plug-in says "not installed". The VST3 file cannot live inside the image: the launcher must copy it to `~/.vst3` at first run.
  5. **Notices:** every bundled library needs its license text (see section 4); a `.deb` leaves that to apt.
- **Untestable here:** building one at all: `appimagetool` and `linuxdeploy` are GitHub release downloads and **both answered 403** from this container; `mksquashfs` is not installed (apt could add it, but the runtime that makes a file an AppImage is the blocked part). What I can test is the content (section 3).
- **Effort:** moderate to high: all of the `.deb` work, plus the SuperCollider relocation, a bundling step, the FUSE question, desktop integration. A guess: another two to four days after the `.deb`.

### 2.3 Flatpak

- **Needed permissions** (from general knowledge of Flatpak; **I could not check any of it here**: `flatpak` is not installed, `flathub.org` and `dl.flathub.org` answered nothing from this container, so no runtime could be fetched):
  - audio: PipeWire access (the socket) and a `libjack` inside the sandbox that talks to it; the launcher's own logic calls `pw-cli`, `wpctl`, `pw-jack` and `jackd`: they would have to exist in the runtime (not checked);
  - `--device=all` for **ALSA sequencer, rawmidi, serial devices (`/dev/ttyACM*`, `/dev/serial/by-id`)** and gamepads; whether supplementary groups such as `dialout` carry into the sandbox is not checked; libmonome reads the serial number through **udev's database** (`udev_device_new_from_devnum`, `phase-2.md` section 1), which the sandbox does not expose by default (`--filesystem=/run/udev:ro` is the usual remedy; not checked); hotplug (`device_monitor.cc`, libudev) is a second place;
  - `--share=network` for the loopback ports (maiden 5000, the REPL 5555/5556, the plug-in bridge); with it the sandbox shares the host's network, so a host Reaper reaches the bridge, without it nothing works;
  - `--socket=x11`/`wayland`, the file chooser **portal** (the code already prefers it: `file_picker.cc` backends portal, zenity, kdialog, tested with a mock portal), `xdg-open` (the runtime's version goes through the OpenURI portal: expected, not checked), real-time scheduling (`org.freedesktop.RealtimeKit1`);
  - `--filesystem=xdg-run/verdandi` so the plug-in's rendezvous file is visible to a host outside the sandbox.
- **What breaks inside a sandbox (reading the code):**
  - the **serialosc conflict check** scans `/proc/*/cmdline` for `serialosc-device`: a sandbox has its own process namespace and **cannot see the host's processes**, so the check goes blind;
  - scripts that run **system commands** (`wget`, `sudo`, `apt`, `systemctl`): the Raspberry Pi installers: the sandbox has none of the host's tools (the shims for `sudo systemctl` would still work, expected; the others do not);
  - the **plug-in check** looks at `/usr/share/SuperCollider/Extensions` and the home: the first is then the runtime's, not the host's (harmless, but not the same);
  - the VST3 **plug-in file** must reach the host's `~/.vst3` (`--filesystem=~/.vst3` or a manual copy) and the plug-in finds norns by `flatpak run <app id>`, which is robust, but it needs a user who runs Reaper outside Flatpak and the Flatpak norns, or both inside Flatpak with the host extension points for plug-ins;
  - `pkill -x norns` in the SLEEP/RESTART actions would work inside (own process namespace; expected).
- **Build:** a manifest that builds norns, **libmonome with the patch**, nng, SuperCollider 3.14.1, sc3-plugins, and **maiden with Go modules and npm packages** (Flathub-style builds are offline: every Go and npm dependency would have to be listed with checksums: hundreds of entries; I did not try). Then maintenance of the manifest.
- **Effort:** high (one to two weeks, a guess) and **I cannot test it here at all**. The benefit (sandbox, automatic updates through a repository) is small for a single-user project and mostly given back by `--device=all`.
- **The plug-in:** discussed above: `flatpak run`, plus the permissions.

### 2.4 A plain installer script

- **What it is:** `linux/setup-deps.sh` + `linux/build.sh` today, or a script that downloads a tarball into `~/.local/opt/verdandi`, writes a `.desktop` file, and `apt install`s the dependencies.
- **Assessment:** not plug and play (the first has compilers, a checkout and minutes of building; the second needs root for the dependencies and a hosted tarball), and it re-implements what a `.deb` already does (dependencies, uninstall, menu entry) without a package manager's bookkeeping. **Keep `setup-deps.sh` and `build.sh` as the developer path.**

### 2.5 Summary

| | plug and play | menu entry | no checkout, no build | PipeWire/JACK | USB serial, udev, MIDI | file dialogs, xdg-open | serialosc and plug-in checks | maiden, plug-in bridge | plug-in finds/starts norns | tested here | effort |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **.deb** | yes (`apt install ./x.deb`) | yes | yes | host's | as today | as today | as today | as today | fixed `/usr/bin/verdandi` | **yes: clean-root install and boot** | low to moderate |
| AppImage | needs FUSE and a launcher helper | not by itself | yes | host's (do not bundle libjack) | as today | as today | as today | as today | path of the file, moves break | partly (content only) | moderate to high |
| Flatpak | yes | yes | yes | permissions + libjack in the runtime | `--device=all`, udev access: unchecked | portal | **blind** (own process namespace) | `--share=network` | `flatpak run`, plus permissions | **no** (no tool, no network to Flathub) | high |
| installer script | no | by hand | no (builds) | host's | as today | as today | as today | as today | by hand | partly | low (exists) |

## 3. What I ran (and what still needs the owner's laptop)

All in this container (Ubuntu 24.04.5, x86_64, 4 cores, root, no sound card, no desktop). Scripts and the last output: `docs/port/packaging/`.

| # | test | result |
|---|---|---|
| 1 | the program tree (binaries, `lua`, `sc`, `resources`, launcher, `doc`, `update`: 29 MB) copied to a separate folder and **mounted read-only** in a private mount namespace (a write to it failed); the norns home in another folder with the `norns` link; the existing headless probe (`norns_probe.sh`) | **norns booted, sclang compiled and listed the engines, nothing was written into the program tree** |
| 2 | SuperCollider **3.14.1 built from source** with the Mac port's flags (Qt off, IDE off, JACK) | built; **11 MB installed**, sclang closure **18 MB** (Ubuntu's: 238 MB; `ldd` of the new `sclang` shows no Qt library); **norns booted with it** and listed `PolySub, SimplePassThru, PolyPerc, TestSine, None` |
| 3 | an **experimental `.deb`** (program + libmonome + the SuperCollider above; a desktop entry; `Depends` from `dpkg-shlibdeps` plus the choices of section 2.1), `apt-get install -s ./x.deb` on this machine | only `xdg-utils` and `libyaml-cpp0.8` are new here |
| 4 | the same `.deb` installed in a **clean minimal Ubuntu 24.04** (`debootstrap --variant=minbase`, then `apt-get install ./x.deb`), then a headless boot with the test-only tools (a display server, jackd2) | install exit 0 (350 new packages in the first run), **no missing library** (`ldd`), and after the two fixes below: **boots and lists the engines** |
| the two failures on the way | (a) my package put SuperCollider into `/opt/verdandi/sc`, which is norns' own class folder: SuperCollider failed to compile; renamed to `supercollider/`. (b) SuperCollider failed to find its class library at the new path: the prefix is compiled in; patched the prefix (same length) for the test | both are real packaging lessons, in 1.1 and 2.1 |
| not possible | building an **AppImage** (tools blocked: 403) or a **Flatpak** (no tool, no network to Flathub) | untested; sections 2.2, 2.3 are reasoning from the code and general knowledge |

**Needs the owner's laptop (Linux Mint 22.2, PipeWire 1.0.5, X11):** installing the package with `apt`/`dpkg` as an ordinary user, the menu entry and its icon in the panel and the taskbar, starting from the menu (and a second click while it runs), PipeWire audio and the `pw-jack` re-run through the packaged launcher, the real grid and arc (`dialout`, a possible udev rule), MIDI devices, the file dialog through the real portal, `xdg-open` for the manual and maiden, an upgrade (a newer `.deb` over an older one: the home is untouched), removal (`apt remove`), and later the plug-in finding `/usr/bin/verdandi`. These go to `HARDWARE-CHECKLIST.md` when the package exists.

## 4. Licensing for redistribution

This is GPL-3.0. Sources: `docs/port/DEPS.md` (the packages and the maiden tables), `macos/licenses.py` (the Mac app's list of notices), the repository's license files. Not legal advice.

**A package must include:**

1. **GPL-3.0 text** (`LICENSE.txt`) and a **copyright file** (`/usr/share/doc/verdandi/copyright`, machine-readable) listing every component below with its license and the license texts.
2. **Corresponding source**, or a written offer valid for three years, for every GPL part: this repository at the release tag; **SuperCollider 3.14.1** (GPL-3.0; the tag and the exact cmake flags); **sc3-plugins** (GPL-2.0-or-later; the pinned commit); **maiden** (GPL-3.0; the pinned commit plus `macos/patches/maiden-host-flag.patch` and `linux/patches/maiden-linux-guard-and-units.patch`); **libmonome** (ISC; with `linux/patches/libmonome-pty-serial.patch`). A source link beside the download is the simplest way to satisfy it.
3. **From the repository tree:** softcut (GPL-3.0, `crone/softcut/LICENSE.txt`), Ableton Link (GPL-2.0-or-later, with its asio part under the Boost license: `third-party/link/…`), lua-cjson (MIT), concurrentqueue (BSD-2-Clause or BSL-1.0), readerwriterqueue (BSD-2-Clause) (the list in `macos/licenses.py`, `REPO_PARTS`).
4. **Fonts** (`resources/`): Roboto (Apache-2.0, `roboto-LICENSE.txt`), Bitstream Vera (`vera-LICENSE.txt`), the bitmap fonts (`bmp-LICENSE.txt`, `tom-thumb-LICENSE.txt`). **No license file exists for `norns.ttf`, `liquid.ttf`, `Particle.ttf` and `basis33.ttf`**: their terms are **unverified** (they come from the norns code base; this needs a look before a public release).
5. **maiden's third-party notices:** the Go modules and npm packages of `DEPS.md` (permissive licenses plus one MPL-2.0 module, `hashicorp/hcl`): their copyright notices are **not carried by the build** (the web bundle has no banners, the Go binary none): a generated notices file is needed (`DEPS.md` lists this as open).
6. **SuperCollider's own third-party code:** SuperCollider's `COPYING` and the licenses of what its source tree carries (not read here).
7. If the VST3 plug-in is in the package: the **VST3 SDK's MIT notice**, and Steinberg's usage guidelines if the word "VST" or the logo appears (`linux-vst3.md` section 3).
8. **For a `.deb`, the shared libraries** (cairo, liblo, libsndfile, SDL2, nng, Lua, ALSA, ...) are separate Debian packages with their own copyright files: **nothing to add**. For an **AppImage or a Flatpak**, everything bundled needs its notice, the LGPL libraries (cairo, liblo, libsndfile and others) must stay dynamically linked and replaceable, and Qt would need its LGPL/GPL notices if it were bundled (the Qt-less SuperCollider avoids Qt, its WebEngine and the codec patents that come with it).
9. **No Node, Go or yarn** is shipped (build tools only).

**Consequence for the choice:** the `.deb` is the cheapest to keep compliant (apt supplies the notices of the system libraries); AppImage and Flatpak add a notices file for dozens of bundled libraries.

## 5. Recommendation

1. **Ship a `.deb` for Ubuntu 24.04 / Mint 22 as the Linux package. Decide Gate B for the `.deb`; keep an AppImage as a later option; do not do Flatpak.** Reasons: it is the only candidate that keeps **everything that works today without a permission question** (PipeWire/JACK, serial grids, udev, ALSA, MIDI, the serialosc check, the system `xdg-open` and portals, loopback); it installs and updates with one command and a menu entry; the plug-in finds norns at a fixed command; the license work is smallest; and it is the only candidate I could build **and** test end to end here (clean-root install and boot). Its limits (Debian family, root to install, no automatic updates) are acceptable for one owner on a Mint laptop.
2. **Bundle SuperCollider 3.14.1 built without Qt**, at the package's fixed prefix. It removes Qt WebEngine (a 238 MB closure, a 36 MB helper process per norns, and the "refuses to start as root" workaround in `linux/norns.sh`) and gives the same SuperCollider on every system. Check that norns' SuperCollider code and the engines run on 3.14.1 (they booted; the engines were listed; the Mac port already ships 3.14.1) and that sc3-plugins built for it load.
3. **Smallest first step (7 small items, tests first):**
   1. `linux/norns.sh` **installed mode** when run from a package tree (detect: no `.git`, or an `INSTALLED` marker file): `NORNS_HOME` defaults to the user's folder (today: `dirname $REPO`), create the `norns` link, prefer `$REPO/supercollider/bin` on `PATH`, `NORNS_MAIDEN` defaults to `$REPO/maiden`, rewrite `sclang_conf.yaml` when the program path changes, show an error dialog on failure when there is no terminal (the menu entry has `Terminal=false`), and bring the running window forward instead of failing silently when started twice. A **developer checkout keeps behaving as today** (the tests do not change).
   2. libmonome: a RUNPATH in the waf build (or `LD_LIBRARY_PATH` in the launcher; the experiment used the second).
   3. `linux/package.sh`: in a clean container builds norns, SuperCollider (final prefix, no Qt), sc3-plugins, maiden; assembles `/opt/verdandi`, the desktop file, the icon, the `copyright` file; computes `Depends` with `dpkg-shlibdeps` and adds `pipewire-jack | jackd2`, `zenity | xdg-desktop-portal`, `xdg-utils`; writes the `.deb`.
   4. A **clean-root test** (the scripts in `docs/port/packaging/`): `apt-get install ./verdandi.deb` in a fresh Ubuntu 24.04 root and the headless boot, in `run_all.sh` as an optional heavy test.
   5. The notices: a generated notices file for maiden's modules, and the answer on the four fonts.
   6. `HARDWARE-CHECKLIST.md` items from section 3.
   7. Decide the home folder name (`~/Verdandi` proposed).
   About two to three days (a guess).
4. **What it does to the existing scripts:** `linux/norns.sh` gains the installed mode above and stays the one launcher; `linux/setup-deps.sh` and `linux/build.sh` stay as the **developer** path (apt build dependencies, waf, maiden build); `linux/maiden-build.sh` is called by `package.sh` into the staging tree instead of the user's home; `run_all.sh` gains the optional package test. `macos/` is untouched. The VST3 plan changes only in 7.4 (finding norns): with the `.deb` it is the fixed command `/usr/bin/verdandi` and the plug-in in `/usr/lib/vst3`, so the planned `launcher.json` is not needed for the package.
5. **AppImage later**, if wanted: the same tree and the same SuperCollider, plus (a) a way around the compiled-in SuperCollider path, (b) the FUSE question on the target systems, (c) a first-run desktop entry and VST3 copy, (d) the notices. Decide after the `.deb` works on the laptop.

**Open decisions for the owner (Gate B, in `DECISIONS.md`):** `.deb` first (recommended) or something else; the home folder (`~/Verdandi` proposed); whether an apt repository is wanted (otherwise: a new file by hand per release); whether to add a udev rule for monome devices (proposal, not tested); AppImage as a later second artifact.

**Confidence.** High that the program, a Qt-less SuperCollider and the launcher run from a read-only package tree and that a `.deb` installs and boots in a clean Ubuntu 24.04 (run here). Medium on the recommendation (it rests on the owner staying on Mint/Ubuntu and on the judgement that Flatpak's costs outweigh its sandbox). Low on everything about Flatpak and AppImage behaviour (neither could be built here).

## 6. What I could not check

- **Building or running an AppImage or a Flatpak** (no tools, GitHub release downloads blocked with 403, Flathub unreachable). Everything about their permissions, bundling lists and behaviour is from the code and general knowledge.
- A **real desktop**: the menu entry, icons and window grouping, the first-start dialogs, the second-click behaviour; **PipeWire with a real card**; **real USB devices**, udev rules and groups; the file portal on the laptop; Reaper scanning `/usr/lib/vst3`.
- That **sc3-plugins** (from apt or built from source) load in SuperCollider 3.14.1 and that **every norns engine** runs on it (only the four engines listed at boot were seen; the Mac port runs 3.14.1).
- **Reproducibility** of the SuperCollider build (it built once, as the Mac recipe says; not timed), the exact size of the final package with maiden and sc3-plugins (estimated), the **licenses of SuperCollider's bundled third-party code** and of four fonts, and a legal reading of the GPL source-offer obligations.
- Whether the `apt` dependency set is **minimal and correct on Linux Mint 22.2** (the clean test used Ubuntu 24.04's archive).
- The `.deb`'s behaviour on **upgrade and removal** (not exercised: no `postinst`/`prerm` scripts were written).

## 7. Gate B decided; the first step (done) and what it found

The owner decided Gate B (see `DECISIONS.md`): `.deb` first, home shared with a developer checkout, a file per release, a narrow udev rule, AppImage later, fonts left open. The first step of section 5 was done:

- **Engines on the bundled SuperCollider:** all six engines run on 3.14.1 with the built sc3-plugins; the differences from 3.13.0 are in `docs/port/supercollider-3.14.md`.
- **Installed mode** in `linux/norns.sh` (tests in `linux/tests/launcher_test.sh`, "DECIDE-HOME" lines). Marker file `INSTALLED` in the program tree (or `NORNS_INSTALLED=1/0`). Home: `NORNS_HOME`, else the first line of `~/.config/verdandi/home` (`~/` allowed), else `~/Verdandi`; a checkout keeps the folder above it as before. `<home>/norns` is created, **or moved when it is a link to another tree** (the tree started last owns it; so a checkout and the package can share one home, with the one rule that the link follows the last start), and **a real folder called `norns` in the home is never replaced** (the launcher refuses and says why). `sclang_conf.yaml` is written again (old one kept as `.old`) when it does not name this tree. From the desktop (no terminal) a failure is shown in a dialog (zenity, kdialog, notify-send) and the launcher's output goes to `<home>/launcher.log`. Not done: bringing the running window forward when started twice (the second start says "norns is already running").
- **libmonome finding:** libmonome opens its protocol modules from a **compiled-in path** (`/usr/local/lib/monome/protocol_*.so`); the experimental package of section 3 used the system copy and would have found no grid. `package.sh` now builds it for `/opt/verdandi` (patch applied). The headless boot does not show this (it does not open a device); a **real grid on the laptop** does (hardware checklist).
- **`linux/package.sh`:** `sc`, `libmonome`, `maiden`, `tree`, `deb`, `all`, `clean-root`, `check FILE`. `clean-root` builds everything in a fresh Ubuntu 24.04 (debootstrap, repository copied to `/build/verdandi`, `linux/setup-deps.sh`, `linux/build.sh`, `package.sh all`).
- **Neutral identity:** `Maintainer: Verdandi packagers <verdandi-packaging@localhost.invalid>` (override `PACKAGE_MAINTAINER`), files owned `root/root`, modification times from the commit, no author line. The copyright file names the upstream authors as groups ("the norns authors (monome)", "the SuperCollider authors", "William Light and the libmonome authors"): the notices of the licences stay in `/opt/verdandi/licenses`. **Privacy scan** (`privacy_scan` in `package.sh`): words that identify the builder (user name, account real name, git identity, the owner of the git remote, the home folder name, `PACKAGE_PRIVACY_EXTRA`) are looked for in every file **name and content** of the stage and of the extracted `.deb`; one found fails the build without printing the word. The test proves that it fails when a word is in the package. Binaries are stripped; the string `/home/<user>/…/build` that waf leaves in `norns` is the one place a login name could get in when building in a home folder: `clean-root` builds in `/build/verdandi`, and the scan catches the other cases.
- **Clean-root test** (`linux/tests/package_test.sh`, in `run_all.sh`; SKIP with a reason without root, debootstrap, network or a built `.deb`; `NORNS_PACKAGE_TEST=0` skips): installs the `.deb` with apt in a minimal Ubuntu 24.04, `ldd` on every binary, boots `/usr/bin/verdandi --terminal` headless **as a normal user** (maiden answers on 127.0.0.1:5000, engines listed, the program tree is not writable by that user, no process left).

### 7.1 USB IDs and the udev rule (decision 4)

`linux/udev/70-verdandi-monome.rules` has two rules, both `SUBSYSTEM=="tty"` on a USB parent with `TAG+="uaccess"` and nothing else (no mode, group, owner or program): the active seat user gets access to the serial port (without `dialout`/`uucp`).

1. **Older grids and arcs (before 2022) and monome kits:** FTDI FT232 chip, `0403:6001`, with a USB serial string that is the monome device name (`ATTRS{serial}=="m[0-9k]*"`: m64-…, m128-…, m256-…, mk…, m40h…, m + digits).
2. **Newer devices** with a USB serial device of their own (the `cafe:1110` grid that the owner named): `ATTRS{manufacturer}=="monome"`, the property that serialosc's detector tests (`ID_VENDOR=monome`).

**What I could verify:** from the source code of **libmonome** (`src/private/devices.h`) the serial-string names of the old devices and that they are FTDI devices (`linux_sysfs.c` reads `/sys/bus/usb/drivers/ftdi_sio`); from **serialosc** (`src/serialosc-detector/libudev.c`) that a device is accepted if it has a `usb-serial` parent (the FTDI ones, no vendor test at all), or a `cdc_acm` parent with `ID_VENDOR=monome` and `ID_MODEL=grid`, or a serial string `m%d`; from monome's documentation (search result summary; the site itself is not reachable from here) that grids before 2022 "use an FTDI USB serial chip" and that the 2022-and-later grids use another microcontroller (RP2040). The syntax of the rules passes `udevadm verify`, and a test (`linux/tests/udev_test.sh`) checks that every rule is limited to USB serial ports, to a monome-specific match and to the uaccess tag.
**What I could not verify:** the numeric IDs `0403:6001` of the **older arcs and grids** (FTDI's default for the FT232R; no public monome page that I could reach lists them; run `lsusb` with your device); that those devices' **manufacturer string is "monome"** (so rule 1 matches on the serial string instead, which came from libmonome's source); the IDs and strings of **any newer model** other than "the manufacturer string is monome" (the `cafe:1110` value is the owner's; `cafe` is a vendor ID that development boards also use, which is why the rule matches the string and not the number); **arcs** of the newer generation; and the whole **hotplug path** (udev applying the tag, `uaccess` giving the user an ACL, `ttyUSB*`/`ttyACM*` permissions with the real device): it needs a grid on the laptop (`HARDWARE-CHECKLIST.md`). A device that none of the rules matches keeps working through the `dialout`/`uucp` group as before; the rule only adds convenience.
