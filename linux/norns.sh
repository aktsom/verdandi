#!/bin/bash
# norns on Linux (desktop): start jackd if none runs, norns (matron + crone + softcut) and sclang
# with HOME set to the norns home, like macos/norns.sh.
#
# layout (same as /home/we on the device):
#   <norns home>/norns          this repository
#   <norns home>/dust           scripts, audio, data
#   <norns home>/matronrc.lua   written on first start (desktop screen)
#
# installed (the .deb: a program tree with an INSTALLED marker file, /opt/verdandi): the norns home is NORNS_HOME, else the
# first line of ~/.config/verdandi/home, else ~/Verdandi. in every mode <norns home>/norns is a link to the program tree; it is
# created, and moved when it points at another tree (a developer checkout and the package can share one home: the tree
# started last owns the link). a real folder called norns in the home is never replaced.
#
# usage: linux/norns.sh [--terminal]
#   default: matron and sclang REPLs are websockets (127.0.0.1:5555/5556), the log is in
#            <norns home>/norns.log; maiden (the web editor and script catalog) at http://127.0.0.1:5000/maiden,
#            its log in <norns home>/maiden.log
#   --terminal: matron's lua REPL and log are this terminal
#
# environment (all optional):
#   NORNS_HOME          the norns home (default: checkout: the folder above this repository; installed: see above)
#   NORNS_INSTALLED     1 / 0: treat this program tree as installed / as a checkout (default: the INSTALLED marker file)
#   NORNS_JACK_DRIVER   jackd driver, default "alsa"; "dummy" for headless runs
#   NORNS_JACK_RATE / NORNS_JACK_PERIOD   default 48000 / 1024
#   NORNS_NO_SCLANG=1   do not start sclang
#   NORNS_AUDIO_SERVER  "auto" (default): use a JACK server that answers; else, if PipeWire runs, run
#                       this script again under pw-jack; else start jackd. "jackd": always start our own
#                       jackd. "pipewire": always use PipeWire's JACK through pw-jack.
#                       NORNS_JACK_DRIVER given (and no server answering) also means our own jackd.
#   NORNS_IN_PORTS / NORNS_OUT_PORTS   sound card to use, as the start of its JACK client name (the
#                       card's name in PipeWire). default: the session's default source / sink under
#                       PipeWire (wpctl), else the first card. audio.conf in the norns home may hold
#                       in_ports=... and out_ports=... (the environment wins)
#   NORNS_NO_SHIMS=1    do not put linux/shims (sudo, systemctl for norns-* units) first on the PATH of norns
#   NORNS_MAIDEN        where maiden is (default <norns home>/maiden, built by linux/maiden-build.sh); started if there
#   NORNS_MANUAL        the page the MANUAL button opens (default linux/manual/manual.html in this repository)
#   NORNS_MAIDEN_PORT   maiden's port (default 5000). maiden and the REPL websockets (5555, 5556) answer on 127.0.0.1 only,
#                       and the REPL websockets only to a browser page that maiden served (ws-wrapper's Origin check)
#   NORNS_DECIDE_ONLY=1 print the decision ("DECIDE action=... server=... in=... out=...") and exit

set -u

TERMINAL=0
[ "${1:-}" = "--terminal" ] && TERMINAL=1

# this script's own absolute path: a re-run (pw-jack) may start in another working directory, so $0 is not enough
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
JACK_DRIVER="${NORNS_JACK_DRIVER:-alsa}"

# the name a person sees (window title, dialogs): linux/brand.sh. internal names keep "Verdandi"
. "$REPO/linux/brand.sh"
export NORNS_DISPLAY_NAME="$VERDANDI_DISPLAY_NAME"
# the window class (the panel and the window list match the menu entry with it) and the window icon: the installed icon, else the repository's
export SDL_VIDEO_X11_WMCLASS="$VERDANDI_WM_CLASS"
if [ -z "${NORNS_ICON:-}" ]; then
    for i in /usr/share/icons/hicolor/256x256/apps/verdandi.png "$REPO/macos/norns-icon.png"; do
        [ -f "$i" ] && { export NORNS_ICON="$i"; break; }
    done
fi

