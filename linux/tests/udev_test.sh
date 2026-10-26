#!/bin/bash
# linux/tests/udev_test.sh: the udev rule of the package is syntactically valid and narrow (monome devices only, nothing but
# the uaccess tag). real hotplug and permissions need a grid: docs/port/HARDWARE-CHECKLIST.md
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
R="$REPO/linux/udev/70-verdandi-monome.rules"
FAIL=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }

[ -f "$R" ] && ok "rule file exists" || { bad "rule file missing"; exit 1; }
RULES="$(grep -v '^[[:space:]]*#' "$R" | grep -v '^[[:space:]]*$')"
[ -n "$RULES" ] && ok "has rules" || bad "no rules"

# every rule: tty subsystem on a usb parent, a monome-specific match, and only the uaccess tag as action
while IFS= read -r line; do
    case "$line" in SUBSYSTEM==\"tty\",\ SUBSYSTEMS==\"usb\",*) ok "tty on usb: ${line:0:60}..." ;; *) bad "rule not limited to usb tty: $line" ;; esac
    case "$line" in
    *'ATTRS{manufacturer}=="monome"'* | *'ATTRS{idVendor}=="0403"'*'ATTRS{idProduct}=="6001"'*'ATTRS{serial}=="m'*) ok "monome-specific match" ;;
    *) bad "no monome-specific match: $line" ;;
    esac
    # remove the matches, what is left must be the tag
    rest="$(echo "$line" | sed -E 's/(SUBSYSTEMS?|ATTRS)(\{[a-zA-Z]+\})?=="[^"]*",? ?//g')"
    [ "$rest" = 'TAG+="uaccess"' ] && ok "only TAG+=\"uaccess\"" || bad "something besides the uaccess tag: '$rest'"
done <<< "$RULES"
grep -qE 'MODE|GROUP|OWNER|RUN|SYMLINK|RESULT' <<< "$RULES" && bad "mode, group, owner, run or symlink in the rules" || ok "no MODE/GROUP/OWNER/RUN/SYMLINK"
# no broad match: a bare vendor id without the product id and the serial name
grep -E 'idVendor=="0403"' <<< "$RULES" | grep -qv 'idProduct=="6001"' && bad "FTDI vendor without product" || ok "FTDI only with product and name"

if command -v udevadm >/dev/null && udevadm verify --help >/dev/null 2>&1; then
    if udevadm verify "$R" >/dev/null 2>&1; then ok "udevadm verify"; else bad "udevadm verify"; udevadm verify "$R"; fi
else
    echo "skip udevadm verify (not available)"
fi
exit $FAIL
