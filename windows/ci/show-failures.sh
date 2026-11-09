#!/usr/bin/env bash
# windows/ci/show-failures.sh: at the end of a job, print the last lines of the log of every step that failed (so the end of the job's own log tells what went wrong, without opening the artifacts)
#   M0_OUT   as in lib.sh      LINES   how many lines of each log (default 40)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
n=0
# a digest of the errors, one line each, so that a long build log is readable at a glance
digest() { # name
    grep -E "error:|undefined reference|fatal error|No such file|cannot find" "$M0_OUT/logs/$1.log" 2> /dev/null | sed -E 's/^.*(D:|\/d)\/a\/verdandi\/verdandi\///' | sort -u | head -"${DIGEST:-50}"
}
for f in "$M0_OUT"/status/*.status; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .status)"
    read -r word detail < "$f"
    if [ "$word" = FAIL ]; then
        n=$((n + 1))
        echo "=== FAILED STEP: $name ($detail): digest of the errors, then the last lines of its log"
        digest "$name"
        echo "--- last lines:"
        m0_tail "$name" "${LINES:-40}"
    fi
done
[ "$n" -eq 0 ] && echo "no failed steps in this job"
exit 0
