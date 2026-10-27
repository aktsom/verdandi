# Verdandi Linux

**Verdandi Linux** is the Linux version of Verdandi: [norns](https://monome.org/docs/norns/), the sound computer by monome,
running natively on a Linux desktop. It is based on the macOS port **Verdandi** by its original author (ha1dcre), which is
based on monome's norns, and it keeps their licence (GPL-3.0) and all their copyright notices (`LICENSE.txt`, the licence
files of the parts, and the files in `/opt/verdandi/licenses` of the package).

In running text this page and the manual say just "Verdandi". An unofficial community port, not affiliated with monome.
The macOS version is described in [readme-macos.md](readme-macos.md) and [readme.md](readme.md).

- what is built and tested, installing, starting, the settings: the manual, `linux/manual/manual.html` (the MANUAL button of the window opens it)
- the package (`.deb`, Ubuntu 24.04 and Linux Mint 22): `linux/package.sh`, `docs/port/packaging.md`
- from source: `linux/setup-deps.sh`, `linux/build.sh`, `linux/norns.sh`
- what still needs real hardware: `docs/port/HARDWARE-CHECKLIST.md`

The names of the project's parts do not change: the package and the command are `verdandi`, the program is in `/opt/verdandi`,
the audio and MIDI ports are called "Verdandi". "Verdandi Linux" is only what you see in the window title and the application menu.
