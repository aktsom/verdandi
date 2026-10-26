# Phase 4 (maiden): the web editor and script catalog on Linux

## Result: decisions taken and what was built

The owner decided (the plan below is unchanged; this is the outcome):
1. maiden is built by default in `linux/setup-deps.sh` and `linux/build.sh`; `NORNS_NO_MAIDEN=1` skips it. Done: `linux/maiden-build.sh` (also run on its own).
2. Browser-origin protection: an Origin check in `ws-wrapper` and Host/Origin checks in the maiden patch, loopback-aware; `macos/` and the Mac port untouched; the same exposure on the Mac written to `KNOWN-ISSUES.md` item 10.
   The exposure was reproduced first (`maiden-exposure-evidence.md`, the failing run is `known-issues-logs/maiden-before.txt`), then fixed. `ws-wrapper/src/main.c` is shared code: the check is **off unless `WS_WRAPPER_ALLOWED_ORIGINS` is set**,
   and `macos/norns.sh` does not set it, so the Mac behaves as before (the code path is not reached; the Mac build was not run here).
3. maiden's systemd unit API and restart commands are off on Linux (`linux/patches/maiden-linux-guard-and-units.patch`): they answer 404 "not available in Verdandi", maiden does not open a D-Bus connection.
4. The MAIDEN button opens the page when something answers on maiden's port, else the window shows "maiden is not running, see log" for a few seconds. The edit is in the shared `matron/src/platform/macos/sdl_bridge.cc`,
   inside `#ifdef NORNS_LINUX_DESKTOP`; the Mac code path is the line it had.
5. to 9., by the recommendations in the plan: port 5000 with `NORNS_MAIDEN_PORT` and a message (done); pinned commit, versions, lockfiles and a checked node archive, no vendored caches (done);
   the catalog as on the Mac, from maiden's own sources at run time (done, checked once by hand against the real source: base.json and community.json were downloaded); item 8 needs nothing; **item 9 (the MANUAL button has no manual on Linux) was not done**: it is independent and
   would copy a file from `macos/manual`, which the owner said to leave alone. Open, listed in STATUS.md.

