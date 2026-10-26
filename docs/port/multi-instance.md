# Several plug-in instances in one DAW project: investigation

Status: **investigation only. No product code was changed.** The measurements were made with scripts in a scratch folder outside the repository (copies in `docs/port/multi-instance/`, with the raw outputs). Everything below says whether it was **read** in the code, **measured** here, or only **expected**.

## Decisions taken by the owner (after this note)

1. **Option D now**: one plug-in instance at a time, with a clear message instead of silent corruption, built into the plug-in plan before any VST3 code exists, together with a **settable bridge port** and an **instance id in the protocol from the start**, so that option A can be added later without redoing the plug-in. Design: `docs/port/linux-vst3.md`.
2. **Option A is not wanted now.** It stays documented here as a future option, with the namespace measurement (section 3.3) and its limits: **Linux only; run as root in a container; not checked for ordinary users** (Ubuntu 24.04 may restrict unprivileged user namespaces); no real audio load or real-time behaviour measured; idle numbers only.
3. **`macos/` and the AUv3 are not touched**; the AUv3's silent-corruption problem is in `KNOWN-ISSUES.md` item 12.
4. **The first plug-in is a Linux VST3**, tested in Reaper on the owner's Linux Mint laptop (PipeWire); Windows follows later. `PLAN.md`: Phase 7 = Linux VST3, Phase 8 = Windows VST3.

## 0. The short answer

- **Today, two instances of the Mac AUv3 in one project do not work, and they fail silently.** There is one bridge on one fixed UDP port (10200); both plug-ins talk to it, it has one audio stream, so it mixes their audio into one stream and splits the answer between them (read from the code; not run, there is no macOS here).
- **Running several full norns instances at once is possible but nothing in norns is built for it.** Measured on Linux with four instances: each one needs about **0.46 GB of RAM and about 6.5 % of a core when idle, and 4.5 to 7 s to start**. They only coexist if each has its **own network namespace and private `/tmp` and `/dev/shm`** (which worked, with no change to norns); with different port blocks and homes alone **only one of them survived**, because at least four values are fixed in the code (crone's OSC port 9999, scsynth 57110, the sidecar's socket path `/tmp/norns-sidecar.ipc`, and the JACK client names).
- **My recommendation: do not build multi-instance now.** Build the **one-instance guard with a clear message** (option D) into the plug-in plan from the start, because today's silent corruption is the worst outcome. Treat "several scripts in one project" as a later, separate project (option A) that is real work (weeks, not days) and not plug and play on the first try. Options B and C do not deliver what the owner wants. Details and the smallest first step are in sections 4 and 5.

## 1. Today's behaviour (the Mac AUv3)

Read: `macos/auv3/NornsAU.mm`, `auv3_bridge.c`, `bridge_protocol.h`, `macos/norns.sh`, `macos/app-launcher.sh`, `macos/auv3/norns-au.entitlements`.

