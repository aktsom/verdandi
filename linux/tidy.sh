#!/bin/bash
# verdandi tidy: look after the files Verdandi makes in the norns home (docs/port/clean-layout.md). reached as `verdandi tidy ...` or `linux/norns.sh tidy ...`
#
#   verdandi tidy list [--tsv]            what is in disabled/, logs/, logs/crash/, the seeded packs and cache/, with sizes
#   verdandi tidy disable PATH WHY        move something out of the way into disabled/ (a line in disabled/MANIFEST.tsv: what, from, when, why, how to restore)
#   verdandi tidy restore ID              put it back where it came from (refuses if that place is taken)
#   verdandi tidy remove-older DAYS [--yes]   what is older than DAYS in those five groups; removes it only with --yes (the CLEAN UP page asks first)
#   verdandi tidy rotate NAME...          the launcher's start-up: keep the last 5 runs of logs/NAME.log, cap launcher.log, keep the last 5 crash reports
#   verdandi tidy cap                     cut a running log that grew over 10 MB to its last megabyte
#   verdandi tidy flatten [--home PATH]   the DRY RUN of the migration of a nested home (~/Verdandi/Verdandi into ~/Verdandi): it only READS, it prints
#                                         what is there, what would be moved and what could go wrong; nothing is moved, changed or deleted. the apply step
#                                         is not built: it waits for the owner to send this output (docs/port/clean-layout.md section 7)
#
# nothing here ever touches dust/ (scripts, samples, data), audio.conf or ui.conf, except `disable` of a path the user names (a plug-in file or folder inside
# dust that stops SuperCollider): a restorable move, never a delete
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


# ---- the files of ours: disabled/, logs/, logs/crash/, seeded packs, cache/ ----
LOG_KEEP=5                    # runs kept of each log (the current one and 4 older)
LOG_CAP=$((10 * 1024 * 1024)) # a running log is cut to its last megabyte above this
LOG_TAIL=$((1024 * 1024))
LAUNCHER_CAP=$((1024 * 1024))
CRASH_KEEP=5

tidy_home() {
    local h
    h="${TIDY_HOME:-$(find_home)}"
    h="${h%/}"
    [ -d "$h" ] || die "the norns home $h does not exist"
    printf '%s' "$h"
}