Not as planned: go-git does not support a `file://` git URL (maiden treats a `file:` URL as a zip path), so the automatic install test uses zip archives; the **git route was tried once by hand** over the network
(`POST .../project/install?url=https://github.com/tehn/awake`: installed `dust/code/awake`), and is not in the suite (needs the network).
Versions seen in this container: Go 1.24.7 (Ubuntu 24.04's apt `golang-go` is 1.22: **not tried**), node 16.20.2, yarn 1.22.22. The clean-user build was run as uid 65534 with `/usr/bin/python` masked, in this container, not in a fresh Ubuntu 24.04 image.

Tests (all in `run_all.sh`): `maiden_test.sh` (24 checks: binds, editor API, install, REPL origin, Host/Origin, unit API), `maiden_launcher_test.sh` (real norns: loopback only, LAN refused, REPL answers maiden's page and refuses another site, port taken, maiden not built, stops with norns),
`maiden_install_test.sh` (install a zip, norns runs it; a script with an ARM plug-in installs, is reported, nothing moved), `maiden_button_test.sh` (stub xdg-open; the note and its disappearance).

# The plan as written before the decisions

Status: **investigation and plan only. Nothing is built or changed by this note.** It covers the maiden item of
`PLAN.md` Phase 4. What was read: the Mac port (`macos/setup-deps.sh`, `macos/norns.sh`, `macos/app-launcher.sh`,
`macos/make-app.sh`, `macos/patches/maiden-host-flag.patch`, `readme-macos.md`, `sdl_bridge.cc`, `menu.lua`), this
repo's `linux/` scripts, `ws-wrapper/`, and the maiden source at the commit the Mac port pins
(`2e64f7d59284962ac68055dd556e3fd8515462f8`, cloned for reading only). Nothing from maiden was compiled here, so
every "builds" below is a prediction, marked as such, to be proved by step 1.

## 1. How the Mac port does it

Pieces (all of them are upstream maiden except the patch and the launcher lines):

| piece | what it is | where it comes from |
|---|---|---|
| `maiden` | one Go binary (gin web server, go-git, cobra). Serves the web app at `/maiden`, the manual at `/doc`, and a REST API at `/api/v1` to list, read, write, rename and delete files under dust, to read catalogs, and to install, update and delete projects (scripts). | `go build` of `monome/maiden` at the pinned commit |
| web app | React app (react-scripts 1.0.17), built to static files `web/build`. | `yarn build` with **node v16.20.2**, `yarn@1.22.22` |
| REPLs | not part of maiden's server. The browser opens two websockets **straight to** `ws://<page host>:5555` (matron) and `:5556` (sclang). The ports are fixed in `web/public/repl-endpoints.json`; only the host name is taken from the page. | `ws-wrapper` (this repo, `ws-wrapper/`), started by `norns.sh` around `norns` and `sclang -i maiden` |
| `maiden-repl` | the terminal client of the same websockets. Source is in this repo (`maiden-repl/`). Independent of the web app. | waf build (already built on Linux) |
| `maiden-host-flag.patch` | adds `--host` to `maiden server`. Stock maiden calls `net.Listen("tcp", ":5000")` (all interfaces); the patch makes it `host:port`, default still all interfaces. | `macos/patches/`, applied by `git apply` in `setup-deps.sh` |
| catalog sources | `maiden/sources/*.json` (list of where the community catalog comes from), copied to `<home>/dust/data/sources/` on first start (what the device's `tool/project-setup.sh` does). `maiden.yaml` points at `$HOME/dust/data/{sources,catalogs}` and `$HOME/dust/code`. | repo contents at the pinned commit |

Build on the Mac (`macos/setup-deps.sh`, "== maiden" block): download node 16 (arm64 tarball, checked against
`SHASUMS256.txt`) into the sources folder, clone maiden at the pinned commit (`clone_at`, shallow), apply the patch,
`GOFLAGS=-mod=mod go build -trimpath -o maiden .` (Go from Homebrew), `yarn install --frozen-lockfile` and `yarn build` in
`web/` with node 16 first on `PATH`, then copy `maiden`, `maiden.yaml`, `web/build` and `sources/*.json` to
`<norns home>/maiden/{,app/build,dist/sources}`. It is skipped when `<home>/maiden/maiden` exists. `make-app.sh` copies
that folder into the `.app` (without `*.map`).

Launch (`macos/norns.sh`): if `$NORNS_MAIDEN/maiden` (default `<home>/maiden`) is executable, it seeds `dust/data/sources` on the
first start, then runs in the background

```
./maiden server --host 127.0.0.1 --port 5000 --app ./app/build --data <home>/dust --doc <home>/norns/doc
```

with output in `<home>/maiden.log`, and prints `maiden at http://127.0.0.1:5000/maiden`. The app launcher sets
`NORNS_MAIDEN` to the copy inside the bundle. `HOME` is the norns home, so maiden's `$HOME/dust` is the same dust the
script sees.

**The MAIDEN button.** In `sdl_bridge.cc` (shared by the Mac and Linux windows) `button_action(SKIN_MAIDEN)` calls
`shell_open_url("http://127.0.0.1:5000/maiden")`. The URL is hard-coded in C. It does not check that anything
listens. On the Mac this opens the default browser (`macos_open_url`); on this Linux build the same call maps to
`xdg-open` (`open_url.c`), so **today the button works as far as opening the browser, and the browser then shows
"connection refused" because no maiden runs on Linux** (the launcher prints no maiden line; `RUN-ON-LAPTOP.md` says so).
MANUAL does not depend on it (`NORNS_MANUAL`, unset on Linux unless a manual is provided, so it does nothing there; a separate
small item, listed in the decisions).

## 2. What Linux needs

**Toolchain.**

- **Go.** maiden's `go.mod` says `go 1.12`; the pinned dependencies are old (gin 1.7.7, go-git 5.2.0) but plain Go. Ubuntu 24.04's `golang-go`
  is 1.22, which should build it with `-mod=mod` as on the Mac (Mac uses current Homebrew Go). *Prediction, to prove in step 1.* Needs
  network at build time to `proxy.golang.org` (reachable from this container). Recommendation: apt `golang-go` (no download,
  no checksum to maintain), build under the repo's own build dir, not in `$HOME/go`: set `GOPATH`/`GOMODCACHE`/`GOCACHE` to a folder under `.deps`
  so the build does not write into the owner's home.
- **node 16.20.2** for the web app only (react-scripts 1.x does not run on current node without hacks). The Mac port downloads the official linux-x64 tarball
  from nodejs.org, checks it against `SHASUMS256.txt`, and keeps it in a private folder; same here (`node-v16.20.2-linux-x64.tar.xz`;
  nodejs.org and registry.npmjs.org are reachable from this container). It is **not** installed system-wide, so it does not collide with a node the owner already has. `yarn` is run via
  `npx -y yarn@1.22.22` exactly as on the Mac, so no `python` and no global npm install is needed. (node-gyp is only needed by
  native npm modules; `macaddress` has none that must compile, and the Mac build shows the lockfile installs without it. To be confirmed on Linux.)
- Already present from the existing deps: `git`, `curl`, `ca-certificates`, `python3`. No `python` command is used by anything above.

**Sources.** maiden: `git fetch --depth 1` of the pinned commit from GitHub (the `clone_at` helper of the Mac script, copied into `linux/`); the
patch is copied from `macos/patches/` or, better, moved to a shared `patches/` folder in a later cleanup (do not touch `macos/` now;
point `linux/setup-deps.sh` at `macos/patches/maiden-host-flag.patch`, one copy, so a fix applies to both). Web dependencies: npm registry via the lockfile. Go modules: proxy.golang.org.
`go.sum` is what pins them; the Mac script's `GOFLAGS=-mod=mod` may update `go.sum` and `go.mod` in the clone, which is harmless (the clone is thrown away), but
the owner should know that "reproducible" here means: same commit, same lockfiles, same major tool versions, not bit-identical binaries (see decision 6).

**Where it goes (as non-root, no `python`).**

- `linux/setup-deps.sh` keeps doing the system part with sudo (apt: add `golang-go`; **nothing else** needs root). The maiden build is a separate section
  that runs as the normal user (like waf in `~/.local/share/waf`), skipped when `<home>/maiden/maiden` exists, so a rerun is cheap.
- Build output goes to `<norns home>/maiden/` (same layout as the Mac: `maiden`, `maiden.yaml`, `app/build/`, `dist/sources/`), which is not in the repo, so the repo stays clean.
  `linux/build.sh` stays "compile norns"; it does not build maiden (it would need the network and take minutes). It only prints a hint if maiden is missing.
  An opt-out `NORNS_NO_MAIDEN=1` for setup-deps.sh (headless CI, or an owner who does not want node on the machine).
- `linux/norns.sh` gets the Mac's block (seed sources on first start, start `maiden server --host 127.0.0.1 ...`, log in `<home>/maiden.log`, print the URL),
  with the PID in the `PIDS` list so the existing cleanup stops it, and restarts of norns do not restart it (as on the Mac).

**Data and installs.** Scripts installed from the catalog go to `<home>/dust/code/<name>/` (what `/home/we/dust/code/...` means to a script, via virtual_home), catalogs to `<home>/dust/data/catalogs/`,
sources to `<home>/dust/data/sources/`. The editor reads and writes anything under `<home>/dust` (audio, data, code), nothing outside. maiden writes downloaded zip archives to `/tmp`
(`downloadURL`), which is fine on Linux.

**Port.** The usual port is **5000** (norns device, and the Mac port's URL). On Linux 5000 is used by some common things (docker registry, Flask dev servers, and UPnP on some
distros), so: default 5000, overridable with `NORNS_MAIDEN_PORT`, and the launcher checks that the port is free before starting and says which port it took (or that it could not).
The **button** needs the port too: it is hard-coded in the shared C file, so Linux needs it passed through an env var that the shared code reads (a small guarded edit
to `sdl_bridge.cc`/`menu.lua`, the Mac default stays 5000). The REPL ports 5555/5556 are fixed by the web app's `repl-endpoints.json` and are not configurable without editing that file in the build
(possible, not recommended).

## 3. Script install: what works and what does not

How maiden installs (from the source, not a guess): `POST /api/v1/catalog/<c>/install/<project>` and `POST /api/v1/project/install?url=...` call `dust.InstallProject`.
For a git URL that is `go-git PlainClone` with submodules into `dust/code/<name>`, for a `.zip` URL download-and-unzip. **maiden itself never runs a dependency step,
never calls `sudo` and never shells out.** (It uses no `git` binary, so a machine without git can still install.) Update is a go-git `Pull`. So the problems found earlier do not come
from maiden but from what happens **after**, when the script runs:

| situation | with maiden on Linux |
|---|---|
| plain Lua scripts, engines written in SuperCollider, samples (catalog categories A and B of `macos/docs/02-katalog-scan.md`: 318 of 351) | work. Install = clone; run from the norns menu, or `;restart` / `norns.script.load` from the maiden REPL. |
| script's own dependency step in Lua (e.g. the `lib/installer` library, or `os.execute("wget ... && unzip ...")`) | runs inside norns, not maiden, so it goes through the shims and `system_cmd` as before (KNOWN-ISSUES 8). `wget`/`unzip`/`apt` shims are still not built. `curl`-based steps work; `wget` only if installed; `apt-get` fails (no sudo password, `sudo -n`). |
| prebuilt **ARM** `.so` UGen bundles (`PortedPlugins-RaspberryPi.zip` and similar, about 71 scripts) | the download works, the plugins **do not load** on x86_64. `plugin_arch_check` reports the bad file before sclang starts, SuperCollider still fails on it. Installing from maiden does not change that. Needs the x86_64 bundles (open decision) or quarantine of the bad files (open decision). |
| `sudo systemctl restart norns-*` in a script | handled by the shim: becomes norns' restart request. Not maiden's concern. |
| maiden's own "restart" buttons (`/api/v1/unit/<name>?do=restart`) | maiden asks **systemd over the system D-Bus**. On a Linux desktop with systemd the connection succeeds, the units `norns-*.service` do not exist, so it answers with an error, as the Mac does (no D-Bus, 503). It cannot restart or stop anything real: the system bus asks for authorization for system units and unprivileged calls are refused, but this should be **tested, not assumed** (step 6). Recommendation: also disable the unit API in the Linux copy (a second small patch next to the host-flag patch), because it can never do anything useful here. |
| scripts needing a native build (`make`, 20 in the catalog) | not run by maiden; same as without maiden. |
| scripts that need absolute device paths other than `/home/we` | same virtual_home rules as now. |

Net: maiden adds browsing, install, update and editing for the 318 pure-Lua/SC scripts at once; for the 71 with ARM plugins it makes the failure easier to reach (one click),
so the plugin check and README line matter more once maiden exists. A good, cheap addition: maiden's own REPL shows the sclang output, where the check's message is also printed (verify in step 5).

## 4. Security

Facts checked in the source and the Mac launcher:

- **maiden's HTTP server** binds `:port` (all interfaces) unless `--host` is given. With the patch and `--host 127.0.0.1` it listens on the loopback only. The launcher line is the
  entire protection: there is no password, no token, no Origin check, no Host check anywhere in maiden. The test in step 4 asserts the bind address from `ss -ltn`, and a request
  to the machine's LAN address is refused.
- **The REPL websockets** (5555 matron, 5556 sclang) are bound by `ws-wrapper` to the URL the launcher gives it: `ws://127.0.0.1:5555`. Already loopback-only in both `linux/norns.sh` and `macos/norns.sh`. Same assertion in the test.
- **What a program on the same machine can do through them.** Anything the user can. matron's REPL runs Lua (`os.execute`, `io.open`, `norns.system_cmd`), sclang's runs SuperCollider code (`"cmd".unixCmd`), and maiden's
  file API writes, renames and deletes any file under `<home>/dust` (and, if a script is written there, the next norns start runs it). The REPLs are not sandboxed and not authenticated, **on the device too**. This is by design.
- **What a web page in the owner's browser can do (not just local programs).** This is the real exposure of the localhost design and it is **not covered by the Mac port's `--host` fix**:
  1. *WebSocket from any website.* Browsers allow any page to open `ws://127.0.0.1:5555`. WebSockets are not blocked by the same-origin policy, and `ws-wrapper`'s nng listener does not check the `Origin` header
     (read the source: no origin handling). A malicious page could therefore send Lua or SuperCollider to the REPL: **remote code execution as the user, from a web page, while norns is running.**
     *This is a prediction from the code and must be proved by a test (step 4), not asserted.*
  2. *Simple cross-site requests to maiden.* A page can send a `POST` without preflight, e.g. `/api/v1/project/install?url=https://...` (clone a repository into `dust/code`; not executed until run, but then it is on the owner's disk and in the script list), or `.../install?url=file:///...` (maiden treats a `file` URL
     as a local zip path). PUT/PATCH/DELETE need a preflight which maiden does not answer, so the browser blocks them.
  3. *DNS rebinding.* maiden does not check the `Host` header, so a rebinding attack can make the browser treat `evil.example` as `127.0.0.1:5000` and read or write dust through the file API.
  Items 1 and 3 are the ones that matter. The same applies to the Mac app today (the owner may want to know that for the Mac as well; I did not change anything there).
- **Mitigations available, from small to large** (decision 3): (a) in `ws-wrapper`, reject WebSocket upgrades whose `Origin` is not absent or `http://127.0.0.1:<maiden port>` / `http://localhost:<port>` (nng has an HTTP-level hook for this; the code is ours, GPL, small, and testable headless with a raw handshake);
  (b) in the maiden patch, a middleware that rejects requests whose `Host` is not `127.0.0.1:<port>` or `localhost:<port>` and whose `Origin` is present and foreign (stops 2 and 3); (c) a random per-session token in the URL
  the button opens, required by both (more change, breaks the plain bookmark `http://127.0.0.1:5000/maiden`); (d) do nothing and document it. Recommendation: **(a) and (b)**, both are small, neither breaks the normal use, and both are
  headlessly testable. (a) also protects `--terminal`-less use without maiden at all, since the REPL ports are open whenever norns runs without `--terminal`, today, on this Linux build. That makes it worth doing even if maiden is never built.

## 5. Plan, with tests

Each step: tests first where code is involved, commit and push small, STATUS.md updated. Steps 1 to 3 need no change to norns itself.

1. **Prove the build (no norns change).** In a clean Ubuntu 24.04 container, as a non-root user with sudo and without `python`: apt `golang-go`, node 16 tarball with checksum, clone at the commit, patch, `go build`, `yarn install --frozen-lockfile`, `yarn build`. Record
   versions, times, sizes, and whether `go.sum` changed. *Headless test:* `maiden version`, `maiden server --host 127.0.0.1 --port 15000 --app ... --data <tmp>` and `curl` `/maiden/` (200), `/api/v1` (JSON), `/api/v1/dust` (lists the temp dir), a PUT of a file and a read back. Needs the network (Go proxy, npm); if a package vanished the failure is the finding.
2. **`linux/setup-deps.sh`: the maiden section** (run as the normal user, skip when built, `NORNS_NO_MAIDEN=1`, license listed in `DEPS.md`: maiden is GPL-3.0, node MIT, the Go and npm packages' licenses to be collected the way `macos/licenses.py` does it for the Mac; list them, do not fetch silently).
   *Test:* the same clean-container run as the earlier setup-deps bug reports (non-root, no `python`), idempotent second run.
3. **`linux/norns.sh`: start maiden** on 127.0.0.1 only, port from `NORNS_MAIDEN_PORT` (default 5000), port-in-use check, seeded sources, log, PID cleanup, URL line. *Tests (in `run_all.sh`, using the headless boot):* `ss -ltn` shows 5000, 5555, 5556 on `127.0.0.1` only (and nothing on `0.0.0.0`/`::`); `curl http://127.0.0.1:5000/maiden/` is 200; the LAN address refuses; a second run with 5000 taken picks the message and does not kill the first; stopping norns stops maiden; norns without maiden built still boots (no regression).
4. **Browser-origin protection** (decision 3). Tests first: a raw WebSocket handshake to 5555 with `Origin: http://evil.example` is refused (and one without Origin or with the maiden origin works); `curl -H 'Host: evil.example'` to maiden is refused; a `POST` with a foreign `Origin` is refused. Write the tests first: they should **fail** on stock behavior, which proves the exposure in section 4 on this machine.
5. **Script install through maiden, headless.** A local bare git repository with a tiny script (no network, `file://` URL, which is what the upstream tests do), installed through the API, then loaded by norns via the existing `norns_probe.sh`. A zip variant. The catalog update against the real source is **not** in the automatic suite (network), only run once by hand and recorded. With an ARM-plugin fixture (a fake `.so` of the wrong ELF class, already in the plugin-check test) installed through the API: `plugin_arch_check` still reports it, nothing crashes.
6. **Unit API.** Test `GET /api/v1/unit/norns-main.service?do=restart` on a system with a system D-Bus (the container has `dbus`): expect an error, no effect. Then decide on the second patch.
7. **The MAIDEN button.** Pass the port by env (guarded edit of shared code, Mac default unchanged; the existing screen/menu scenarios and the C tests must still pass; the Mac build is the owner's check as before). *Headless test:* click the button in the Xvfb scenario with a fake `xdg-open` in `PATH` that records its argument: it must be `http://127.0.0.1:<port>/maiden`. When maiden is not running the button could instead show a short notice in the window (decision 5).
8. **Docs and packaging:** `RUN-ON-LAPTOP.md` (how to open maiden; the ARM plugin warning; where scripts go), `HARDWARE-CHECKLIST.md`, `DEPS.md`, `STATUS.md`. The AppImage/Flatpak decision (gate B) decides how `<home>/maiden` is bundled (read-only inside the package, as the Mac does inside the `.app`).

**Cannot be tested without the owner's laptop:** that the real default browser opens from the button and renders the web app (Xvfb has no browser worth the name; a headless Chromium is available here via Playwright
and can render the page and use the REPL websocket, which is a good approximation but is not the owner's browser); the whole catalog install against GitHub from the owner's network; installing and running real scripts with real audio; the
cross-site attack in the owner's actual browser (Playwright/Chromium here can show the Origin behavior, Firefox is not available here); behavior of port 5000 on the owner's machine; the editor in a browser while Reaper has the card.

**Decisions for the owner**

1. Build maiden on Linux at all, in `linux/setup-deps.sh` (node 16 and Go as above, about a few hundred MB of caches), default on with `NORNS_NO_MAIDEN=1` as opt-out? Recommendation: yes.
2. Go from apt (`golang-go` 1.22) or the official tarball? Recommendation: apt.
3. Browser-origin protection: (a) ws-wrapper Origin check and (b) a Host/Origin check in the maiden patch (recommended), only (a), the token variant, or nothing but a documented warning. Note that this also covers the Mac app; should the Mac get the same (shared code in `ws-wrapper`; the maiden patch is under `macos/`), or stay as it is? I would not touch `macos/` without your word.
4. The unit API (systemd) disabled in the Linux copy of maiden (recommended), or left alone?
5. Port: default 5000 with `NORNS_MAIDEN_PORT` and a clear message when taken (recommended). When maiden is not running, should the MAIDEN button open a browser tab with "connection refused" (today) or do nothing and say so in the window?
6. Reproducibility level: pinned commit, tool versions, lockfiles, checksum for node (recommended), or also vendoring a Go module cache and an npm offline cache in the repo (large, not recommended)?
7. The catalog: use maiden's own community catalog source (network at runtime, as the Mac does) or ship a snapshot? Recommendation: as the Mac.
8. Which of the open items it depends on to be useful for the 71 scripts with ARM plugins: x86_64 plugin bundles, quarantine of bad plugins, `wget`/`apt` shims. They are separate decisions listed in `STATUS.md`; maiden does not need them to be built, but they decide how good the experience is.
9. MANUAL on Linux has no manual file (`NORNS_MANUAL` is unset). Add one (the Mac's `macos/manual` adapted) or hide the button action? Small, independent.