| question | answer | how I know |
|---|---|---|
| Who starts the bridge? | `macos/norns.sh` (`start_auv3`) starts **one** `auv3_bridge` next to norns, with Verdandi.app. The plug-in does **not** start norns or the bridge: "norns itself keeps running in its own window". | read |
| One bridge or two? | **One** process, one JACK client named `auv3` (ports `out_1/2`, `in_1/2`), one UDP socket bound to `127.0.0.1:10200` (`NB_PORT`; the bridge reads `NORNS_AUV3_PORT`). A second `norns.sh` is refused (`pgrep -x 'norns|Verdandi'`), so a second bridge cannot appear from the launcher. | read |
| Which port do the plug-ins use? | Both use the constant `NB_PORT` = 10200 **compiled into the plug-in** (`NornsAU.mm`: `addr.sin_port = htons(NB_PORT)`). The plug-in does **not** read `NORNS_AUV3_PORT`, so a plug-in cannot be pointed at another bridge. | read |
| What does each plug-in do? | `Bridge::start` (on `allocateRenderResources`) opens its own connected UDP socket (ephemeral local port) and a thread that sends 128-frame stereo blocks (`NB_AUDIO`), MIDI bytes (`NB_MIDI`) and, when it stops, one `NB_BYE`. It stays transparent (passes audio through) while no reply arrives for 0.5 s. | read |
| What does the bridge do with packets from two plug-ins? | It keeps **one** `adapter` and one `rate`, and answers each audio packet to the **sender's address** (`sendto(..., from)`). Both plug-ins therefore get answers and look connected, but the adapter is one stream: it is pushed alternately with block A, block B, and each answer is the next 128 frames of that one stream. | read |
| What would be heard? | norns' input is the two plug-ins' blocks interleaved (block by block), and each plug-in receives every other block of norns' one output. The expected result is chopped, mixed audio on both tracks. | **expected** (derived from the code, not run) |
| `NB_AUDIO` | audio block from the plug-in, answered with norns' output for the same `seq`. The bridge calls `deactivate()` + `activate()` when `sample_rate` differs from the last packet, so two projects/hosts at different rates would flip it back and forth. | read |
| `NB_MIDI` | raw MIDI bytes from any plug-in go to **one** CoreMIDI source "Verdandi AUv3" (client "Verdandi AUv3 bridge"): the two tracks' MIDI merge into one stream. | read |
| `NB_BYE` | from **either** plug-in: `deactivate()` for everybody (crone's audio connections go back to the interface, `usleep(100000)`, adapter destroyed). The other plug-in's next audio packet re-activates it. Also: 1 s without any packet deactivates. So removing or bypassing one plug-in interrupts the other for a moment. | read; the glitch is **expected** |
| Transport and tempo | The protocol has only `NB_AUDIO`, `NB_MIDI`, `NB_BYE`. **No tempo, no transport, no position** reach norns today, for one instance or several. (`PLAN.md` Phase 7 already plans a transport message.) | read |
| What does the Mac app do for several? | Nothing: one Verdandi.app, one norns home (`~/norns`, or `NORNS_USER_HOME`), one set of ports. The launcher refuses a second norns. | read |
| The plug-in's own state | `NornsAU.mm` keeps no state (`parameterTree` is empty, no `fullState`): a project stores nothing about the script. | read |

Not verified: anything on macOS (no Mac here), a DAW, real audio.

## 2. Inventory of what an instance owns

"Fixed" means: a value in the code that cannot be changed without editing the code. "Flag" means: a command-line or environment setting exists.

### 2.1 Network ports (all on 127.0.0.1 unless noted)

| port | what | where it is set | configurable? |
|---|---|---|---|
| UDP 8888 | matron's OSC in (events from crone/SuperCollider) | `matron/src/args.cc:19` (`loc_port`), flag `-l`; **SuperCollider sends to the constant** `Crone.txPort = 8888` in `sc/core/Crone.sc:14,30` | matron flag only. The SC side is fixed, so `-l` alone breaks the link (**expected** from the code; I did not measure it separately) |
| UDP 10111 | matron's OSC for scripts (`remote_port`) | `args.cc:21`, flag `-o` | flag |
| UDP 57120 | sclang's language port: where matron sends engine commands | sclang default; matron uses `args.cc:20` (`-e`, `oracle.cc:148`) **and** a second constant `OSC_CRONE_PORT "57120"` in `matron/src/osc.cc:23,41`; sclang flag `-u` changes its port | partly: the two matron places must agree with `-u` |
| UDP 9999 | crone's OSC in | `crone/src/OscInterface.cpp:39` (a `FIXME: should get port configs from program args`) **and** `sc/core/Crone.sc:29`; matron's side has `-c` (`args.cc:22`) | **fixed in crone and SC** |
| UDP 57110 | scsynth | SuperCollider's default; `Crone.sc:55` uses `Server.local` | fixed (no setting in norns' SC code) |
| TCP 5555 / 5556 | matron / sclang REPL websockets (`ws-wrapper`) | `linux/norns.sh:318,335` (URL given to `ws-wrapper`); **the maiden web app has them fixed** in `web/public/repl-endpoints.json` (`maiden_app_location:5555/5556`) | launcher yes; maiden's page only by serving another `repl-endpoints.json` |
| TCP 5000 | maiden | `NORNS_MAIDEN_PORT` (Linux launcher) | yes |
| UDP 10200 | plug-in bridge (Mac) | `bridge_protocol.h` `NB_PORT`; bridge `NORNS_AUV3_PORT` | bridge only (the plug-in side is compiled in) |
| mDNS | matron registers a DNS-SD service named `norns`, type `_osc._udp`, on its OSC port | `matron/src/osc.cc:38` | fixed name (the mDNS daemon renames duplicates; effect not tested) |
| Ableton Link | Link's own discovery and session | `matron/src/clocks/clock_link.cc` | not examined; several instances on one machine would find each other as Link peers (**expected**) |

