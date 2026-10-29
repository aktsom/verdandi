#!/bin/bash
# verdandi tidy: look after the files Verdandi makes in the norns home (docs/port/clean-layout.md). reached as `verdandi tidy ...` or `linux/norns.sh tidy ...`
#
#   verdandi tidy flatten [--home PATH]   the DRY RUN of the migration of a nested home (~/Verdandi/Verdandi into ~/Verdandi): it only READS, it prints
#                                         what is there, what would be moved and what could go wrong; nothing is moved, changed or deleted. the apply step
#                                         is not built: it waits for the owner to send this output (docs/port/clean-layout.md section 7)
#
# nothing here ever touches dust/ (scripts, samples, data), audio.conf or ui.conf
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"

say() { printf '%s\n' "$*"; }
die() { printf 'verdandi tidy: %s\n' "$*" >&2; exit 1; }

# bytes as 1.5G, 23M, 4K (one decimal below 10)
human() {
    awk -v b="${1:-0}" 'BEGIN {
        split("B K M G T", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        if (i == 1) printf "%d%s", b, u[i]; else if (b < 10) printf "%.1f%s", b, u[i]; else printf "%d%s", b, u[i]
    }'
}
bytes_of() { du -sb -- "$1" 2>/dev/null | cut -f1; }
# files and links (a link is user data too: the check after a move counts both)
count_files() { find "$1" \( -type f -o -type l \) 2>/dev/null | wc -l; }

# the norns home, as linux/norns.sh decides it (the environment, the config file, the default; a checkout: the folder above it)
find_home() {
    if [ -n "${NORNS_HOME:-}" ]; then printf '%s' "$NORNS_HOME"; return; fi
    if [ -f "$REPO/INSTALLED" ] || [ "${NORNS_INSTALLED:-}" = 1 ]; then
        local conf="${XDG_CONFIG_HOME:-${HOME:-}/.config}/verdandi/home" h
        h="$(head -n 1 "$conf" 2>/dev/null | tr -d '\r')"
        case "$h" in "~/"*) h="${HOME:-}/${h#\~/}" ;; esac
        if [ -n "$h" ]; then printf '%s' "$h"; else printf '%s' "${HOME:-}/Verdandi"; fi
    else
        dirname "$REPO"
    fi
}

# is a norns, sclang or jackd running? (any home: a plain process name match, no command lines read)
running_programs() {
    local out="" n
    for n in norns sclang scsynth jackd maiden; do
        pgrep -x "$n" >/dev/null 2>&1 && out="$out $n"
    done
    printf '%s' "${out# }"
}

