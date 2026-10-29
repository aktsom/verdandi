# Build and run the Linux version on your laptop

For a normal Ubuntu or Debian-based desktop with PipeWire. Read section 2 before you run anything: the
setup script installs a lot with `sudo`.

**What has been tested, honestly.** Everything in this branch was built and tested in one place: an Ubuntu 24.04
container (x86_64, run as root, no sound card, no desktop session, no window manager, bare Xvfb), with a dummy
JACK driver, plus fake sound cards (JACK clients with physical-flagged ports) and stub `wpctl`/`pw-cli`/`pw-jack`
for the PipeWire decisions. **Nothing has been run on a real desktop, with real audio, under real PipeWire, on
Debian or Mint.** (Linux Mint 22 is Ubuntu 24.04 underneath, so the package names should match; I have not seen
it run.) Sections 1, 3 and 4 are my best instructions, not a record of something that worked on a laptop.
Where I know of a risk I say so. What your laptop data changed is in `phase-3.md`.

## 1. Steps (Ubuntu 24.04 or a derivative, X11 or Wayland session)

```bash
# 1. get the code, on the branch, in a folder of its own
mkdir -p ~/verdandi-home
git clone -b linux-port <url of this repository> ~/verdandi-home/norns
cd ~/verdandi-home/norns

# 2. dependencies (section 2 says exactly what it does; read it first). needs sudo
linux/setup-deps.sh

# 3. build (a few minutes on 4 cores); result: build/norns/norns
linux/build.sh

# 4. check it works at all, with no sound and no window needed (a few minutes, needs the test tools of step 2)
linux/tests/run_all.sh
```

Why `~/verdandi-home/norns`: `linux/norns.sh` uses the folder **above** the repository as "the norns home"
(like `/home/we` on the device): `dust/` (scripts, samples), `matronrc.lua`, logs and settings go there, and
`HOME` is set to it while norns runs. If you clone into `~/verdandi`, your whole home folder becomes the
norns home. To use another folder: `NORNS_HOME=/some/folder linux/norns.sh` (it must contain `norns` -> the repo).

**Run, first without sound (recommended first run).** This starts its own silent JACK server, so nothing
depends on PipeWire; it checks the window, keys, grid, menu and dialogs:

```bash
cd ~/verdandi-home/norns
NORNS_JACK_DRIVER=dummy linux/norns.sh --terminal
```
`--terminal` keeps matron's Lua prompt and its log in this terminal (maiden, the web editor, starts in either mode, but its
norns console only works without `--terminal`: see "maiden" at the end). Close the window or press Ctrl+Q in it to quit.

**Run with sound under PipeWire (your Linux Mint 22.2 laptop).** Nothing to prefix any more: `linux/norns.sh`
looks for a JACK server; if none answers and PipeWire runs, it starts itself again under `pw-jack` (needs
`pipewire-jack`, which you have), and says so. Order of what you see in the terminal:

```bash
cd ~/verdandi-home/norns
linux/norns.sh --terminal
#   norns.sh: no JACK server, but PipeWire runs: starting again under pw-jack
#   norns.sh: audio server: pipewire, input 'Built-in Audio Analog Stereo', output 'Built-in Audio Analog Stereo'
#   crone: input connected to 'Built-in Audio Analog Stereo'
#   crone: output connected to 'Built-in Audio Analog Stereo'
```
(the names are your default source and default sink: `wpctl inspect @DEFAULT_AUDIO_SINK@ | grep node.description`).

- **Which card.** norns plays to the **default sink** and listens to the **default source** of the desktop
  (Cinnamon sound settings, or `wpctl set-default <id>`), read when norns starts. To pin a card, put one or both
  lines in `~/verdandi-home/audio.conf` (the start of the name that `pw-jack jack_lsp` shows before the colon):
  ```
  out_ports=AudioQuest
  in_ports=Built-in
  ```
  The environment wins over the file: `NORNS_OUT_PORTS=AudioQuest linux/norns.sh --terminal`.
- **If no card is found** (or the name matches nothing), norns still starts, unconnected: the device window shows
  "AUDIO: not connected, see SYSTEM > AUDIO", and SYSTEM > AUDIO has crone's message. A name that matches nothing
  falls back to the default card and says so.