### 2.2 JACK and MIDI names

| name | what | where | per instance? |
|---|---|---|---|
| `crone`, `softcut` | crone's two JACK clients (ports `crone:input_1..6`, `output_1..6`, `softcut:…`) | `crone/src/MixerClient.cpp:19`, `SoftcutClient.cpp:31` (`Client<…>("crone")`, `Client.h:98` opens it **without** an exact-name flag) | fixed. On a shared JACK server the second is renamed `crone-01` (**measured**: `unique name 'crone-01' assigned`, `'softcut-01'`, `'SuperCollider-01'`), and then the **fixed connect commands** in `sc/core/Crone.sc:80-84` (`jack_connect "crone:output_5" "SuperCollider:in_1"` and three more) wire the **first** instance's ports. |
| `SuperCollider` | scsynth's JACK client | SuperCollider (`SuperCollider:in_1…`) | fixed; renamed on a shared server |
| `matron-clock` | JACK client that reads the frame time | `matron/src/jack_client.cpp:33` | fixed |
| `Verdandi` (port `midi_in`) | JACK MIDI input (Linux) | `matron/src/platform/linux/jack_midi_in.cc:27,28` | fixed |
| `Verdandi ctl` | control client for the input routing | `matron/src/platform/linux/app_audio_linux.cc:130` | fixed |
| own-client list | SYS/APP never take these as "applications" | `crone/src/InputRoute.h:37`: `crone, softcut, SuperCollider, Verdandi, Verdandi ctl` | a renamed second instance (`crone-01`…) would **not** be in the list, so SYS of instance 1 would take instance 2 as an "application" (**expected** from the code) |
| ALSA sequencer client `Verdandi`, port `norns keys` | the virtual keyboard window's MIDI source | `matron/src/platform/linux/keys_midi.cc:34,35` | fixed (needs `/dev/snd/seq`: absent in the test container, so not exercised) |
| ALSA virtual rawmidi | upstream's virtual MIDI device | `matron/src/device/device_midi.cc:155` (`"virtual"`) | upstream; failed in the container (`/dev/snd/seq` missing), so not exercised |
| Mac: CoreMIDI `Verdandi AUv3` (client `Verdandi AUv3 bridge`), `norns keys` | | `auv3_bridge.c`, `sdl_bridge.cc` | fixed |
| the plug-in's JACK client `auv3` | | `auv3_bridge.c` | one per machine |

### 2.3 Files

