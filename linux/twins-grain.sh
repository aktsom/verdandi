#!/bin/bash
# the script twins ships its own grain UGen, TwinGrain, inside its folder (lib/ugens: the C++ source, the class TwinGrain.sc.in and a prebuilt x86_64/aarch64/armv7l TwinGrain.so.in). the
# twins repository has no licence, so Verdandi does not ship a copy of it. what twins' own installer does on K3 ("Missing SuperCollider Libraries: TwinGrain") is a plain copy of the two files
# of the script into <extensions>/twins/TwinGrain.sc and TwinGrain.so, after a load test; this does that same copy for the user before sclang starts, on the user's machine, so that the
# "missing" screen does not come up for a file the user already has. docs/port/phase-m29.md, DECISIONS.md.
#
#   twins-grain.sh sync <norns home>
#       - twins is not installed (dust/code/twins), no file for x86_64 in it, no python3, the installer's skip marker (dust/data/twins/skip_TwinGrain_x86_64) is there, or
#         the file does not load (the installer's own test: python3 ctypes.CDLL): nothing happens, silent
#       - another TwinGrain.sc / TwinGrain.so / TwinGrain_scsynth.so exists in the extension folders or dust/code (outside the script's own lib/ugens folder and outside
#         <extensions>/twins): left alone, one line (two copies make sclang stop: duplicate class)
#       - <extensions>/twins/TwinGrain.sc and .so already are byte for byte the script's files: silent
#       - else they are written (temp names, then renamed), one line says so. a TwinGrain of an older twins in that folder is replaced (that folder is the installer's own)
#       never deletes anything, never needs a network. NORNS_TWINS_GRAIN=0 (or twins_grain=0 in audio.conf) turns it off. always exits 0.
set -u

enabled() {
    case "$(printf '%s' "${NORNS_TWINS_GRAIN:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

cmd_sync() {
    local home="$1"
    enabled || return 0
    local tw="$home/dust/code/twins" ext="$home/.local/share/SuperCollider/Extensions"
    local sc="$tw/lib/ugens/TwinGrain.sc.in" so="$tw/lib/ugens/x86_64/TwinGrain.so.in"
    [ -f "$sc" ] && [ -f "$so" ] || return 0
    # only an x86_64 machine takes the x86_64 file (the installer reads the machine of scsynth; this build is x86_64 only)
    [ "$(uname -m)" = x86_64 ] || return 0
    [ -f "$home/dust/data/twins/skip_TwinGrain_x86_64" ] && return 0
    command -v python3 > /dev/null 2>&1 || return 0
    python3 -c 'import ctypes,sys; ctypes.CDLL(sys.argv[1])' "$so" > /dev/null 2>&1 || return 0
    local other r
    for r in "$ext" /usr/local/share/SuperCollider/Extensions /usr/share/SuperCollider/Extensions "$home/dust/code"; do
        [ -d "$r" ] || continue
        other="$(find "$r" -type f \( -name 'TwinGrain.sc' -o -name 'TwinGrain.so' -o -name 'TwinGrain_scsynth.so' \) -not -path "$ext/twins/*" -not -path "$tw/lib/ugens/*" 2> /dev/null | head -n 1)"
        if [ -n "$other" ]; then
            echo "twins: $other exists, so twins' own TwinGrain was not copied (two copies make SuperCollider stop: duplicate class)"
            return 0
        fi
    done
    local d="$ext/twins"
    if cmp -s "$sc" "$d/TwinGrain.sc" && cmp -s "$so" "$d/TwinGrain.so"; then
        return 0
    fi
    mkdir -p "$d" 2> /dev/null || { echo "twins: cannot write to $d"; return 0; }
    local t1 t2
    t1="$(mktemp "$d/.TwinGrain.sc.XXXXXX" 2> /dev/null)" && t2="$(mktemp "$d/.TwinGrain.so.XXXXXX" 2> /dev/null)" || { echo "twins: cannot write to $d"; return 0; }
    if cp "$sc" "$t1" 2> /dev/null && cp "$so" "$t2" 2> /dev/null && chmod 755 "$t2" && mv -f "$t2" "$d/TwinGrain.so" && mv -f "$t1" "$d/TwinGrain.sc"; then
        echo "twins: copied twins' own TwinGrain (lib/ugens of the script) to $d, the copy its installer would make"
    else
        echo "twins: could not copy TwinGrain to $d"
    fi
    for t in "$t1" "$t2"; do
        [ -f "$t" ] && rm -f "${t:?}"
    done
    return 0
}

case "${1:-}" in
    sync) shift; cmd_sync "$@"; exit 0 ;;
    *) echo "usage: $0 sync <norns home>" >&2; exit 2 ;;
esac