- **SYSTEM > AUDIO** (HOME page > SYSTEM > AUDIO): INPUT, OUTPUT and RATE
  show what is connected and PipeWire's rate (48000) and cannot be changed; BUFFER is an experimental request
  for a quantum (APPLY restarts norns; the request is made through `PIPEWIRE_QUANTUM`, PipeWire may refuse it).
- **The input (MIC button, or right-click > Input):** MIC is the capture ports of the card norns chose (found by port flags,
  not by name), SYS is the sound of **every application except norns** (a browser, a player: each stream is a JACK client
  named after the application, `Vivaldi`, `Vivaldi-73`, ...), APP is one application of the list in the right-click menu,
  OFF disconnects everything. Streams that start later join SYS by themselves. norns' own output is never in SYS (no
  feedback). While SYS or APP is on, the applications keep playing directly and norns' input monitor is switched off.
  An optional "sink monitor" input (all that the sound card plays, norns included, so it can feed back) is off unless you put
  `sys_monitor=1` in `audio.conf` (or `NORNS_SYS_MONITOR=1`); the device then shows a warning while it is on.
  With MIC on, the input is the live microphone of the **default source**: with speakers and a script that plays its input,
  keep the volume low or use headphones (acoustic feedback).
- **The internal clock under SYS (fixed):** your bisect found that with SYS or APP on, the internal clock froze or crawled under PipeWire with WirePlumber
  (the clock reads JACK's frame time, whose base jumps when applications are linked into crone). It is fixed in this build (`KNOWN-ISSUES.md` item 6). **To check
  your own machine with `NORNS_CLOCK_DEBUG`:** start norns with the variable set, `NORNS_CLOCK_DEBUG=1 linux/norns.sh --terminal`, choose SYS (MIC button or the right-click
  menu), and watch the terminal for lines like `clock: jack frame time jumped by 560.691 s (forward, accepted)` or `... by -503.146 s (backward, new base followed)`.
  One forward line at start is normal. A line appears only for jumps of more than a second; none during normal running. If a backward line appears and the tempo is still
  right (`clock.get_tempo()`, and in a script `clock.get_beats()` growing by 2 per second at 120 BPM), the fix is working; if the clock is slow again, send the lines.
  A forward jump after the start is still accepted and can make a coroutine waiting on `clock.sync` fire in a burst once (measured, see `KNOWN-ISSUES.md`: handling proposed, not applied).
- **MIDI from a DAW (Reaper):** norns' JACK MIDI input is the port `Verdandi:midi_in` (device "Verdandi JACK in", vport 1).
  Connect Reaper's MIDI output (under PipeWire a `Midi-Bridge` port such as `Client-<n> Virtual RawMIDI`) to it with
  `pw-jack jack_connect "<Reaper's port>" Verdandi:midi_in` or qpwgraph; `pw-jack jack_lsp -t | grep -i midi` lists them. Set
  `clock_source` to midi in PARAMS > CLOCK. To have it made (and made again when it is dropped) put
  `midi_in_from=Midi-Bridge:Client-* Virtual RawMIDI` in `~/verdandi-home/audio.conf` (the start of the port's whole name as `jack_lsp` shows it, a `*` for the client number that changes between runs; norns' own MIDI ports and `Midi Through` are never linked;
  several prefixes separated by `;`; `NORNS_MIDI_IN_FROM=...` in the environment wins). It is off without that line. norns checks every
  2 seconds, logs `midi: connected/reconnected ...`, and SYSTEM > DEVICES > MIDI shows "AUTO-LINK: n linked". The test script `window_probe.lua` now listens on every "Verdandi" MIDI device (the JACK input and
  the keys window).
- **Fixed:** `error code: 22 (Invalid argument) in "pthread_create"` on key presses was the metro thread of the screensaver timer
  failing to start (a 16 KiB stack and a desktop's large thread-local storage; `KNOWN-ISSUES.md` item 4). Metros now get a
  256 KiB stack. If a metro still cannot start, norns says "metro N did not start" once; tell me if you ever see it.
- **Setup fixes from your reports** (all three are in `linux/`, nothing for you to change): the libmonome step runs its waf with
  `python3`; waf is installed in `~/.local/share/waf`; the re-run under `pw-jack` uses the script's absolute path (run it
  as plain `linux/norns.sh --terminal`; `pw-jack linux/norns.sh` also works).
- Other overrides: `NORNS_AUDIO_SERVER=jackd` (own jackd, needs a card PipeWire does not hold; or
  `NORNS_JACK_DRIVER=dummy` for silence), `NORNS_AUDIO_SERVER=pipewire` (always `pw-jack`).
- To look at it: `pw-jack jack_lsp -c` shows norns' connections (`crone:input_1` from `...:capture_FL`,
  `crone:output_1` to `...:playback_FL`); `pw-top` shows the norns clients and their quantum.

