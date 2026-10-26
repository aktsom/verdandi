# Dependencies of the Linux port and their licenses

Verdandi is GPL-3.0. Everything below is compatible with it. The Linux port adds no code
dependencies beyond what upstream norns and the macOS port already use; this lists what
`linux/setup-deps.sh` installs. Versions are Ubuntu 24.04's unless noted.

| Package | Used for | License |
|---|---|---|
| libmonome 1.4.9 (built from source, git tag) | grid/arc | ISC |
| waf 2.1.9 (built from the GitLab tag) | build system, tool only | BSD-3-Clause |
| jackd2 / libjack | audio server and API | GPL-2.0+ / LGPL-2.1+ |
| supercollider-server, -language 3.13 | scsynth, sclang | GPL-3.0+ |
| sc3-plugins | UGens | GPL-2.0+ |
| SDL2 | window (upstream `screen:sdl`) | zlib |
| cairo | drawing | LGPL-2.1 or MPL-1.1 |
| liblo | OSC | LGPL-2.1+ |
| nng 1.7 | sidecar IPC | MIT |
| Lua 5.3 | scripting | MIT |
| libsndfile, libsamplerate | audio files | LGPL-2.1+, BSD-2-Clause |
| ALSA, libudev, libevdev, libgpiod, glib | device layer | LGPL-2.1+, LGPL-2.1+, MIT, LGPL-2.1+, LGPL-2.1+ |
| avahi-compat-libdnssd | zeroconf | LGPL-2.1+ |
| FFTW3 | softcut/crone | GPL-2.0+ |
| maiden (monome/maiden at one commit, built from source by `linux/maiden-build.sh`; patched) | web editor and script catalog | GPL-3.0 |
| Go (Ubuntu `golang-go`, 1.22) | builds maiden, tool only | BSD-3-Clause |
| Go modules of maiden (gin, go-git, cobra, viper, logrus, go-systemd and their dependencies, from its `go.sum`) | linked into the maiden binary | MIT, Apache-2.0, BSD-3-Clause, BSD-2-Clause (per module; the full list is not collected yet, see the open item below) |
| node 16.20.2 (nodejs.org tarball, SHA-256 checked, kept in the build folder only) | builds maiden's web app, tool only | MIT (node), with its bundled third-party licenses |
| yarn 1.22.22 (via npx) and the npm packages of maiden's web app (React, react-ace and others, from its `yarn.lock`) | the web app that the browser loads | BSD-2-Clause (yarn); MIT, BSD, Apache-2.0 per package (the list is not collected yet) |
| readline, ncurses | maiden-repl | GPL-3.0+, MIT |
| Boost headers | build | BSL-1.0 |
| Xvfb, xauth, x11-apps (xwd), xdotool | headless tests only | MIT/X11, BSD-3-Clause for xdotool |
| dbus (dbus-run-session), python3-gi | headless tests only (mock portal) | AFL-2.1/GPL-2.0+, LGPL-2.1+ |
| zenity | file dialog fallback (runtime, optional; also installed for the tests) | LGPL-2.1+ |
| GIO (part of glib) | XDG portal file dialog over D-Bus | LGPL-2.1+ |
| ImageMagick (`convert`) | headless tests only (screenshots) | ImageMagick license (Apache-2.0 style) |
| git submodules: softcut-lib, Ableton Link, lua-cjson, concurrentqueue, readerwriterqueue, doctest, trompeloeil | as upstream | see each repository (Link: GPL-2.0+) |

**Open item (maiden):** the licenses of maiden's Go modules and npm packages are not collected here. The Mac port collects them into the app
(`macos/licenses.py`, not used for Linux). Before a package is shipped (gate B), do the same for Linux; none is expected to be incompatible
with GPL-3.0, but that is not checked.
