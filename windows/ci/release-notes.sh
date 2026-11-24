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
echo "ONE zip, with the same name for every build: **Verdandi-windows-latest.zip**. It works for everyone: with an ASIO driver (low latency, DRIVER low latency on SYSTEM > AUDIO), with no ASIO driver on the PC, and with a driver that another program holds (Verdandi then plays through the normal Windows audio on the same hardware and says so). It carries the GPLv3 notices and the sources of the ASIO part (\`ASIO-NOTICE.txt\`, \`SOURCE-OFFER.txt\`, \`source\\\`; docs/port/asio-licence.md). **Verdandi-windows-$VERSION-$SHORT.zip** is the same file with the version in its name, kept so that an older build can be fetched."
echo
echo "> **The old name is gone:** \`Verdandi-windows-asio-latest.zip\` is no longer on this page. The update routine of 0.10.21 and earlier asks for that name: it says the download failed and changes nothing. Download \`Verdandi-windows-latest.zip\` once by hand (the folder name inside, \`Verdandi\`, and the folder you keep it in stay as they are); from 0.10.22 on, \`update-and-run.cmd\` asks for the new name."
echo
echo "1. Download **Verdandi-windows-latest.zip** below. Right-click it, Properties, tick *Unblock*, OK. Extract it into a folder of your own (Windows: Extract All puts it in a folder called \`Verdandi-windows-latest\`; the zip contains one folder, \`Verdandi\`, with no version in its name: the folder is the same for every build, so a Windows Defender exclusion for it keeps working). Which build it is: \`VERSION.txt\` and \`BUILD.txt\` in that folder, the log, the home page."
echo "2. Double-click \`Verdandi.exe\` in that folder. To update: close Verdandi, delete the old folder (your files are in \`%USERPROFILE%\\Verdandi\` and stay), extract the new zip into the same place. Or double-click \`update-and-run.cmd\`: it fetches the newest build and puts it in the same folder name that the folder you run it from has (\`Verdandi\` or, from an earlier ASIO build, \`Verdandi-asio\`), keeping the old one next to it as \`.previous\` until you delete it."
if [ -n "$REPO" ]; then
    echo "3. The newest build is always at https://github.com/$REPO/releases/tag/windows-latest"
fi
echo
echo "Commit: \`$SHA\`"
