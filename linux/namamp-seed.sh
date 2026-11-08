#!/bin/bash
# the NamAmp plug-in that ships with Verdandi (x86_64), and how it gets to the place princeton and its engine look: <extensions>/princeton/NamAmp.so.
#
#   namamp-seed.sh stamp <pack dir> <serial> <upstream commit> <build date> <verdandi version> [source note]
#       (package build) writes <pack>/.verdandi-namamp: pack=NamAmp, serial, commit, built, verdandi, source and the sha256 of <pack>/NamAmp.so
#   namamp-seed.sh seed <pack dir> <norns home>
#       (launcher, before sclang starts, after the start-up heal) copies the plug-in with its stamp
#         - when the script folder dust/code/princeton or Extensions/princeton exists (nobody else gets a file) and there is no NamAmp.so there: seeded (temp folder,
#           then rename; the date of the package is kept: the engine wants the file older than the start of sclang)
#         - there with our stamp, the sha256 matches, an older serial: replaced by the newer pack
#         - anything else (a file that is not ours, a copy that was changed): left alone, one line says why. a wrong-architecture file is moved aside by the
#           start-up heal (linux/plugin-heal.sh) before this runs
#       never deletes or overwrites what is not its own, never needs a network. NORNS_NAMAMP=0 (namamp=0 in audio.conf) turns it off. always exits 0. no pack folder
#       (a source checkout): silent.
#   namamp-seed.sh info <norns home>
#       state=own|modified|foreign|none and the stamp as key=value lines
set -u

STAMP=.verdandi-namamp
SO=NamAmp.so

ext_of() { echo "$1/.local/share/SuperCollider/Extensions"; }

enabled() {
    case "$(printf '%s' "${NORNS_NAMAMP:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

stamp_get() { sed -n "s/^$2=//p" "$1" 2> /dev/null | head -n 1; }
sha_of() { sha256sum "$1" 2> /dev/null | cut -d' ' -f1; }

# our copy in <dir>: the stamp says pack=NamAmp and the plug-in is as it was written
own_intact() {
    local d="$1"
    [ -f "$d/$STAMP" ] && [ "$(stamp_get "$d/$STAMP" pack)" = NamAmp ] && [ -f "$d/$SO" ] && [ "$(sha_of "$d/$SO")" = "$(stamp_get "$d/$STAMP" sha256)" ]
}

cmd_stamp() {
    local d="$1" serial="$2" commit="$3" built="$4" ver="$5" source="${6:-}"
    {
        echo "pack=NamAmp"
        echo "serial=$serial"
        echo "commit=$commit"
        echo "built=$built"
        echo "verdandi=$ver"
        if [ -n "$source" ]; then echo "source=$source"; fi
        echo "sha256=$(sha_of "$d/$SO")"
    } > "$d/$STAMP"
}

cmd_seed() {
    local pack="$1" home="$2"
    enabled || return 0
    [ -f "$pack/$SO" ] && [ -f "$pack/$STAMP" ] && [ -d "$home" ] || return 0
    local ext dir dest serial cur tmp
    ext="$(ext_of "$home")"
    dir="$ext/princeton"
    dest="$dir/$SO"
    [ -d "$home/dust/code/princeton" ] || [ -d "$dir" ] || return 0
    serial="$(stamp_get "$pack/$STAMP" serial)"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ ! -f "$dir/$STAMP" ] || [ "$(stamp_get "$dir/$STAMP" pack)" != NamAmp ]; then
            echo "NamAmp: $dest is not from Verdandi, left alone (a wrong-architecture one is moved aside by the start-up heal, then Verdandi's own copy is seeded)"
            return 0
        fi
        cur="$(stamp_get "$dir/$STAMP" serial)"
        case "$cur$serial" in *[!0-9]*) return 0 ;; esac
        [ "$serial" -gt "$cur" ] || return 0
        if ! own_intact "$dir"; then
            echo "NamAmp: $dest has changed since Verdandi put it there, left alone (a newer plug-in is available; move the file aside to get it)"
            return 0
        fi
    fi
    mkdir -p "$dir" 2> /dev/null && tmp="$(mktemp -d "$dir/.namamp-new.XXXXXX" 2> /dev/null)" || { echo "NamAmp: cannot write to $dir"; return 0; }
    # the stamp first: a copy without a stamp would be taken for someone else's and never touched again, a stamp without the plug-in is seeded again
    if cp -a "$pack/$SO" "$tmp/$SO" 2> /dev/null && cp "$pack/$STAMP" "$tmp/$STAMP" 2> /dev/null && mv -f "$tmp/$STAMP" "$dir/$STAMP" 2> /dev/null && mv -f "$tmp/$SO" "$dest" 2> /dev/null; then
        rmdir "$tmp" 2> /dev/null
        if [ -n "${cur:-}" ]; then
            echo "NamAmp: updated $dest to serial $serial"
        else
            echo "NamAmp: seeded $dest (serial $serial, $(stamp_get "$dir/$STAMP" commit | cut -c1-7))"
        fi
    else
        rm -rf "$tmp"
        echo "NamAmp: could not copy the plug-in to $dest"
    fi
    return 0
}

cmd_info() {
    local d state
    d="$(ext_of "$1")/princeton"
    if [ ! -e "$d/$SO" ]; then echo "state=none"; return 0; fi
    if [ ! -f "$d/$STAMP" ] || [ "$(stamp_get "$d/$STAMP" pack)" != NamAmp ]; then echo "state=foreign"; return 0; fi
    if own_intact "$d"; then state=own; else state=modified; fi
    echo "state=$state"
    cat "$d/$STAMP"
}

case "${1:-}" in
    stamp) shift; cmd_stamp "$@" ;;
    seed) shift; cmd_seed "$@"; exit 0 ;;
    info) shift; cmd_info "$@" ;;
    *) echo "usage: $0 stamp <pack> <serial> <commit> <date> <version> [source] | seed <pack> <home> | info <home>" >&2; exit 2 ;;
esac