| item | value | where | per instance? |
|---|---|---|---|
| norns home | `<home>/` (`NORNS_HOME`; Mac: `~/norns` or `NORNS_USER_HOME`); `HOME` is set to it while norns runs | `linux/norns.sh`, `macos/app-launcher.sh` | the **only** thing that is already one knob |
| `dust/code`, `dust/audio` | scripts and samples | the home | shared by design, but two instances running **the same script** would share its data folder |
| `dust/data/system.state`, `system.pset`, `dust/data/<script>/` | norns state and script data (psets, patterns) | `lua/core/state.lua:62,103`, `lua/core/script.lua` | one set per home; two instances in one home would overwrite each other |
| `audio.conf` | settings written by SYSTEM > AUDIO | home | per home |
| `.norns-input`, `.mic-off` | the kept input choice (MIC/SYS/APP/OFF) | `lua/core/menu.lua` | per home |
| `.vgrid-size` | the virtual grid size | `readme-macos.md` (`sdl_bridge.cc`) | per home |
| `.norns-restart`, `.norns-restart-audio`, `.norns-request-restart` | restart marks and the shim's request | `linux/norns.sh:305`, `matron/src/system_cmd.cc`, `linux/shims` | per home (good) |
| `.plugin-mismatch`, `disabled-plugins/` | the plug-in check's list and target | `linux/plugin_arch_check.cc` | per home |
| `norns.log`, `sclang.log`, `maiden.log`, `auv3_bridge.log` | logs | launchers | per home |
| `.config/SuperCollider/sclang_conf.yaml`, `.local/share/SuperCollider/Extensions` | SC configuration and extensions | `linux/norns.sh`, under `HOME` | per home (the extensions folder would be shared by symlink) |
| `maiden/` | the built maiden | `linux/maiden-build.sh` | one copy can serve many (static files + a binary), but see 2.4 |
| `/tmp/norns-sidecar.ipc` | the **sidecar's socket** (`ipc:///tmp/norns-sidecar.ipc`), the helper process that runs shell commands for matron | `norns/sidecar.cpp:25` | **fixed path**: a second instance's sidecar would not be able to listen on it while the first one holds it (**expected**; not measured separately; every instance has a `sidecar` process, see the lists below) |
| `/tmp/nornsgridXXXXXX` | the virtual grid's pty directory | `matron/src/platform/macos/vgrid_device.c:91` (`mkdtemp`) | unique per instance already |
| `/tmp/norns-update-status`, `…-progress` | the device's update page | `lua/core/menu/update.lua:7` | not on the desktop menu |
| `/tmp/maiden-*` | maiden's downloaded zips | maiden | unique names |
| JACK's `/dev/shm` segments and sockets | per JACK **server name** | jackd | per server name (works with `jackd -n`, **measured**) |
| lock or pid files | none found by searching the code; the only "lock" is `pgrep -x norns` in the launchers | `linux/norns.sh:196`, `macos/norns.sh:98` | see 2.5 |

### 2.4 Windows, devices, processes

- **The device window:** one SDL window titled "Verdandi" (plus separate windows for the virtual grid, arc and keys): one set per instance, nothing in the window says which instance it is.
- **A real grid or arc** can belong to **one** process: libmonome opens the serial port, and a second reader steals bytes (the serialosc case in `KNOWN-ISSUES.md` shows what that looks like). **crow** is the same (a serial port). **Real MIDI devices:** ALSA raw MIDI lets several processes read one device (each gets the data) and merges output; the DAW normally owns MIDI hardware and passes it to the plug-in, so this is a DAW decision. Not tested.
- **serialosc** (an external service) holds a grid's serial port for its own clients: unchanged by this question.
- **maiden:** one HTTP server (16 MB resident, **measured**) bound to one port, with `--data` pointing at one `dust` and two fixed console ports (above): one maiden is one norns.

### 2.5 The launcher's own state (found by reading)

- `pgrep -x norns` at the start of `linux/norns.sh` (and `pgrep -x 'norns|Verdandi'` on the Mac): a second launcher **refuses to start** ("norns is already running").
- `matron/src/system_cmd.cc:151-160`: SLEEP and RESTART run `pkill -TERM -x norns` (Linux) or `pkill -TERM -a -x 'norns|Verdandi'` (Mac): they signal **every process with that name**, so with several instances one instance's SLEEP or RESTART would stop **all** of them.
- The headless tests and a few shims also use `pkill` by name; irrelevant for users.

## 3. Measurements

All on this container (Ubuntu 24.04 x86_64, 4 cores, root, **no sound card**: jackd with the dummy driver, Xvfb, no PipeWire), with the real `build/norns/norns`, `sclang` and `scsynth`, **no script loaded**. Scripts, `docs/port/multi-instance/` (`inst.sh` starts one instance, `measure.py` starts N and reports, `lo_up.py`, `runall.sh`). The home of instance N is `…/homeN` with a link `norns` → the repository; nothing in the repository was changed.
CPU is the idle CPU over 20 s as a percentage of **one core**; memory is PSS (shared pages are shared out among the processes that map them). The jackd processes were **not** included (jackd detaches into its own session; with the dummy driver it is small, with a real driver it is the audio engine).

### 3.1 One instance