TAB="$(printf '\t')"
MANIFEST_HEADER="id${TAB}what${TAB}from${TAB}when_utc${TAB}why${TAB}stored${TAB}size${TAB}status${TAB}restore"
# a path as one shell word in single quotes
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
oneline() { printf '%s' "$1" | tr '\t\n\r' '   '; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch_of() { date -u -d "$1" +%s 2>/dev/null || echo 0; }

# write the manifest from a new copy and rename it: a crash never leaves half a file
manifest_write() { # file with the new content
    mv -f -- "$1" "${MANIFEST:?}"
}
manifest_init() {
    mkdir -p "${DISABLED:?}" || die "cannot create $DISABLED"
    [ -f "$MANIFEST" ] || { printf '%s\n' "$MANIFEST_HEADER" > "$MANIFEST.tmp" && manifest_write "$MANIFEST.tmp"; }
}

setup_dirs() {
    HOME_DIR="$(tidy_home)"
    DISABLED="$HOME_DIR/disabled"
    MANIFEST="$DISABLED/MANIFEST.tsv"
    LOGS="$HOME_DIR/logs"
    CRASH="$LOGS/crash"
    CACHE="$HOME_DIR/cache"
    EXT="$HOME_DIR/.local/share/SuperCollider/Extensions"
}

cmd_disable() {
    [ $# -eq 2 ] || die "usage: verdandi tidy disable PATH WHY"
    setup_dirs
    local path="${1%/}" why
    why="$(oneline "$2")"
    [ -e "$path" ] || [ -L "$path" ] || die "$path does not exist"
    # the real place of the path, without following a final link: the folder it is in, resolved, and its name
    local dir base abs
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || die "cannot read the folder of $path"
    base="$(basename "$path")"
    abs="$dir/$base"
    local home_real
    home_real="$(cd "$HOME_DIR" && pwd -P)"
    case "$abs" in
    "$home_real"/*) ;;
    *) die "$path is not inside the norns home ($home_real): only things in the home can be moved to disabled/" ;;
    esac
    local rel="${abs#"$home_real"/}"
    case "$rel" in
    dust | dust/code | dust/audio | dust/data | audio.conf | ui.conf | norns | matronrc.lua | version.txt | disabled | backups | logs | cache | .config | .local | .local/share | .local/share/SuperCollider | .local/share/SuperCollider/Extensions)
        die "$rel is not something to move out of the way (your scripts, samples, data and settings, and Verdandi's own folders are never moved)" ;;
    disabled/* | backups/* | logs/* | cache/*) die "$rel is already in one of Verdandi's own folders" ;;
    esac
    manifest_init
    local id n=0 stamp
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    id="$stamp-1"
    # an id is never used twice: not while its folder exists and not after (the manifest keeps the history)
    while [ -e "$DISABLED/$id" ] || awk -F'\t' -v id="$id" 'NR > 1 && $1 == id { f = 1 } END { exit !f }' "$MANIFEST"; do n=$((n + 1)); id="$stamp-$((n + 1))"; done
    # the same file system, so that this is a rename and never a copy followed by a delete
    local sz what
    if [ "$(stat -c %d "$HOME_DIR")" != "$(stat -c %d "$(dirname "$abs")")" ]; then
        die "$path is on another file system than the norns home: move it by hand"
    fi
    if [ -L "$abs" ]; then what="link $base"; sz=0; elif [ -d "$abs" ]; then what="folder $base"; sz="$(bytes_of "$abs")"; else what="file $base"; sz="$(stat -c %s "$abs")"; fi
    mkdir "$DISABLED/$id" || die "cannot create $DISABLED/$id"
    if ! mv -- "$abs" "$DISABLED/$id/$base"; then
        rmdir "${DISABLED:?}/${id:?}" 2>/dev/null
        die "could not move $path"
    fi
    local restore="mv $(shq "$DISABLED/$id/$base") $(shq "$abs")"
    cp -f -- "$MANIFEST" "$MANIFEST.tmp"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$(oneline "$what")" "$(oneline "$abs")" "$(now_utc)" "$why" "disabled/$id/$base" "$sz" disabled "$restore" >> "$MANIFEST.tmp"
    manifest_write "$MANIFEST.tmp"
    say "moved $path to disabled/$id/$base (id $id). to put it back: verdandi tidy restore $id"
}

# one manifest line by id -> the fields MF_*, or return 1
manifest_find() {
    [ -f "$MANIFEST" ] || return 1
    local line
    line="$(awk -F'\t' -v id="$1" 'NR > 1 && $1 == id { print; exit }' "$MANIFEST")"
    [ -n "$line" ] || return 1
    IFS="$TAB" read -r MF_ID MF_WHAT MF_FROM MF_WHEN MF_WHY MF_STORED MF_SIZE MF_STATUS MF_RESTORE <<EOF
$line
EOF
    return 0
}
manifest_set_status() { # id new-status
    awk -F'\t' -v OFS='\t' -v id="$1" -v st="$2" 'NR > 1 && $1 == id { $8 = st } { print }' "$MANIFEST" > "$MANIFEST.tmp" && manifest_write "$MANIFEST.tmp"
}

cmd_restore() {
    [ $# -eq 1 ] || die "usage: verdandi tidy restore ID"
    setup_dirs
    manifest_find "$1" || die "no item with id $1 in disabled/MANIFEST.tsv (see: verdandi tidy list)"
    [ "$MF_STATUS" = disabled ] || die "item $1 is not in disabled/ any more (status: $MF_STATUS)"
    local stored="$HOME_DIR/$MF_STORED"
    [ -e "$stored" ] || [ -L "$stored" ] || die "$stored is missing: the item was removed from disabled/ by hand"
    if [ -e "$MF_FROM" ] || [ -L "$MF_FROM" ]; then
        die "cannot restore: $MF_FROM exists again. move or rename that first, then run the restore again"
    fi
    mkdir -p "$(dirname "$MF_FROM")" || die "cannot create the folder of $MF_FROM"
    mv -- "$stored" "$MF_FROM" || die "could not move it back"
    rmdir "${DISABLED:?}/${MF_ID:?}" 2>/dev/null
    manifest_set_status "$MF_ID" restored
    say "restored $MF_FROM"
}

# ---- listing: group, id, name, epoch, bytes, extra (one tab separated line each; the CLEAN UP page reads --tsv) ----
collect() {
    setup_dirs
    local e id
    # disabled/: the manifest's items that are still there; anything else in disabled/ is shown as "not ours"
    if [ -f "$MANIFEST" ]; then
        while IFS="$TAB" read -r id what from when why stored size status restore; do
            [ "$id" = id ] && continue
            [ "$status" = disabled ] || continue
            [ -e "$HOME_DIR/$stored" ] || [ -L "$HOME_DIR/$stored" ] || continue
            printf 'disabled\t%s\t%s\t%s\t%s\t%s\n' "$id" "$what" "$(epoch_of "$when")" "$size" "$why"
        done < "$MANIFEST"
    fi
    if [ -d "$DISABLED" ]; then
        while IFS= read -r e; do
            id="$(basename "$e")"
            [ "$id" = MANIFEST.tsv ] && continue
            [ "$id" = MANIFEST.tsv.tmp ] && continue
            if [ -f "$MANIFEST" ] && awk -F'\t' -v id="$id" 'NR > 1 && $1 == id && $8 == "disabled" { f = 1 } END { exit !f }' "$MANIFEST"; then continue; fi
            printf 'notours\t%s\t%s\t%s\t%s\t%s\n' "$id" "$id" "$(stat -c %Y "$e")" "$(bytes_of "$e")" "in disabled/ but not in the manifest: never removed by Verdandi"
        done < <(find "$DISABLED" -mindepth 1 -maxdepth 1 | sort)
    fi
    # logs: the current ones and the older runs (only the older runs can be removed)
    if [ -d "$LOGS" ]; then
        while IFS= read -r e; do
            id="$(basename "$e")"
            case "$id" in
            *.[0-9].log) printf 'logs\t%s\t%s\t%s\t%s\told run\n' "$id" "$id" "$(stat -c %Y "$e")" "$(stat -c %s "$e")" ;;
            *.log) printf 'logcurrent\t%s\t%s\t%s\t%s\tcurrent\n' "$id" "$id" "$(stat -c %Y "$e")" "$(stat -c %s "$e")" ;;
            esac
        done < <(find "$LOGS" -maxdepth 1 -type f | sort)
    fi
    if [ -d "$CRASH" ]; then
        while IFS= read -r e; do
            id="$(basename "$e")"
            printf 'crash\t%s\t%s\t%s\t%s\t\n' "$id" "$id" "$(stat -c %Y "$e")" "$(stat -c %s "$e")"
        done < <(find "$CRASH" -maxdepth 1 -type f -name 'crash-*.txt' | sort)
    fi
    # seeded packs: a folder in an extension folder that carries our stamp file
    if [ -d "$EXT" ]; then
        while IFS= read -r e; do
            [ -f "$e/.verdandi-pack" ] || continue
            id="$(basename "$e")"
            printf 'seeded\t%s\t%s\t%s\t%s\t%s\n' "$id" "$id" "$(stat -c %Y "$e/.verdandi-pack")" "$(bytes_of "$e")" "$(head -n 1 "$e/.verdandi-pack" | tr '\t' ' ')"
        done < <(find "$EXT" -mindepth 1 -maxdepth 1 -type d | sort)
    fi
    if [ -d "$CACHE" ]; then
        printf 'cache\tcache\tcache/\t%s\t%s\t\n' "$(stat -c %Y "$CACHE")" "$(bytes_of "$CACHE")"
    fi
}

cmd_list() {
    local tsv=0
    [ "${1:-}" = --tsv ] && tsv=1
    setup_dirs
    local lines
    lines="$(collect)"
    if [ $tsv -eq 1 ]; then
        [ -n "$lines" ] && printf '%s\n' "$lines"
        return 0
    fi
    say "the norns home: $HOME_DIR"
    local g title
    for g in disabled notours logcurrent logs crash seeded cache; do
        case "$g" in
        disabled) title="disabled/ (moved there for you, restorable with: verdandi tidy restore ID)" ;;
        notours) title="in disabled/ but not in the manifest (never removed by Verdandi)" ;;
        logcurrent) title="logs/ (current runs, kept)" ;;
        logs) title="logs/ (older runs)" ;;
        crash) title="logs/crash/ (the last $CRASH_KEEP crash reports)" ;;
        seeded) title="seeded packs (ours: they carry a .verdandi-pack stamp)" ;;
        cache) title="cache/ (libraries' caches, safe to delete)" ;;
        esac
        local part total=0 n=0 gid name epoch bytes extra
        part="$(printf '%s\n' "$lines" | awk -F'\t' -v g="$g" '$1 == g')"
        [ -n "$part" ] || continue
        say ""
        say "$title"
        while IFS="$TAB" read -r _ gid name epoch bytes extra; do
            n=$((n + 1)); total=$((total + bytes))
            say "   $(printf '%-34s' "$name") $(date -u -d "@$epoch" +%Y-%m-%d 2>/dev/null)  $(printf '%6s' "$(human "$bytes")")  ${extra}"
        done <<EOF
$part
EOF
        say "   $n item(s), $(human "$total")"
    done
    [ -n "$lines" ] || say "nothing of Verdandi's own is stored here yet"
    return 0
}

cmd_remove_older() {
    local days="" yes=0
    while [ $# -gt 0 ]; do
        case "$1" in
        --yes) yes=1; shift ;;
        [0-9]*) days="$1"; shift ;;
        *) die "usage: verdandi tidy remove-older DAYS [--yes]" ;;
        esac
    done
    [ -n "$days" ] || die "usage: verdandi tidy remove-older DAYS [--yes]"
    setup_dirs
    local limit now
    now="$(date -u +%s)"
    limit=$((now - days * 86400))
    local lines picked
    lines="$(collect)"
    picked="$(printf '%s\n' "$lines" | awk -F'\t' -v lim="$limit" '($1 == "disabled" || $1 == "logs" || $1 == "crash" || $1 == "seeded") && $4 < lim { print }')"
    # the cache: files older than the limit inside cache/ (the folder itself stays)
    local cache_old=0 cache_bytes=0
    if [ -d "$CACHE" ]; then
        cache_old="$(find "$CACHE" -type f -mtime +"$days" 2>/dev/null | wc -l)"
        cache_bytes="$(find "$CACHE" -type f -mtime +"$days" -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')"
    fi
    local n=0 total=0 g id name epoch bytes extra
    if [ -n "$picked" ]; then
        while IFS="$TAB" read -r g id name epoch bytes extra; do
            n=$((n + 1)); total=$((total + bytes))
            say "older than $days days: $g  $name  $(human "$bytes")"
        done <<EOF
$picked
EOF
    fi
    if [ "$cache_old" -gt 0 ]; then n=$((n + 1)); total=$((total + cache_bytes)); say "older than $days days: cache  $cache_old file(s)  $(human "$cache_bytes")"; fi
    say "$n item(s), $(human "$total")"
    if [ $yes -ne 1 ]; then
        say "nothing was removed (add --yes to remove exactly these)"
        return 0
    fi
    [ $n -eq 0 ] && return 0
    if [ -n "$picked" ]; then
        while IFS="$TAB" read -r g id name epoch bytes extra; do
            [ -n "$id" ] || continue
            case "$g" in
            disabled)
                # only an item the manifest lists as disabled, and only its own folder
                if manifest_find "$id" && [ "$MF_STATUS" = disabled ] && [ -d "$DISABLED/$id" ]; then
                    rm -rf -- "${DISABLED:?}/${id:?}" && manifest_set_status "$id" removed
                fi ;;
            logs) rm -f -- "${LOGS:?}/${id:?}" ;;
            crash) rm -f -- "${CRASH:?}/${id:?}" ;;
            seeded) if [ -f "$EXT/$id/.verdandi-pack" ]; then rm -rf -- "${EXT:?}/${id:?}"; fi ;;
            esac
        done <<EOF
$picked
EOF
    fi
    if [ "$cache_old" -gt 0 ]; then
        find "${CACHE:?}" -type f -mtime +"$days" -delete 2>/dev/null
        find "${CACHE:?}" -mindepth 1 -type d -empty -delete 2>/dev/null
    fi
    say "removed."
}

# the launcher's start-up: keep the last LOG_KEEP runs of each named log; cap launcher.log; keep the last CRASH_KEEP crash reports
cmd_rotate() {
    setup_dirs
    mkdir -p "$LOGS" "$CRASH" "$CACHE" || die "cannot create the folders under $HOME_DIR"
    local name i
    for name in "$@"; do
        case "$name" in
        *[!A-Za-z0-9_]* | "") die "rotate: '$name' is not a log name" ;;
        esac
        rm -f -- "${LOGS:?}/$name.$((LOG_KEEP - 1)).log"
        i=$((LOG_KEEP - 2))
        while [ $i -ge 1 ]; do
            [ -f "$LOGS/$name.$i.log" ] && mv -f -- "$LOGS/$name.$i.log" "$LOGS/$name.$((i + 1)).log"
            i=$((i - 1))
        done
        [ -f "$LOGS/$name.log" ] && mv -f -- "$LOGS/$name.log" "$LOGS/$name.1.log"
        : > "$LOGS/$name.log"
    done
    if [ -f "$LOGS/launcher.log" ] && [ "$(stat -c %s "$LOGS/launcher.log")" -gt $LAUNCHER_CAP ]; then
        mv -f -- "$LOGS/launcher.log" "$LOGS/launcher.1.log"
    fi
    # the crash reports: the newest CRASH_KEEP stay
    local old f
    old="$(find "$CRASH" -maxdepth 1 -type f -name 'crash-*.txt' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +$((CRASH_KEEP + 1)) | cut -d' ' -f2-)"
    if [ -n "$old" ]; then
        while IFS= read -r f; do
            case "$f" in "$CRASH"/crash-*.txt) rm -f -- "$f" ;; esac
        done <<EOF
$old
EOF
    fi
    return 0
}

# a running log over LOG_CAP is cut to its last megabyte in place (the writers append, so they carry on at the new end)
cmd_cap() {
    setup_dirs
    local f sz
    [ -d "$LOGS" ] || return 0
    for f in "$LOGS"/*.log; do
        [ -f "$f" ] || continue
        case "$f" in *.[0-9].log) continue ;; esac
        sz="$(stat -c %s "$f")"
        if [ "$sz" -gt $LOG_CAP ] || { [ "$(basename "$f")" = launcher.log ] && [ "$sz" -gt $LAUNCHER_CAP ]; }; then
            if tail -c $LOG_TAIL "$f" > "$f.cut"; then
                printf '[verdandi tidy: the log was cut to its last megabyte]\n' > "$f"
                cat "$f.cut" >> "$f"
            fi
            rm -f "$f.cut"
        fi
    done
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
    say "usage: verdandi tidy list [--tsv] | disable PATH WHY | restore ID | remove-older DAYS [--yes] | rotate NAME... | cap | flatten [--home PATH]"
    say "       list: what is in disabled/, logs/, logs/crash/, seeded packs and cache/ with sizes; disable: move something into disabled/ (restorable);"
    say "       restore: put it back; remove-older: show (and with --yes remove) what is older than DAYS in those groups; flatten: dry run of the migration of a nested home"
}

case "${1:-}" in
list) shift; cmd_list "$@" ;;
disable) shift; cmd_disable "$@" ;;
restore) shift; cmd_restore "$@" ;;
remove-older) shift; cmd_remove_older "$@" ;;
rotate) shift; cmd_rotate "$@" ;;
cap) shift; cmd_cap "$@" ;;
flatten) shift; cmd_flatten "$@" ;;
-h | --help | help | "") usage ;;
*) usage >&2; die "unknown command '$1'" ;;
esac