# installed tree (the .deb) or checkout
if [ -n "${NORNS_INSTALLED:-}" ]; then
    INSTALLED="$NORNS_INSTALLED"
elif [ -f "$REPO/INSTALLED" ]; then
    INSTALLED=1
else
    INSTALLED=0
fi
if [ "$INSTALLED" = 1 ]; then MODE=installed; else MODE=dev; fi

# the norns home and where it came from
if [ -n "${NORNS_HOME:-}" ]; then
    HOME_SOURCE=env
elif [ "$INSTALLED" = 1 ]; then
    HOME_CONF="${XDG_CONFIG_HOME:-${HOME:-}/.config}/verdandi/home"
    NORNS_HOME="$(head -n 1 "$HOME_CONF" 2>/dev/null | tr -d '\r')"
    case "$NORNS_HOME" in
    "~/"*) NORNS_HOME="${HOME:-}/${NORNS_HOME#\~/}" ;;
    esac
    if [ -n "$NORNS_HOME" ]; then
        HOME_SOURCE=config
    else
        NORNS_HOME="${HOME:-}/Verdandi"
        HOME_SOURCE=default
    fi
else
    NORNS_HOME="$(dirname "$REPO")"
    HOME_SOURCE=repo
fi
case "$NORNS_HOME" in /*) ;; *) echo "norns.sh: the norns home '$NORNS_HOME' is not an absolute path"; exit 1 ;; esac
# exported now: HOME is set to the norns home below, and the run under pw-jack (a second run of this script) must find the same home, not work out
# "$HOME/Verdandi" again from the changed HOME (that was ~/Verdandi/Verdandi on PipeWire machines)
export NORNS_HOME

# <norns home>/norns must lead to this tree (matron reads $HOME/norns/lua and $HOME/norns/resources). ok, create, repoint
# (a link that points at another tree) or conflict (a real folder that is not this tree)
LINK="$NORNS_HOME/norns"
if [ -L "$LINK" ] || [ -e "$LINK" ]; then
    if [ "$(cd "$LINK" 2>/dev/null && pwd -P)" = "$(cd "$REPO" && pwd -P)" ]; then
        LINK_STATE=ok
    elif [ -L "$LINK" ]; then
        LINK_STATE=repoint
    else
        LINK_STATE=conflict
    fi
else
    LINK_STATE=create
fi

# started from the desktop there is no terminal: the problems are shown in a dialog and the output is kept in a file
[ -z "${NORNS_HAVE_TTY:-}" ] && { [ -t 1 ] || [ -t 2 ]; } && export NORNS_HAVE_TTY=1
fail() {
    echo "norns.sh: $*"
    if [ -z "${NORNS_HAVE_TTY:-}" ]; then
        if command -v zenity >/dev/null; then zenity --error --title="$VERDANDI_DISPLAY_NAME" --no-markup --text="$*" 2>/dev/null
        elif command -v kdialog >/dev/null; then kdialog --error "$*" 2>/dev/null
        elif command -v notify-send >/dev/null; then notify-send "$VERDANDI_DISPLAY_NAME" "$*" 2>/dev/null
        fi
    fi
    exit 1
}

jack_up() { jack_lsp >/dev/null 2>&1; }
pw_up() { pw-cli info 0 >/dev/null 2>&1; }
PW_JACK="${NORNS_PW_JACK:-$(command -v pw-jack || true)}"
# a key from audio.conf in the norns home (the last one wins)
conf_get() { sed -n "s/^$1=//p" "$NORNS_HOME/audio.conf" 2>/dev/null | tail -1; }
# the name of PipeWire's default sink / source: also the name of its JACK client
pw_default() { wpctl inspect "$1" 2>/dev/null | sed -n 's/.*node\.description = "\(.*\)".*/\1/p' | head -1; }

