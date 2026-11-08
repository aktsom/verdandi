#!/bin/bash
# plugin-heal.sh heal <norns home>
# (launcher, at every start, before sclang) any wrong-architecture SuperCollider plug-in that would stop sclang is moved aside into <home>/disabled/ with
# `verdandi tidy disable` (manifest line: what, from where, when, why, the restore command; nothing is deleted), one log line, and one plain note for the window
# (<home>/.plugin-heal-note, shown once by the menu; said once per day for the same plug-ins). what counts is what build/linux/plugin_arch_check finds in the user's
# extension folder and in dust/code (it writes <home>/.plugin-fix: a folder when all its plug-ins are wrong, else the files): never a Lua library, a non-ELF file, a
# plug-in that fits this machine, or anything outside those two places; a plug-in outside the norns home (a system folder) is not moved here, the plug-in check reports it.
# when Verdandi ships an x86-64 replacement (NamAmp, mi-UGens) the note says so, and the seed that runs next puts it in.
# NORNS_PLUGIN_HEAL=0 (plugin_heal=0 in audio.conf) turns it off; NORNS_PLUGIN_CHECK=0 turns the check, and so this, off. always exits 0. tools: PLUGIN_ARCH_CHECK_TOOL, NORNS_TIDY;
# NORNS_NAMAMP_PACK / NORNS_MI_PACK say where Verdandi's own packs are (to know what it can replace).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

enabled() {
    case "$(printf '%s' "${NORNS_PLUGIN_HEAL:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 1 ;; esac
    return 0
}
is_off() { case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in 0 | off | false | no) return 0 ;; esac; return 1; }

# does Verdandi ship a replacement for what is in $1 (a file or a folder)? 0 if every plug-in in it has one
replaced() {
    local t="$1" f base any=1 all=0
    local files
    if [ -d "$t" ]; then files="$(find "$t" -type f \( -name '*.so' -o -name '*.scx' \) 2> /dev/null)"; else files="$t"; fi
    [ -n "$files" ] || return 1
    while IFS= read -r f; do
        base="${f##*/}"
        case "$base" in
        NamAmp.so)
            if ! is_off "${NORNS_NAMAMP:-}" && [ -f "${NORNS_NAMAMP_PACK:-$HERE/../namamp/NamAmp}/NamAmp.so" ]; then any=0; else all=1; fi ;;
        Mi[A-Z]*.so | Mi[A-Z]*.scx)
            if ! is_off "${NORNS_MI_UGENS:-}" && [ -f "${NORNS_MI_PACK:-$HERE/../mi-ugens/mi-UGens}/.verdandi-stamp" ]; then any=0; else all=1; fi ;;
        *) all=1 ;;
        esac
    done <<EOF
$files
EOF
    [ $any = 0 ] && [ $all = 0 ]
}

cmd_heal() {
    local home="$1"
    enabled || return 0
    [ -d "$home" ] || return 0
    local tool="${PLUGIN_ARCH_CHECK_TOOL:-$HERE/../build/linux/plugin_arch_check}"
    local tidy="${NORNS_TIDY:-$HERE/tidy.sh}"
    [ -x "$tool" ] && [ -x "$tidy" ] || return 0
    "$tool" "$home" > /dev/null 2>&1 || return 0
    [ -s "$home/.plugin-fix" ] || return 0
    local home_real
    home_real="$(cd "$home" && pwd -P)"
    local n=0 ids="" names="" target why res id base rep_all=0 rep_any=1 arm=0
    while IFS="$(printf '\t')" read -r target why; do
        [ -n "$target" ] || continue
        case "$target" in "$home"/* | "$home_real"/*) ;; *) continue ;; esac
        [ -e "$target" ] || continue
        base="${target##*/}"
        if replaced "$target"; then rep_any=0; else rep_all=1; fi
        case "$why" in *ARM*) arm=1 ;; esac
        res="$(NORNS_HOME="$home" TIDY_HOME="$home" "$tidy" disable "$target" "${why:-wrong-architecture plug-in}" 2>&1)" || continue
        id="$(printf '%s' "$res" | sed -n 's/.*(id \([^)]*\)).*/\1/p' | head -n 1)"
        n=$((n + 1)); ids="$ids $id"; names="${names:+$names, }$base"
    done < "$home/.plugin-fix"
    [ $n -gt 0 ] || return 0
    echo "plugin heal: moved $n wrong-architecture SuperCollider plug-in item(s) ($names) into $home/disabled/ so that SuperCollider can start; to put one back: verdandi tidy restore <id> (ids:${ids})"
    # the window note, once per day for the same names
    local what sentence short arts
    short="$names"
    [ "$(printf '%s' "$names" | tr -cd ',' | wc -c)" -gt 2 ] && short="$(printf '%s' "$names" | cut -d, -f1-3), ..."
    if [ $arm = 1 ]; then what="Raspberry Pi plug-in"; else what="plug-in for another machine"; fi
    if printf '%s' "$names" | grep -q ','; then arts="A script installed ${what}s"; else arts="A script installed a ${what}"; fi
    if [ $rep_all = 0 ]; then
        sentence="$arts ($short). Moved aside; Verdandi's own x86-64 copy is in use."
    elif [ $rep_any = 0 ]; then
        sentence="$arts ($short). Moved aside so that SuperCollider can start; Verdandi's own copy is in use where it has one, the other scripts' engines will not work."
    elif printf '%s' "$names" | grep -q ','; then
        sentence="$arts ($short). Moved aside so that SuperCollider can start; the scripts' engines that need them will not work."
    else
        sentence="$arts ($short). Moved aside so that SuperCollider can start; the script's engine that needs it will not work."
    fi
    local state today key
    today="$(date +%Y-%m-%d)"
    key="$today $(printf '%s' "$names" | tr ',' '\n' | tr -d ' ' | sort -u | tr '\n' ' ')"
    if [ "$(cat "$home/.plugin-heal-state" 2> /dev/null)" != "$key" ]; then
        printf '%s\n' "$sentence" > "$home/.plugin-heal-note" 2> /dev/null || true
    fi
    printf '%s\n' "$key" > "$home/.plugin-heal-state" 2> /dev/null || true
    return 0
}

case "${1:-}" in
    heal) shift; cmd_heal "$@"; exit 0 ;;
    *) echo "usage: $0 heal <norns home>" >&2; exit 2 ;;
esac
