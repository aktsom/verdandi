# M36: the one-click Linux install (the .deb as the thing the owner downloads)

Base: 4c1f7ad7 (M35 part A pushed and green). Linux files and workflows only: `windows/` and the `windows-latest` release are not touched, no Windows zip is made. The plan is `docs/port/phase-m35-deb.md`; the owner decided: (1) the .deb uses the Windows version number, (2) published by hand or on a tag, (3) Ubuntu 24.04 / Linux Mint 22 (noble), amd64 only.

## What exists (read in the code, verified)

- `linux/package.sh` builds `/opt/verdandi` (norns, SuperCollider 3.14.1 without Qt, sc3-plugins, mi-UGens, PortedPlugins, NamAmp, libmonome, maiden, fonts, manual, licences), `/usr/bin/verdandi`, the menu entry, the icon, a udev rule. `package_test.sh` installs it in a clean Ubuntu 24.04 root (debootstrap), boots it as a normal user and checks the seeded packs, the read-only tree, maiden. Nothing builds the .deb in CI.
- Version today: `0.1~git<date>.<commit count>.<hash>`. `Depends` = `dpkg-shlibdeps` + `pipewire-jack | jackd2`, `zenity | xdg-desktop-portal`, `xdg-utils`; `Recommends: curl, unzip` (GDebi does not install Recommends).
- `postinst`/`postrm` (heredocs in `package.sh`) only reload udev rules. No `preinst`/`prerm`. Nothing in the package touches a home folder; the launcher creates `~/Verdandi` and the link `~/Verdandi/norns -> /opt/verdandi` at the first start, and seeds the packs into `~/Verdandi/.local/share/SuperCollider/Extensions` (the launcher sets HOME to the norns home) by serial.
- The Windows release: `windows/ci/publish-release.sh` (adds/replaces, reads the release back, per-commit release plus a fixed-address one, the 403 on the per-commit tag) and its stand-in-`gh` test.
- The version line of the program is `VERDANDI_BUILD` (home page, logs). Windows sets it from `BUILD.txt`. Linux sets nothing.

## What changes

1. **Version.** The .deb version is `<first line of windows/VERSION>-<number of commits>` (now `0.10.21-<n>`). The first part is the Windows number, so the numbers match; the commit count after the dash grows with every build, so two Linux-only builds under the same Windows number still replace each other (Linux-only phases do not change `windows/VERSION`, and this phase must not). Old packages are `0.1~git...`; `0.10.21` is higher than `0.1~git...` (checked with `dpkg --compare-versions`), so **no epoch is needed**. `PACKAGE_REVISION` overrides the count (tests build an "older" package with it).
2. **BUILD.txt** in the program tree (first line `<version> <short hash>`, like Windows) and `norns.sh` sets `VERDANDI_BUILD` from it and writes `norns.sh: build ...` as the first line of its output (launcher.log from the menu entry). A checkout has no BUILD.txt and shows nothing, as today.
3. **Depends.** `curl` and `unzip` move from Recommends to Depends. The list is checked by installing the .deb in a clean Ubuntu 24.04 root with only the base packages. What is not covered is said in the doc and the manual (no PipeWire or JACK daemon running on a plain PulseAudio Mint).
4. **Maintainer scripts** become files (`linux/debian/preinst, postinst, prerm, postrm`) so they can be tested. preinst: refuses an install or upgrade while a norns of this installation runs ("close Verdandi first"). postinst/postrm: reload udev rules (as before). prerm: refuses removal while it runs. None writes or deletes anything in a home folder or outside `/opt/verdandi` and the desktop files.
5. **CI**: `.github/workflows/linux-package.yml`, on a tag `linux-v*` or by hand, never on push: builds the .deb on `ubuntu-24.04` (cache of the SuperCollider build), builds the previous commit's .deb as the "older" package, runs the install / upgrade / remove / version tests in a clean ubuntu:24.04 container, and publishes.
6. **Publishing**: `linux/ci/publish-release.sh` + `release-notes.sh`, modelled on the Windows ones: the release `linux-latest` (fixed names `Verdandi-linux-latest.deb`, `.sha256`, `BUILD.txt`, and the versioned `Verdandi-linux-<version>-<hash>.deb`), only adds or replaces its own files, reads the release back and fails with the names when one is missing, the 403 workaround for the per-commit release `linux-<hash>`. Never touches `windows-*` releases. Tested with a stand-in `gh` (`linux/tests/linux_release_publish_test.sh`).
7. **Docs**: `readme-linux.md` and the Linux manual: download, double-click, password, the menu entry, update; building from a checkout is for development.

## What stays

macOS, Windows, `windows/`, `windows-latest`, the existing `linux-tests` job (the new tests that need a built .deb skip in it, exactly as `package_test.sh` does; the fast ones are a few seconds). `linux/build.sh` and the checkout run. The pack seed rules.

## Tests (each shown to fail on the old code or a deliberately broken package: `docs/port/phase-m36-without.txt`)

- `package_version_test.sh` (new form), `linux_release_publish_test.sh` (stand-in gh), `deb_scripts_test.sh` (the maintainer scripts in a throw-away root: a running norns stops install/remove, nothing under a fake home changes, nothing is written outside the expected places), `package_recommends_test.sh` (now Depends).
- `deb_upgrade_test.sh` (clean Ubuntu 24.04 root; needs root, debootstrap and two .debs): install, boot, log checks (norns and SuperCollider up, mi-UGens seeded, PortedPlugins and twins' requirement check, no class errors), upgrade from the older .deb with a marker in a fake `~/Verdandi` untouched and no second copy of a pack, remove (data stays), version in the package = BUILD.txt = the program's version line.