# which audio server: SERVER (jackd, pipewire, jack = something else answering), ACTION
decide_server() {
    local want="${NORNS_AUDIO_SERVER:-auto}"
    SERVER=jack
    if jack_up; then
        ACTION=use-running
        if [ "${NORNS_REEXEC:-0}" = 1 ] || { pw_up && jack_lsp 2>/dev/null | grep -q '^Midi-Bridge:'; }; then
            SERVER=pipewire
        fi
        return
    fi
    if [ "$want" = jackd ] || { [ "$want" = auto ] && { [ -n "${NORNS_JACK_DRIVER:-}" ] || ! pw_up; }; }; then
        ACTION=start-jackd
        SERVER=jackd
        return
    fi
    SERVER=pipewire
    if [ "${NORNS_REEXEC:-0}" = 1 ]; then
        ACTION=pipewire-no-jack
    elif pw_up && [ -x "$PW_JACK" ]; then
        ACTION=reexec-pw-jack
    else
        ACTION=need-pw-jack
    fi
}

# the card to use, as a prefix of its JACK client name ("" = the first one)
decide_devices() {
    IN_PORTS="${NORNS_IN_PORTS:-$(conf_get in_ports)}"
    OUT_PORTS="${NORNS_OUT_PORTS:-$(conf_get out_ports)}"
    if [ "$SERVER" = pipewire ]; then
        local d
        if [ -z "$IN_PORTS" ]; then
            d="$(pw_default @DEFAULT_AUDIO_SOURCE@)"
            case "$d" in "Monitor of "*) d="" ;; esac
            IN_PORTS="$d"
        fi
        [ -z "$OUT_PORTS" ] && OUT_PORTS="$(pw_default @DEFAULT_AUDIO_SINK@)"
    fi
}

# audio.conf (written by SYSTEM > AUDIO): input= output= (ALSA devices for our own jackd), rate=, period=;
# NORNS_JACK_RATE / NORNS_JACK_PERIOD in the environment win. without a file: 48000 Hz, period 1024
read_audio_conf() {
    local v
    JACK_IN="$(conf_get input)"
    JACK_OUT="$(conf_get output)"
    v="$(conf_get rate)"
    case "$v" in 44100 | 48000 | 88200 | 96000) ;; *) v=48000 ;; esac
    JACK_RATE="${NORNS_JACK_RATE:-$v}"
    v="$(conf_get period)"
    case "$v" in 64 | 128 | 256 | 512 | 1024) ;; *) v=1024 ;; esac
    JACK_PERIOD="${NORNS_JACK_PERIOD:-$v}"
}
jackd_args() {
    if [ "$JACK_DRIVER" = dummy ]; then
        # the dummy driver needs no realtime; jackd -r keeps it quiet in containers
        JACKD_ARGS=(-r -d dummy -r "$JACK_RATE" -p "$JACK_PERIOD")
    else
        JACKD_ARGS=(-d "$JACK_DRIVER" -r "$JACK_RATE" -p "$JACK_PERIOD")
        # one device chosen: the other side is the first card, named, so jackd opens both
        if [ "$JACK_DRIVER" = alsa ] && [ -n "$JACK_IN$JACK_OUT" ]; then
            JACKD_ARGS+=(-C "${JACK_IN:-hw:0}" -P "${JACK_OUT:-hw:0}")
        fi
    fi
}
# PipeWire's sample rate: the system's, not ours
pw_rate() { pw-metadata -n settings 0 clock.rate 2>/dev/null | sed -n "s/.*key:'clock\.rate' value:'\([0-9]*\)'.*/\1/p" | head -1; }

# the rate shown on SYSTEM > AUDIO, and under PipeWire the buffer request (experimental): audio.conf period
# becomes PIPEWIRE_QUANTUM for everything we start. an own PIPEWIRE_QUANTUM in the environment stays
decide_rate() {
    QUANTUM=""
    case "$SERVER" in
    jackd) AUDIO_RATE="$JACK_RATE" ;;
    pipewire)
        AUDIO_RATE="$(pw_rate)"
        AUDIO_RATE="${AUDIO_RATE:-48000}"
        local p
        p="$(conf_get period)"
        case "$p" in 64 | 128 | 256 | 512 | 1024 | 2048) QUANTUM="$p/$AUDIO_RATE" ;; esac
        if [ -n "$QUANTUM" ] && [ -z "${PIPEWIRE_QUANTUM:-}" ]; then export PIPEWIRE_QUANTUM="$QUANTUM"; fi
        ;;
    *) AUDIO_RATE="$(jack_samplerate 2>/dev/null)" ;;
    esac
}