| | |
|---|---|
| start to ready (norns up and sclang has listed the engines) | **4.5 s** (twice) |
| idle CPU | **7.4 % of a core** (`norns` = matron + crone + softcut 6.2 %, scsynth 1.2 %, sclang 0.1 %) |
| memory (PSS) | **558 MB**: `norns` 304 MB, `sclang` 156 MB, `scsynth` 58 MB, two `QtWebEngineProc` 36 MB, `sidecar` 2 MB (`sandbox-1-per-process.txt`) |
| ports | UDP 8888, 9999, 10111 (norns), 57120 (sclang), 57110 and 57120 (scsynth shares sclang's socket) |
| JACK | clients `crone` (12 ports), `softcut` (4), `SuperCollider` (4), `Verdandi` (1), `system` |

### 3.2 Two and four, as the code is (different port blocks and homes, own JACK server names: `jack` mode; one shared server: `shared` mode)

Instance 1 keeps the default ports, the others get a block (`-l -e -o` for matron, `-u` for sclang; crone and scsynth have no flag). Started one after the other, each when the previous was ready.

| run | result |
|---|---|
| `shared` (one JACK server), 2 instances | instance 1 ready in 6.5 s. **Instance 2's `norns` process died at once**: `liblo error: 9904; cannot find free port` (crone's 9999 is taken). Its sclang kept running with no norns: `*** ERROR: failed to open UDP socket: address in use` (57110). Fixed names were never an issue here because crone never got that far. |
| `jack` (own server `jN` per instance), 2 instances | the same: instance 2 fails at crone's 9999. A separate JACK server per instance did **not** help. |
| `jack`, 4 instances | in the kept run one instance (the first) reached ready, after 100.6 s (an unexplained outlier, not investigated; the other runs took 4.5 to 7 s); **the other three died at port 9999** and left their `sclang` behind. In an earlier run **all four started at once and only one survived**: whichever crone bound 9999 first won, the rest died. So with parallel start (a project load) **which instance survives is a race**. |
| shared JACK server, instances started at once (first run; its output file was overwritten, the lines were read from the console) | `unique name 'crone-01' assigned`, `'softcut-01'`, `JackDriver: client name is 'SuperCollider-01'`, `Cannot connect to shared memory`, `address in use`: duplicate JACK names are renamed and everything is wired to the first instance. |

So the **hard clashes are**: crone's OSC port 9999, scsynth's 57110, matron's 8888 as used by SuperCollider, the sidecar's `/tmp` socket (not separately measured), and the JACK client names on a shared server. Flags exist for some of the **other** ports only.

### 3.3 Two and four, each in its own network and mount namespace (`unshare -n -m`, loopback up, a private `/tmp` and `/dev/shm`, the X socket shared): no clashes, no changes to norns

All instances use the **default** ports and names, in their own namespaces; each has its own jackd (dummy driver). All started at the same time:

| instances | start to ready | idle CPU (total, of one core) | memory (PSS, total) |
|---|---|---|---|
| 1 | 4.5 s | 7.4 % | 0.56 GB |
| 2 | 5.0 s (both) | 14.0 % (7.0 % each) | 0.99 GB (0.49 GB each) |
| 4 | 6.9 to 7.4 s | 25.9 % (6.4 to 6.5 % each) | **1.84 GB** (0.46 GB each) |

Every instance bound 8888, 9999, 10111 (norns), 57120 (sclang), 57110 (scsynth), and nothing failed (`sandbox-*.txt`). A first attempt with the loopback interface down failed (`_NetAddr_SendMsg` errors): my harness's error, fixed (`lo_up.py`).

What this shows: **the clashes are all in names and ports, not in the audio engine**: with separate name spaces four norns instances run side by side at a predictable cost. It does **not** show that this is a usable design: it needs namespaces (Linux only, see 4A), the idle cost is for norns with **no script and no audio load**, and I measured no real-time behaviour (xruns, latency) at all.

### 3.4 Not measured

Real audio load (a script with engines and softcut), real-time behaviour, a real sound card or PipeWire with several instances, the DAW, macOS, Windows, startup of four instances on a slower disk, `maiden` per instance beyond its idle 16 MB, `-l` with the SuperCollider side unmodified (expected to break), the sidecar clash on its own, SYS taking a renamed instance as an application, Ableton Link between instances, Linux unprivileged namespaces (I ran as root; **I believe Ubuntu 24.04 restricts unprivileged user namespaces by default through AppArmor, which would need a profile or a sandbox tool; not checked**).

