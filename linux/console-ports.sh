#!/bin/bash
# linux/console-ports.sh (M25): the two console websockets of maiden (norns 5555, sclang 5556) when another program holds a port. the same rules as the Windows launcher (windows/launcher/console_port.h,
# docs/port/phase-m22.md): the default port is used when it is free; when another program holds it, the first free port of default+100 ... default+199 (never the other console's port) is used instead, maiden's page
# is told, and one plain line says which program holds the default port; when no port is free that console is off. a busy port never stops norns, SuperCollider or the audio.
#
#   console-ports.sh free PORT                       exit 0 when nothing listens on PORT (127.0.0.1 and the wildcard addresses), 1 when something does
#   console-ports.sh choose DEFAULT OTHER            prints the port to use: DEFAULT, or a free one in DEFAULT+100..199 (never OTHER), or 0 (none free)
#   console-ports.sh holder PORT                     prints "name (process N)" of the program that listens on PORT, "name" when only that is known, nothing when it cannot be found
#   console-ports.sh why WHAT DEFAULT GOT            prints the plain line (WHAT: norns or sclang; GOT: the port used instead, 0 = console off); the holder of DEFAULT is looked up
#   console-ports.sh app-copy FROM TO NORNS SCLANG   a copy of maiden's page (FROM) in TO whose repl-endpoints.json names the two console ports (a console that is off keeps its default)
# a program that holds the port for a moment only (an earlier Verdandi that is still shutting down) is waited for: NORNS_PORT_WAIT seconds (default 2) before the default port is given up.

set -u

# the kernel's tables of TCP sockets (IPv4, and IPv6 where there is any: a missing file would stop awk)
tcp_tables() {
    local f
    for f in /proc/net/tcp /proc/net/tcp6; do [ -r "$f" ] && echo "$f"; done
}

# does anything listen on this TCP port? read from the kernel's table (no connect: a connect could disturb the program that holds it)
listening() {
    local hex
    hex="$(printf '%04X' "$1")"
    awk -v h=":$hex" '$4 == "0A" && substr($2, length($2) - 4) == h { found = 1 } END { exit !found }' $(tcp_tables) 2> /dev/null
}

port_free() {
    ! listening "$1"
}

holder() {
    local hex inode fd pid name
    hex="$(printf '%04X' "$1")"
    inode="$(awk -v h=":$hex" '$4 == "0A" && substr($2, length($2) - 4) == h { print $10; exit }' $(tcp_tables) 2> /dev/null)"
    [ -n "$inode" ] && [ "$inode" != 0 ] || return 0
    for fd in /proc/[0-9]*/fd/*; do
        if [ "$(readlink "$fd" 2> /dev/null)" = "socket:[$inode]" ]; then
            pid="${fd#/proc/}"
            pid="${pid%%/*}"
            name="$(cat "/proc/$pid/comm" 2> /dev/null)"
            if [ -n "$name" ]; then echo "$name (process $pid)"; else echo "process $pid"; fi
            return 0
        fi
    done
    # the socket is there but its owner cannot be read (another user's program): the port is held, the name is not known
    return 0
}

choose() {
    local def="$1" other="$2" p waited=0
    # an earlier instance that is still shutting down lets go of its port in a moment
    while [ "$def" != "$other" ] && ! port_free "$def" && [ "$waited" -lt $(( ${NORNS_PORT_WAIT:-2} * 5 )) ]; do
        sleep 0.2
        waited=$((waited + 1))
    done
    if [ "$def" != "$other" ] && port_free "$def"; then echo "$def"; return; fi
    p=$((def + 100))
    while [ "$p" -lt $((def + 200)) ]; do
        if [ "$p" != "$other" ] && port_free "$p"; then echo "$p"; return; fi
        p=$((p + 1))
    done
    echo 0
}

why() {
    local what="$1" def="$2" got="$3" who
    who="$(holder "$def")"
    [ -n "$who" ] || who="another program"
    if [ "$got" -gt 0 ]; then
        echo "port $def is used by $who: the $what console in maiden uses port $got instead"
    else
        echo "port $def is used by $who: the $what console in maiden is off, everything else runs"
    fi
}

app_copy() {
    local from="$1" to="$2" nport="$3" sport="$4"
    [ -d "$from" ] || return 1
    rm -rf "$to"
    mkdir -p "$to" || return 1
    cp -r "$from"/. "$to"/ || return 1
    printf '{\n    "norns": "ws://maiden_app_location:%s",\n    "supercollider": "ws://maiden_app_location:%s"\n}\n' "${nport:-5555}" "${sport:-5556}" > "$to/repl-endpoints.json"
}

case "${1:-}" in
free) port_free "${2:?port}" ;;
choose) choose "${2:?default}" "${3:-0}" ;;
holder) holder "${2:?port}" ;;
why) why "${2:?what}" "${3:?default}" "${4:?got}" ;;
app-copy) app_copy "${2:?from}" "${3:?to}" "${4:-5555}" "${5:-5556}" ;;
*)
    echo "usage: console-ports.sh free|choose|holder|why|app-copy ..." >&2
    exit 2
    ;;
esac
