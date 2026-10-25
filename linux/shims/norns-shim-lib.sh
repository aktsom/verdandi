# shared by the sudo and systemctl shims in this folder. norns.sh puts this folder first on the PATH of norns itself (matron, its sidecar and
# so the commands a script runs with os.execute or norns.system_cmd), not of jackd or sclang.
#
# why: a script's installer runs "sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service" (the Raspberry Pi's
# services). there are no such units on this build (linux/norns.sh starts norns), and a real sudo may wait for a password, which blocks
# matron's thread when the command is run with os.execute: the window and the REPL look dead. the shims recognise only commands about
# norns-* units; everything else goes on to the real program.

SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# the PATH without this folder: to find the real programs
shim_real_path() {
    local out="" p
    local IFS=:
    for p in $PATH; do
        [ "$p" = "$SHIM_DIR" ] || out="${out:+$out:}$p"
    done
    echo "$out"
}

shim_real() { # name: the real program, or nothing
    PATH="$(shim_real_path)" command -v "$1"
}

shim_log() { # one line on stderr (matron's log, or the output of the command)
    echo "norns: $*" >&2
}

# a norns unit: norns-jack.service, norns-matron, norns.target ...
shim_is_norns_unit() {
    case "$1" in
    norns | norns.service | norns.target | norns-*) return 0 ;;
    *) return 1 ;;
    esac
}

# a restart of norns: lua picks the request up (lua/core/menu.lua, within a few seconds) and calls _norns.restart(), the clean way; if nobody
# does within NORNS_SHIM_WATCHDOG seconds (matron stuck), the shim does what _norns.reset does itself: the restart mark for linux/norns.sh and
# an end signal for norns. the background job holds none of the caller's pipes (a sidecar waits for them to close)
shim_request_restart() {
    local home="${HOME:-/}"
    touch "$home/.norns-request-restart"
    (
        sleep "${NORNS_SHIM_WATCHDOG:-20}"
        if [ -f "$home/.norns-request-restart" ]; then
            rm -f "$home/.norns-request-restart"
            touch "$home/.norns-restart"
            pkill -TERM -x norns
        fi
    ) < /dev/null > /dev/null 2>&1 &
    disown 2> /dev/null || true
}

# does a systemctl command line (without "systemctl") name a norns unit? (the sudo shim: only then it does not go to the real sudo)
shim_systemctl_is_norns() {
    local verb="" a
    for a in "$@"; do
        case "$a" in
        -*) ;;
        *)
            if [ -z "$verb" ]; then
                verb="$a"
            elif shim_is_norns_unit "$a"; then
                return 0
            fi
            ;;
        esac
    done
    return 1
}

# systemctl [options] verb unit...  (called by both shims). returns the exit status
shim_systemctl() {
    local verb="" units=() a
    for a in "$@"; do
        case "$a" in
        -*) ;; # --user, --no-block, -q ...
        *) if [ -z "$verb" ]; then verb="$a"; else units+=("$a"); fi ;;
        esac
    done
    local norns=0 u
    for u in "${units[@]:-}"; do
        shim_is_norns_unit "$u" && norns=1
    done
    if [ "$norns" = 1 ]; then
        case "$verb" in
        restart | try-restart | reload-or-restart | try-reload-or-restart)
            shim_log "there is no systemd for norns on this build ('systemctl $*' was asked for): norns restarts itself instead (restart requested)"
            shim_request_restart
            return 0
            ;;
        start | reload | enable | daemon-reload)
            shim_log "there is no systemd for norns on this build ('systemctl $*' was asked for): norns is already running, nothing done"
            return 0
            ;;
        stop | disable | kill)
            shim_log "'systemctl $*' is not supported on this build (there is no systemd for norns): close the norns window to stop it; nothing done"
            return 1
            ;;
        esac
    fi
    local real
    real="$(shim_real systemctl)"
    if [ -z "$real" ]; then
        echo "systemctl: not available" >&2
        return 127
    fi
    exec "$real" "$@"
}