**Plain JACK instead of PipeWire.** If you use `jackd` or qjackctl yourself, start it first; then
`linux/norns.sh` finds it. If nothing runs and PipeWire holds the sound card, `NORNS_JACK_DRIVER=alsa` (the
default) fails because the card is busy: use the `dummy` driver or `pw-jack`.

**Put a script on it.** With maiden: click MAIDEN in the window (see "maiden" at the end), or open
`http://127.0.0.1:5000/maiden`, and use the library icon to install from the catalog. Without maiden: copy a script folder into `~/verdandi-home/dust/code/<name>/<name>.lua`
(or use the menu's "Import files..." / "Import folder..."), then in the norns window use HOME > SELECT. A tiny
test script that reports every key, encoder, grid, arc and MIDI event on the terminal:
```bash
mkdir -p ~/verdandi-home/dust/code/probe
cp linux/tests/scripts/window_probe.lua ~/verdandi-home/dust/code/probe/
```

### Debian and other derivatives
Package names in section 2 are the Ubuntu 24.04 ones. Debian 12/13, Mint, Pop!_OS and others are untested; I did
not check which package names or versions exist there (for example the nng, SuperCollider and sc3-plugins
packages). libmonome and waf are built by the script on every system.

## 2. What `linux/setup-deps.sh` does (review it: it is about 50 lines)

It runs `sudo` for these (apt, libmonome in `/usr/local`), and nothing else; waf goes into your home without it:

1. `apt-get update`, then `apt-get install -y --no-install-recommends` of:
   - **to build:** build-essential, ca-certificates, curl, git, pkg-config, python3, libasound2-dev,
     libavahi-client-dev, libavahi-compat-libdnssd-dev, libboost-dev, libcairo2-dev, libevdev-dev,
     libfftw3-dev, libglib2.0-dev, libgpiod-dev, libjack-jackd2-dev, liblo-dev, liblua5.3-dev, libncurses-dev,
     libnng-dev, libreadline-dev, libsamplerate0-dev, libsdl2-dev, libsndfile1-dev, libudev-dev, golang-go
   - **to run:** jackd2, lua5.3, supercollider-server, supercollider-language, sc3-plugins-server,
     sc3-plugins-language (SuperCollider brings Qt WebEngine: several hundred MB with its dependencies)
   - **for the tests only:** xvfb, xauth, x11-apps, xdotool, imagemagick, dbus, python3-gi,
     gir1.2-glib-2.0, zenity (zenity is also the file-dialog fallback at runtime)
2. Builds **libmonome 1.4.9** (git tag from github.com/monome/libmonome; its bundled waf is run as `python3 ./waf`,
   because a stock Ubuntu/Mint has no `python` command: an earlier version of the script failed there with
   "/usr/bin/env: 'python': No such file or directory") with this repository's patch
   (`linux/patches/libmonome-pty-serial.patch`) and installs it into **`/usr/local`** (libmonome in
   `/usr/local/lib`, header in `/usr/local/include`, a marker file `/usr/local/share/verdandi/libmonome-pty-serial`),
   then runs `ldconfig`. Skipped if the marker exists.
3. Builds **waf 2.1.9** from the GitLab tag (the waf in the repository needs a python module that Python 3.12
   removed) and installs it as **`~/.local/share/waf/waf`**, owned by you (waf unpacks its library next to itself,
   so an earlier version of the script that installed it as root into `/opt/waf` made `linux/build.sh` fail for a
   normal user with "Cannot unpack waf lib into /opt/waf/..."). No `sudo` is used for this step. If you ran the old
   script, run `linux/setup-deps.sh` again (libmonome is skipped, waf is installed in your home); `linux/build.sh`
   and `run_all.sh` look in `~/.local/share/waf`, then the old `/opt/waf`, then the PATH, or use `WAF=/path/to/waf`.

Effects to know about: `jackd2` and `libjack-jackd2-dev` come in next to PipeWire (on Ubuntu both can be
installed; `pw-jack` selects PipeWire's JACK library for one program, nothing system-wide changes); jackd2's
installer may ask about real-time privileges (the script sets non-interactive, which answers no).
Not touched: your PipeWire setup, your home folder (except `~/.local/share/waf` and what the build writes inside the repository
folder: `build/`, `.waf3-*` and the submodules under `third-party/` and `crone/softcut/`).

If you do not want the test tools, delete `xvfb xauth x11-apps xdotool imagemagick dbus python3-gi
gir1.2-glib-2.0` from the install line (then `linux/tests/run_all.sh` skips what needs them). A
`--no-test-deps` switch would be better; say if you want it.
4. Builds **maiden** (`linux/maiden-build.sh`, as you, no `sudo`): the pinned commit of monome/maiden with two patches, node 16.20.2 in a temporary folder, into `~/verdandi-home/maiden` (see "maiden" at the end of this file).
   `NORNS_NO_MAIDEN=1 linux/setup-deps.sh` skips it. A failure only prints a warning.

## 3. In a container instead (nothing installed on the laptop)

**Tested:** an Ubuntu 24.04 container, headless (this is how everything here was tested): all of
`linux/tests/run_all.sh` passes there. Roughly:
```bash
docker run --rm -it -v "$PWD":/work/norns ubuntu:24.04 bash      # PWD = the repo on the laptop
  apt-get update && apt-get install -y sudo git ca-certificates curl
  cd /work/norns && linux/setup-deps.sh && linux/build.sh && linux/tests/run_all.sh
```
(`run_all.sh` starts its own Xvfb, JACK dummy and everything; run as root as I did, norns sets the two
`QTWEBENGINE_*` variables that SuperCollider's Qt needs as root.)

**Not tested: the window on your screen from a container.** The idea, with X11 (on Wayland this goes through
XWayland):
```bash
xhost +local:                                   # allows local containers to use your X server; undo: xhost -local:
docker run --rm -it -e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "$PWD":/work/home/norns ubuntu:24.04 bash
  # inside, after setup-deps.sh and build.sh as above:
  cd /work/home/norns && NORNS_HOME=/work/home NORNS_JACK_DRIVER=dummy linux/norns.sh --terminal
```
That gives the window and input with silent audio. Sound from a container needs PipeWire's socket inside it
(`-v "$XDG_RUNTIME_DIR/pipewire-0:/tmp/pw/pipewire-0" -e XDG_RUNTIME_DIR=/tmp/pw`, `apt install pipewire-jack`; norns.sh then
finds PipeWire itself) and meets the same questions as on the laptop; I did not try it. `/dev/snd` pass-through
(`--device /dev/snd`) only works if nothing else on the laptop holds the card, which PipeWire does.
Files from the container's file manager and portals do not exist in a container (no desktop session):
"Import files..." needs `zenity` (installed) and your X server, which works, or a portal, which does not.

## 4. Checklist: what to try

Run with `--terminal` so that you can see messages. Tick or note what happened; whatever fails, copy the
terminal output and `~/verdandi-home/logs/jackd.log` and `logs/sclang.log` if present.

**Window**
- [ ] The device window opens (aluminium box, black screen, buttons MIX TAPE HOME PARAMS MIC GRID ARC KEYS
      MAIDEN MANUAL MUTE across the top, the screen at its lower left, K1 E1 above it, E2 E3 K2 K3 to its right; no OUT slider and no K/E text); the black frame around the screen has the Mac's proportions; it resizes without breaking (the screen scales with the window: crisp at 75/100/125/150 percent, very slightly soft in between; smallest size is half); closing it ends norns.
- [ ] With the script above loaded, or from HOME > SELECT, the screen shows the script's picture.
- [ ] It looks right on your screen scale (HiDPI) and in X11 *and* Wayland if you can try both.
- [ ] **SYSTEM > UI** (HOME > SYSTEM > UI): BRIGHTNESS, COLOUR (white, yellow, pink, custom hex typed on the keyboard), CONTRAST (0 = the old linear look, higher = lighter dim greys). The detailed list is in `HARDWARE-CHECKLIST.md`, "SYSTEM > UI". In short: the Cheat Codes 2 loops page at CONTRAST 0, 0.3 and 0.5 (which is closest to your norns?), one colour change, one custom hex colour, a low brightness.

**Keys and knobs**
- [ ] Click K1-K3 (they light and norns reacts); drag a knob; scroll over E1-E3.
- [ ] Keyboard (window focused): `1 2 3` = K1 K2 K3; `q w`, `a s`, `z x` turn E1, E2, E3; Shift = bigger steps.
- [ ] The KEYS button (or F7): the piano window opens; click a key and type `a w s e d f ...`; `z`/`x` octave. With a
      script that listens to MIDI, the notes arrive (device "Verdandi keys").

**Grid and arc**
- [ ] GRID (or F6): the grid window opens; a script with `grid.connect()` sees "virtual grid"; clicking a key
      reaches the script; the script's LEDs show in the window; 64/128/256 buttons below the grid.
- [ ] ARC (or F8): four knobs; scrolling turns, right-click pushes; LEDs from the script show.

**Menu and files**
- [ ] Right-click on the device or F10 opens the menu; mouse and arrow keys + Enter work; Escape closes it.
- [ ] "Import files..." opens **your desktop's file dialog** (not zenity's grey one, if you have a portal);
      choose a `.wav`: a note on the device says it was linked in `dust/audio/mac`; with "Copy samples into
      dust" ticked it is copied. Also try dragging a `.wav` from the file manager onto the window (Shift held:
      a copy).
- [ ] A script's own file chooser (for example buffer 1 sample in PARAMS of a script that has it): by default **only norns's own browser** comes up on the screen (drive it with the keys); no window opens over it.
      Right-click menu > **Open the file dialog when a script loads a file**: tick it, open the chooser again: your desktop's dialog comes up next to the browser; choose a `.wav`: the script gets it as before. Cancel the dialog: the browser is still there and works. Untick it: the next chooser has no dialog. Quit and start Verdandi again: the tick is still there (menu) and the setting is in `~/Verdandi/ui.conf` as `file_dialog=1`.
- [ ] "Show dust folder" and "Show tape folder" open your file manager.

**Screenshot and GIF**
- [ ] Menu > Screenshot (or Ctrl+Shift+S): a PNG appears in `~/Pictures` (or the folder from
      `xdg-user-dirs`), four times the OLED size, crisp pixels.
- [ ] Menu > Record GIF, wait a few seconds with something moving on the screen, menu > Stop GIF recording:
      an animated GIF appears in the same folder and plays.

**Audio** (`linux/norns.sh --terminal` finds PipeWire itself; see "Run with sound under PipeWire")
- [ ] The terminal shows the re-run under pw-jack and "audio server: pipewire, input '...', output '...'" with your
      default source and sink; norns starts without "no ADC ports found".
- [ ] A script with an engine makes sound on the default sink; the output level on the MIX page (E2, or drag the OUT column on the screen) changes the volume and MUTE (top right) silences it and gives it back; changing the
      default sink in the desktop's sound settings and restarting norns moves the sound.
- [ ] `pw-jack jack_lsp -c`: crone's ports are connected to your card's `capture_*` / `playback_*` only (no MIDI port).
- [ ] SYSTEM > AUDIO shows the cards and 48000, read-only; unplug the USB DAC while it is the chosen one (or give a wrong
      `out_ports=` in `audio.conf`): norns starts, with the warning in the window.
- [ ] SYSTEM > RESTART restarts norns (this used to fail on desktop Linux).

Please also note: your distribution and version, X11 or Wayland, the desktop (GNOME, KDE, ...), whether you
use PipeWire (`pactl info | grep "Server Name"`), and the output of `pw-jack jack_lsp -p` if the audio line fails.

## A real grid and serialosc (read this before plugging in a grid)
If serialosc is installed as a system service (`serialosc.service`, started at boot), its `serialosc-device` process opens the grid's serial port
(`/dev/ttyACM0`, the number changes between plug-ins; also reachable as `/dev/serial/by-id/usb-monome_grid_m...-if00`) **at the same time as norns**. Two
programs reading one serial stream steal each other's bytes: grid events lag, arrive out of order, or invalid (a row 33 on an 8-row grid). norns now
**checks** for this when it opens a grid or arc (at start and at every plug-in) and every 3 seconds afterwards, and only **tells you**; it stops nothing:
- **a line in the log** (once per plug-in), in plain words, with the commands: `sudo systemctl stop serialosc.service` to stop serialosc for this session and
  `sudo systemctl start serialosc.service` to start it again later. **Replug the grid after stopping it.**
- **a standing note on the device window:** `GRID: serialosc has this grid, see log`. It goes away by itself when the conflict is gone (a few seconds after
  serialosc stops or the grid is unplugged). If the audio is not connected as well, the grid note is shown first.
- How it looks: it scans `/proc/*/cmdline` for a `serialosc-device` process whose last argument is the same device as norns opened (by-id symlinks and the
  changing ttyACM number are resolved) and the open files of serialosc processes where readable; `serialoscd` and `serialosc-detector` alone are not a conflict.
  It needs no root; processes it cannot read are skipped.
- **Turn the check off:** `NORNS_SERIALOSC_CHECK=0` in the environment, or `serialosc_check=0` in `~/verdandi-home/audio.conf` (the environment wins).
  Norns never uses serialosc's OSC route here (that is a later item).

## Scripts that install SuperCollider libraries, and scripts that restart norns
- **A script's own installer (K3 "Install") may download Raspberry Pi files** (for example `PortedPlugins-RaspberryPi.zip`). Those 32-bit ARM `.so` files cannot load on your
  machine, and SuperCollider then does not start at all ("SUPERCOLLIDER FAIL", no engines, `wrong ELF class: ELFCLASS32` in `logs/sclang.log`). norns now **checks for this before SuperCollider starts**:
  it reads the header of every plug-in in `~/verdandi-home/.local/share/SuperCollider/Extensions`, `/usr/local/share/SuperCollider/Extensions`, `/usr/share/SuperCollider/Extensions`
  (and `*_scsynth.so` in `dust/code`) and compares it with this machine. For each **folder** with wrong files it prints **one line** in the terminal with the folder, each bad file in it and what it is ("A_scsynth.so (32-bit ARM); this machine is x86_64"), why SuperCollider will fail,
  and the exact command (`verdandi tidy disable '<folder>' '<why>'`) to move it (or its folder) into `~/verdandi-home/disabled/` with a line in `disabled/MANIFEST.tsv`, restorable (it **never** moves or deletes anything itself; SYSTEM > CLEAN UP does the same after a confirmation), and the device window shows
  `PLUGINS: wrong-architecture plug-in, see SYSTEM > CLEAN UP` until no wrong file is left. SuperCollider stops at the first bad file, so `sclang.log` shows only one of them: the list from norns can be longer. After moving the files, restart norns.
  Turn the check off with `NORNS_PLUGIN_CHECK=0` or `plugin_check=0` in `~/verdandi-home/audio.conf`.
- **"sudo systemctl restart norns-..." from a script** (a script's installer asks for a restart this way, for the Raspberry Pi's services): on this build norns now answers it itself. The command returns at
  once with exit 0, prints one line (`norns: there is no systemd for norns on this build ... norns restarts itself instead`), and norns restarts within a few seconds (through its own restart, `linux/norns.sh` starts it again). Other
  `sudo` commands from scripts run with `sudo -n`: if a password would be needed they fail at once instead of waiting and freezing norns. `NORNS_NO_SHIMS=1` switches this off. A script that calls `/usr/bin/sudo` by its full path is not covered.

## maiden: the web editor, the consoles and the script catalog
`linux/setup-deps.sh` and `linux/build.sh` build maiden (`linux/maiden-build.sh`, as you, not as root) into `~/verdandi-home/maiden`: it needs the network (Go modules, npm packages, node 16.20.2 from nodejs.org with a checked
SHA-256), a few minutes, and about 1.6 GB of temporary space in `~/verdandi-home/.maiden-build`, which is deleted afterwards (`MAIDEN_KEEP_BUILD=1` keeps it). `NORNS_NO_MAIDEN=1` skips it (norns works without; the launcher says
"maiden is not built"). If the build fails (no network) the scripts print a warning and go on; run `linux/maiden-build.sh` again later. The node used for the web app is only in the temporary folder; nothing is installed system-wide besides `golang-go`.

`linux/norns.sh` starts it next to norns (also with `--terminal`) and prints `maiden at http://127.0.0.1:5000/maiden` (log: `~/verdandi-home/maiden.log`). The **MAIDEN button** in the window opens that page;
if nothing answers on the port (not built, port taken, crashed) it opens nothing and the window shows "maiden is not running, see log" for a few seconds.
- **The norns console in the maiden page needs a start without `--terminal`.** matron has one text stream for its Lua prompt: with `--terminal` that is this terminal (stdin and stdout), without it `ws-wrapper` takes the stream and offers it on
  `ws://127.0.0.1:5555` (the maiden page, `maiden-repl`). A stream cannot be both, so with `--terminal` nothing listens on 5555 and the page says "not connected to norns" (the SuperCollider console on 5556 is separate and unaffected).
  The launcher prints a line about this in `--terminal` mode, and the MAIDEN button shows "maiden: no norns console with --terminal" when it opens the page. To have a terminal prompt **and** the page: start `linux/norns.sh` without `--terminal`
  and, in a second terminal, run `build/maiden-repl/maiden-repl` (it connects to 5555 and 5556 as the page does; the matron log is then in `~/verdandi-home/norns.log`).
- **Port:** 5000, or `NORNS_MAIDEN_PORT=5001 linux/norns.sh` if something else has 5000 (the launcher says so and does not start maiden then). The consoles (matron 5555, sclang 5556) are fixed ports.
- **Where things go:** scripts you install go to `~/verdandi-home/dust/code/<name>/`, catalogs to `dust/data/catalogs`, sources to `dust/data/sources` (filled on the first start). The editor can read and write everything under `~/verdandi-home/dust`, and nothing outside it.
- **Safety:** maiden and the consoles answer on `127.0.0.1` only. In addition a web page from **another site** open in your browser cannot use them: the consoles only keep a browser connection whose page came from maiden's own address
  (127.0.0.1 or localhost with maiden's port), and maiden refuses requests with another `Host` or `Origin`. `maiden-repl` and scripts on your machine are not affected. This is explained in `docs/port/maiden-exposure-evidence.md`.
  The same exposure exists on the Mac app; nothing was changed there (`KNOWN-ISSUES.md`, item 10).
- **What installing a script does:** maiden only downloads it (git clone, or unzip) into `dust/code`. It runs nothing. What a script does after (its own K3 "Install" dependency step) is as described above under "Scripts that install SuperCollider libraries":
  Raspberry Pi plug-ins are reported and do not load on this machine; `sudo systemctl restart norns-*` becomes a norns restart. maiden's own console commands `;restart` and the like (they talk to systemd) answer
  "not available in Verdandi" here: restart norns from its window.

## The screen in its own window (docs/port/detach-plan.md)
- [ ] Which of your scripts read the keys Verdandi now takes (F9 detach, F11 fullscreen; F12 is reserved and not used yet): run `verdandi scan-fkeys` (it only reads `~/Verdandi/dust/code`) and read the RESULT line. Send me the output if a script is named.
- [ ] Click the **SCREEN** button above the top right corner of the screen (or press F9, or menu > Screen in its own window): a window "Verdandi screen" opens with only the picture; the main window shows the dark panel with the sentence "The screen is in its own window. Click here or press F9 to bring it back." and every control still works.
- [ ] With the screen window focused, use the **keyboard only**: 1 2 3, Q W A S Z X, arrows, F1-F5, F6 (grid window), Ctrl+Shift+S (a screenshot appears), Ctrl+O. They do what they do in the main window. Clicking and scrolling over the picture does nothing.
- [ ] Resize the screen window by dragging its edge: at exactly 640 x 320, 1024 x 512, 1280 x 640 the pixels are flat squares; in between they stay sharp (look closely at a letter), with black bars when it is not 2:1.
- [ ] F11 in the screen window: fullscreen on your display, the cursor hides after 2 seconds, F11 or a double click returns to the same size and place. Shift+F11: the title bar goes away (drag the picture to move it, drag an edge to resize); Shift+F11 brings it back.
- [ ] SYSTEM > UI: change brightness, colour, contrast: both windows change together. Record a GIF and take a screenshot from each mode: the same.
- [ ] F10 in the screen window: the main window comes forward with its menu. Close the **screen window** with its close button: the screen is back in the main window and norns keeps running. Detach again, close the **main window**: norns quits.
- [ ] Detach, move and resize the screen window, quit with Ctrl+Q, start again: it comes back detached at the same place and size. `cat ~/Verdandi/screen-window.conf` shows what is kept.
- [ ] Open the virtual grid, arc and keyboard windows with the screen detached, press cells, play a note, use your real grid or MIDI keyboard: nothing changes. Minimise the screen window and the main window in turn: the other still works.

## Files, logs and cleaning up (docs/port/clean-layout.md)
- [ ] Everything Verdandi makes is in `~/Verdandi`: `logs/`, `logs/crash/`, `disabled/` (when you moved something), `backups/` (only before a migration), `cache/`; no `norns.log`, `sclang.log` etc. loose in the home, no hidden `.cache`. `ls -A ~/Verdandi` shows it.
- [ ] Start and stop norns three times: `ls ~/Verdandi/logs` shows `sclang.log`, `sclang.1.log`, `sclang.2.log` (and the same for norns, jackd, maiden); the log of the run before the last is still there.
- [ ] HOME > SYSTEM > CLEAN UP: each group is one line with a size; compare with `du -sh ~/Verdandi/logs ~/Verdandi/cache ~/Verdandi/disabled`. K3 on a line opens it; nothing changes until a second K3; K2 says no.
- [ ] **If you have the nested folder `~/Verdandi/Verdandi`:** run `verdandi tidy flatten` again (it only reads, norns may be running): it now also names the broken link and the links that point elsewhere. If it says `RESULT ready`: **close Verdandi completely** (window, maiden tab is fine), then run `verdandi tidy flatten --apply`. It prints what it will do and asks you to type one line; type it exactly. It makes a backup of `dust/` first (hard links: instant, no space), moves by renaming, checks the number of files and the size of `dust/` and the list of every path, and prints a summary that ends with how to undo. **Send me the whole output.** Then start Verdandi and look at your scripts and samples. `verdandi tidy flatten --undo` puts everything back; the backup folder `~/Verdandi/backups/flatten-<time>/` stays until you delete it yourself.
- [ ] Open a link from the window (MANUAL, MAIDEN): the browser opens as before, and **no new folder** appears in `~/Verdandi` (`ls -a ~/Verdandi` shows no `.mozilla`, `.config/mozilla` or `cache/mozilla`). If a Firefox profile is already in `~/Verdandi/.config/mozilla` or `~/Verdandi/.mozilla` from before, it is a leftover: check its date with `stat ~/Verdandi/.config/mozilla`; when it is older than the fix, move it away (`verdandi tidy disable ~/Verdandi/.config/mozilla 'browser profile made by an older launcher'`) and it can be restored from CLEAN UP.
- [ ] A plug-in for another machine (a file `X_scsynth.so` that is 32-bit ARM, in `dust/code/<script>/`): the line "ARM PLUG-INS" appears on CLEAN UP; K3 K3 moves it to `disabled/`; DISABLED lists it with its reason; K3 on it, K3 restores it. Your scripts and samples are untouched either way.
