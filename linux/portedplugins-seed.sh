#!/bin/bash
# the PortedPlugins pack that ships with Verdandi (x86_64: AnalogChew, AnalogLoss, AnalogDegrade for the script twins, and the rest of the collection), and how it gets into
# the user's SuperCollider extension folder. the pattern of mi-ugens-seed.sh (docs/port/phase-m29.md).
#
#   portedplugins-seed.sh stamp <pack dir> <serial> <upstream commit> <build date> <verdandi version> [source note]
#       (build) writes <pack>/.verdandi-stamp and <pack>/.verdandi-files (sha256 of every file) so that a later seed can tell its own untouched copy from anything else
#   portedplugins-seed.sh seed <pack dir> <norns home>
#       (launcher, before sclang starts) copies the pack to <home>/.local/share/SuperCollider/Extensions/PortedPlugins
#         - the folder is not there and no class of the pack is defined anywhere else (the extension folders, dust/code): seeded (temp folder, then rename)
#         - it is there with an older serial of ours and every file is as we wrote it: replaced by the newer pack
#         - anything else (a folder that is not ours, a copy the user changed, another file with one of our class names): left alone, one line says why
#       never deletes or overwrites what is not its own, never needs a network. NORNS_PORTED=0 (or ported=0 in audio.conf) turns it off. always exits 0: a failure here
#       must not stop norns. no pack folder (a checkout whose build step has not run): silent.
#   portedplugins-seed.sh heal <pack dir> <norns home>
#       (launcher, after seed) the script twins' own installer downloads the Raspberry Pi PortedPlugins (class files and ARM plug-ins) into the extension folder. when Verdandi's
#       own copy is in the extension folder and intact, the foreign class files and plug-ins with the names of the pack that are found in the user's extension folder and
#       dust/code, and are not a working x86_64 pair, are moved into <home>/disabled/ with `verdandi tidy disable` (manifest line, how to restore; nothing is deleted), one line. a
#       foreign x86_64 pair is left alone and reported (two copies make sclang stop: duplicate class). own copy missing or changed: nothing is moved.
#       NORNS_PORTED_HEAL=0 turns it off. always exits 0.
#   portedplugins-seed.sh info <norns home>
#       prints the stamp of the copy in the extension folder as key=value lines (state=own|modified|foreign|none)
set -u

STAMP=.verdandi-stamp
LIST=.verdandi-files
PACK=PortedPlugins

ext_of() { echo "$1/.local/share/SuperCollider/Extensions"; }

