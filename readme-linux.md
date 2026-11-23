# Verdandi Linux

**Verdandi Linux** is the Linux version of Verdandi: [norns](https://monome.org/docs/norns/), the sound computer by monome,
running natively on a Linux desktop. It is based on the macOS port **Verdandi** by its original author (ha1dcre), which is
based on monome's norns, and it keeps their licence (GPL-3.0) and all their copyright notices (`LICENSE.txt`, the licence
files of the parts, and the files in `/opt/verdandi/licenses` of the package).

In running text this page and the manual say just "Verdandi". An unofficial community port, not affiliated with monome.
The macOS version is described in [readme-macos.md](readme-macos.md) and [readme.md](readme.md).

- what is built and tested, installing, starting, the settings: the manual, `linux/manual/manual.html` (the MANUAL button of the window opens it)
- **install (one file):** on the Releases page of this repository open the release `linux-latest` and download `Verdandi-linux-latest.deb` (Ubuntu 24.04 and Linux Mint 22, 64-bit, about 16 MB). Double-click it, click Install, type your password: the installer (GDebi or the Software Manager) fetches everything it needs. Start **Verdandi Linux** from the application menu. To update, close Verdandi and double-click the newer file the same way; your folder `~/Verdandi` is not touched. The page also has the `.sha256` file and `BUILD.txt` (which build it is). How the package is built and tested: `linux/package.sh`, `.github/workflows/linux-package.yml`, `docs/port/phase-m36.md`, `docs/port/packaging.md`
- from source (for development and testing, not for installing): `linux/setup-deps.sh`, `linux/build.sh`, `linux/norns.sh`; this makes a copy that runs from the checkout, separate from the installed program
- what still needs real hardware: `docs/port/HARDWARE-CHECKLIST.md`

The names of the project's parts do not change: the package and the command are `verdandi`, the program is in `/opt/verdandi`,
the audio and MIDI ports are called "Verdandi". "Verdandi Linux" is only what you see in the window title and the application menu.