## 4. Design options

Common to all: the plug-in is a thin client (the AUv3 today, the VST3 later) that talks UDP to a bridge next to norns (`PLAN.md` Phase 7: "mirror the AUv3 design").

### A) One norns process per plug-in instance, a per-instance id, a small supervisor

- **What it is:** each plug-in instance owns a full norns (matron+crone+softcut+sclang+scsynth+sidecar+maiden if wanted) in its own home, port block and JACK names, started and stopped by a **supervisor** (a small background program started by the first plug-in, or by the launcher) that the plug-in finds through a fixed rendezvous (one well-known socket) and asks "give me instance <id>".
- **Instance id and stability:** the plug-in creates a random id (UUID) when first created and stores it in its saved state (VST3 `getState/setState`, AU `fullState`); the DAW stores it in the project and returns it on reload and after a DAW restart. The port block, JACK names and window title are **not** derived from the id (a hash can collide with a port in use) but allocated by the supervisor at runtime (lowest free slot, probed with `bind`) and recorded; the **home folder** is keyed by the id (`instances/<uuid>/`). Hard case: **"duplicate track"** copies the state, so two live instances have the same id: the supervisor must notice and give the newcomer a new id and a **copy** of the home.
- **Project recall:** the plug-in state must carry the script name, the params (a pset) and what the script keeps in its own data folder (patterns, small files); samples stay referenced by path (as in any sampler, not portable). This needs a "save everything about this instance into a blob" and "restore it before the script starts" function in norns that does not exist (norns saves a pset to a file under `dust/data/<script>/`; scripts keep other state themselves, some only in memory, as on the device). Realistic for the params, partial for the rest.
- **Transport and clock:** independent of the number of instances but required for each: the bridge needs tempo/transport (Option C of `docs/port/clock-notes.md`, planned): the plug-in sends the host's tempo, play state and position; the simplest working path is the plug-in turning them into MIDI clock/start/stop bytes through `NB_MIDI` (norns follows MIDI clock: tested on Linux through `Verdandi:midi_in`). Relative timing between instances then depends on UDP and the block size (about 8 ms of latency per plug-in on the Mac, plus jitter); the plug-in reports a fixed latency to the DAW.
- **Real devices:** each instance would need an explicit owner: a per-instance setting "grid = <serial>", default "the first instance", shown in the plug-in; the second instance sees the device as absent. MIDI hardware stays with the DAW and arrives as plug-in MIDI.
- **maiden:** one maiden per instance (16 MB each, **measured**), on the instance's port, with the instance's `--data`, and its own copy of `repl-endpoints.json` for the console ports, and an origin list per instance (`WS_WRAPPER_ALLOWED_ORIGINS` already takes a list). The plug-in window gets an "Open maiden" button that opens the right URL, so nobody types a port. Without a switcher in maiden's page this is one browser tab per instance.
- **Resource cost (measured, idle, no script):** about **0.46 to 0.56 GB and 6.5 to 7.5 % of a core per instance**, startup **4.5 to 7 s** per instance (in parallel for a project load). A project with 8 instances is about 3.7 GB before any sound is made.
- **Cleanup after a crash:** the supervisor must find orphans: each instance in its own process group/session with a heartbeat file; instances exit when no plug-in has talked to them for N seconds (the bridge already treats 1 s of silence as "AU gone"); stale `/dev/shm` JACK segments and the `/tmp` socket are removed at the next start. If the DAW crashes, up to 0.5 GB per instance stays resident until the timeout.
- **What it needs in the code (the "no clashes" part):**
  1. Make the fixed values configurable, from one per-instance environment: crone's OSC port (`OscInterface.cpp:39`, `Crone.sc:29`), `Crone.txPort` (`Crone.sc:14,30`), scsynth's port (a `ServerOptions` setting in `Crone.sc`), matron's `osc.cc:23` constant, the sidecar's socket path (`norns/sidecar.cpp:25`), maiden's console ports (per-instance `repl-endpoints.json`).
  2. Per-instance **JACK server names** (works with `jackd -n`, measured; I believe PipeWire's JACK does not offer named servers, which would rule it out on the Linux default here; **not checked**) or per-instance **client names** (`crone`, `softcut`, `matron-clock`, `Verdandi`, `Verdandi ctl`, SuperCollider's client name, the five fixed `jack_connect` lines in `Crone.sc:80-84`, and `crone/src/InputRoute.h:37`'s own-client list).
  3. Replace `pkill -x norns` in `system_cmd.cc:151-160` and the `pgrep -x norns` guard by per-instance process handling.
  4. Instance title in the window and the grid/arc/keys windows.
  The shared code is derived from upstream norns (crone, SC classes), so these are patches against code that is not ours to freeze.
- **Linux shortcut:** run each instance in its own network and mount namespace (measured in 3.3): **no code changes for 1 to 3 above**, only a launcher. Cost: needs user namespaces (possibly restricted, see 3.4), does not exist on macOS or Windows, and moves the problem to the sandbox (how does the instance reach the PipeWire socket, the X display, the sound card? In a plug-in design the audio goes through the bridge, so the first matters less).
- **Windows:** no namespaces (so item 1 to 3 are mandatory), no `pkill`, nng's `ipc://` becomes a named pipe, JACK for Windows (named servers exist there), a VST3 hosted in one DAW process that may sandbox plug-ins, processes spawned from a plug-in (Windows security software, working directory, console windows). None of it examined.
- **Honest assessment against the owner's criteria:**
  plug and play: not at first, many moving parts;
  ordered: yes (ids, slots, per-instance homes, one supervisor);
  easy to manage: only if the plug-in UI hides all of it (a status line, an "open maiden" button, a "devices" selector);
  little convolution: **no** (a supervisor, an id/duplicate protocol, a state blob, device ownership, per-instance maiden).
  Estimated work (a guess): parameterizing the code a few days with tests; supervisor, ids and crash cleanup about a week; project recall of script state a week or more and never complete for scripts that keep state in memory; plus the Windows work. **Weeks.**

### B) One norns hosting several scripts

- **What norns would need:** matron has one Lua state with global script functions (`init`, `redraw`, `key`, `enc`), one `params` set, one `norns.script`, one engine in SuperCollider (`Crone.engine`, the CroneEngine of the running script), one set of softcut voices and buffers, one screen, one set of metros and clocks. Several scripts at once means several Lua states with their own globals, per-script params, per-script engine slots and softcut voice allocation, and a model for the screen and keys. (Read from the architecture and the headers; I did not trace every global.)
- **Is it realistic?** No. It is a rewrite of norns' core, it makes scripts no longer run "unchanged" (their globals and `norns.state` assumptions), and it would diverge from upstream for good. Resource cost would be lower, everything else harder. Not recommended under any circumstance for this project.

### C) One norns; every plug-in instance is only a multi-channel audio/MIDI connection to the one running script

- **What it is:** the single norns keeps running one script; each plug-in instance is a channel strip: it sends its audio to a numbered input pair and receives from a numbered output pair, with its own MIDI channel or port.
- **What it does not give:** **"each with its own norns script"**. They all talk to the same script. Whatever the script does is global; crone has two stereo inputs and a stereo main output (`crone:input_1/2`, `output_1/2`; the other ports are internal), so more channels need crone changes.
- **What it needs:** an instance id and a channel number in the bridge protocol, a mixer in the bridge (one `jack_adapter` per instance instead of one), a rule for what happens when several instances feed the same input, and a state that stores only "which channel". One bridge, one norns, one maiden, one home, one set of ports: **no clash problem at all**, and about 0.55 GB total.
- **Assessment:** plug and play: yes; ordered: yes; easy to manage: yes; little convolution: moderate (the bridge protocol and mixer). But it is a different feature ("several strips of one norns") and the owner's request is several scripts.

### D) Not supported, with a clear message

- **What it is:** one instance at a time. The second plug-in instance finds the bridge taken and shows "Verdandi is already connected to another plug-in instance: only one at a time" instead of corrupting the audio.
- **What it needs:** a few lines in the protocol: the bridge remembers the **first sender** (address) and, for packets from another address, answers a new type `NB_BUSY` (or nothing), and takes over when the owner says `NB_BYE` or has been silent for 1 s (already the rule); the plug-in shows the status. It also makes the project load order irrelevant: the first instance that renders wins. The id/slot/state questions do not arise.
- **Stable across reload and restart:** not needed. Recall stores only what a single instance stores. **Real devices, maiden, clock:** as today, one of each. **Resource cost:** one norns. **Crash cleanup:** the existing 1 s silence timeout. **Windows:** the same, trivially.
- **Assessment:** plug and play: yes; ordered, easy: yes; convolution: none. It does not do what the owner wants; it makes the limit explicit and safe.

### Summary

| | plug and play | ordered | easy to manage | convolution | several **scripts** | cost per extra instance |
|---|---|---|---|---|---|---|
| A with code changes | after much work | yes | only with a good plug-in UI | **high** | yes | ~0.5 GB, ~7 % core, 5 s |
| A on Linux with namespaces | needs namespace rights | yes | same | medium, Linux only | yes | the same |
| B | – | – | – | **rewrite of norns** | yes | lower | 
| C | yes | yes | yes | moderate | **no** | ~0 |
| D | yes | yes | yes | none | no | none |

## 5. Recommendation

1. **Build D now, as part of the plug-in plan, before any plug-in code exists on Windows or Linux:** one instance per machine, enforced in the bridge, with a message in the plug-in. It is small, removes today's silent corruption, and costs nothing that A or C would not also need (A needs an owner concept per instance anyway). I would also **fix the plug-in's port**: the AU ignores `NORNS_AUV3_PORT` (compiled-in `NB_PORT`), which blocks any later per-instance routing; the VST3 should read a setting or ask the supervisor from the start. (The AUv3 is under `macos/`; changing it is the owner's decision.)
2. **Do not build A as a first-class feature now.** It is feasible (measured: four instances in namespaces cost 1.84 GB and about 26 % of a core idle and start in 7 s) but it is weeks of work across crone, SuperCollider classes, the launcher, the plug-in and a supervisor, and the result is still not plug and play for the user (device ownership, recall of script state, per-instance maiden, a duplicate-track protocol). It is "convoluted" by the owner's own test.
3. **If several scripts per project are really wanted, the cheapest honest route is manual and outside the plug-in:** several **stand-alone** Verdandi instances, each started with its own home (and on Linux its own namespaces), each connected to the DAW through JACK/PipeWire ports. That needs no plug-in changes, but it is manual (not the plug and play asked for).
4. **Option C** is worth reconsidering later as a separate feature ("channel strips"), not as the answer to this question. **Option B: never.**
5. **Smallest first step if A is ever wanted:** a launcher flag `--instance <name>` for Linux that starts a norns in its own home and namespaces (about the harness in `docs/port/multi-instance/inst.sh`), plus tests that start two and check no clash, so the cost and failure modes are known on a real machine; then the supervisor. Decide after seeing a real DAW session with D in place.

**Effect on the existing plug-in plan** (`PLAN.md` Phase 7): add the guard (D) and a settable bridge port to the bridge protocol design; keep the planned transport message (needed in any case); nothing else changes. If A is chosen later, the protocol also needs an instance id and a hello/handshake before audio, which is cheap to leave room for now (a `NB_HELLO` type and a version field in `nb_header_t`).

**Confidence.** High that today's AUv3 cannot serve two instances (read from the code; **not run**). High for the measured clashes and costs **on this container with no real audio load**. Medium for the recommendation: it rests on a judgement that the work of A is "convoluted"; the numbers say it is feasible and cheap per instance, the effort estimates are guesses. Low for anything about Windows, VST3 hosts, other DAWs, PipeWire with several instances, macOS, real-time behaviour, and Ubuntu's namespace restrictions for ordinary users.

**Could not check:** a DAW with two plug-ins, macOS, Windows, real audio (xruns), real scripts and engines, PipeWire, unprivileged namespaces on Ubuntu 24.04, `maiden` and the browser with several instances, the matron `-l` flag against the unmodified SuperCollider side, Link between instances, mDNS renaming, the sidecar clash alone.
