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
| readline, ncurses | maiden-repl | GPL-3.0+, MIT |
| Boost headers | build | BSL-1.0 |
| Xvfb, xauth, x11-apps (xwd), xdotool | headless tests only | MIT/X11, BSD-3-Clause for xdotool |
| ImageMagick (`convert`) | headless tests only (screenshots) | ImageMagick license (Apache-2.0 style) |
| git submodules: softcut-lib, Ableton Link, lua-cjson, concurrentqueue, readerwriterqueue, doctest, trompeloeil | as upstream | see each repository (Link: GPL-2.0+) |
