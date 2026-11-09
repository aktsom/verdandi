#!/usr/bin/env bash
# windows/ci/report.sh: turns the status files and logs of all M0 jobs (collected in $M0_OUT) into M0-REPORT.md: one table, the tail of every failed log, the tool versions. this is the file the owner reads and sends back.
#   M0_OUT   folder with status/*.status and logs/*.log (the workflow downloads the artifacts of the jobs into it)
#   M0_RUN   text for the head of the report (run URL, commit, runner), set by the workflow
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
out="$M0_OUT/M0-REPORT.md"
pass=0 fail=0 skip=0

# which milestone part each step proves, in the order of the table
group_of() {
    case "$1" in
        sc-*) echo "M0a SuperCollider build" ;;
        msys2-* | lua53-* | libmonome-* | link-* | inventory) echo "M0a toolchain and dependencies" ;;
        pt-*) echo "M0a portable tests" ;;
        smoke-*) echo "M0b boot smoke" ;;
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

{
    echo
    echo "**$pass passed, $fail failed, $skip skipped.**"
    echo
    echo "A failed step is information, not a disaster: M0 exists to find these. Send this file together with the zip of the run (or the logs folder in it)."
    if [ -f "$M0_OUT/inventory-summary.txt" ]; then
        echo
        echo "## Porting inventory"
        echo
        echo '```'
        cat "$M0_OUT/inventory-summary.txt"
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
            m0_tail "$name" 25
            echo '```'
        fi
    done
} >> "$out"

cat "$out"
# the job fails when a step of the CORE parts failed, so that the green/red mark of the run is meaningful: SuperCollider build and the smoke test. the rest is reported only
core_fail=0
for f in "$M0_OUT"/status/sc-*.status "$M0_OUT"/status/smoke-*.status; do
    [ -e "$f" ] || continue
    read -r word _ < "$f"
    [ "$word" = FAIL ] && core_fail=1
done
exit "$core_fail"
