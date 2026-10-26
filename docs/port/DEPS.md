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

## Licenses of maiden (collected, Phase 4)

maiden itself (monome/maiden at the pinned commit, patched by `linux/patches` and `macos/patches/maiden-host-flag.patch`) is **GPL-3.0** (its `LICENSE`). Collected on 2026-10-26 from a real build of `linux/maiden-build.sh` (Go 1.24.7, node 16.20.2, yarn 1.22.22):
the Go modules actually linked into the binary (`go list -deps` of the main package, linux/amd64: 40 modules besides maiden and its three `pkg/` modules, which are GPL-3.0 parts of maiden), and the npm packages actually bundled into the web app (read from the build's source map: 118 packages).
Licenses were read from each module's `LICENSE` file (Go) or `package.json` (npm) and, for Go, matched against the license texts by a small script; two were then read by hand (marked). Not a legal opinion.

### Go modules linked into the `maiden` binary

| module | version | license | determined from |
|---|---|---|---|
| github.com/coreos/go-systemd | v0.0.0-20181031085051-9002847aa142 | Apache-2.0 | LICENSE (https://proxy.golang.org/github.com/coreos/go-systemd/@v/v0.0.0-20181031085051-9002847aa142.zip) |
| github.com/emirpasic/gods | v1.12.0 | BSD-2-Clause (+ ISC for part of the code) | LICENSE (BSD-2-Clause text; the file also holds an ISC notice for the AVL tree, read by hand) (https://proxy.golang.org/github.com/emirpasic/gods/@v/v1.12.0.zip) |
| github.com/fsnotify/fsnotify | v1.4.7 | BSD-3-Clause | LICENSE (https://proxy.golang.org/github.com/fsnotify/fsnotify/@v/v1.4.7.zip) |
| github.com/gin-contrib/sse | v0.1.0 | MIT | LICENSE (https://proxy.golang.org/github.com/gin-contrib/sse/@v/v0.1.0.zip) |
| github.com/gin-gonic/gin | v1.7.7 | MIT | LICENSE (https://proxy.golang.org/github.com/gin-gonic/gin/@v/v1.7.7.zip) |
| github.com/go-git/gcfg | v1.5.0 | BSD-3-Clause | LICENSE (https://proxy.golang.org/github.com/go-git/gcfg/@v/v1.5.0.zip) |
| github.com/go-git/go-billy/v5 | v5.0.0 | Apache-2.0 | LICENSE (https://proxy.golang.org/github.com/go-git/go-billy/v5/@v/v5.0.0.zip) |
| github.com/go-git/go-git/v5 | v5.2.0 | Apache-2.0 | LICENSE (https://proxy.golang.org/github.com/go-git/go-git/v5/@v/v5.2.0.zip) |
| github.com/go-playground/locales | v0.14.0 | MIT | LICENSE (https://proxy.golang.org/github.com/go-playground/locales/@v/v0.14.0.zip) |
| github.com/go-playground/universal-translator | v0.18.0 | MIT | LICENSE (https://proxy.golang.org/github.com/go-playground/universal-translator/@v/v0.18.0.zip) |
| github.com/go-playground/validator/v10 | v10.10.1 | MIT | LICENSE (https://proxy.golang.org/github.com/go-playground/validator/v10/@v/v10.10.1.zip) |
| github.com/godbus/dbus | v0.0.0-20181101234600-2ff6f7ffd60f | BSD-2-Clause | LICENSE (https://proxy.golang.org/github.com/godbus/dbus/@v/v0.0.0-20181101234600-2ff6f7ffd60f.zip) |
| github.com/golang/protobuf | v1.5.2 | BSD-3-Clause | LICENSE (https://proxy.golang.org/github.com/golang/protobuf/@v/v1.5.2.zip) |
| github.com/hashicorp/hcl | v1.0.0 | MPL-2.0 | LICENSE (https://proxy.golang.org/github.com/hashicorp/hcl/@v/v1.0.0.zip) |
| github.com/imdario/mergo | v0.3.9 | BSD-3-Clause | LICENSE (https://proxy.golang.org/github.com/imdario/mergo/@v/v0.3.9.zip) |
| github.com/jbenet/go-context | v0.0.0-20150711004518-d14ea06fba99 | MIT | LICENSE (https://proxy.golang.org/github.com/jbenet/go-context/@v/v0.0.0-20150711004518-d14ea06fba99.zip) |
| github.com/kevinburke/ssh_config | v0.0.0-20190725054713-01f96b0aa0cd | MIT | LICENSE (https://proxy.golang.org/github.com/kevinburke/ssh_config/@v/v0.0.0-20190725054713-01f96b0aa0cd.zip) |
| github.com/leodido/go-urn | v1.2.1 | MIT | LICENSE (https://proxy.golang.org/github.com/leodido/go-urn/@v/v1.2.1.zip) |
| github.com/magiconair/properties | v1.8.0 | BSD-2-Clause | LICENSE (https://proxy.golang.org/github.com/magiconair/properties/@v/v1.8.0.zip) |
| github.com/mattn/go-isatty | v0.0.14 | MIT | LICENSE (https://proxy.golang.org/github.com/mattn/go-isatty/@v/v0.0.14.zip) |
| github.com/mitchellh/go-homedir | v1.1.0 | MIT | LICENSE (https://proxy.golang.org/github.com/mitchellh/go-homedir/@v/v1.1.0.zip) |
| github.com/mitchellh/mapstructure | v1.1.2 | MIT | LICENSE (https://proxy.golang.org/github.com/mitchellh/mapstructure/@v/v1.1.2.zip) |
| github.com/pelletier/go-toml | v1.2.0 | MIT | LICENSE (https://proxy.golang.org/github.com/pelletier/go-toml/@v/v1.2.0.zip) |
| github.com/sergi/go-diff | v1.1.0 | MIT | LICENSE (https://proxy.golang.org/github.com/sergi/go-diff/@v/v1.1.0.zip) |
| github.com/sirupsen/logrus | v1.4.1 | MIT | LICENSE (https://proxy.golang.org/github.com/sirupsen/logrus/@v/v1.4.1.zip) |
| github.com/spf13/afero | v1.1.2 | Apache-2.0 | LICENSE.txt (https://proxy.golang.org/github.com/spf13/afero/@v/v1.1.2.zip) |
| github.com/spf13/cast | v1.3.0 | MIT | LICENSE (https://proxy.golang.org/github.com/spf13/cast/@v/v1.3.0.zip) |
| github.com/spf13/cobra | v0.0.3 | Apache-2.0 | LICENSE.txt (https://proxy.golang.org/github.com/spf13/cobra/@v/v0.0.3.zip) |
| github.com/spf13/jwalterweatherman | v1.0.0 | MIT | LICENSE (https://proxy.golang.org/github.com/spf13/jwalterweatherman/@v/v1.0.0.zip) |
| github.com/spf13/pflag | v1.0.3 | BSD-3-Clause | LICENSE (https://proxy.golang.org/github.com/spf13/pflag/@v/v1.0.3.zip) |
| github.com/spf13/viper | v1.3.2 | MIT | LICENSE (https://proxy.golang.org/github.com/spf13/viper/@v/v1.3.2.zip) |
| github.com/ugorji/go/codec | v1.2.7 | MIT | LICENSE (https://proxy.golang.org/github.com/ugorji/go/codec/@v/v1.2.7.zip) |
| github.com/xanzy/ssh-agent | v0.2.1 | Apache-2.0 | LICENSE (https://proxy.golang.org/github.com/xanzy/ssh-agent/@v/v0.2.1.zip) |
| golang.org/x/crypto | v0.0.0-20220321153916-2c7772ba3064 | BSD-3-Clause | LICENSE (https://proxy.golang.org/golang.org/x/crypto/@v/v0.0.0-20220321153916-2c7772ba3064.zip) |
| golang.org/x/net | v0.0.0-20211112202133-69e39bad7dc2 | BSD-3-Clause | LICENSE (https://proxy.golang.org/golang.org/x/net/@v/v0.0.0-20211112202133-69e39bad7dc2.zip) |
| golang.org/x/sys | v0.0.0-20220319134239-a9b59b0215f8 | BSD-3-Clause | LICENSE (https://proxy.golang.org/golang.org/x/sys/@v/v0.0.0-20220319134239-a9b59b0215f8.zip) |
| golang.org/x/text | v0.3.7 | BSD-3-Clause | LICENSE (https://proxy.golang.org/golang.org/x/text/@v/v0.3.7.zip) |
| google.golang.org/protobuf | v1.27.1 | BSD-3-Clause | LICENSE (https://proxy.golang.org/google.golang.org/protobuf/@v/v1.27.1.zip) |
| gopkg.in/warnings.v0 | v0.1.2 | BSD-2-Clause | LICENSE (https://proxy.golang.org/gopkg.in/warnings.v0/@v/v0.1.2.zip) |
| gopkg.in/yaml.v2 | v2.4.0 | Apache-2.0 + MIT (the libyaml port) | LICENSE, LICENSE.libyaml, NOTICE (https://proxy.golang.org/gopkg.in/yaml.v2/@v/v2.4.0.zip) |

The Go standard library is linked in too: BSD-3-Clause (the Go toolchain, Ubuntu `golang-go`).

### npm packages bundled into the web app (118)

| package | version | license | determined from |
|---|---|---|---|
| @babel/runtime | 7.28.6 | MIT | package.json (https://www.npmjs.com/package/@babel/runtime/v/7.28.6) |
| @emotion/is-prop-valid | 0.8.8 | MIT | package.json (https://www.npmjs.com/package/@emotion/is-prop-valid/v/0.8.8) |
| @emotion/memoize | 0.7.4 | MIT | package.json (https://www.npmjs.com/package/@emotion/memoize/v/0.7.4) |
| @emotion/unitless | 0.7.5 | MIT | package.json (https://www.npmjs.com/package/@emotion/unitless/v/0.7.5) |
| ace-builds | 1.43.6 | BSD-3-Clause | package.json (https://www.npmjs.com/package/ace-builds/v/1.43.6) |
| array-includes | 3.1.9 | MIT | package.json (https://www.npmjs.com/package/array-includes/v/3.1.9) |
| asap | 2.0.6 | MIT | package.json (https://www.npmjs.com/package/asap/v/2.0.6) |
| babel-runtime | 6.26.0 | MIT | package.json (https://www.npmjs.com/package/babel-runtime/v/6.26.0) |
| bowser | 1.9.4 | MIT | package.json (https://www.npmjs.com/package/bowser/v/1.9.4) |
| call-bind | 1.0.8 | MIT | package.json (https://www.npmjs.com/package/call-bind/v/1.0.8) |
| call-bind-apply-helpers | 1.0.2 | MIT | package.json (https://www.npmjs.com/package/call-bind-apply-helpers/v/1.0.2) |
| call-bound | 1.0.4 | MIT | package.json (https://www.npmjs.com/package/call-bound/v/1.0.4) |
| classname | 0.0.0 | ISC | package.json (https://www.npmjs.com/package/classname/v/0.0.0) |
| connected-react-router | 6.9.3 | MIT | package.json (https://www.npmjs.com/package/connected-react-router/v/6.9.3) |
| deep-equal | 1.1.2 | MIT | package.json (https://www.npmjs.com/package/deep-equal/v/1.1.2) |
| define-data-property | 1.1.4 | MIT | package.json (https://www.npmjs.com/package/define-data-property/v/1.1.4) |
| define-properties | 1.2.1 | MIT | package.json (https://www.npmjs.com/package/define-properties/v/1.2.1) |
| diff-match-patch | 1.0.5 | Apache-2.0 | package.json (https://www.npmjs.com/package/diff-match-patch/v/1.0.5) |
| dunder-proto | 1.0.1 | MIT | package.json (https://www.npmjs.com/package/dunder-proto/v/1.0.1) |
| es-abstract | 1.24.1 | MIT | package.json (https://www.npmjs.com/package/es-abstract/v/1.24.1) |
| es-define-property | 1.0.1 | MIT | package.json (https://www.npmjs.com/package/es-define-property/v/1.0.1) |
| es-errors | 1.3.0 | MIT | package.json (https://www.npmjs.com/package/es-errors/v/1.3.0) |
| es-object-atoms | 1.1.1 | MIT | package.json (https://www.npmjs.com/package/es-object-atoms/v/1.1.1) |
| es-to-primitive | 1.3.0 | MIT | package.json (https://www.npmjs.com/package/es-to-primitive/v/1.3.0) |
| exenv | 1.2.2 | BSD-3-Clause | package.json (https://www.npmjs.com/package/exenv/v/1.2.2) |
| function-bind | 1.1.2 | MIT | package.json (https://www.npmjs.com/package/function-bind/v/1.1.2) |
| functions-have-names | 1.2.3 | MIT | package.json (https://www.npmjs.com/package/functions-have-names/v/1.2.3) |
| get-intrinsic | 1.3.0 | MIT | package.json (https://www.npmjs.com/package/get-intrinsic/v/1.3.0) |
| get-proto | 1.0.1 | MIT | package.json (https://www.npmjs.com/package/get-proto/v/1.0.1) |
| gopd | 1.2.0 | MIT | package.json (https://www.npmjs.com/package/gopd/v/1.2.0) |
| has-property-descriptors | 1.0.2 | MIT | package.json (https://www.npmjs.com/package/has-property-descriptors/v/1.0.2) |
| has-symbols | 1.1.0 | MIT | package.json (https://www.npmjs.com/package/has-symbols/v/1.1.0) |
| has-tostringtag | 1.0.2 | MIT | package.json (https://www.npmjs.com/package/has-tostringtag/v/1.0.2) |
| hasown | 2.0.2 | MIT | package.json (https://www.npmjs.com/package/hasown/v/2.0.2) |
| history | 4.10.1 | MIT | package.json (https://www.npmjs.com/package/history/v/4.10.1) |
| hoist-non-react-statics | 3.3.2 | BSD-3-Clause | package.json (https://www.npmjs.com/package/hoist-non-react-statics/v/3.3.2) |
| hyphenate-style-name | 1.1.0 | BSD-3-Clause | package.json (https://www.npmjs.com/package/hyphenate-style-name/v/1.1.0) |
| immutable | 3.8.3 | MIT | package.json (https://www.npmjs.com/package/immutable/v/3.8.3) |
| inline-style-prefixer | 2.0.5 | MIT | package.json (https://www.npmjs.com/package/inline-style-prefixer/v/2.0.5) |
| invariant | 2.2.4 | MIT | package.json (https://www.npmjs.com/package/invariant/v/2.2.4) |
| is-absolute | 1.0.0 | MIT | package.json (https://www.npmjs.com/package/is-absolute/v/1.0.0) |
| is-arguments | 1.2.0 | MIT | package.json (https://www.npmjs.com/package/is-arguments/v/1.2.0) |
| is-callable | 1.2.7 | MIT | package.json (https://www.npmjs.com/package/is-callable/v/1.2.7) |
| is-date-object | 1.1.0 | MIT | package.json (https://www.npmjs.com/package/is-date-object/v/1.1.0) |
| is-regex | 1.2.1 | MIT | package.json (https://www.npmjs.com/package/is-regex/v/1.2.1) |
| is-relative | 1.0.0 | MIT | package.json (https://www.npmjs.com/package/is-relative/v/1.0.0) |
| is-string | 1.1.1 | MIT | package.json (https://www.npmjs.com/package/is-string/v/1.1.1) |
| is-symbol | 1.1.1 | MIT | package.json (https://www.npmjs.com/package/is-symbol/v/1.1.1) |
| is-unc-path | 1.0.0 | MIT | package.json (https://www.npmjs.com/package/is-unc-path/v/1.0.0) |
| is-what | 3.14.1 | MIT | package.json (https://www.npmjs.com/package/is-what/v/3.14.1) |
| is-windows | 1.0.2 | MIT | package.json (https://www.npmjs.com/package/is-windows/v/1.0.2) |
| linkify-it | 2.2.0 | MIT | package.json (https://www.npmjs.com/package/linkify-it/v/2.2.0) |
| lodash | 4.17.23 | MIT | package.json (https://www.npmjs.com/package/lodash/v/4.17.23) |
| lodash-es | 4.17.23 | MIT | package.json (https://www.npmjs.com/package/lodash-es/v/4.17.23) |
| lodash._getnative | 3.9.1 | MIT | package.json (https://www.npmjs.com/package/lodash._getnative/v/3.9.1) |
| lodash.get | 4.4.2 | MIT | package.json (https://www.npmjs.com/package/lodash.get/v/4.4.2) |
| lodash.isarguments | 3.1.0 | MIT | package.json (https://www.npmjs.com/package/lodash.isarguments/v/3.1.0) |
| lodash.isarray | 3.0.4 | MIT | package.json (https://www.npmjs.com/package/lodash.isarray/v/3.0.4) |
| lodash.isequal | 4.5.0 | MIT | package.json (https://www.npmjs.com/package/lodash.isequal/v/4.5.0) |
| lodash.isequalwith | 4.4.0 | MIT | package.json (https://www.npmjs.com/package/lodash.isequalwith/v/4.4.0) |
| lodash.keys | 3.1.2 | MIT | package.json (https://www.npmjs.com/package/lodash.keys/v/3.1.2) |
| map-cache | 0.2.2 | MIT | package.json (https://www.npmjs.com/package/map-cache/v/0.2.2) |
| math-intrinsics | 1.1.0 | MIT | package.json (https://www.npmjs.com/package/math-intrinsics/v/1.1.0) |
| memoize-one | 5.2.1 | MIT | package.json (https://www.npmjs.com/package/memoize-one/v/5.2.1) |
| merge-anything | 2.4.4 | MIT | package.json (https://www.npmjs.com/package/merge-anything/v/2.4.4) |
| object-assign | 4.1.1 | MIT | package.json (https://www.npmjs.com/package/object-assign/v/4.1.1) |
| object-is | 1.1.6 | MIT | package.json (https://www.npmjs.com/package/object-is/v/1.1.6) |
| object-keys | 1.1.1 | MIT | package.json (https://www.npmjs.com/package/object-keys/v/1.1.1) |
| parse-filepath | 1.0.2 | MIT | package.json (https://www.npmjs.com/package/parse-filepath/v/1.0.2) |
| path-browserify | 0.0.1 | MIT | package.json (https://www.npmjs.com/package/path-browserify/v/0.0.1) |
| path-root | 0.1.1 | MIT | package.json (https://www.npmjs.com/package/path-root/v/0.1.1) |
| path-root-regex | 0.1.2 | MIT | package.json (https://www.npmjs.com/package/path-root-regex/v/0.1.2) |
| path-to-regexp | 1.9.0 | MIT | package.json (https://www.npmjs.com/package/path-to-regexp/v/1.9.0) |
| process | 0.11.10 | MIT | package.json (https://www.npmjs.com/package/process/v/0.11.10) |
| promise | 8.0.1 | MIT | package.json (https://www.npmjs.com/package/promise/v/8.0.1) |
| prop-types | 15.8.1 | MIT | package.json (https://www.npmjs.com/package/prop-types/v/15.8.1) |
| radium | 0.19.6 | MIT | package.json (https://www.npmjs.com/package/radium/v/0.19.6) |
| react | 16.14.0 | MIT | package.json (https://www.npmjs.com/package/react/v/16.14.0) |
| react-ace | 9.5.0 | MIT | package.json (https://www.npmjs.com/package/react-ace/v/9.5.0) |
| react-audio-player | 0.17.0 | MIT | package.json (https://www.npmjs.com/package/react-audio-player/v/0.17.0) |
| react-dom | 16.14.0 | MIT | package.json (https://www.npmjs.com/package/react-dom/v/16.14.0) |
| react-is | 16.13.1 | MIT | package.json (https://www.npmjs.com/package/react-is/v/16.13.1) |
| react-lifecycles-compat | 3.0.4 | MIT | package.json (https://www.npmjs.com/package/react-lifecycles-compat/v/3.0.4) |
| react-linkify | 0.2.2 | MIT | package.json (https://www.npmjs.com/package/react-linkify/v/0.2.2) |
| react-modal | 3.16.3 | MIT | package.json (https://www.npmjs.com/package/react-modal/v/3.16.3) |
| react-redux | 6.0.1 | MIT | package.json (https://www.npmjs.com/package/react-redux/v/6.0.1) |
| react-router | 5.3.4 | MIT | package.json (https://www.npmjs.com/package/react-router/v/5.3.4) |
| react-scripts | 1.0.17 | MIT | package.json (https://www.npmjs.com/package/react-scripts/v/1.0.17) |
| react-spinners-kit | 1.9.1 | MIT | package.json (https://www.npmjs.com/package/react-spinners-kit/v/1.9.1) |
| react-split-pane | 0.1.92 | MIT | package.json (https://www.npmjs.com/package/react-split-pane/v/0.1.92) |
| react-style-proptype | 3.2.2 | MIT | package.json (https://www.npmjs.com/package/react-style-proptype/v/3.2.2) |
| react-tooltip | 3.11.6 | MIT | package.json (https://www.npmjs.com/package/react-tooltip/v/3.11.6) |
| react-transition-group | 2.9.0 | BSD-3-Clause | package.json (https://www.npmjs.com/package/react-transition-group/v/2.9.0) |
| react-treebeard | 2.1.0 | MIT | package.json (https://www.npmjs.com/package/react-treebeard/v/2.1.0) |
| reactjs-popup | 1.5.0 | MIT | package.json (https://www.npmjs.com/package/reactjs-popup/v/1.5.0) |
| redux | 3.7.2 | MIT | package.json (https://www.npmjs.com/package/redux/v/3.7.2) |
| redux-thunk | 2.4.2 | MIT | package.json (https://www.npmjs.com/package/redux-thunk/v/2.4.2) |
| regexp.prototype.flags | 1.5.4 | MIT | package.json (https://www.npmjs.com/package/regexp.prototype.flags/v/1.5.4) |
| reselect | 3.0.1 | MIT | package.json (https://www.npmjs.com/package/reselect/v/3.0.1) |
| resolve-pathname | 3.0.0 | MIT | package.json (https://www.npmjs.com/package/resolve-pathname/v/3.0.0) |
| safe-regex-test | 1.1.0 | MIT | package.json (https://www.npmjs.com/package/safe-regex-test/v/1.1.0) |
| scheduler | 0.19.1 | MIT | package.json (https://www.npmjs.com/package/scheduler/v/0.19.1) |
| set-function-length | 1.2.2 | MIT | package.json (https://www.npmjs.com/package/set-function-length/v/1.2.2) |
| set-function-name | 2.0.2 | MIT | package.json (https://www.npmjs.com/package/set-function-name/v/2.0.2) |
| string.prototype.trim | 1.2.10 | MIT | package.json (https://www.npmjs.com/package/string.prototype.trim/v/1.2.10) |
| styled-components | 4.4.1 | MIT | package.json (https://www.npmjs.com/package/styled-components/v/4.4.1) |
| stylis | 3.5.4 | MIT | package.json (https://www.npmjs.com/package/stylis/v/3.5.4) |
| stylis-rule-sheet | 0.0.10 | MIT | package.json (https://www.npmjs.com/package/stylis-rule-sheet/v/0.0.10) |
| symbol-observable | 1.2.0 | MIT | package.json (https://www.npmjs.com/package/symbol-observable/v/1.2.0) |
| tiny-invariant | 1.3.3 | MIT | package.json (https://www.npmjs.com/package/tiny-invariant/v/1.3.3) |
| tlds | 1.261.0 | MIT | package.json (https://www.npmjs.com/package/tlds/v/1.261.0) |
| uc.micro | 1.0.6 | MIT | package.json (https://www.npmjs.com/package/uc.micro/v/1.0.6) |
| unc-path-regex | 0.1.2 | MIT | package.json (https://www.npmjs.com/package/unc-path-regex/v/0.1.2) |
| value-equal | 1.0.1 | MIT | package.json (https://www.npmjs.com/package/value-equal/v/1.0.1) |
| velocity-animate | 1.5.2 | MIT | package.json (https://www.npmjs.com/package/velocity-animate/v/1.5.2) |
| velocity-react | 1.4.3 | MIT | package.json (https://www.npmjs.com/package/velocity-react/v/1.4.3) |
| warning | 4.0.3 | MIT | package.json (https://www.npmjs.com/package/warning/v/4.0.3) |
| whatwg-fetch | 2.0.3 | MIT | package.json (https://www.npmjs.com/package/whatwg-fetch/v/2.0.3) |

### Tools used only to build (not part of what is installed or redistributed)

| tool | version | license | note |
|---|---|---|---|
| node | 16.20.2 | MIT, with the licenses of its bundled parts (V8: BSD-3-Clause, OpenSSL: Apache-2.0, ICU, zlib, llhttp, c-ares, libuv and others: permissive, listed in the `LICENSE` file of the tarball, 34 entries) | `https://nodejs.org/dist/v16.20.2/`, SHA-256 checked; kept in the build folder, which is deleted after the build |
| yarn | 1.22.22 | BSD-2-Clause | run through `npx` |
| Go toolchain | 1.22 (Ubuntu `golang-go`) / 1.24.7 (used here) | BSD-3-Clause | |
| react-scripts (webpack, babel and the rest of the build chain) | 1.0.17 | MIT (the build chain has hundreds of further packages, installed in the build folder only; not collected) | its output is in the web app, see below |

### Needs attention for redistribution

- **GPL-3.0 compatibility.** Everything found is permissive (MIT, BSD-2/3-Clause, ISC, Apache-2.0) except one weak-copyleft module, so all of it can be combined with GPL-3.0 code. **Apache-2.0** (7 Go modules and `diff-match-patch` in the web app) is compatible with GPL-3.0 (not with GPL-2.0-only); maiden is GPL-3.0, so this holds here.
- **MPL-2.0: `github.com/hashicorp/hcl` v1.0.0** (pulled in by viper, for config files). File-level copyleft: if the files of that module are redistributed (source or inside the binary), the MPL-covered files must remain available in source under MPL-2.0, and modifications to them must be MPL-2.0. They are not modified here. Keep the link to the source in the notices.
- **Notices are not carried by the build.** MIT, BSD and Apache-2.0 require the copyright notice and license text to be kept with a redistribution (binary too). The Go binary does not contain them, and the minified web bundle has **no** license banners (searched: no `Copyright` or `@license` in `main.*.js`). A packaged build needs a notices file made from these tables and the license texts (the Mac port does this with `macos/licenses.py`, not used for Linux). Not built.
- **Apache-2.0 NOTICE files:** `gopkg.in/yaml.v2` has a `NOTICE`; the others were not checked for one. Include them in the notices.
- **Five bundled npm packages have no license file in their package** (`babel-runtime`, `classname`, `react-scripts`, `styled-components`, `stylis-rule-sheet`): the license is only the `license` field of `package.json` (MIT, ISC for `classname`), so the exact copyright holder lines would have to come from their repositories.
- **Dual or composite licenses:** `github.com/emirpasic/gods` (BSD-2-Clause with an ISC part) and `gopkg.in/yaml.v2` (Apache-2.0 with the MIT-licensed libyaml port): both texts must be kept.
- **maiden's own artwork** (`maiden_16/32/96.png`, `manifest.json`): covered by maiden's GPL-3.0 repository, nothing separate was found; not checked image by image. The web app loads no web fonts or other external resources from `public/` (the build output has only those files).

### What could not be determined

- **Transitive npm packages that are not bundled but are in the build folder** (the build chain, hundreds of packages): not collected, because they are not part of what is installed. A different build chain would change the answer.
- **Go modules for other platforms** (the list is for linux/amd64; another architecture may link a few more `x/sys`-style files from the same modules, not new modules as far as `go list` shows for amd64 only; arm64 was not run).
- **Patent and trademark terms**, export rules, and the exact copyright holder lines: not read module by module; the license **type** is what is listed.
- **Whether every license text matched was the complete one** (a module may carry a second license in a subfolder): only the top-level license files were read, apart from the two noted.
- **Licenses of the other (non-maiden) rows above** are Ubuntu's package licenses as stated in this file, not re-checked here.
