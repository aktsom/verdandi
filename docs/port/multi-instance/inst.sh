#!/bin/bash
# one headless instance. usage: inst.sh N MODE   (MODE: shared = the one JACK server "default", flags for ports only;
#                                                  jack = own JACK server name per instance + flags; sandbox = own network+mount namespace, same fixed ports)
# runs in the foreground (the harness starts it in its own session). nothing in the repository is changed.
N="$1"; MODE="$2"
REPO=/home/user/verdandi
S=/tmp/claude-0/multi
H=$S/home$N
mkdir -p "$H/dust/code" "$H/dust/audio" "$H/dust/data" "$H/.config/SuperCollider"
[ -e "$H/norns" ] || ln -s "$REPO" "$H/norns"
[ -f "$H/matronrc.lua" ] || echo "_boot.add_io('screen:sdl', {})" > "$H/matronrc.lua"
cat > "$H/.config/SuperCollider/sclang_conf.yaml" <<SC
includePaths:
    - "$REPO/sc/core"
    - "$REPO/sc/engines"
    - "$H/dust"
excludePaths:
    []
postInlineWarnings: false
SC
export HOME="$H" JACK_NO_START_SERVER=1 NORNS_HARDWARE_KEYS=1 NORNS_PLATFORM=linux SDL_NO_SIGNAL_HANDLERS=1 DISPLAY=:99 SDL_AUDIODRIVER=dummy
export PATH="$REPO/linux/shims:$PATH"
export QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox
BASE=$((20000 + 100 * N))
MARGS=()
LANGARGS=()
# instance 1 keeps the default ports; the others get a block (the flags that exist: matron -l/-e/-o, sclang -u; crone and scsynth have none)
if [ "$MODE" != sandbox ] && [ "$N" -gt 1 ]; then
    MARGS=(-l $((BASE)) -e $((BASE + 3)) -o $((BASE + 2)))
    LANGARGS=(-u $((BASE + 3)))
fi
[ "$MODE" = jack ] && export JACK_DEFAULT_SERVER="j$N"
inner() {
    cd "$H"
    if [ "$MODE" = jack ] || [ "$MODE" = sandbox ]; then
        jackd -n "${JACK_DEFAULT_SERVER:-default}" -r -d dummy -r 48000 -p 1024 > "$H/jackd.log" 2>&1 &
        for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
    fi
    ( tail -f /dev/null | "$REPO/build/norns/norns" "${MARGS[@]}" > "$H/norns.log" 2>&1 ) &
    for _ in $(seq 100); do jack_lsp 2> /dev/null | grep -q "^crone:input_5$\|^crone-0[0-9]:input_5$" && break; sleep 0.2; done
    ( tail -f /dev/null | QT_QPA_PLATFORM=offscreen sclang -i maiden "${LANGARGS[@]}" > "$H/sclang.log" 2>&1 ) &
    wait
}
if [ "$MODE" = sandbox ]; then
    export -f inner
    export H S REPO MODE MARGS LANGARGS
    exec unshare -n -m -- bash -c '
        python3 /tmp/claude-0/multi/lo_up.py
        mkdir -p /run/x11ref /run/multiref && mount --bind /tmp/.X11-unix /run/x11ref && mount --bind '"$S"' /run/multiref
        mount -t tmpfs tmpfs /tmp && mkdir -p /tmp/.X11-unix && mount --bind /run/x11ref /tmp/.X11-unix
        mkdir -p '"$S"' && mount --bind /run/multiref '"$S"'
        mount -t tmpfs tmpfs /dev/shm
        inner'
else
    inner
fi
