#!/usr/bin/env bash
# windows/ci/release-notes.sh: the text of a release on GitHub: the commit message, the checks of the run (from the status files of the report artifact), the known limits, how to get and start it.
#   VERSION SHORT SHA RUN_URL      the build (windows/VERSION, short hash, commit, address of the workflow run)
#   STATUS_DIR                     folder with <step>.status files ("PASS", "FAIL <code>", "SKIP <reason>"; lib.sh); may be missing
#   REPO                           owner/name, for the links
#   COMMIT_MESSAGE                 default: git log -1 of SHA
# prints Markdown on stdout
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../.." && pwd)"
VERSION="${VERSION:?}" SHORT="${SHORT:?}" SHA="${SHA:-unknown}" RUN_URL="${RUN_URL:-}" STATUS_DIR="${STATUS_DIR:-}" REPO="${REPO:-}"
MSG="${COMMIT_MESSAGE:-$(git -C "$REPO_DIR" log -1 --format=%B "$SHA" 2> /dev/null | grep -v -E '^(Co-Authored-By|Claude-Session):' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')}"

pass=() fail=() skip=() soft=()
NONBLOCKING_CHECKS="${NONBLOCKING_CHECKS-}"
if [ -n "$STATUS_DIR" ] && [ -d "$STATUS_DIR" ]; then
    for f in "$STATUS_DIR"/*.status; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .status)"
        word="$(head -n 1 "$f" | cut -d' ' -f1)"
        case "$word" in
            PASS) pass+=("$name") ;;
            FAIL)
                case " $NONBLOCKING_CHECKS " in
                    *" $name "*) soft+=("$name") ;;
                    *) fail+=("$name") ;;
                esac
                ;;
            *) skip+=("$name ($(head -n 1 "$f" | cut -d' ' -f2-))") ;;
        esac
    done
fi

echo "# Verdandi for Windows $VERSION ($SHORT)"
echo
echo "A test build of Verdandi (norns on a Windows PC). Version **$VERSION**, build **$SHORT**."
echo
echo "## What this build is"
echo
printf '%s\n' "$MSG" | sed 's/^/> /'
echo
if [ ${#fail[@]} -gt 0 ]; then
    echo "> **WARNING: ${#fail[@]} check(s) of the workflow failed for this build:** ${fail[*]}. It is published for the record; the *windows-latest* release is not replaced by it."
    echo
fi
if [ ${#soft[@]} -gt 0 ]; then
    echo "> **Known red check, not holding this build back:** ${soft[*]} (a test of the build process that is being fixed; the build was published anyway)."
    echo
fi
echo "## Checks of the workflow run"
echo
echo "${#pass[@]} passed, $((${#fail[@]} + ${#soft[@]})) failed, ${#skip[@]} skipped. Run: ${RUN_URL:-(not given)}"
echo
if [ ${#pass[@]} -gt 0 ]; then
    echo "<details><summary>The checks that passed</summary>"
    echo
    printf -- '- %s\n' "${pass[@]}"
    echo
    echo "</details>"
    echo
fi
if [ ${#fail[@]} -gt 0 ]; then
    echo "Failed:"
    printf -- '- %s\n' "${fail[@]}"
    echo
fi
if [ ${#soft[@]} -gt 0 ]; then
    echo "Failed, but not blocking (known):"
    printf -- '- %s\n' "${soft[@]}"
    echo
fi
if [ ${#skip[@]} -gt 0 ]; then
    echo "Skipped:"
    printf -- '- %s\n' "${skip[@]}"
    echo
fi
echo "## Known limits"
echo
cat "$REPO_DIR/windows/KNOWN-LIMITS.md"
echo
echo "## Get it and start it"
echo
if [ "${HAVE_ASIO:-0}" = 1 ]; then
    echo "Two zips: **Verdandi-windows-$VERSION-$SHORT.zip** (WASAPI only, the default, no ASIO code in it) and **Verdandi-windows-asio-$VERSION-$SHORT.zip** (the same program with PortAudio built with ASIO; it carries the GPLv3 notices and the sources of the ASIO part, see \`ASIO-NOTICE.txt\` in it and docs/port/asio-licence.md). Start with the default one."
    echo
else
    echo "This release has only the WASAPI zip (the ASIO build was not made, or did not pass its checks, in this run)."
    echo
fi
echo "1. Download **Verdandi-windows-$VERSION-$SHORT.zip** below. Right-click it, Properties, tick *Unblock*, OK. Extract it into a folder of your own (it contains one folder, \`Verdandi-$VERSION-$SHORT\`, so builds never overwrite each other)."
echo "2. Double-click \`Verdandi.exe\` in that folder. Next time double-click \`update-and-run.cmd\` there: it fetches the newest build, unpacks it next to this one and starts it. Your files stay in \`%USERPROFILE%\\Verdandi\`."
if [ -n "$REPO" ]; then
    echo "3. The newest build is always at https://github.com/$REPO/releases/tag/windows-latest"
fi
echo
echo "Commit: \`$SHA\`"