JACK_DRIVER="${NORNS_JACK_DRIVER:-alsa}"
decide_server
decide_devices
read_audio_conf
decide_rate
# NORNS_DECIDE_ONLY=reexec: as 1, but a decision to re-run under pw-jack is carried out (tests the re-run)
if [ "${NORNS_DECIDE_ONLY:-0}" = 1 ] || { [ "${NORNS_DECIDE_ONLY:-0}" = reexec ] && [ "$ACTION" != reexec-pw-jack ]; }; then
    echo "DECIDE action=$ACTION server=$SERVER in=$IN_PORTS out=$OUT_PORTS"
    echo "DECIDE-HOME mode=$MODE home=$NORNS_HOME source=$HOME_SOURCE link=$LINK_STATE"
    if [ "$ACTION" = start-jackd ]; then
        jackd_args
        echo "DECIDE-JACKD ${JACKD_ARGS[*]}"
    fi
    echo "DECIDE-RATE ${AUDIO_RATE:-}"
    echo "DECIDE-QUANTUM ${QUANTUM}"
    exit 0
fi

# the user's own HOME and XDG folders, for the programs the window starts for the user (xdg-open: the default browser is in the
# user's ~/.config/mimeapps.list, not in the norns home). matron gives them back to xdg-open only (matron/src/platform/macos/open_url.c)
export NORNS_USER_HOME="${NORNS_USER_HOME:-${HOME:-}}"
for v in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME; do
    [ -n "${!v:-}" ] && export "NORNS_USER_$v=${!v}"
done
export HOME="$NORNS_HOME"
export JACK_NO_START_SERVER=1
# no norns hardware: the keyboard drives K1-3 / E1-3 when nothing else wants the keys
# (lua/core/keyboard.lua)
export NORNS_HARDWARE_KEYS=1
export NORNS_PLATFORM=linux
# SDL would catch SIGTERM and turn it into a quit event nothing reads yet (no window event pump
# on linux until phase 2): let the signal end norns
export SDL_NO_SIGNAL_HANDLERS=1
mkdir -p "$NORNS_HOME" || fail "cannot create the norns home $NORNS_HOME"
cd "$NORNS_HOME" || exit 1
# from the desktop: what this script says goes to a file
if [ -z "${NORNS_HAVE_TTY:-}" ] && [ "$INSTALLED" = 1 ] && [ $TERMINAL -eq 0 ] && [ "${NORNS_LAUNCHER_LOG:-1}" != 0 ]; then
    exec >> "$NORNS_HOME/launcher.log" 2>&1
fi
case "$LINK_STATE" in
conflict) fail "$LINK is a folder that is not this program ($REPO). Move it away, or choose another norns home (NORNS_HOME, or ~/.config/verdandi/home)." ;;
repoint) echo "norns.sh: $LINK pointed at $(readlink "$LINK"), now at $REPO" ; ln -sfn "$REPO" "$LINK" ;;
create) ln -s "$REPO" "$LINK" || fail "cannot create $LINK" ;;
esac

# the parts of an installed tree that are not in a system folder
if [ -d "$REPO/supercollider/bin" ]; then export PATH="$REPO/supercollider/bin:$PATH"; fi
if [ -d "$REPO/lib" ]; then export LD_LIBRARY_PATH="$REPO/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi

mkdir -p dust/code dust/audio dust/data
if [ -f "$REPO/update/version.txt" ] && ! cmp -s "$REPO/update/version.txt" version.txt; then
    cp "$REPO/update/version.txt" version.txt
fi
if [ ! -f matronrc.lua ]; then
    cat > matronrc.lua <<'RC'
-- Linux desktop: the norns window (screen:sdl). keys and encoders: see readme-macos.md
_boot.add_io('screen:sdl', {})
RC
fi

# sclang: the include paths norns-config.sc sets up on the device
SC_CONF="$NORNS_HOME/.config/SuperCollider"
mkdir -p "$SC_CONF"
# written again when the program moved (checkout vs package): the old file is kept as .old
if [ -f "$SC_CONF/sclang_conf.yaml" ] && ! grep -qF "\"$REPO/sc/core\"" "$SC_CONF/sclang_conf.yaml"; then
    echo "norns.sh: sclang_conf.yaml named another program folder: written again (the old one is sclang_conf.yaml.old)"
    mv -f "$SC_CONF/sclang_conf.yaml" "$SC_CONF/sclang_conf.yaml.old"
