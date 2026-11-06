#!/bin/bash
# the mi-UGens pack that ships with Verdandi (x86_64), and how it gets into the user's SuperCollider extension folder.
#
#   mi-ugens-seed.sh stamp <pack dir> <serial> <upstream commit> <build date> <verdandi version> [source note]
#       (package build) writes <pack>/.verdandi-stamp and <pack>/.verdandi-files (sha256 of every file) so that a later seed can tell
#       its own untouched copy from anything else
#   mi-ugens-seed.sh seed <pack dir> <norns home>
#       (launcher, before sclang starts) copies the pack to <home>/.local/share/SuperCollider/Extensions/mi-UGens
#         - the folder is not there and no other Mi*.sc exists in the extension folders or dust/code: seeded (temp folder, then rename)
#         - it is there with an older stamp of ours and every file is as we wrote it: replaced by the newer pack
#         - anything else (a folder that is not ours, a copy the user changed, another Mi*.sc): left alone, one line says why
#       never deletes or overwrites what is not its own, never needs a network. NORNS_MI_UGENS=0 (or mi_ugens=0 in audio.conf) turns it off.
#       always exits 0: a failure here must not stop norns. no pack folder (a source checkout): silent.
#   mi-ugens-seed.sh heal <pack dir> <norns home>
#       (launcher, before sclang starts, after seed) a script or mod that downloaded the Raspberry Pi mi-UGens leaves files that stop SuperCollider. when
#       Verdandi's own copy is in the extension folder and intact (stamp and sha256 list match) the foreign wrong-architecture mi-UGens items that
#       build/linux/mi_heal finds (the user's extension folder and dust/code only, never other plug-ins) are moved into <home>/disabled/ with
#       `verdandi tidy disable` (manifest line with what, from where, when, why and how to restore; nothing is deleted), one log line, and a note for the
#       window is left in <home>/.mi-heal-note (shown once). own copy missing or changed: nothing is moved (the PLUGINS note and SYSTEM > CLEAN UP stay). a
#       foreign copy that loads here is left alone, one line (duplicate classes: the class check). NORNS_MI_UGENS_HEAL=0 (mi_ugens_heal=0 in audio.conf)
#       turns it off. MI_HEAL_TOOL (the scanner) and NORNS_TIDY (the tidy tool) say where the tools are. always exits 0; no tool or no pack: silent.
#   mi-ugens-seed.sh info <norns home>
#       prints the stamp of the copy in the extension folder as key=value lines (state=own|modified|foreign|none)
set -u

STAMP=.verdandi-stamp
LIST=.verdandi-files

ext_of() { echo "$1/.local/share/SuperCollider/Extensions"; }

