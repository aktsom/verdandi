#!/usr/bin/env bash
# windows/ci/inventory.sh (M0a): the porting inventory. compiles every source file of matron/src and crone/src that is not macOS- or Linux-specific with -fsyntax-only and records the FIRST error of each file (or OK).
# nothing is linked and nothing is expected to pass on the first runs: the table shows which files the Windows platform layer has to replace (missing headers like <alsa/...>, <poll.h>, <sys/...>) and which are already portable.
# output: $M0_OUT/inventory.tsv (file, OK or ERR, first error) and the counts in $M0_OUT/inventory-summary.txt
#   CC, CXX   compilers (default gcc and g++ of the PATH, that is MinGW in the MSYS2 UCRT64 shell)
# the functions below are called through m0_run (shellcheck cannot see that)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO" || exit 1
CC="${CC:-gcc}"
CXX="${CXX:-g++}"

# include flags from whatever pkg-config knows; the packages that are missing are simply left out, and show up in the errors
PKG_FLAGS=""
if command -v pkg-config > /dev/null 2>&1; then
    for p in liblo cairo cairo-ft lua53 sndfile jack sdl2 nng; do
        PKG_FLAGS="$PKG_FLAGS $(pkg-config --cflags "$p" 2> /dev/null)"
    done
fi
INC="-I matron/src -I matron/src/hardware -I matron/src/device -I norns -I crone/softcut/softcut-lib/include -I crone/softcut/softcut-lib -I matron/src/platform/common -I crone/src -I common -I third-party/concurrentqueue -I third-party/readerwriterqueue -I third-party/link/include -I third-party/link/extensions/abl_link/include -I third-party/lua-cjson -I build/package/cache/libmonome/public"

inventory() {
    local out="$M0_OUT/inventory.tsv" f err ok=0 bad=0 flags
    : > "$out"
    while IFS= read -r f; do
        case "$f" in
            *.c) flags="$CC -x c -std=gnu11" ;;
            *) flags="$CXX -x c++ -std=gnu++14" ;;
        esac
        # shellcheck disable=SC2086
        err=$($flags -fsyntax-only -w $INC $PKG_FLAGS "$f" 2>&1 | grep -m1 -E "error|Error" || true)
        if [ -z "$err" ]; then
            printf '%s\tOK\t\n' "$f" >> "$out"
            ok=$((ok + 1))
        else
            printf '%s\tERR\t%s\n' "$f" "$(printf '%s' "$err" | tr '\t' ' ' | cut -c1-200)" >> "$out"
            bad=$((bad + 1))
        fi
    done < <(find matron/src crone/src -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) \
        -not -path '*/platform/macos/*' -not -path '*/platform/linux/*' -not -path '*/hardware/*' | sort)
    printf 'files that compile on their own: %s\nfiles with an error: %s\n' "$ok" "$bad" | tee "$M0_OUT/inventory-summary.txt"
    categorise
}

# the first error of every failing file, sorted into what has to be done about it
#   POSIX/Linux system header   the file uses an API Windows does not have (needs the Windows platform layer or a port)
#   dependency header           a library the runner does not have yet (package or include path to add)
#   project header              a header of this repository that was not found (our include path list is incomplete)
#   other error                 anything else (read the line)
categorise() {
    local out="$M0_OUT/inventory.tsv" md="$M0_OUT/inventory-categories.md" f st err h cat
    : > "$md.tmp"
    while IFS=$'\t' read -r f st err; do
        [ "$st" = ERR ] || continue
        h="$(printf '%s' "$err" | sed -nE 's/.*fatal error: ([^:]+): No such file.*/\1/p')"
        if [ -n "$h" ]; then
            case "$h" in
                alsa/* | libevdev/* | libudev.h | libgpiod.h | gpiod.h | sys/* | poll.h | unistd.h | pthread.h | semaphore.h | termios.h | netinet/* | arpa/* | dirent.h | dlfcn.h | signal.h | fcntl.h | pty.h | utmp.h | execinfo.h | linux/*) cat="POSIX/Linux system header" ;;
                faust/* | glib* | gio/* | gobject/* | jack/* | softcut/* | avahi* | dns_sd.h | lo/* | cairo* | lua* | sndfile.h | SDL* | nng/* | monome.h | abl_link.h | ableton/* | cjson/* | readline/* | ncurses.h) cat="dependency header" ;;
                *) cat="project header" ;;
            esac
        else
            cat="other error"; h="$err"
        fi
        printf '%s\t%s\t%s\n' "$cat" "$h" "$f" >> "$md.tmp"
    done < "$out"
    {
        echo "# Porting inventory by category"
        echo
        echo "Files that compile on their own (first run: all of matron/src and crone/src outside platform/linux, platform/macos, hardware):"
        echo
        grep -P '\tOK\t' "$out" | cut -f1 | sed 's/^/- /'
        for cat in "POSIX/Linux system header" "dependency header" "project header" "other error"; do
            echo
            echo "## $cat"
            echo
            grep -F "$cat" "$md.tmp" | awk -F'\t' '{ if ($1 == "'"$cat"'") print "- `" $3 "`: " $2 }'
        done
    } > "$md"
    rm -f "$md.tmp"
    cat "$md"
}

m0_init
m0_run inventory inventory
exit 0