fi
if [ ! -f "$SC_CONF/sclang_conf.yaml" ]; then
    cat > "$SC_CONF/sclang_conf.yaml" <<SC
includePaths:
    - "$REPO/sc/core"
    - "$REPO/sc/engines"
    - "$NORNS_HOME/dust"
excludePaths:
    []
postInlineWarnings: false
SC
fi

if pgrep -x norns >/dev/null; then
    fail "norns is already running"
fi

# the MANUAL button of the window opens this (the window says so if the file is not there)
export NORNS_MANUAL="${NORNS_MANUAL:-$REPO/linux/manual/manual.html}"
if [ -x "$REPO/maiden/maiden" ]; then MAIDEN_DEFAULT="$REPO/maiden"; else MAIDEN_DEFAULT="$NORNS_HOME/maiden"; fi
MAIDEN="${NORNS_MAIDEN:-$MAIDEN_DEFAULT}"
MAIDEN_PORT="${NORNS_MAIDEN_PORT:-5000}"
case "$MAIDEN_PORT" in '' | *[!0-9]*) echo "norns.sh: NORNS_MAIDEN_PORT='$MAIDEN_PORT' is not a port number"; exit 1 ;; esac
export NORNS_MAIDEN_PORT="$MAIDEN_PORT" # the MAIDEN button of the window opens this port
# the pages maiden serves: the only origins a browser may open the REPL websockets from (ws-wrapper)
WS_ORIGINS="http://127.0.0.1:$MAIDEN_PORT,http://localhost:$MAIDEN_PORT"

PIDS=""
JACK_PID=""
# a process and everything below it, children first
tree() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done
    kill "$1" 2>/dev/null
}
cleanup() {
    trap - EXIT INT TERM
    local p
    # reverse start order: jackd goes last, after everything that plays through it
    for p in $(echo $PIDS | tr ' ' '\n' | tac); do tree "$p"; done
    wait 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

case "$ACTION" in
reexec-pw-jack)
    echo "norns.sh: no JACK server, but PipeWire runs: starting again under pw-jack"
    export NORNS_REEXEC=1
    exec "$PW_JACK" /bin/bash "$SELF" "$@"
    ;;
need-pw-jack)
    echo "norns.sh: PipeWire is the sound server here but pw-jack is not available (or PipeWire is not running)."
    echo "          install it (Debian/Ubuntu: sudo apt install pipewire-jack), or use our own JACK:"
    echo "          NORNS_AUDIO_SERVER=jackd NORNS_JACK_DRIVER=dummy linux/norns.sh   (silent)"
    exit 1
    ;;
pipewire-no-jack)
    fail "no JACK server answers even under pw-jack. Is pipewire-jack installed and PipeWire running?"
    ;;
esac
echo "norns.sh: audio server: $SERVER${IN_PORTS:+, input '$IN_PORTS'}${OUT_PORTS:+, output '$OUT_PORTS'}"
export NORNS_AUDIO_SERVER_MODE="$SERVER"
# the optional sink monitor input (hears norns too); off unless asked: environment or audio.conf sys_monitor=1
NORNS_SYS_MONITOR="${NORNS_SYS_MONITOR:-$(conf_get sys_monitor)}"
export NORNS_SYS_MONITOR
# the optional MIDI auto-connect: JACK MIDI output port name prefixes (";" between) to link to Verdandi:midi_in. off by default
NORNS_MIDI_IN_FROM="${NORNS_MIDI_IN_FROM:-$(conf_get midi_in_from)}"
export NORNS_MIDI_IN_FROM
# serialosc (serialosc-device) on the grid's serial port is reported; NORNS_SERIALOSC_CHECK=0 or serialosc_check=0 in audio.conf turns that off
NORNS_SERIALOSC_CHECK="${NORNS_SERIALOSC_CHECK:-$(conf_get serialosc_check)}"
export NORNS_SERIALOSC_CHECK
# SuperCollider plug-ins built for another machine (a script's installer fetched a Raspberry Pi bundle): reported before sclang starts, never moved.
# NORNS_PLUGIN_CHECK=0 or plugin_check=0 in audio.conf turns the check off
NORNS_PLUGIN_CHECK="${NORNS_PLUGIN_CHECK:-$(conf_get plugin_check)}"
export NORNS_PLUGIN_CHECK