# ---- flatten: the dry run ----
cmd_flatten() {
    local home="" apply=0
    while [ $# -gt 0 ]; do
        case "$1" in
        --home) home="${2:-}"; shift 2 ;;
        --apply | --undo) apply=1; shift ;;
        *) die "flatten: unknown argument '$1' (usage: verdandi tidy flatten [--home PATH])" ;;
        esac
    done
    if [ $apply -eq 1 ]; then
        die "flatten --apply is not built yet: only the dry run exists. run 'verdandi tidy flatten' and send the output; nothing is moved before you have confirmed the plan"
    fi
    [ -n "$home" ] || home="$(find_home)"
    home="${home%/}"
    local nested="$home/Verdandi"
    say "verdandi tidy flatten: DRY RUN. this only reads. nothing is moved, changed or deleted."
    say ""
    say "outer home:  $home"
    say "nested home: $nested"
    if [ ! -d "$home" ]; then say "RESULT nothing-to-do: the home does not exist"; return 0; fi
    if [ ! -d "$nested" ] || [ -L "$nested" ]; then
        say "RESULT nothing-to-do: there is no folder $nested (the home is not nested)"
        return 0
    fi
    if [ ! -e "$nested/dust" ] && [ ! -L "$nested/norns" ] && [ ! -e "$nested/audio.conf" ] && [ ! -e "$nested/matronrc.lua" ]; then
        say "RESULT nothing-to-do: $nested exists but does not look like a norns home (no dust, norns link, audio.conf or matronrc.lua): it is left alone"
        return 0
    fi

    local problems=0 reasons=""
    note_problem() { problems=$((problems + 1)); reasons="$reasons
  - $1"; }

    # 1. can it be done safely
    say "== checks"
    local run
    run="$(running_programs)"
    if [ -n "$run" ]; then
        say "   running now: $run. stop Verdandi before the real move (the dry run does not care)"
    else
        say "   no norns, sclang, scsynth, jackd or maiden is running"
    fi
    local dev_outer dev_nested
    dev_outer="$(stat -c %d "$home")"; dev_nested="$(stat -c %d "$nested")"
    if [ "$dev_outer" = "$dev_nested" ]; then
        say "   same file system: every move would be a rename (no data copied, none deleted)"
    else
        say "   DIFFERENT file systems: a rename is not possible, the move would be refused"
        note_problem "the nested folder is on another file system than the home"
    fi
    local avail
    avail="$(df -B1 --output=avail "$home" 2>/dev/null | tail -n 1 | tr -d ' ')"

    # 2. what is in the nested home (the content that has to be kept)
    say ""
    say "== inside the nested home ($nested)"
    local e name total=0 sz fc
    while IFS= read -r e; do
        name="$(basename "$e")"
        if [ -L "$e" ]; then
            say "   $name   (link -> $(readlink "$e"))"
        elif [ -d "$e" ]; then
            sz="$(bytes_of "$e")"; fc="$(count_files "$e")"
            say "   $name/   $(human "$sz"), $fc files and links"
            total=$((total + sz))
        else
            sz="$(stat -c %s "$e")"
            say "   $name   $(human "$sz")"
            total=$((total + sz))
        fi
    done < <(find "$nested" -mindepth 1 -maxdepth 1 | sort)
    say "   total $(human "$total")"
    local dust_files=0 dust_bytes=0
    if [ -d "$nested/dust" ]; then
        dust_files="$(count_files "$nested/dust")"; dust_bytes="$(bytes_of "$nested/dust")"
        say "   dust/ (yours): $dust_files files and links, $(human "$dust_bytes"): scripts $(find "$nested/dust/code" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l), audio files $(find "$nested/dust/audio" -type f 2>/dev/null | wc -l), data files $(find "$nested/dust/data" -type f 2>/dev/null | wc -l)"
    fi

    # 3. what is in the outer home besides the nested folder (leftovers, or something of yours)
    say ""
    say "== inside the outer home ($home), without the nested folder"
    local outer_n=0 outer_user=0
    while IFS= read -r e; do
        name="$(basename "$e")"
        [ "$name" = Verdandi ] && continue
        outer_n=$((outer_n + 1))
        if [ -L "$e" ]; then
            say "   $name   (link -> $(readlink "$e"))"
        elif [ -d "$e" ]; then
            fc="$(count_files "$e")"; sz="$(bytes_of "$e")"
            say "   $name/   $(human "$sz"), $fc files and links$([ "$fc" = 0 ] && echo " (only empty folders)")"
            [ "$name" = dust ] && [ "$fc" != 0 ] && outer_user=$((outer_user + 1))
        else
            say "   $name   $(human "$(stat -c %s "$e")")"
        fi
    done < <(find "$home" -mindepth 1 -maxdepth 1 | sort)
    [ $outer_n -eq 0 ] && say "   (nothing else)"
    if [ $outer_user -gt 0 ]; then
        say "   NOTE: the outer dust/ holds files. they would be moved to backups/ (never overwritten, never deleted) and you decide what to do with them"
    fi

    # 4. names that exist on both sides
    say ""
    say "== names on both sides (the plan keeps the nested one in place and puts the outer one in backups/)"
    local both=0 same
    while IFS= read -r e; do
        name="$(basename "$e")"
        [ "$name" = Verdandi ] && continue
        [ -e "$nested/$name" ] || [ -L "$nested/$name" ] || continue
        both=$((both + 1))
        same="different"
        if [ -f "$e" ] && [ -f "$nested/$name" ] && cmp -s "$e" "$nested/$name"; then same="identical"; fi
        if [ -L "$e" ] && [ -L "$nested/$name" ] && [ "$(readlink "$e")" = "$(readlink "$nested/$name")" ]; then same="identical (the same link)"; fi
        if [ -d "$e" ] && [ ! -L "$e" ] && [ "$(count_files "$e")" = 0 ]; then same="outer one has only empty folders"; fi
        say "   $name: $same"
    done < <(find "$home" -mindepth 1 -maxdepth 1 | sort)
    [ $both -eq 0 ] && say "   (none)"

    # 5. links that would break
    say ""
    say "== links inside the nested home"
    local links_in=0 links_out=0 broken=0 l target
    while IFS= read -r l; do
        target="$(readlink "$l")"
        case "$target" in
        "$nested"/* | "$nested")
            links_in=$((links_in + 1))
            say "   would need a new target (points into the nested folder): ${l#$nested/} -> $target"
            ;;
        *) links_out=$((links_out + 1)) ;;
        esac
        [ -e "$l" ] || broken=$((broken + 1))
    done < <(find "$nested" -type l 2>/dev/null | sort)
    say "   $links_out link(s) point elsewhere (unchanged by the move), $links_in point into the nested folder, $broken already broken"

    # 6. files that hold the old absolute path (small text files outside dust/audio): they are regenerated or reported, never trusted
    say ""
    say "== small files that contain the old path $nested"
    local holders=0
    while IFS= read -r e; do
        holders=$((holders + 1))
        say "   ${e#$nested/}"
    done < <(find "$nested" -path "$nested/dust/audio" -prune -o -path "$nested/backups" -prune -o -path "$nested/norns" -prune -o -type f -size -1024k -print0 2>/dev/null | xargs -0 grep -lIF -- "$nested" 2>/dev/null | sort | head -50)
    [ $holders -eq 0 ] && say "   (none)"
    if [ -f "$nested/.config/SuperCollider/sclang_conf.yaml" ]; then
        say "   the SuperCollider settings above list <home>/dust: the plan keeps the old file as sclang_conf.yaml.old and the launcher writes a new one"
    fi

    # 7. the plan
    say ""
    say "== the plan (nothing of this has been done)"
    say "   1. a backup folder backups/flatten-<time>/ in $home with before.tree (every path and size of both folders)"
    say "      and a HARD-LINK copy of dust/ ($dust_files files and links, no extra disk space; a full copy on request: $(human "$dust_bytes") needed, $(human "${avail:-0}") free)"
    say "   2. the outer leftovers ($outer_n item(s)) go to backups/flatten-<time>/outer/ or, if they are only empty folders, are removed with rmdir"
    say "   3. every entry of the nested home is renamed up into $home (no overwrite)"
    say "   4. $nested is removed only if it is empty by then"
    say "   5. sclang_conf.yaml is kept as .old and written again; links into the nested folder ($links_in) are rewritten only on your confirmation"
    say "   6. checks: file count and size of dust/ equal before and after ($dust_files files and links, $(human "$dust_bytes")); an undo is possible from the manifest"

    say ""
    if [ $problems -eq 0 ]; then
        say "RESULT ready: nothing found that stops the move ($links_in link(s) into the nested folder need your confirmation, $holders small file(s) hold the old path). dust/ would be moved as $dust_files files and links, $(human "$dust_bytes"). send this output and say go; nothing happens before that"
    else
        say "RESULT not-ready:$reasons"
    fi
    return 0
}

usage() {
    say "usage: verdandi tidy flatten [--home PATH]    dry run of the migration of a nested norns home (reads only)"
}

case "${1:-}" in
flatten) shift; cmd_flatten "$@" ;;
-h | --help | help | "") usage ;;
*) usage >&2; die "unknown command '$1'" ;;
esac