enabled() {
    case "$(printf '%s' "${NORNS_PORTED:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

stamp_get() { sed -n "s/^$2=//p" "$1" 2> /dev/null | head -n 1; }

# 0 if every file listed in <dir>/.verdandi-files is unchanged and there is no other file in <dir>
intact() {
    local d="$1"
    [ -f "$d/$LIST" ] || return 1
    (cd "$d" && sha256sum --quiet -c "$LIST" > /dev/null 2>&1) || return 1
    local a b
    a="$(cd "$d" && find . -type f -not -name "$STAMP" -not -name "$LIST" | sort)"
    b="$(sed 's/^[0-9a-f]*  //' "$d/$LIST" | sort)"
    [ "$a" = "$b" ]
}

cmd_stamp() {
    local d="$1" serial="$2" commit="$3" built="$4" ver="$5" source="${6:-}"
    rm -f "${d:?}/${STAMP:?}" "${d:?}/${LIST:?}"
    (cd "$d" && find . -type f | sort | xargs -d '\n' sha256sum > "../.ported-files.$$" && mv "../.ported-files.$$" "$LIST") || return 1
    {
        echo "pack=$PACK"
        echo "serial=$serial"
        echo "commit=$commit"
        echo "built=$built"
        echo "verdandi=$ver"
        if [ -n "$source" ]; then echo "source=$source"; fi
    } > "$d/$STAMP"
}

# the class names of a pack (one per line)
class_names() { ls "$1/Classes" 2> /dev/null | sed -n 's/\.sc$//p'; }

# the roots where a foreign copy would be found
roots_of() { echo "$(ext_of "$1")" /usr/local/share/SuperCollider/Extensions /usr/share/SuperCollider/Extensions "$1/dust/code"; }

# the first class file of the pack's names found outside <skip> in the extension folders and dust/code (the .sc files only: those make duplicate classes)
other_class() {
    local pack="$1" home="$2" skip="$3" r f names=() n first=1
    for n in $(class_names "$pack"); do
        [ $first = 1 ] || names+=(-o)
        first=0
        names+=(-name "$n.sc")
    done
    [ ${#names[@]} -gt 0 ] || return 1
    for r in $(roots_of "$home"); do
        [ -d "$r" ] || continue
        f="$(find "$r" -type f \( "${names[@]}" \) -not -path "$skip/*" 2> /dev/null | head -n 1)"
        [ -n "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

cmd_seed() {
    local pack="$1" home="$2"
    enabled || return 0
    [ -d "$pack" ] && [ -f "$pack/$STAMP" ] || return 0
    local ext dest tmp serial cur
    ext="$(ext_of "$home")"
    dest="$ext/$PACK"
    serial="$(stamp_get "$pack/$STAMP" serial)"
    if [ -e "$dest" ]; then
        if [ ! -f "$dest/$STAMP" ] || [ "$(stamp_get "$dest/$STAMP" pack)" != "$PACK" ]; then
            echo "PortedPlugins: $dest is not from Verdandi, left alone (the pack Verdandi ships was not copied)"
            return 0
        fi
        cur="$(stamp_get "$dest/$STAMP" serial)"
        case "$cur$serial" in *[!0-9]*) return 0 ;; esac
        [ "$serial" -gt "$cur" ] || return 0
        if ! intact "$dest"; then
            echo "PortedPlugins: $dest has changed since Verdandi put it there, left alone (a newer pack is available; remove the folder to get it)"
            return 0
        fi
        tmp="$(mktemp -d "$ext/.ported-new.XXXXXX")" || { echo "PortedPlugins: cannot write to $ext"; return 0; }
        if cp -a "$pack/." "$tmp/" 2> /dev/null && mv "$dest" "$tmp.old" && mv "$tmp" "$dest"; then
            rm -rf "${tmp:?}.old"
            echo "PortedPlugins: updated $dest to serial $serial ($(stamp_get "$dest/$STAMP" commit | cut -c1-7))"
        else
            [ -d "$tmp.old" ] && [ ! -e "$dest" ] && mv "$tmp.old" "$dest"
            rm -rf "${tmp:?}"
            echo "PortedPlugins: could not update $dest, left as it was"
        fi
        return 0
    fi
    # twins' own Raspberry Pi download (class files and ARM plug-ins) cannot work here and would make the copy impossible: moved aside first (disabled/, restorable)
    do_heal "$pack" "$home" 0 0
    local other
    if other="$(other_class "$pack" "$home" "$dest")"; then
        echo "PortedPlugins: $other exists, so the pack Verdandi ships was not copied (two copies make SuperCollider stop: duplicate class)"
        return 0
    fi
    mkdir -p "$ext" 2> /dev/null && tmp="$(mktemp -d "$ext/.ported-new.XXXXXX" 2> /dev/null)" || { echo "PortedPlugins: cannot write to $ext"; return 0; }
    if cp -a "$pack/." "$tmp/" 2> /dev/null && mv "$tmp" "$dest" 2> /dev/null; then
        echo "PortedPlugins: seeded $dest (serial $serial, $(stamp_get "$dest/$STAMP" commit | cut -c1-7))"
    else
        rm -rf "${tmp:?}"
        echo "PortedPlugins: could not copy the pack to $dest"
    fi
    return 0
}

cmd_info() {
    local d state
    d="$(ext_of "$1")/$PACK"
    if [ ! -e "$d" ]; then echo "state=none"; return 0; fi
    if [ ! -f "$d/$STAMP" ]; then echo "state=foreign"; return 0; fi
    if intact "$d"; then state=own; else state=modified; fi
    echo "state=$state"
    cat "$d/$STAMP"
}

heal_enabled() {
    case "$(printf '%s' "${NORNS_PORTED_HEAL:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

intact_own() {
    local d
    d="$(ext_of "$1")/$PACK"
    [ -f "$d/$STAMP" ] && [ "$(stamp_get "$d/$STAMP" pack)" = "$PACK" ] && intact "$d"
}

# the machine of an ELF file: x86 (x86_64), arm (32 or 64 bit ARM), other, or none when it is not an ELF file
elf_kind() {
    local m magic
    magic="$(od -An -tx1 -N4 "$1" 2> /dev/null | tr -d ' \n')"
    [ "$magic" = 7f454c46 ] || { echo none; return; }
    m="$(od -An -tu1 -j18 -N2 "$1" 2> /dev/null | awk '{ print $1 + 256 * $2 }')"
    case "$m" in 62) echo x86 ;; 40 | 183) echo arm ;; *) echo other ;; esac
}

NOTE_TEXT="twins' Raspberry Pi PortedPlugins were moved aside; Verdandi's own copy is in use."

# the foreign files with the names of the pack that cannot work here (a Raspberry Pi plug-in, a class file with no working x86_64 plug-in beside it) are moved into disabled/.
# require_own=1 (the launcher's heal): only when Verdandi's own copy is in the extension folder and intact. require_own=0 (the seed, before it copies): the files cannot load on this
# machine anyway, and they are the reason a pack could not be copied; report_keep=0: a working foreign copy is not reported here (the seed says it in its own line)
do_heal() {
    local pack="$1" home="$2" require_own="$3" report_keep="$4"
    heal_enabled || return 0
    [ -d "$pack" ] && [ -f "$pack/$STAMP" ] && [ -d "$home" ] || return 0
    local tidy="${NORNS_TIDY:-$(dirname "$0")/tidy.sh}"
    [ -x "$tidy" ] || return 0
    if [ "$require_own" = 1 ]; then intact_own "$home" || return 0; fi
    local dest r f n kind moves="" keep="" names=() first=1
    dest="$(ext_of "$home")/$PACK"
    for n in $(class_names "$pack"); do
        [ $first = 1 ] || names+=(-o)
        first=0
        names+=(-name "$n.sc" -o -name "$n.so" -o -name "${n}_scsynth.so")
    done
    [ ${#names[@]} -gt 0 ] || return 0
    for r in "$(ext_of "$home")" "$home/dust/code"; do
        [ -d "$r" ] || continue
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in "$dest"/*) continue ;; esac
            case "$f" in *.sc) kind=sc ;; *) kind="$(elf_kind "$f")" ;; esac
            if [ "$kind" = x86 ]; then
                keep="$keep
$f"
            else
                moves="$moves
$f"
            fi
        done <<EOF
$(find "$r" -type f \( "${names[@]}" \) 2> /dev/null | sort)
EOF
    done
    # a class file is moved only when no working x86_64 plug-in of the same name sits next to it or next to its Classes folder (a working pair is a real second copy: reported, not moved)
    local n_moved=0 ids="" res id base dir d
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            *.sc)
                base="$(basename "$f" .sc)"
                dir="$(dirname "$f")"
                # the plug-in sits next to the class file or, in a pack, next to its Classes folder
                for d in "$dir/$base.so" "$dir/${base}_scsynth.so" "$dir/../$base.so" "$dir/../${base}_scsynth.so"; do
                    if [ -f "$d" ] && [ "$(elf_kind "$d")" = x86 ]; then
                        keep="$keep
$f"
                        continue 2
                    fi
                done
                ;;
        esac
        res="$(NORNS_HOME="$home" TIDY_HOME="$home" "$tidy" disable "$f" "a PortedPlugins file that is not Verdandi's (Raspberry Pi or a second copy)" 2>&1)" || continue
        id="$(printf '%s' "$res" | sed -n 's/.*(id \([^)]*\)).*/\1/p' | head -n 1)"
        n_moved=$((n_moved + 1))
        ids="$ids $id"
    done <<EOF
$moves
EOF
    if [ $n_moved -gt 0 ]; then
        echo "PortedPlugins: moved $n_moved foreign PortedPlugins file(s) into $home/disabled/ (Verdandi's own copy is in use); to put one back: verdandi tidy restore <id> (ids:${ids})"
        printf '%s\n' "$NOTE_TEXT" > "$home/.ported-heal-note" 2> /dev/null || true
    fi
    if [ "$report_keep" = 1 ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            echo "PortedPlugins: $f is a copy that is not Verdandi's, left alone (two copies make SuperCollider stop with duplicate classes: SYSTEM > CLEAN UP > CLASSES names them)"
        done <<EOF
$keep
EOF
    fi
    return 0
}

cmd_heal() { do_heal "$1" "$2" 1 1; }

case "${1:-}" in
    heal) shift; cmd_heal "$@"; exit 0 ;;
    stamp) shift; cmd_stamp "$@" ;;
    seed) shift; cmd_seed "$@"; exit 0 ;;
    info) shift; cmd_info "$@" ;;
    *) echo "usage: $0 stamp <pack> <serial> <commit> <date> <version> | seed <pack> <home> | heal <pack> <home> | info <home>" >&2; exit 2 ;;
esac