AUDIO_TOOL="$REPO/build/linux/audio_devices"
export NORNS_AUDIO_TOOL="$AUDIO_TOOL"
export NORNS_AUDIO_RATE="${AUDIO_RATE:-}"
AUDIO_CONF="$NORNS_HOME/audio.conf"

# our own jackd with the settings of audio.conf; 1 if it does not come up
run_jackd() {
    jackd_args
    echo "norns.sh: starting jackd (${JACK_DRIVER}, ${JACK_RATE} Hz, period ${JACK_PERIOD}${JACK_IN:+, input $JACK_IN}${JACK_OUT:+, output $JACK_OUT})"
    jackd "${JACKD_ARGS[@]}" < /dev/null > "$NORNS_HOME/jackd.log" 2>&1 &
    JACK_PID=$!
    PIDS="$PIDS $JACK_PID"
    local n=0
    until jack_up; do
        n=$((n + 1))
        if [ $n -gt 50 ] || ! kill -0 "$JACK_PID" 2>/dev/null; then
            return 1
        fi
        sleep 0.2
    done
}
start_jackd() {
    read_audio_conf
    run_jackd && return 0
    # the chosen setting does not start (device gone, rate not supported): the defaults, and
    # audio.conf.failed tells SYSTEM > AUDIO
    if [ -f "$AUDIO_CONF" ]; then
        echo "norns.sh: audio settings did not start, using the defaults"
        tree "$JACK_PID"
        mv -f "$AUDIO_CONF" "$AUDIO_CONF.failed"
        read_audio_conf
        run_jackd && return 0
    fi
    echo "norns.sh: jackd did not start, see $NORNS_HOME/jackd.log"
    [ -z "${NORNS_HAVE_TTY:-}" ] && fail "jackd did not start (no sound server). See $NORNS_HOME/jackd.log"
    return 1
}
if [ "$ACTION" = start-jackd ]; then
    start_jackd || exit 1
    export NORNS_AUDIO_RATE="$JACK_RATE"
fi

WS="$REPO/build/ws-wrapper/ws-wrapper"
NORNS_BIN="$REPO/build/norns/norns"
[ -x "$NORNS_BIN" ] || fail "$NORNS_BIN not built, run linux/build.sh"
RESTART_MARK="$NORNS_HOME/.norns-restart"
AUDIO_MARK="$NORNS_HOME/.norns-restart-audio"
rm -f "$RESTART_MARK" "$AUDIO_MARK"

start_norns() {
    export NORNS_IN_PORTS="$IN_PORTS" NORNS_OUT_PORTS="$OUT_PORTS"
    # before norns and sclang start: SuperCollider stops at the first plug-in it cannot load. report only (one line per file)
    [ -x "$REPO/build/linux/plugin_arch_check" ] && "$REPO/build/linux/plugin_arch_check" "$NORNS_HOME" | sed 's/^/norns.sh: /'
    # norns and the commands its scripts run (os.execute, norns.system_cmd) get linux/shims first on the PATH: "sudo systemctl restart norns-*" (a script's
    # installer) becomes a restart request, and sudo never waits for a password (linux/shims/norns-shim-lib.sh). NORNS_NO_SHIMS=1: not
    local shimpath="$PATH"
    [ "${NORNS_NO_SHIMS:-0}" = 1 ] || shimpath="$REPO/linux/shims:$PATH"
    if [ $TERMINAL -eq 1 ]; then
        # explicit <&0: a non-interactive shell gives background jobs /dev/null as stdin
        PATH="$shimpath" "$NORNS_BIN" <&0 &
    else
        WS_WRAPPER_ALLOWED_ORIGINS="$WS_ORIGINS" PATH="$shimpath" "$WS" "ws://127.0.0.1:5555" "$NORNS_BIN" < /dev/null > "$NORNS_HOME/norns.log" 2>&1 &
    fi
    NORNS_PID=$!
    PIDS="$PIDS $NORNS_PID"
    [ "${NORNS_NO_SCLANG:-0}" = "1" ] && return
    # sclang wires scsynth into crone's jack ports, so wait for crone
    local n=0
    until jack_lsp 2>/dev/null | grep -q '^crone:input_5$'; do
        n=$((n + 1))
        if [ $n -gt 100 ] || ! kill -0 "$NORNS_PID" 2>/dev/null; then
            echo "norns.sh: crone did not come up, sclang not started"
            return
        fi
        sleep 0.2
    done
    # sclang's Qt WebEngine refuses to start as root (containers) without this
    [ "$(id -u)" -eq 0 ] && export QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox
    WS_WRAPPER_ALLOWED_ORIGINS="$WS_ORIGINS" QT_QPA_PLATFORM=offscreen "$WS" "ws://127.0.0.1:5556" sclang -i maiden \
        < /dev/null > "$NORNS_HOME/sclang.log" 2>&1 &
    SCLANG_PID=$!
    PIDS="$PIDS $SCLANG_PID"
}

