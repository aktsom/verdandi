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
#                                         what is there, what would be moved and what could go wrong; nothing is moved, changed or deleted
#   verdandi tidy flatten --apply [--full-copy]   the move: renames only, a backup first (hard links of dust/, or a full copy), a typed confirmation, checks of
#                                         dust/ before and after, an automatic rollback on any mismatch. norns must not be running
#   verdandi tidy flatten --undo [ID]     puts it back from the manifest in backups/flatten-<time>/ and checks the result (docs/port/clean-layout.md section 7)
#
# nothing here ever touches dust/ (scripts, samples, data), audio.conf, ui.conf, box.conf, box-presets/, midimap.conf, midimap-presets/ or screen-window.conf, except `disable` of a path the user names (a plug-in file or folder inside
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
    dust | dust/code | dust/audio | dust/data | audio.conf | ui.conf | box.conf | box-presets | box-presets/* | midimap.conf | midimap.conf.tmp | midimap-presets | midimap-presets/* | screen-window.conf | norns | matronrc.lua | version.txt | disabled | backups | logs | cache | .config | .local | .local/share | .local/share/SuperCollider | .local/share/SuperCollider/Extensions)
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

# ---- flatten: the dry run, --apply and --undo ----
# the dry run only reads. --apply and --undo are further down (fl_apply, fl_undo); the arguments are read here
cmd_flatten() {
    local home="" mode=dry full=0 undo_id=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --home) home="${2:-}"; shift 2 ;;
        --apply) mode=apply; shift ;;
        --undo) mode=undo; shift; case "${1:-}" in "" | --*) ;; *) undo_id="$1"; shift ;; esac ;;
        --full-copy) full=1; shift ;;
        *) die "flatten: unknown argument '$1' (usage: verdandi tidy flatten [--apply [--full-copy] | --undo [ID]] [--home PATH])" ;;
        esac
    done
    [ -n "$home" ] || home="$(find_home)"
    home="${home%/}"
    case "$mode" in
    apply) fl_apply "$home" "$full"; return $? ;;
    undo) fl_undo "$home" "$undo_id"; return $? ;;
    esac
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
    local links_in=0 links_out=0 broken=0 l target rel
    local elsewhere_lines="" broken_lines="" into_lines=""
    while IFS= read -r l; do
        target="$(readlink "$l")"
        rel="${l#$nested/}"
        case "$target" in
        "$nested"/* | "$nested")
            links_in=$((links_in + 1))
            into_lines="$into_lines
   into the nested folder: $rel -> $target (would need a new target)"
            ;;
        *)
            links_out=$((links_out + 1))
            elsewhere_lines="$elsewhere_lines
   elsewhere: $rel -> $target (unchanged by the move)"
            ;;
        esac
        if [ ! -e "$l" ]; then
            broken=$((broken + 1))
            broken_lines="$broken_lines
   broken: $rel -> $target (the target is not there; already so before the move)"
        fi
    done < <(find "$nested" -type l 2>/dev/null | LC_ALL=C sort)
    [ -n "$into_lines" ] && say "${into_lines#
}"
    [ -n "$elsewhere_lines" ] && say "${elsewhere_lines#
}"
    [ -n "$broken_lines" ] && say "${broken_lines#
}"
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
    say "   6. checks: file count and size of dust/ equal before and after ($dust_files files and links, $(human "$dust_bytes")); any mismatch rolls everything back by itself"
    say "   7. undo at any time: verdandi tidy flatten --undo (from the manifest in the backup folder)"

    say ""
    if [ $problems -eq 0 ]; then
        say "RESULT ready: nothing found that stops the move ($links_in link(s) into the nested folder need your confirmation, $holders small file(s) hold the old path). dust/ would be moved as $dust_files files and links, $(human "$dust_bytes"). to do it: stop Verdandi, then run: verdandi tidy flatten --apply (it asks you to type a confirmation line first; nothing happens before that)"
    else
        say "RESULT not-ready:$reasons"
    fi
    return 0
}

# ---- flatten --apply and --undo (docs/port/clean-layout.md section 7) ----
# the rules, in the order the code follows them:
#   * nothing of norns running (norns, sclang, scsynth, jackd, maiden), the nested home and every entry in it on the file system of the outer home (a rename,
#     never a copy), a typed confirmation, a state file that says "in-progress" until the end
#   * before anything moves: backups/flatten-<UTC>/ with before.tree, dust.list (every path, size and link target of dust/), a hard-link copy of dust/
#     (dust-links/, no extra space; --full-copy makes a real copy: dust-copy/) and MANIFEST
#   * moves are renames only, never an overwrite (mv -n, and an existing outer name is first moved into backups/.../outer/). each move is written to
#     the manifest BEFORE it is made, so that an interrupted run can be undone
#   * after the moves: the count, the sizes and the listing of dust/ are compared with dust.list, and (hard-link backup) every file is still the same inode as in the
#     backup. any mismatch, any failed move and any TERM/INT/HUP rolls everything back by itself
#   * nothing is deleted anywhere in this code: not a file, not a folder. the only removal is `rmdir` of the empty nested folder at the end
# TIDY_FLATTEN_HOOK (tests only): a program called as `hook after-move N`, `hook before-rename N DEST`, `hook after-moves`

FL_STATE=""   # the backup folder while --apply runs (for the signal handler)
FL_HOME=""
FL_NESTED=""

fl_hook() { [ -n "${TIDY_FLATTEN_HOOK:-}" ] && "$TIDY_FLATTEN_HOOK" "$@"; return 0; }

# paths, types, sizes and link targets (dust/: modes are not compared, a link has no size, a folder none)
fl_listing() { # dir
    (cd "$1" && {
        find . -mindepth 1 -type d -printf '%P\td\t0\t\n'
        find . -mindepth 1 ! -type d -printf '%P\t%y\t%s\t%l\n' | awk -F'\t' 'BEGIN { OFS = "\t" } $2 == "l" { $3 = 0 } { print }'
    } | LC_ALL=C sort)
}
# the home as it is before the move: everything but backups/
fl_tree() { # dir
    (cd "$1" && {
        find . -mindepth 1 -path ./backups -prune -o -type d -printf '%P\td\t0\t%m\t\n'
        find . -mindepth 1 -path ./backups -prune -o ! -type d -printf '%P\t%y\t%s\t%m\t%l\n'
    } | LC_ALL=C sort)
}
fl_counts() { # dir -> "FILES BYTES" (files and links; the sum of the sizes of the regular files)
    (cd "$1" && printf '%s %s\n' "$(find . -mindepth 1 \( -type f -o -type l \) | wc -l)" "$(find . -type f -printf '%s\n' | awk '{ s += $1 } END { printf "%d", s }')")
}
fl_state_get() { cat "$1/STATE" 2>/dev/null; }
fl_state_set() { printf '%s\n' "$2" > "$1/STATE.tmp" && mv -f -- "$1/STATE.tmp" "$1/STATE"; }
fl_manifest() { printf '%s\n' "$*" >> "${FL_STATE:?}/MANIFEST"; }

# the newest backup folder that is in one of the given states
fl_find_backup() { # home states...
    local home="$1" d st want b=""
    shift
    for d in $(ls -d "$home"/backups/flatten-* 2>/dev/null | LC_ALL=C sort -r); do
        st="$(fl_state_get "$d")"
        for want in "$@"; do [ "$st" = "$want" ] && { b="$d"; break; }; done
        [ -n "$b" ] && break
    done
    printf '%s' "$b"
}

# put everything back by reading the manifest backwards. each step looks at what is really there first, so it works for a finished run, a half run and
# a killed run. returns 0 when every path of before.tree exists again, 1 otherwise
fl_restore() { # backup-folder
    local b="$1" kind a c d e mode problems=0 n lines
    local home nested
    home="$(sed -n 's/^home\t//p' "$b/MANIFEST" | head -n 1)"
    nested="$(sed -n 's/^nested\t//p' "$b/MANIFEST" | head -n 1)"
    [ -n "$home" ] && [ -n "$nested" ] || { say "   the manifest of $b has no home line: cannot restore"; return 1; }
    lines="$(grep -c '^\(move\|rmdir\|conf\|relink\)	' "$b/MANIFEST")"
    # a step that is done is written to UNDONE, so a second run (after something in the way was cleared) does not read a half-restored state as a conflict
    local idx stepok
    while IFS="$TAB" read -r idx kind a c d e; do
        grep -qx -- "$idx" "$b/UNDONE" 2>/dev/null && continue
        stepok=1
        case "$kind" in
        relink) # path old new
            if [ -L "$a" ] && [ "$(readlink "$a")" = "$d" ]; then
                ln -s -- "$c" "$a.verdandi-undo" && mv -T -- "$a.verdandi-undo" "$a" || { say "   could not put the link $a back"; stepok=0; }
            fi
            ;;
        conf) # path old-file
            if [ -f "$c" ]; then
                if [ -e "$a" ]; then mv -n -T -- "$a" "$b/conf-generated" 2>/dev/null || mv -n -T -- "$a" "$b/conf-generated.$$"; fi
                mv -n -T -- "$c" "$a" || { say "   could not put $a back"; stepok=0; }
            fi
            ;;
        rmdir) # path mode: the nested folder, removed at the end
            [ -d "$a" ] || { mkdir -- "$a" && chmod "$c" "$a"; } || { say "   could not make $a again"; stepok=0; }
            ;;
        move) # from to
            if { [ -e "$c" ] || [ -L "$c" ]; } && [ ! -e "$a" ] && [ ! -L "$a" ]; then
                mkdir -p -- "$(dirname "$a")"
                mv -n -T -- "$c" "$a" || { say "   could not move $c back to $a"; stepok=0; }
            elif { [ -e "$c" ] || [ -L "$c" ]; } && { [ -e "$a" ] || [ -L "$a" ]; }; then
                say "   both $a and $c exist: left as they are (look at them by hand)"; stepok=0
            fi
            ;;
        esac
        if [ $stepok = 1 ]; then printf '%s\n' "$idx" >> "$b/UNDONE"; else problems=1; fi
    done < <(awk -F'\t' '$1 == "move" || $1 == "rmdir" || $1 == "conf" || $1 == "relink" { print NR "\t" $0 }' "$b/MANIFEST" | tac)
    # a file of dust/ that went missing is linked back from the hard-link backup (nothing else is ever added to dust/)
    if { [ -d "$b/dust-links" ] || [ -d "$b/dust-copy" ]; } && [ -d "$nested/dust" ]; then
        local before_n after_n
        before_n="$(find "$nested/dust" \( -type f -o -type l \) | wc -l)"
        if [ -d "$b/dust-links" ]; then cp -al -n -- "$b/dust-links/." "$nested/dust/" 2>/dev/null; else cp -a -n -- "$b/dust-copy/." "$nested/dust/" 2>/dev/null; fi
        after_n="$(find "$nested/dust" \( -type f -o -type l \) | wc -l)"
        [ "$after_n" != "$before_n" ] && say "   restored $((after_n - before_n)) missing file(s) of dust/ from the backup copy"
    fi
    # every path of before.tree is there again?
    local missing
    missing="$(LC_ALL=C comm -23 <(cut -f1,2 "$b/before.tree" | LC_ALL=C sort) <(fl_tree "$home" | cut -f1,2 | LC_ALL=C sort) | head -n 5)"
    if [ -n "$missing" ]; then
        say "   NOT everything is back. missing:"
        printf '%s\n' "$missing" | sed 's/^/     /'
        problems=1
    fi
    local changed
    changed="$(LC_ALL=C comm -13 <(LC_ALL=C sort "$b/before.tree") <(fl_tree "$home") | wc -l)"
    say "   put back: $lines recorded step(s) undone; $changed entr$([ "$changed" = 1 ] && echo y || echo ies) differ from before.tree (files you made or changed after the move are expected here)"
    if [ -f "$b/dust.list" ] && [ -d "$nested/dust" ]; then
        local want_n got
        want_n="$(wc -l < "$b/dust.list")"
        got="$(fl_listing "$nested/dust")"
        if [ "$got" = "$(cat "$b/dust.list")" ]; then
            say "   dust/ is as it was: $(fl_counts "$nested/dust" | awk '{ print $1 " files and links, " $2 " bytes" }'), every path, size and link target the same"
        else
            say "   dust/ differs from dust.list ($(printf '%s\n' "$got" | wc -l) entries now, $want_n before): files you made or changed after the move are expected here"
        fi
    fi
    return $problems
}

fl_on_signal() {
    trap - INT TERM HUP
    say ""
    say "verdandi tidy: interrupted by a signal: rolling back"
    fl_fail_and_rollback "interrupted by a signal"
}

# the end of a failed run: restore, say so, leave the state "rolled-back" (or "failed" when the restore itself was not complete)
fl_fail_and_rollback() { # why
    local b="${FL_STATE:?}"
    trap - INT TERM HUP
    say ""
    say "verdandi tidy flatten: FAILED: $1"
    say "   rolling everything back (the manifest in $b says what was moved)"
    if fl_restore "$b"; then
        fl_state_set "$b" rolled-back
        say "   rolled back: the home is as it was before this run. nothing was lost. the backup folder $b stays (it takes no space; delete it yourself when you do not need it)"
    else
        fl_state_set "$b" failed
        say "   ROLLBACK INCOMPLETE. nothing was deleted, and dust/ also exists as hard links in $b/dust-links. do not start Verdandi; send this output"
    fi
    exit 1
}

fl_check_nested() { # home nested -> 0 when it is a norns home that looks nested
    local home="$1" nested="$2"
    [ -d "$home" ] || die "the home $home does not exist"
    if [ ! -d "$nested" ] || [ -L "$nested" ]; then say "RESULT nothing-to-do: there is no folder $nested (the home is not nested)"; return 1; fi
    if [ ! -e "$nested/dust" ] && [ ! -L "$nested/norns" ] && [ ! -e "$nested/audio.conf" ] && [ ! -e "$nested/matronrc.lua" ]; then
        say "RESULT nothing-to-do: $nested exists but does not look like a norns home (no dust, norns link, audio.conf or matronrc.lua): it is left alone"
        return 1
    fi
    return 0
}

fl_apply() { # home full-copy
    local home="$1" full="$2" nested="$1/Verdandi" run
    say "verdandi tidy flatten --apply: move $nested up into $home"
    fl_check_nested "$home" "$nested" || return 0

    # ---- refusals: nothing has been changed so far ----
    run="$(running_programs)"
    [ -z "$run" ] || die "running now: $run. stop Verdandi (all of it) first, then run this again. nothing was changed"
    local half
    half="$(fl_find_backup "$home" in-progress failed)"
    [ -z "$half" ] || die "an earlier flatten was interrupted ($half, state $(fl_state_get "$half")). run 'verdandi tidy flatten --undo' first. nothing was changed"
    [ ! -L "$nested/dust" ] || die "$nested/dust is a link: that layout is not handled by the move. send the dry run output. nothing was changed"
    [ ! -e "$nested/backups" ] && [ ! -L "$nested/backups" ] || die "$nested has a backups folder of its own: move it away first, the move needs backups/ in $home. nothing was changed"
    local dev_home e name
    dev_home="$(stat -c %d "$home")"
    while IFS= read -r -d '' e; do
        name="${e##*/}"
        [ "$(stat -c %d "$e")" = "$dev_home" ] || die "$name is on another file system than $home: a rename is not possible, so nothing is moved. nothing was changed"
        case "$name" in *"$TAB"* | *$'\n'*) die "the name of $name has a tab or a new line in it: not handled. nothing was changed" ;; esac
    done < <(find "$nested" -mindepth 1 -maxdepth 1 -print0)
    [ "$(stat -c %d "$nested")" = "$dev_home" ] || die "$nested is on another file system than $home. nothing was changed"

    # ---- what will happen, and the typed confirmation ----
    local counts files bytes avail
    counts="$(fl_counts "$nested/dust" 2>/dev/null || echo "0 0")"
    files="${counts% *}"; bytes="${counts#* }"
    local links_into=0 l target links_list=""
    if [ -d "$nested/dust" ]; then
        while IFS= read -r l; do
            target="$(readlink "$l")"
            case "$target" in "$nested"/* | "$nested") links_into=$((links_into + 1)); links_list="$links_list
     ${l#$nested/} -> $target" ;; esac
        done < <(find "$nested/dust" -type l | LC_ALL=C sort)
    fi
    say "   dust/ (yours): $files files and links, $(human "$bytes")"
    say "   the home is not changed until you type the line below. everything is a rename, nothing is deleted, a backup is made first, and"
    say "   'verdandi tidy flatten --undo' puts it back."
    if [ "$full" = 1 ]; then
        avail="$(df -B1 --output=avail "$home" | tail -n 1 | tr -d ' ')"
        [ "${avail:-0}" -ge $((bytes + bytes / 10 + 1048576)) ] || die "a full copy of dust/ needs $(human "$bytes") and $(human "${avail:-0}") are free. use the hard-link backup (no --full-copy). nothing was changed"
        say "   --full-copy: dust/ is copied for real ($(human "$bytes") of disk space)"
    else
        say "   backup of dust/: hard links (no extra disk space)"
    fi
    local line expect="flatten $nested into $home"
    say "   type exactly this line and press Enter to go on (anything else stops, nothing is changed):"
    say "   $expect"
    IFS= read -r line || line=""
    [ "$line" = "$expect" ] || die "the confirmation line was not typed (confirmation needed). nothing was changed"
    local rewrite=0
    if [ $links_into -gt 0 ]; then
        say "   $links_into link(s) in dust/ point into the nested folder and would break after the move:$links_list"
        say "   point them into $home instead? type yes (anything else leaves them as they are, broken until you fix them)"
        IFS= read -r line || line=""
        [ "$line" = yes ] && rewrite=1
    fi

    # ---- the backup, before anything moves ----
    local stamp b n=1
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p -- "$home/backups" || die "cannot create $home/backups"
    b="$home/backups/flatten-$stamp"
    while ! mkdir -- "$b" 2>/dev/null; do n=$((n + 1)); b="$home/backups/flatten-$stamp-$n"; [ $n -gt 50 ] && die "cannot create a backup folder in $home/backups"; done
    FL_STATE="$b"; FL_HOME="$home"; FL_NESTED="$nested"
    fl_state_set "$b" in-progress
    printf 'home\t%s\nnested\t%s\nstarted\t%s\n' "$home" "$nested" "$(now_utc)" > "$b/MANIFEST"
    say ""
    say "== backup: $b"
    fl_tree "$home" > "$b/before.tree"
    say "   before.tree: $(wc -l < "$b/before.tree") paths"
    if [ -d "$nested/dust" ]; then
        fl_listing "$nested/dust" > "$b/dust.list"
        if [ "$full" = 1 ]; then
            cp -a -- "$nested/dust" "$b/dust-copy" || { fl_state_set "$b" aborted; die "the copy of dust/ failed: nothing was moved ($b is kept, you can delete it)"; }
        else
            cp -al -- "$nested/dust" "$b/dust-links" || { fl_state_set "$b" aborted; die "the hard-link copy of dust/ failed: nothing was moved ($b is kept, you can delete it)"; }
        fi
        local bk="$b/dust-links"
        [ "$full" = 1 ] && bk="$b/dust-copy"
        if [ "$(fl_listing "$bk")" != "$(cat "$b/dust.list")" ]; then
            fl_state_set "$b" aborted
            die "the backup copy of dust/ does not match dust/: nothing was moved ($b is kept, you can delete it)"
        fi
        say "   dust/ saved as $([ "$full" = 1 ] && echo "a full copy (dust-copy/)" || echo "hard links (dust-links/)"): the copy has the same $files files and links"
    fi

    # ---- the moves ----
    trap fl_on_signal INT TERM HUP
    say ""
    say "== moving"
    mkdir -p -- "$b/outer"
    local moved=0 renames=0 outer_kept=0 dest
    while IFS= read -r -d '' e; do
        name="${e##*/}"
        dest="$home/$name"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            # an outer entry with the same name: into backups/.../outer (a rename), never overwritten
            fl_manifest "move$TAB$dest$TAB$b/outer/$name"
            mv -n -T -- "$dest" "$b/outer/$name" && [ ! -e "$dest" ] && [ ! -L "$dest" ] || fl_fail_and_rollback "could not move the outer $name into $b/outer"
            moved=$((moved + 1)); outer_kept=$((outer_kept + 1))
            fl_hook after-move "$moved"
        fi
        renames=$((renames + 1))
        fl_hook before-rename "$renames" "$dest"
        fl_manifest "move$TAB$e$TAB$dest"
        mv -n -T -- "$e" "$dest" 2>/dev/null
        if [ -e "$e" ] || [ -L "$e" ] || { [ ! -e "$dest" ] && [ ! -L "$dest" ]; }; then
            fl_fail_and_rollback "$name was not moved (the name $dest is taken, or the rename failed); nothing is overwritten"
        fi
        moved=$((moved + 1))
        fl_hook after-move "$moved"
        say "   $name"
    done < <(find "$nested" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
    # the nested folder is empty now: rmdir (it refuses if not)
    if [ -z "$(ls -A "$nested" 2>/dev/null)" ]; then
        fl_manifest "rmdir$TAB$nested$TAB$(stat -c %a "$nested")"
        rmdir -- "$nested" || fl_fail_and_rollback "could not remove the empty folder $nested"
    else
        fl_fail_and_rollback "$nested is not empty after the moves: $(ls -A "$nested" | head -n 3 | tr '\n' ' ')"
    fi
    fl_hook after-moves

    # ---- the files that hold the old path ----
    local conf="$home/.config/SuperCollider/sclang_conf.yaml" old content
    if [ -f "$conf" ] && grep -qF -- "$nested" "$conf"; then
        old="$conf.old"
        [ -e "$old" ] && old="$conf.old-$stamp"
        fl_manifest "conf$TAB$conf$TAB$old"
        mv -n -T -- "$conf" "$old" || fl_fail_and_rollback "could not keep sclang_conf.yaml as $old"
        content="$(cat -- "$old"; printf x)"; content="${content%x}"
        printf '%s' "${content//"$nested"/"$home"}" > "$conf.tmp" && mv -T -- "$conf.tmp" "$conf" || fl_fail_and_rollback "could not write the new sclang_conf.yaml"
        say ""
        say "== SuperCollider settings: the old file is kept as ${old#$home/}, the new one names $home/dust"
    fi
    local relinked=0
    if [ $rewrite = 1 ] && [ -d "$home/dust" ]; then
        while IFS= read -r l; do
            target="$(readlink "$l")"
            case "$target" in "$nested"/* | "$nested") ;; *) continue ;; esac
            case "$l" in *"$TAB"*) continue ;; esac
            fl_manifest "relink$TAB$l$TAB$target$TAB$home${target#$nested}"
            ln -s -- "$home${target#$nested}" "$l.verdandi-new" && mv -T -- "$l.verdandi-new" "$l" || fl_fail_and_rollback "could not rewrite the link $l"
            relinked=$((relinked + 1))
        done < <(find "$home/dust" -type l | LC_ALL=C sort)
        say "== links: $relinked link(s) in dust/ now point into $home"
    fi

    # ---- the check ----
    say ""
    say "== check"
    local after_counts exp_list now_list
    after_counts="$(fl_counts "$home/dust" 2>/dev/null || echo "0 0")"
    if [ "$after_counts" != "$files $bytes" ]; then
        fl_fail_and_rollback "the file count or size of dust/ does not match: before $files files and links, $bytes bytes; after ${after_counts% *} files and links, ${after_counts#* } bytes"
    fi
    say "   count and size of dust/: $files files and links, $bytes bytes, the same as before"
    if [ -f "$b/dust.list" ]; then
        if [ $rewrite = 1 ]; then
            exp_list="$(awk -F'\t' -v n="$nested" -v h="$home" 'BEGIN { OFS = "\t" } $2 == "l" && (index($4, n "/") == 1 || $4 == n) { $4 = h substr($4, length(n) + 1) } { print }' "$b/dust.list")"
        else
            exp_list="$(cat "$b/dust.list")"
        fi
        now_list="$(fl_listing "$home/dust")"
        [ "$now_list" = "$exp_list" ] || fl_fail_and_rollback "the listing of dust/ (paths, sizes, link targets) does not match the one taken before the move (differs: $(diff <(printf '%s\n' "$exp_list") <(printf '%s\n' "$now_list") | grep -c '^[<>]') lines)"
        say "   every path, size and link target in dust/ is the same as before"
    fi
    if [ "$full" != 1 ] && [ -d "$b/dust-links" ]; then
        local inode_bad
        inode_bad="$(LC_ALL=C comm -3 <(cd "$b/dust-links" && find . -type f -printf '%P\t%i\n' | LC_ALL=C sort) <(cd "$home/dust" && find . -type f -printf '%P\t%i\n' | LC_ALL=C sort) | wc -l)"
        [ "$inode_bad" = 0 ] || fl_fail_and_rollback "$inode_bad file(s) of dust/ are no longer the same file as in the backup copy (changed or replaced)"
        say "   every file of dust/ is still the very same file as in the backup (same inode)"
    fi
    trap - INT TERM HUP
    fl_state_set "$b" done
    printf 'finished\t%s\n' "$(now_utc)" >> "$b/MANIFEST"

    # ---- the summary ----
    local holders
    holders="$(find "$home" -path "$home/dust" -prune -o -path "$home/backups" -prune -o -path "$home/norns" -prune -o -path "$home/logs" -prune -o -path "$home/cache" -prune -o -type f -size -1024k -print0 2>/dev/null | xargs -0 grep -lIF -- "$nested" 2>/dev/null | sed "s|^$home/||" | grep -v '\.old' | head -n 10)"
    local broken_now
    broken_now="$(find "$home/dust" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)"
    {
        say ""
        say "== DONE: $home is flat now"
        say "   moved: $moved item(s) ($renames from the nested folder, $outer_kept outer leftover(s) set aside); $nested is gone"
        say "   dust/: $files files and links, $(human "$bytes"), checked before and after: nothing lost, nothing changed"
        say "   outer leftovers: $b/outer/ (nothing was overwritten or deleted; look at them and delete them yourself if you do not need them)"
        say "   links rewritten: $relinked$([ $links_into -gt 0 ] && [ $rewrite = 0 ] && echo " (not asked for: $links_into link(s) still point into the old folder and are broken)")"
        say "   links broken in dust/ (already broken before the move or left as they were): $broken_now"
        [ -n "$holders" ] && say "   small files that still name the old path (the launcher writes them again at the next start): $(printf '%s' "$holders" | tr '\n' ' ')"
        say "   backup: $b (before.tree, dust.list, $([ "$full" = 1 ] && echo dust-copy || echo "dust-links, hard links, no space used"), MANIFEST)"
        say "   TO UNDO:  verdandi tidy flatten --undo"
        say "   next: start Verdandi and look at your scripts and samples. when you are sure, the backup folder can be deleted by hand."
    } | tee "$b/SUMMARY"
    return 0
}

fl_undo() { # home id
    local home="$1" id="$2" b run
    say "verdandi tidy flatten --undo"
    [ -d "$home" ] || die "the home $home does not exist"
    run="$(running_programs)"
    [ -z "$run" ] || die "running now: $run. stop Verdandi (all of it) first. nothing was changed"
    if [ -n "$id" ]; then
        b="$home/backups/$id"
        [ -d "$b" ] || b="$id"
        [ -f "$b/MANIFEST" ] || die "no backup folder '$id' (look in $home/backups/)"
    else
        b="$(fl_find_backup "$home" in-progress failed done)"
        [ -n "$b" ] || { say "nothing to undo: no flatten backup in $home/backups/ is finished or interrupted (state in-progress, failed or done)"; return 1; }
    fi
    case "$(fl_state_get "$b")" in
    undone | rolled-back | aborted) die "$b was already $(fl_state_get "$b"): nothing to undo" ;;
    esac
    say "   undoing $b (state $(fl_state_get "$b"))"
    FL_STATE="$b"
    if fl_restore "$b"; then
        fl_state_set "$b" undone
        say ""
        say "== UNDONE: the home is as it was before the move. $b stays (no space used by the hard links; delete it yourself when you do not need it)"
        return 0
    fi
    fl_state_set "$b" failed
    say ""
    say "== UNDO INCOMPLETE: see above. nothing was deleted; dust/ also exists as hard links in $b/dust-links. do not start Verdandi; send this output"
    return 1
}

usage() {
    say "usage: verdandi tidy list [--tsv] | disable PATH WHY | restore ID | remove-older DAYS [--yes] | rotate NAME... | cap | flatten [--apply [--full-copy] | --undo [ID]] [--home PATH]"
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
