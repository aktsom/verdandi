#!/bin/bash
# linux/tests/waf_path_test.sh: a SUDO_USER that is no account here (an environment from another machine, as can reach
# the clean root of package.sh) or is root is ignored by linux/waf-path.sh; a real account is kept.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FAIL=0
t() { # name, SUDO_USER value, expected ("unset" or the value)
    local got
    got="$(env -i PATH=/usr/bin:/bin HOME=/root SUDO_USER="$2" bash -c ". '$REPO/linux/waf-path.sh'; echo \"\${SUDO_USER:-unset}\"")"
    [ "$got" = "$3" ] && echo "ok   $1" || { echo "FAIL $1: got '$got', want '$3'"; FAIL=1; }
}
t "unknown account is ignored" no_such_account_xyz unset
t "root is ignored" root unset
t "a real account is kept" nobody nobody
exit $FAIL
