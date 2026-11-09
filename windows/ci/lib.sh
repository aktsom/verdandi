#!/usr/bin/env bash
# windows/ci/lib.sh: helpers shared by the M0 scripts (sourced). Every step of the M0 workflow is run through m0_run: it keeps its own log, never stops the job by itself, and writes
# one status file ($M0_OUT/status/<name>.status: "PASS", "FAIL <exit code>" or "SKIP <reason>") that windows/ci/report.sh turns into the table of the report. nothing here is specific to
# Windows: the scripts are bash (Git Bash or MSYS2 on the runner), so that they can be checked with shellcheck and run on Linux for the parts that do not need Windows.
#   M0_OUT   where logs and status files go (default: ./m0-out)
set -u

M0_OUT="${M0_OUT:-$PWD/m0-out}"
export M0_OUT

m0_init() {
    mkdir -p "$M0_OUT/status" "$M0_OUT/logs"
}

m0_status() { # name word [text]
    mkdir -p "$M0_OUT/status"
    printf '%s %s\n' "$2" "${3:-}" > "$M0_OUT/status/$1.status"
}

# m0_run <name> <command...>: runs the command, its output goes to the log and to the console; returns its exit code. a step that failed says so in its status file
m0_run() {
    local name="$1" rc
    shift
    m0_init
    echo "::group::$name"
    "$@" 2>&1 | tee "$M0_OUT/logs/$name.log"
    rc=${PIPESTATUS[0]}
    echo "::endgroup::"
    if [ "$rc" -eq 0 ]; then
        m0_status "$name" PASS
    else
        m0_status "$name" FAIL "exit $rc"
        echo "m0: step $name failed (exit $rc), the job goes on" >&2
    fi
    return "$rc"
}

m0_skip() { # name reason
    m0_init
    m0_status "$1" SKIP "$2"
}

# the last lines of a log, for the report
m0_tail() { # name [lines]
    tail -n "${2:-15}" "$M0_OUT/logs/$1.log" 2> /dev/null
}
