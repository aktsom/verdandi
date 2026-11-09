#!/usr/bin/env bash
# windows/ci/report.sh: turns the status files and logs of all M0 jobs (collected in $M0_OUT) into M0-REPORT.md: one table, the tail of every failed log, the tool versions. this is the file the owner reads and sends back.
#   M0_OUT   folder with status/*.status and logs/*.log (the workflow downloads the artifacts of the jobs into it)
#   M0_RUN   text for the head of the report (run URL, commit, runner), set by the workflow
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
# a digest of the errors, one line each, so that a long build log is readable at a glance
digest() { # name
    grep -E "error:|undefined reference|fatal error|No such file|cannot find" "$M0_OUT/logs/$1.log" 2> /dev/null | sed -E 's/^.*(D:|\/d)\/a\/verdandi\/verdandi\///' | sort -u | head -"${DIGEST:-50}"
}
out="$M0_OUT/M0-REPORT.md"
pass=0 fail=0 skip=0

# which milestone part each step proves, in the order of the table
group_of() {
    case "$1" in
        sc-*) echo "M0a SuperCollider build" ;;
        msys2-* | lua53-* | libmonome-* | link-* | inventory) echo "M0a toolchain and dependencies" ;;
        pt-*) echo "M0a portable tests" ;;
        smoke-*) echo "M0b boot smoke" ;;
        norns-* | launcher-*) echo "M1 build of norns.exe and the launcher" ;;
        assemble | package) echo "M1 runnable folder and zip" ;;
        m1-*) echo "M1 start test (headless)" ;;
        info-*) echo "M0b findings (information)" ;;
        *) echo "other" ;;
    esac
}

{
    echo "# Verdandi Windows M0 report"
    echo
    echo "${M0_RUN:-run: (not set)}"
    echo
    echo "| part | step | result | detail |"
    echo "|---|---|---|---|"
} > "$out"

for f in "$M0_OUT"/status/*.status; do
    [ -e "$f" ] || continue
    read -r word _ < "$f"
    case "$word" in PASS) pass=$((pass + 1)) ;; SKIP) skip=$((skip + 1)) ;; *) fail=$((fail + 1)) ;; esac
done
# the table is built in a pipe (sorted by part), the counts above are not
for f in "$M0_OUT"/status/*.status; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .status)"
    read -r word detail < "$f"
    printf '%s\t| %s | %s | %s | %s |\n' "$(group_of "$name")" "$(group_of "$name")" "$name" "$word" "$detail"
done | sort -t "$(printf '\t')" -k1,1 -s | cut -f2- >> "$out"

# a job that hung or was cancelled leaves no status at all: say so instead of staying silent
missing=""
for part in ${M0_REQUIRE:-sc smoke}; do
    ls "$M0_OUT"/status/"$part"*.status > /dev/null 2>&1 || missing="$missing $part"
done
{
    if [ -n "$missing" ]; then
        echo
        echo "**NO RESULT from:$missing (the job failed before its first step finished, was cancelled, or timed out).**"
    fi
    echo
    echo "**$pass passed, $fail failed, $skip skipped.**"
    echo
    echo "A failed step is information, not a disaster: M0 exists to find these. Send this file together with the zip of the run (or the logs folder in it)."
    if [ -f "$M0_OUT/inventory-summary.txt" ]; then
        echo
        echo "## Porting inventory (counts)"
        echo
        echo '```'
        cat "$M0_OUT/inventory-summary.txt"
        echo '```'
    fi
    if [ -f "$M0_OUT/inventory-categories.md" ]; then
        echo
        sed 's/^# /### /; s/^## /#### /' "$M0_OUT/inventory-categories.md"
    fi
    if [ -f "$M0_OUT/portable-summary.txt" ]; then
        echo
        echo "## Portable tests: which compile and run, which need porting"
        echo
        echo '```'
        cat "$M0_OUT/portable-summary.txt"
        echo '```'
    fi
    if [ -f "$M0_OUT/msys2-packages.txt" ]; then
        echo
        echo "## MSYS2 packages"
        echo
        echo '```'
        cat "$M0_OUT/msys2-packages.txt"
        echo '```'
    fi
    for f in "$M0_OUT"/status/*.status; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .status)"
        read -r word _ < "$f"
        if [ "$word" = FAIL ]; then
            echo
            echo "## Last lines of the log: $name"
            echo
            echo '```'
            digest "$name"
            echo "--- last lines:"
            m0_tail "$name" 25
            echo '```'
        fi
    done
} >> "$out"

cat "$out"
# the job fails when a step of the CORE parts failed, so that the green/red mark of the run is meaningful: SuperCollider build and the smoke test. the rest is reported only
core_fail=0
[ -n "$missing" ] && core_fail=1
for f in "$M0_OUT"/status/sc-*.status "$M0_OUT"/status/smoke-*.status "$M0_OUT"/status/norns-*.status "$M0_OUT"/status/launcher-*.status "$M0_OUT"/status/assemble.status "$M0_OUT"/status/package.status "$M0_OUT"/status/m1-*.status; do
    [ -e "$f" ] || continue
    read -r word _ < "$f"
    [ "$word" = FAIL ] && core_fail=1
done
exit "$core_fail"