enabled() {
    case "$(printf '%s' "${NORNS_MI_UGENS:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

stamp_get() { # file key
    sed -n "s/^$2=//p" "$1" 2> /dev/null | head -n 1
}

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
    rm -f "$d/$STAMP" "$d/$LIST"
    (cd "$d" && find . -type f | sort | xargs -d '\n' sha256sum > "../.mi-files.$$" && mv "../.mi-files.$$" "$LIST") || return 1
    {
        echo "pack=mi-UGens"
        echo "serial=$serial"
        echo "commit=$commit"
        echo "built=$built"
        echo "verdandi=$ver"
        if [ -n "$source" ]; then echo "source=$source"; fi
    } > "$d/$STAMP"
}

# the first Mi*.sc that is not inside <skip> (the extension folders and dust/code)
other_mi() {
    local home="$1" skip="$2" r f
    for r in "$(ext_of "$home")" /usr/local/share/SuperCollider/Extensions /usr/share/SuperCollider/Extensions "$home/dust/code"; do
        [ -d "$r" ] || continue
        f="$(find "$r" -name 'Mi*.sc' -not -path "$skip/*" 2> /dev/null | head -n 1)"
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
    dest="$ext/mi-UGens"
    serial="$(stamp_get "$pack/$STAMP" serial)"
    if [ -e "$dest" ]; then
        if [ ! -f "$dest/$STAMP" ] || [ "$(stamp_get "$dest/$STAMP" pack)" != mi-UGens ]; then
            echo "mi-UGens: $dest is not from Verdandi, left alone (the pack Verdandi ships was not copied)"
            return 0
        fi
        cur="$(stamp_get "$dest/$STAMP" serial)"
        case "$cur$serial" in *[!0-9]*) return 0 ;; esac
        [ "$serial" -gt "$cur" ] || return 0
        if ! intact "$dest"; then
            echo "mi-UGens: $dest has changed since Verdandi put it there, left alone (a newer pack is available; remove the folder to get it)"
            return 0
        fi
        tmp="$(mktemp -d "$ext/.mi-ugens-new.XXXXXX")" || { echo "mi-UGens: cannot write to $ext"; return 0; }
        if cp -a "$pack/." "$tmp/" 2> /dev/null && mv "$dest" "$tmp.old" && mv "$tmp" "$dest"; then
            rm -rf "$tmp.old"
            echo "mi-UGens: updated $dest to serial $serial ($(stamp_get "$dest/$STAMP" commit | cut -c1-7))"
        else
            [ -d "$tmp.old" ] && [ ! -e "$dest" ] && mv "$tmp.old" "$dest"
            rm -rf "$tmp"
            echo "mi-UGens: could not update $dest, left as it was"
        fi
        return 0
    fi
    local other
    if other="$(other_mi "$home" "$dest")"; then
        echo "mi-UGens: $other exists, so the pack Verdandi ships was not copied (two copies make SuperCollider stop: duplicate class)"
        return 0
    fi
    mkdir -p "$ext" 2> /dev/null && tmp="$(mktemp -d "$ext/.mi-ugens-new.XXXXXX" 2> /dev/null)" || { echo "mi-UGens: cannot write to $ext"; return 0; }
    if cp -a "$pack/." "$tmp/" 2> /dev/null && mv "$tmp" "$dest" 2> /dev/null; then
        echo "mi-UGens: seeded $dest (serial $serial, $(stamp_get "$dest/$STAMP" commit | cut -c1-7))"
    else
        rm -rf "$tmp"
        echo "mi-UGens: could not copy the pack to $dest"
    fi
    return 0
}

cmd_info() {
    local d state
    d="$(ext_of "$1")/mi-UGens"
    if [ ! -e "$d" ]; then echo "state=none"; return 0; fi
    if [ ! -f "$d/$STAMP" ]; then echo "state=foreign"; return 0; fi
    if intact "$d"; then state=own; else state=modified; fi
    echo "state=$state"
    cat "$d/$STAMP"
}

heal_enabled() {
    case "$(printf '%s' "${NORNS_MI_UGENS_HEAL:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}

NOTE_TEXT="A script downloaded Raspberry Pi mi-UGens. Moved aside; Verdandi's own copy is in use."

cmd_heal() {
    local pack="$1" home="$2"
    heal_enabled || return 0
    [ -d "$pack" ] && [ -f "$pack/$STAMP" ] && [ -d "$home" ] || return 0
    local tool="${MI_HEAL_TOOL:-$(dirname "$0")/../build/linux/mi_heal}"
    local tidy="${NORNS_TIDY:-$(dirname "$0")/tidy.sh}"
    [ -x "$tool" ] && [ -x "$tidy" ] || return 0
    local out arms x86
    out="$("$tool" scan "$home" 2> /dev/null)" || return 0
    arms="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "arm"')"
    x86="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "x86" { print $2 }')"
    if [ -n "$arms" ]; then
        if ! intact_own "$home"; then
            echo "mi-UGens: Raspberry Pi mi-UGens found, but Verdandi's own copy is missing or changed, so nothing was moved (see the PLUGINS note and SYSTEM > CLEAN UP)"
        else
            local n=0 ids="" path kind why res id
            while IFS="$(printf '\t')" read -r _ path kind why; do
                [ -n "$path" ] || continue
                res="$(NORNS_HOME="$home" TIDY_HOME="$home" "$tidy" disable "$path" "$why" 2>&1)" || continue
                id="$(printf '%s' "$res" | sed -n 's/.*(id \([^)]*\)).*/\1/p' | head -n 1)"
                n=$((n + 1)); ids="$ids $id"
            done <<EOF
$arms
EOF
            if [ $n -gt 0 ]; then
                echo "mi-UGens: moved $n foreign Raspberry Pi mi-UGens item(s) into $home/disabled/ (Verdandi's own copy is in use); to put one back: verdandi tidy restore <id> (ids:${ids})"
                printf '%s\n' "$NOTE_TEXT" > "$home/.mi-heal-note" 2> /dev/null || true
            fi
        fi
    fi
    local p
    for p in $x86; do
        echo "mi-UGens: $p is a copy of mi-UGens that is not Verdandi's, left alone (two copies make SuperCollider stop with duplicate classes: SYSTEM > CLEAN UP > CLASSES names them)"
    done
    return 0
}

# the own copy is there, stamped, and every file as it was written (the same rule as the update)
intact_own() {
    local d
    d="$(ext_of "$1")/mi-UGens"
    [ -f "$d/$STAMP" ] && [ "$(stamp_get "$d/$STAMP" pack)" = mi-UGens ] && intact "$d"
}

case "${1:-}" in
    heal) shift; cmd_heal "$@"; exit 0 ;;
    stamp) shift; cmd_stamp "$@" ;;
    seed) shift; cmd_seed "$@"; exit 0 ;;
    info) shift; cmd_info "$@" ;;
    *) echo "usage: $0 stamp <pack> <serial> <commit> <date> <version> | seed <pack> <home> | info <home>" >&2; exit 2 ;;
esac