start_norns

# maiden: the web editor, the REPL consoles and the script catalog, as on the Mac: on 127.0.0.1 only (--host, a patch of
# macos/patches), and its guard (linux/patches) also refuses requests that a web page on another site makes. the same
# origins are the only ones the REPL websockets accept from a browser
if [ -x "$MAIDEN/maiden" ]; then
    # first start: the catalog sources maiden installs scripts from (tool/project-setup.sh of maiden)
    if [ ! -d dust/data/sources ]; then
        mkdir -p dust/data/sources dust/data/catalogs
        cp "$MAIDEN"/dist/sources/*.json dust/data/sources/ 2>/dev/null
    fi
    if (exec 3<>"/dev/tcp/127.0.0.1/$MAIDEN_PORT") 2>/dev/null; then
        echo "norns.sh: port $MAIDEN_PORT is in use: maiden is not started (another port: NORNS_MAIDEN_PORT=5001 linux/norns.sh)"
    else
        (cd "$MAIDEN" && exec ./maiden server --host 127.0.0.1 --port "$MAIDEN_PORT" --app ./app/build \
            --data "$NORNS_HOME/dust" --doc "$NORNS_HOME/norns/doc" < /dev/null > "$NORNS_HOME/maiden.log" 2>&1) &
        PIDS="$PIDS $!"
        echo "norns.sh: maiden at http://127.0.0.1:$MAIDEN_PORT/maiden (log: $NORNS_HOME/maiden.log)"
    fi
else
    echo "norns.sh: maiden is not built (linux/maiden-build.sh): no web editor"
fi
[ $TERMINAL -eq 0 ] && echo "norns.sh: matron log in $NORNS_HOME/norns.log"
[ $TERMINAL -eq 1 ] && echo "norns.sh: --terminal: matron's Lua prompt is this terminal, so maiden's norns console (port 5555) is not available; start without --terminal for it (and run build/maiden-repl/maiden-repl for a terminal prompt next to it)"

while :; do
    wait "$NORNS_PID"
    [ -f "$RESTART_MARK" ] || break
    rm -f "$RESTART_MARK"
    echo "norns.sh: restarting norns and sclang"
    [ -n "${SCLANG_PID:-}" ] && tree "$SCLANG_PID"
    n=0
    while jack_lsp 2>/dev/null | grep -q '^crone:' && [ $n -lt 25 ]; do
        sleep 0.2
        n=$((n + 1))
    done
    # new audio settings from SYSTEM > AUDIO: our own jackd restarts with them; for the other servers
    # the devices and the buffer request are read again
    if [ -f "$AUDIO_MARK" ]; then
        rm -f "$AUDIO_MARK"
        if [ -n "$JACK_PID" ]; then
            echo "norns.sh: restarting audio"
            tree "$JACK_PID"
            wait "$JACK_PID" 2>/dev/null
            start_jackd || break
            export NORNS_AUDIO_RATE="$JACK_RATE"
        fi
    fi
    decide_devices
    decide_rate
    start_norns
done
